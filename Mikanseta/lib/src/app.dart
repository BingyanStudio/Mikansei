import 'dart:async';

import 'package:flutter/foundation.dart';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'domain.dart';
import 'store.dart';
import 'cloud_sync.dart';
import 'local_folder_sync.dart';
import 'segmented_strip.dart';
import 'theme.dart';
import 'editor.dart';
import 'android_system.dart';
import 'calendar_view.dart';
import 'student_tools.dart';
import 'system_services.dart';

const appVersion = '0.4.4 (10)';

class MikansetaApp extends StatelessWidget {
  const MikansetaApp({
    super.key,
    required this.store,
    this.cloud,
    this.localSync,
  });
  final EntryStore store;
  final CloudSync? cloud;
  final LocalFolderSync? localSync;
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: store,
    builder: (context, _) => MaterialApp(
      title: 'Mikanseta',
      debugShowCheckedModeBanner: false,
      theme: KraftTheme.build(Brightness.light),
      darkTheme: KraftTheme.build(Brightness.dark),
      locale: const Locale('zh', 'CN'),
      supportedLocales: const [Locale('zh', 'CN'), Locale('en')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      themeMode: switch (store.preferences["appearance"]) {
        "light" => ThemeMode.light,
        "dark" => ThemeMode.dark,
        _ => ThemeMode.system,
      },
      home: HomePage(store: store, cloud: cloud, localSync: localSync),
    ),
  );
}

class HomePage extends StatefulWidget {
  const HomePage({super.key, required this.store, this.cloud, this.localSync});
  final EntryStore store;
  final CloudSync? cloud;
  final LocalFolderSync? localSync;
  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> with WidgetsBindingObserver {
  int page = 0;
  String query = '';
  String filter = '全部';
  Timer? _refresh;
  final searchFocus = FocusNode();
  final searchController = TextEditingController();
  bool calendarSyncing = false;
  bool editing = false;
  bool readingRoutes = false;
  bool popupVisible = false;
  final pendingPopups = <Map<String, dynamic>>[];
  final handledPopups = <String>{};
  bool initialCalendarSync = false;
  String? calendarSyncError;
  EntryStore get store => widget.store;
  CloudSync? get cloud => widget.cloud;
  LocalFolderSync? get localSync => widget.localSync;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    store.addListener(onStoreReady);
    NativeStorage.channel.setMethodCallHandler((call) async {
      if (call.method == "routesAvailable") {
        readRoutes();
      }
      if (call.method == 'foregroundReminder') {
        showForeground(Map<String, dynamic>.from(call.arguments as Map));
      }
      if (call.method == "serviceError" && mounted) {
        message("${call.arguments}");
      }
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => onStoreReady());
    _refresh = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    store.removeListener(onStoreReady);
    NativeStorage.channel.setMethodCallHandler(null);
    _refresh?.cancel();
    searchFocus.dispose();
    searchController.dispose();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      setState(() {});
      syncCalendar();
      store.refreshServices();
      readRoutes();
      cloud?.syncNow();
      localSync?.syncNow();
    }
  }

  Future<void> showForeground(Map<String, dynamic> item) async {
    final id = item['id'] as String;
    if (handledPopups.contains(id) || pendingPopups.any((p) => p['id'] == id)) {
      return;
    }
    pendingPopups.add(item);
    if (popupVisible || !mounted) return;
    popupVisible = true;
    try {
      while (pendingPopups.isNotEmpty && mounted) {
        if (!mounted) break;
        final next = pendingPopups.removeAt(0);
        handledPopups.add(next['id'] as String);
        final action = await showDialog<String>(
          context: context,
          builder: (context) => AlertDialog(
            title: Text(next['title'] as String),
            content: Text(next['body'] as String),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, 'dismiss'),
                child: const Text('知道了'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(context, 'snooze'),
                child: const Text('稍后提醒'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(context, 'open'),
                child: const Text('打开'),
              ),
              if (next['canComplete'] != false)
                FilledButton(
                  onPressed: () => Navigator.pop(context, 'complete'),
                  child: const Text('完成'),
                ),
            ],
          ),
        );
        await NativeStorage.invokeMethod('foregroundAction', {
          'id': next['id'],
          'action': action ?? 'dismiss',
        });
      }
    } finally {
      popupVisible = false;
    }
  }

  Future<void> readRoutes() async {
    if (store.loading || readingRoutes || !mounted) return;
    readingRoutes = true;
    try {
      final routes =
          await NativeStorage.invokeListMethod<dynamic>("takeRoutes") ?? [];
      for (final raw in routes) {
        if (!mounted) break;
        final route = Map<String, dynamic>.from(raw as Map);
        final url = Uri.tryParse(route["url"] as String? ?? "");
        final id =
            route["entryID"] as String? ??
            (url?.host == "entry" || url?.host == "focus"
                ? url?.pathSegments.lastOrNull
                : null);
        if (route["courseID"] != null) {
          final c = store.courses
              .where((c) => c.id == route["courseID"])
              .firstOrNull;
          if (c != null) {
            await showDialog<void>(
              context: context,
              builder: (_) =>
                  EntryEditor(store: store, entry: c.homework(), isNew: true),
            );
          }
        } else if (id != null) {
          final e = store.find(id);
          if (e != null) {
            if (route["action"] == "complete") {
              if (!e.completed) store.toggle(id);
            } else if (url?.host == "focus") {
              final start = url?.queryParameters["action"] == "start";
              if ((e.startedAt == null) == start) store.focus(id);
            } else {
              details(e);
            }
          }
        } else if (url?.host == "new") {
          await edit(
            kind:
                EntryKind.values
                    .where((k) => k.name == url?.queryParameters["kind"])
                    .firstOrNull ??
                EntryKind.task,
          );
        } else if (url?.host == "today" || url?.host == "tasks") {
          setState(() => page = url?.host == "tasks" ? 1 : 0);
        }
      }
    } catch (_) {
      /* A platform without routes keeps the shared UI usable. */
    } finally {
      readingRoutes = false;
    }
  }

  void onStoreReady() {
    if (!store.loading && !initialCalendarSync) {
      initialCalendarSync = true;
      syncCalendar();
      WidgetsBinding.instance.addPostFrameCallback((_) => readRoutes());
    }
  }

  Future<void> syncCalendar() async {
    if (!AndroidSystem.supported ||
        calendarSyncing ||
        store.loading ||
        store.readOnly ||
        editing) {
      return;
    }
    calendarSyncing = true;
    try {
      await AndroidSystem.sync(store, canImport: () => mounted && !editing);
      calendarSyncError = null;
    } catch (error) {
      final text = AndroidSystem.error(error);
      if (mounted && calendarSyncError != text) message('日历导入未完成：$text');
      calendarSyncError = text;
    } finally {
      calendarSyncing = false;
    }
  }

  Future<void> edit({
    Entry? entry,
    EntryKind? kind,
    DateTime? start,
    DateTime? end,
  }) async {
    if (store.readOnly || store.loading || editing) return;
    editing = true;
    try {
      await showDialog<void>(
        context: context,
        builder: (context) => EntryEditor(
          store: store,
          entry: entry,
          kind: kind,
          start: start,
          end: end,
        ),
      );
    } finally {
      editing = false;
      if (mounted) syncCalendar();
    }
  }

  void details(Entry entry) => showDialog<void>(
    context: context,
    builder: (context) => EntryDetails(
      store: store,
      id: entry.id,
      onEdit: () => edit(entry: store.find(entry.id)),
    ),
  );
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: store,
    builder: (context, _) => Shortcuts(
      shortcuts: const {
        SingleActivator(LogicalKeyboardKey.keyN, meta: true): AddIntent(),
        SingleActivator(LogicalKeyboardKey.keyN, control: true): AddIntent(),
        SingleActivator(LogicalKeyboardKey.keyF, meta: true): SearchIntent(),
        SingleActivator(LogicalKeyboardKey.keyF, control: true): SearchIntent(),
      },
      child: Actions(
        actions: {
          AddIntent: CallbackAction<AddIntent>(
            onInvoke: (_) {
              edit(kind: page == 3 ? EntryKind.note : null);
              return null;
            },
          ),
          SearchIntent: CallbackAction<SearchIntent>(
            onInvoke: (_) {
              searchFocus.requestFocus();
              return null;
            },
          ),
        },
        child: Focus(
          autofocus: true,
          child: LayoutBuilder(
            builder: (context, bounds) {
              final desktop = bounds.maxWidth >= 760;
              final titles = ['今日', '我的清单', '日程', '笔记', '设置'];
              final destinations = [
                Icons.wb_sunny_outlined,
                Icons.checklist_rounded,
                Icons.calendar_month_outlined,
                Icons.notes_rounded,
                Icons.tune_rounded,
              ];
              return Scaffold(
                appBar: AppBar(
                  title: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(titles[page]),
                      if (page == 0)
                        Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: Text(
                            '${dateLabel(DateTime.now(), time: false)} · 一件一件，慢慢完成',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.bodySmall
                                ?.copyWith(
                                  color: Theme.of(context)
                                      .colorScheme
                                      .onSurfaceVariant,
                                ),
                          ),
                        ),
                    ],
                  ),
                  actions: [
                    if (page != 4)
                      Padding(
                        padding: const EdgeInsets.only(right: 14),
                        child: desktop
                            ? Tooltip(
                                message: '添加事项',
                                child: FilledButton.icon(
                                  onPressed: store.readOnly
                                      ? null
                                      : () => edit(
                                          kind: page == 3
                                              ? EntryKind.note
                                              : null,
                                        ),
                                  icon: const Icon(Icons.add),
                                  label: const Text('添加事项'),
                                ),
                              )
                            : IconButton.filledTonal(
                                tooltip: '添加事项',
                                style: IconButton.styleFrom(
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(14),
                                  ),
                                  minimumSize: const Size(44, 44),
                                ),
                                onPressed: store.readOnly
                                    ? null
                                    : () => edit(
                                        kind: page == 2
                                            ? EntryKind.schedule
                                            : page == 3
                                            ? EntryKind.note
                                            : null,
                                      ),
                                icon: const Icon(Icons.add),
                              ),
                      ),
                  ],
                ),
                bottomNavigationBar: desktop
                    ? null
                    : SafeArea(
                        top: false,
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              color: Theme.of(context).colorScheme.surface,
                              borderRadius: BorderRadius.circular(24),
                              border: Border.all(
                                color: Theme.of(context).colorScheme.outline
                                    .withValues(alpha: .16),
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: .05),
                                  blurRadius: 18,
                                  offset: const Offset(0, 6),
                                ),
                              ],
                            ),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(24),
                              child: NavigationBar(
                                selectedIndex: page,
                                onDestinationSelected: (index) =>
                                    setState(() => page = index),
                                destinations: List.generate(
                                  titles.length,
                                  (i) => NavigationDestination(
                                    icon: Icon(destinations[i]),
                                    label: titles[i],
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                body: Row(
                  children: [
                    if (desktop)
                      NavigationRail(
                        selectedIndex: page,
                        onDestinationSelected: (index) =>
                            setState(() => page = index),
                        labelType: NavigationRailLabelType.all,
                        destinations: List.generate(
                          titles.length,
                          (i) => NavigationRailDestination(
                            icon: Icon(destinations[i]),
                            label: Text(titles[i]),
                          ),
                        ),
                      ),
                    Expanded(
                      child: Column(
                        children: [
                          if (store.error != null)
                            MaterialBanner(
                              content: Text(store.error!),
                              leading: const Icon(Icons.info_outline),
                              actions: [
                                if (store.saveFailed)
                                  TextButton(
                                    onPressed: store.retrySave,
                                    child: const Text('重试保存'),
                                  )
                                else
                                  TextButton(
                                    onPressed: null,
                                    child: const Text('数据已保留'),
                                  ),
                              ],
                            ),
                          if (store.loading)
                            const Expanded(
                              child: Center(child: CircularProgressIndicator()),
                            )
                          else
                            Expanded(
                              child: Center(
                                child: ConstrainedBox(
                                  constraints: const BoxConstraints(
                                    maxWidth: 1000,
                                  ),
                                  child: AnimatedSwitcher(
                                    duration:
                                        MediaQuery.maybeOf(context)
                                                ?.disableAnimations ==
                                            true
                                        ? Duration.zero
                                        : const Duration(milliseconds: 160),
                                    switchInCurve: Curves.easeOut,
                                    switchOutCurve: Curves.easeIn,
                                    child: KeyedSubtree(
                                      key: ValueKey(page),
                                      child: page == 2
                                          ? calendar(desktop)
                                          : page == 4
                                          ? settings()
                                          : taskPage(),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    ),
  );
  Widget taskPage() {
    final now = store.clock();
    final board = TaskBoard(store.entries, now);
    List<Entry> entries;
    if (page == 3) {
      entries = store.entries.where((e) => !e.isTask).toList()
        ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    } else if (page == 0) {
      entries = board.focus;
    } else {
      entries = switch (filter) {
        '已超时' => board.overdue,
        '紧急' => board.visible.where((e) => e.priority == 2).toList(),
        '常态' => board.visible.where((e) => e.repeatRule != 'never').toList(),
        '作业' =>
          board.visible.where((e) => e.kind == EntryKind.homework).toList(),
        '历史' => board.history,
        _ => board.visible,
      };
    }
    entries = entries.where((e) => e.matches(query)).toList();
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 100),
      children: [
        if (page == 0) ...[
          Card(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 14),
              child: Row(
                children: [
                  Expanded(child: metric('${board.open.length}', '未完成')),
                  metricDivider(),
                  Expanded(
                    child: metric(
                      '${board.overdue.length}',
                      '已超时',
                      alert: true,
                    ),
                  ),
                  metricDivider(),
                  Expanded(
                    child: metric('${board.finishedToday.length}', '今日完成'),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 14),
          if (store.running case final Entry running) ...[
            Card(
              child: InkWell(
                borderRadius: BorderRadius.circular(18),
                onTap: () => details(running),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
                  child: Row(
                    children: [
                      Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                          color: Theme.of(context).colorScheme.primaryContainer,
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          Icons.timelapse,
                          size: 20,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '正在做 · ${running.title}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              durationLabel(running.focusSeconds(now)),
                              style: const TextStyle(
                                fontFeatures: [FontFeature.tabularFigures()],
                                fontSize: 18,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        tooltip: '暂停计时',
                        onPressed: store.readOnly
                            ? null
                            : () => store.focus(running.id),
                        icon: const Icon(Icons.pause_rounded),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 14),
          ],
        ],
        TextField(
          controller: searchController,
          focusNode: searchFocus,
          onChanged: (value) => setState(() => query = value),
          decoration: InputDecoration(
            hintText: '搜索事项、科目或提交平台',
            prefixIcon: const Icon(Icons.search, size: 20),
            suffixIcon: query.isEmpty
                ? null
                : IconButton(
                    tooltip: '清除搜索',
                    icon: const Icon(Icons.close, size: 20),
                    onPressed: () {
                      searchController.clear();
                      setState(() => query = '');
                    },
                  ),
          ),
        ),
        const SizedBox(height: 12),
        if (page == 1) ...[
          SegmentedStrip<String>(
            label: '事项筛选',
            choices: const ['全部', '已超时', '紧急', '作业', '常态', '历史'],
            selection: filter,
            title: (label) => label,
            onChanged: (label) => setState(() => filter = label),
          ),
          const SizedBox(height: 12),
        ],
        if (entries.isEmpty)
          EmptyState(
            icon: page == 3 ? Icons.notes : Icons.check_circle_outline,
            title: query.isNotEmpty
                ? '没有找到匹配的事项'
                : page == 0
                ? '今天可以轻松一点'
                : filter == '历史'
                ? '历史记录会在次日出现'
                : '这里还没有事项',
            message: page == 0 ? '以后到期的事项仍在「我的清单」里。' : '先记下标题，时间和细节可以稍后补充。',
          )
        else
          AnimatedEntryList(
            entries: entries,
            now: now,
            onDetails: details,
            store: store,
            showGroups: page != 3 && filter != '历史',
          ),
      ],
    );
  }

  Widget metric(String value, String label, {bool alert = false}) {
    final colors = Theme.of(context).colorScheme;
    return Column(
      children: [
        Text(
          value,
          style: TextStyle(
            fontSize: 22,
            height: 1.1,
            fontWeight: FontWeight.w700,
            color: alert ? colors.error : colors.onSurface,
          ),
        ),
        const SizedBox(height: 3),
        Text(
          label,
          style: TextStyle(fontSize: 11, color: colors.onSurfaceVariant),
        ),
      ],
    );
  }

  Widget metricDivider() => Container(
    width: 1,
    height: 28,
    color: Theme.of(context).colorScheme.outline.withValues(alpha: .15),
  );
  Widget calendar(bool desktop) => ScheduleCalendar(
    store: store,
    onOpen: details,
    onCreate: (start, end) =>
        edit(kind: EntryKind.schedule, start: start, end: end),
  );

  Widget settings() => ListView(
    padding: const EdgeInsets.fromLTRB(20, 12, 20, 50),
    children: [
      Card(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Mikanseta',
                style: Theme.of(context).textTheme.headlineSmall
                    ?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 4),
              const Text('Flutter 测试版 · 牛皮浅棕'),
              const SizedBox(height: 10),
              Text('版本 ${store.displayVersion}'),
              const SizedBox(height: 8),
              Text(
                '${store.entries.length} 个事项 · ${store.saving
                    ? '正在保存'
                    : store.saveFailed
                    ? '保存待重试'
                    : '已保存在本机'}',
              ),
            ],
          ),
        ),
      ),
      const SizedBox(height: 20),
      ListTile(
        leading: const Icon(Icons.notifications_active),
        title: const Text('提醒、小组件与实时活动'),
        subtitle: Text(store.serviceError ?? '系统权限、提醒状态、今日 DDL'),
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute<void>(
            builder: (_) => ServicesSettings(store: store),
          ),
        ),
      ),
      DropdownButtonFormField<String>(
        initialValue: store.preferences['appearance'] as String? ?? 'system',
        decoration: const InputDecoration(labelText: '外观'),
        items: const [
          DropdownMenuItem(value: 'system', child: Text('跟随系统')),
          DropdownMenuItem(value: 'light', child: Text('浅色')),
          DropdownMenuItem(value: 'dark', child: Text('深色')),
        ],
        onChanged: (v) => store.setPreferences({'appearance': v}),
      ),
      ListTile(
        leading: const Icon(Icons.school),
        title: const Text('课表与下课登记提醒'),
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute<void>(builder: (_) => CoursesPage(store: store)),
        ),
      ),
      ListTile(
        leading: const Icon(Icons.message_outlined),
        title: const Text('从群消息添加'),
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute<void>(
            builder: (_) => MessageImportPage(store: store),
          ),
        ),
      ),
      if (AndroidSystem.supported) ...[
        Card(
          child: Column(
            children: [
              ListTile(
                leading: const Icon(Icons.calendar_month),
                title: const Text('系统日历来源'),
                subtitle: const Text('选择来源、导入日程与设置自动更新'),
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute<void>(
                    builder: (_) => AndroidCalendarPage(store: store),
                  ),
                ),
              ),
              const Divider(height: 1),
              if (defaultTargetPlatform == TargetPlatform.android)
                ListTile(
                  leading: const Icon(Icons.alarm),
                  title: const Text('打开系统时钟'),
                  subtitle: const Text('可在事项详情创建闹钟或系统倒计时'),
                  onTap: () async {
                    try {
                      await AndroidSystem.call<bool>('showClock');
                    } catch (error) {
                      if (mounted) message(AndroidSystem.error(error));
                    }
                  },
                ),
            ],
          ),
        ),
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 12),
          child: Text('仅导入你勾选的来源。由 Mikanseta 管理的提醒随事项更新；手动创建到系统时钟的记录独立保留。'),
        ),
      ],
      Text('数据', style: Theme.of(context).textTheme.titleMedium),
      const SizedBox(height: 8),
      Card(
        child: Column(
          children: [
            ListTile(
              leading: const Icon(Icons.file_download_outlined),
              title: const Text('导入 Mikansei 备份'),
              subtitle: const Text('合并 JSON 备份，同编号保留较新事项'),
              enabled: !store.readOnly,
              onTap: store.readOnly
                  ? null
                  : () async {
                      try {
                        final count = await store.importBackup();
                        if (count != null && mounted) message('已导入 $count 个事项');
                      } catch (error) {
                        if (mounted) message('未完成导入：$error');
                      }
                    },
            ),
            const Divider(height: 1),
            ListTile(
              leading: const Icon(Icons.file_upload_outlined),
              title: const Text('导出备份'),
              subtitle: const Text('可交回 Mikansei，或作为独立备份保存'),
              onTap: () async {
                try {
                  final saved = await store.exportBackup();
                  if (mounted && saved) message('备份已导出');
                } catch (error) {
                  if (mounted) message('导出失败：$error');
                }
              },
            ),
          ],
        ),
      ),
      const SizedBox(height: 20),
      Text('账户同步', style: Theme.of(context).textTheme.titleMedium),
      const SizedBox(height: 8),
      if (cloud != null)
        _AccountSettings(store: store, cloud: cloud!)
      else
        const Card(
          child: Padding(
            padding: EdgeInsets.all(18),
            child: Text(
              '未配置 Supabase 账户服务。构建时通过 --dart-define 提供 SUPABASE_URL 与 SUPABASE_ANON_KEY 后可用，步骤见 Documentation/SUPABASE_SETUP.md。',
            ),
          ),
        ),
      const SizedBox(height: 20),
      Text('本机同步（与 Mikansei）', style: Theme.of(context).textTheme.titleMedium),
      const SizedBox(height: 8),
      if (localSync != null)
        _LocalSyncSettings(localSync: localSync!)
      else
        const Card(
          child: Padding(
            padding: EdgeInsets.all(18),
            child: Text('共享文件夹同步不可用。'),
          ),
        ),
      const SizedBox(height: 20),
      Text('迁移进度', style: Theme.of(context).textTheme.titleMedium),
      const SizedBox(height: 8),
      const Card(
        child: Padding(
          padding: EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('已可使用', style: TextStyle(fontWeight: FontWeight.w700)),
              SizedBox(height: 6),
              Text(
                '清单与 Checklist、月 / 日 / 周日历、拖动选时段、循环与计时、课表及课后登记、消息解析、系统日历与提醒、小组件和今日 DDL 展示、备份。',
              ),
              SizedBox(height: 18),
              Text('同步', style: TextStyle(fontWeight: FontWeight.w700)),
              SizedBox(height: 6),
              Text(
                '账户与跨设备云同步已接入 Supabase（见上方账户同步），源码与单元测试通过，真实设备登录同步待验证。共享文件夹同步已接入 macOS、iOS 与 Android，可与原版 Mikansei 及其它 Mikanseta 设备自动合并。',
              ),
              SizedBox(height: 12),
              Text(
                '系统功能需要对应权限。iPhone 实时活动需要 iOS 17、原生闹钟需要 iOS 26；Mac 使用系统通知，安卓的锁屏展示为常驻通知。',
              ),
            ],
          ),
        ),
      ),
      const SizedBox(height: 18),
      const Text(
        '两个 App 的本地数据分别保存。导入备份会复制事项，不会自动共享修改；Mikanseta 登录同一账号后，各设备的数据经账户自动同步。主题跟随系统切换浅色与深色。',
      ),
      if (MediaQuery.sizeOf(context).width >= 760) ...[
        const SizedBox(height: 16),
        const Text('电脑快捷键：⌘/Ctrl + N 添加，⌘/Ctrl + F 搜索。'),
      ],
    ],
  );
  void message(String text) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
}

class AddIntent extends Intent {
  const AddIntent();
}

class SearchIntent extends Intent {
  const SearchIntent();
}

class AnimatedEntryList extends StatefulWidget {
  const AnimatedEntryList({
    super.key,
    required this.entries,
    required this.now,
    required this.store,
    required this.onDetails,
    required this.showGroups,
  });
  final List<Entry> entries;
  final DateTime now;
  final EntryStore store;
  final ValueChanged<Entry> onDetails;
  final bool showGroups;
  @override
  State<AnimatedEntryList> createState() => _AnimatedEntryListState();
}

class _AnimatedEntryListState extends State<AnimatedEntryList> {
  Duration get motion => MediaQuery.disableAnimationsOf(context)
      ? Duration.zero
      : const Duration(milliseconds: 380);
  final listKey = GlobalKey<AnimatedListState>();
  late List<Entry> items;
  // AnimatedList keeps its outgoing child builder alive for the transition.
  // Index current snapshots so that child can refresh if the same ID changes.
  final _latestEntries = <String, Entry>{};
  @override
  void initState() {
    super.initState();
    items = List.of(widget.entries);
    _latestEntries.addEntries(items.map((entry) => MapEntry(entry.id, entry)));
  }

  @override
  void didUpdateWidget(AnimatedEntryList old) {
    super.didUpdateWidget(old);
    final next = widget.entries;
    for (var index = items.length - 1; index >= 0; index--) {
      if (!next.any((e) => e.id == items[index].id)) remove(index);
    }
    for (var index = 0; index < next.length; index++) {
      if (index < items.length && items[index].id == next[index].id) {
        items[index] = next[index];
        continue;
      }
      final oldIndex = items.indexWhere((e) => e.id == next[index].id);
      if (oldIndex >= 0) remove(oldIndex, replacement: next[index]);
      items.insert(index, next[index]);
      listKey.currentState?.insertItem(index, duration: motion);
    }
    _latestEntries
      ..clear()
      ..addEntries(items.map((entry) => MapEntry(entry.id, entry)));
  }

  void remove(int index, {Entry? replacement}) {
    final removed = replacement ?? items[index];
    items.removeAt(index);
    listKey.currentState?.removeItem(
      index,
      (context, animation) => liveTransition(removed, animation),
      duration: motion,
    );
  }

  Widget liveTransition(Entry entry, Animation<double> animation) =>
      ListenableBuilder(
        listenable: widget.store,
        builder: (context, _) => transition(
          _latestEntries[entry.id] ?? widget.store.find(entry.id) ?? entry,
          animation,
          null,
        ),
      );

  Widget transition(
    Entry entry,
    Animation<double> animation,
    String? heading,
  ) => SizeTransition(
    sizeFactor: CurvedAnimation(
      parent: animation,
      curve: Curves.easeInOutCubic,
    ),
    child: FadeTransition(
      opacity: animation,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (heading != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(3, 14, 0, 10),
              child: Row(
                children: [
                  Text(
                    heading,
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontSize: 13,
                      letterSpacing: .3,
                      color: heading == '已超时'
                          ? Theme.of(context).colorScheme.error
                          : Theme.of(context).colorScheme.onSurface,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 7,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.surfaceContainer,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      '${items.where((e) => group(e) == heading).length}',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: EntryTile(
              entry: entry,
              now: widget.now,
              store: widget.store,
              onDetails: () => widget.onDetails(entry),
            ),
          ),
        ],
      ),
    ),
  );
  String group(Entry e) => e.completed
      ? '今日已完成'
      : e.overdue(widget.now)
      ? '已超时'
      : '未完成';
  @override
  Widget build(BuildContext context) => AnimatedList(
    key: listKey,
    initialItemCount: items.length,
    shrinkWrap: true,
    physics: const NeverScrollableScrollPhysics(),
    itemBuilder: (context, index, animation) {
      final e = items[index];
      final heading =
          widget.showGroups &&
              (index == 0 || group(items[index - 1]) != group(e))
          ? group(e)
          : null;
      return transition(e, animation, heading);
    },
  );
}

class EntryTile extends StatelessWidget {
  const EntryTile({
    super.key,
    required this.entry,
    required this.now,
    required this.store,
    required this.onDetails,
  });
  final Entry entry;
  final DateTime now;
  final EntryStore store;
  final VoidCallback onDetails;
  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final overdue = entry.overdue(now);
    final metaColor = overdue ? scheme.error : scheme.onSurfaceVariant;
    final when = entry.kind == EntryKind.schedule && entry.start != null
        ? '${dateLabel(entry.start!, time: !entry.allDay)}${entry.allDay ? ' 全天' : '–${clockLabel(entry.end!)}'}'
        : entry.due != null
        ? 'DDL ${dateLabel(entry.due!)}'
        : '未设截止时间';
    final tags = [
      if (entry.category.isNotEmpty) entry.category,
      if (entry.platform.isNotEmpty) entry.platform,
      if (entry.location.isNotEmpty) entry.location,
      if (entry.repeatRule != 'never') repeatLabels[entry.repeatRule]!,
    ];
    Widget meta(IconData icon, String text, Color color) => Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 12.5, color: color),
        const SizedBox(width: 3),
        Text(text, style: TextStyle(fontSize: 12, color: color)),
      ],
    );
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onDetails,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(10, 10, 6, 10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (entry.isTask)
                IconButton(
                  tooltip: entry.completed ? '恢复未完成' : '标记完成',
                  iconSize: 24,
                  style: IconButton.styleFrom(
                    fixedSize: const Size(44, 44),
                    padding: EdgeInsets.zero,
                  ),
                  onPressed: store.readOnly
                      ? null
                      : () => store.toggle(entry.id),
                  icon: Icon(
                    entry.completed
                        ? Icons.check_circle
                        : Icons.radio_button_unchecked,
                    color: scheme.primary,
                  ),
                )
              else
                Padding(
                  padding: const EdgeInsets.all(10),
                  child: Container(
                    width: 34,
                    height: 34,
                    decoration: BoxDecoration(
                      color: scheme.primaryContainer,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(Icons.notes, size: 19, color: scheme.primary),
                  ),
                ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    AnimatedDefaultTextStyle(
                      duration: MediaQuery.disableAnimationsOf(context)
                          ? Duration.zero
                          : const Duration(milliseconds: 220),
                      style: Theme.of(context).textTheme.titleMedium!.copyWith(
                        fontSize: 17,
                        fontWeight: FontWeight.w600,
                        decoration: entry.completed
                            ? TextDecoration.lineThrough
                            : null,
                        color: scheme.onSurface,
                      ),
                      child: Text(
                        entry.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Wrap(
                      spacing: 10,
                      runSpacing: 3,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        meta(
                          switch (entry.kind) {
                            EntryKind.task => Icons.check_circle_outline,
                            EntryKind.schedule => Icons.calendar_today_outlined,
                            EntryKind.homework => Icons.menu_book_outlined,
                            EntryKind.note => Icons.notes,
                          },
                          entry.kind.label,
                          metaColor,
                        ),
                        if (entry.priority > 0)
                          meta(
                            Icons.flag_outlined,
                            priorities[entry.priority],
                            entry.priority == 2 ? scheme.error : scheme.primary,
                          ),
                        if (entry.isTask) meta(Icons.schedule, when, metaColor),
                      ],
                    ),
                    if (tags.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(
                          tags.join(' · '),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 12, color: metaColor),
                        ),
                      ),
                    if (entry.steps.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      _InlineChecklist(
                        entry: entry,
                        store: store,
                        onDetails: onDetails,
                      ),
                    ],
                  ],
                ),
              ),
              if (entry.isTask && !entry.completed)
                IconButton(
                  tooltip: entry.startedAt == null ? '开始计时' : '暂停计时',
                  iconSize: 22,
                  style: IconButton.styleFrom(
                    fixedSize: const Size(40, 40),
                    padding: EdgeInsets.zero,
                  ),
                  onPressed: store.readOnly
                      ? null
                      : () => store.focus(entry.id),
                  icon: Icon(
                    entry.startedAt == null
                        ? Icons.play_arrow_rounded
                        : Icons.pause_rounded,
                    color: scheme.primary,
                  ),
                )
              else
                const SizedBox(width: 8),
            ],
          ),
        ),
      ),
    );
  }
}

class _InlineChecklist extends StatelessWidget {
  const _InlineChecklist({
    required this.entry,
    required this.store,
    required this.onDetails,
  });
  final Entry entry;
  final EntryStore store;
  final VoidCallback onDetails;

  @override
  Widget build(BuildContext context) {
    final steps = entry.steps;
    final done = steps.where((step) => step.done).length;
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            SizedBox(
              width: 64,
              child: LinearProgressIndicator(
                value: done / steps.length,
                minHeight: 3,
                borderRadius: BorderRadius.circular(2),
                semanticsLabel:
                    '${entry.title}的子事项进度，已完成 $done 项，共 ${steps.length} 项',
              ),
            ),
            Text(
              '$done/${steps.length} 项',
              style: Theme.of(context).textTheme.bodySmall
                  ?.copyWith(color: scheme.onSurfaceVariant),
            ),
          ],
        ),
        ...steps
            .take(3)
            .map(
              (step) => CheckboxListTile(
                key: ValueKey('inline-step-${entry.id}-${step.id}'),
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                dense: true,
                visualDensity: VisualDensity.compact,
                value: step.done,
                title: Text(
                  step.title,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    decoration: step.done ? TextDecoration.lineThrough : null,
                    color: step.done
                        ? scheme.onSurfaceVariant
                        : scheme.onSurface,
                  ),
                ),
                onChanged: store.readOnly
                    ? null
                    : (_) => store.toggleStep(entry.id, step.id),
              ),
            ),
        if (steps.length > 3)
          TextButton(
            onPressed: onDetails,
            child: Text('查看全部 ${steps.length} 个步骤'),
          ),
      ],
    );
  }
}

class EntryDetails extends StatelessWidget {
  const EntryDetails({
    super.key,
    required this.store,
    required this.id,
    required this.onEdit,
  });
  final EntryStore store;
  final String id;
  final VoidCallback onEdit;
  @override
  Widget build(BuildContext context) => Ticking(
    builder: (context) => ListenableBuilder(
      listenable: store,
      builder: (context, _) {
        final entry = store.find(id);
        if (entry == null) return const AlertDialog(content: Text('事项已删除。'));
        return Dialog(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 580),
            child: Padding(
              padding: const EdgeInsets.all(22),
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            entry.title,
                            style: Theme.of(context).textTheme.headlineSmall,
                          ),
                        ),
                        IconButton(
                          tooltip: '关闭',
                          onPressed: () => Navigator.pop(context),
                          icon: const Icon(Icons.close),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Text(
                      [
                        entry.kind.label,
                        priorities[entry.priority],
                        entry.category,
                      ].where((s) => s.isNotEmpty).join(' · '),
                    ),
                    if (entry.due != null)
                      detail('截止时间', dateLabel(entry.due!)),
                    if ([
                      'https',
                      'http',
                    ].contains(Uri.tryParse(entry.platform)?.scheme))
                      TextButton.icon(
                        onPressed: () async {
                          try {
                            await NativeStorage.invokeMethod(
                              'openExternalURL',
                              entry.platform,
                            );
                          } catch (e) {
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(content: Text('无法打开链接：$e')),
                              );
                            }
                          }
                        },
                        icon: const Icon(Icons.open_in_new),
                        label: const Text('打开提交平台'),
                      ),
                    if (entry.start != null)
                      detail(
                        '开始时间',
                        '${dateLabel(entry.start!)}${entry.allDay ? ' 全天' : ''}',
                      ),
                    if (entry.end != null)
                      detail('结束时间', dateLabel(entry.end!)),
                    if (entry.platform.isNotEmpty)
                      detail('处理平台', entry.platform),
                    if (entry.location.isNotEmpty)
                      detail('处理地点', entry.location),
                    if (entry.estimate != null)
                      detail('预计用时', '${entry.estimate} 分钟'),
                    if (entry.body.isNotEmpty) ...[
                      const SizedBox(height: 18),
                      SelectableText(entry.body),
                    ],
                    if (entry.steps.isNotEmpty) ...[
                      const SizedBox(height: 18),
                      const Text(
                        'Checklist',
                        style: TextStyle(fontWeight: FontWeight.w700),
                      ),
                      ...entry.steps.map(
                        (s) => CheckboxListTile(
                          contentPadding: EdgeInsets.zero,
                          controlAffinity: ListTileControlAffinity.leading,
                          value: s.done,
                          title: Text(
                            s.title,
                            style: TextStyle(
                              decoration: s.done
                                  ? TextDecoration.lineThrough
                                  : null,
                            ),
                          ),
                          onChanged: store.readOnly
                              ? null
                              : (_) => store.toggleStep(id, s.id),
                        ),
                      ),
                    ],
                    if (entry.source.isNotEmpty) detail('来源', entry.source),
                    if (entry.repeatRule != 'never')
                      detail('循环', repeatLabels[entry.repeatRule]!),
                    if (entry.isTask)
                      detail(
                        '累计专注',
                        durationLabel(entry.focusSeconds(store.clock())),
                      ),
                    if (AndroidSystem.supported && entry.isTask)
                      AndroidEntryActions(entry: entry, store: store),
                    const SizedBox(height: 20),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        FilledButton.icon(
                          onPressed: store.readOnly
                              ? null
                              : () {
                                  Navigator.pop(context);
                                  onEdit();
                                },
                          icon: const Icon(Icons.edit_outlined),
                          label: const Text('编辑'),
                        ),
                        if (entry.isTask)
                          OutlinedButton(
                            onPressed: store.readOnly
                                ? null
                                : () => store.toggle(id),
                            child: Text(entry.completed ? '恢复未完成' : '标记完成'),
                          ),
                        if (entry.isTask && !entry.completed)
                          OutlinedButton(
                            onPressed: store.readOnly
                                ? null
                                : () => store.focus(id),
                            child: Text(
                              entry.startedAt == null ? '开始计时' : '暂停计时',
                            ),
                          ),
                        TextButton(
                          onPressed: store.readOnly
                              ? null
                              : () async {
                                  final confirmed = await showDialog<bool>(
                                    context: context,
                                    builder: (context) => AlertDialog(
                                      title: const Text('删除这条事项？'),
                                      content: const Text('仅删除这条记录，其他循环事项会保留。'),
                                      actions: [
                                        TextButton(
                                          onPressed: () =>
                                              Navigator.pop(context, false),
                                          child: const Text('取消'),
                                        ),
                                        TextButton(
                                          onPressed: () =>
                                              Navigator.pop(context, true),
                                          child: const Text('删除'),
                                        ),
                                      ],
                                    ),
                                  );
                                  if (confirmed == true && context.mounted) {
                                    store.delete(id);
                                    Navigator.pop(context);
                                  }
                                },
                          child: const Text('删除'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    ),
  );
  Widget detail(String label, String text) => Padding(
    padding: const EdgeInsets.only(top: 10),
    child: Text('$label · $text'),
  );
}

class Ticking extends StatefulWidget {
  const Ticking({super.key, required this.builder});
  final WidgetBuilder builder;
  @override
  State<Ticking> createState() => _TickingState();
}

class _TickingState extends State<Ticking> {
  late final Timer timer;
  @override
  void initState() {
    super.initState();
    timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    timer.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.builder(context);
}

class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.message,
  });
  final IconData icon;
  final String title;
  final String message;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 34, horizontal: 18),
    child: Column(
      children: [
        Icon(icon, size: 38, color: Theme.of(context).colorScheme.primary),
        const SizedBox(height: 14),
        Text(title, style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        Text(
          message,
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
    ),
  );
}

class _AccountSettings extends StatefulWidget {
  const _AccountSettings({required this.store, required this.cloud});
  final EntryStore store;
  final CloudSync cloud;
  @override
  State<_AccountSettings> createState() => _AccountSettingsState();
}

class _AccountSettingsState extends State<_AccountSettings> {
  final emailController = TextEditingController();
  final codeController = TextEditingController();

  @override
  void dispose() {
    emailController.dispose();
    codeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.cloud,
    builder: (context, _) {
      final cloud = widget.cloud;
      if (!cloud.initialized) {
        return const Padding(
          padding: EdgeInsets.all(20),
          child: Text('正在连接账户服务…'),
        );
      }
      if (cloud.initError != null) {
        return Padding(
          padding: const EdgeInsets.all(20),
          child: Text(cloud.initError!),
        );
      }
      return cloud.email == null ? _loginForm(cloud) : _statusForm(cloud);
    },
  );

  Widget _loginForm(CloudSync cloud) => Padding(
    padding: const EdgeInsets.fromLTRB(4, 4, 4, 12),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ListTile(
          leading: const Icon(Icons.cloud_outlined),
          title: const Text('登录 Supabase 账户'),
          subtitle: const Text('同一账号的设备之间自动同步待办、日程、笔记、课表与计时'),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: TextField(
            controller: emailController,
            keyboardType: TextInputType.emailAddress,
            autofillHints: const [AutofillHints.email],
            decoration: const InputDecoration(labelText: '邮箱'),
          ),
        ),
        if (cloud.codeTarget != null)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: TextField(
              controller: codeController,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                labelText: '验证码（已发送至 ${cloud.codeTarget}）',
              ),
            ),
          ),
        if (cloud.loginError != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: Text(
              cloud.loginError!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 8, 0),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(
                onPressed: cloud.sendingCode
                    ? null
                    : () async {
                        if (emailController.text.trim().isEmpty) return;
                        await cloud.sendCode(emailController.text);
                      },
                child: Text(cloud.codeTarget == null ? '发送验证码' : '重新发送'),
              ),
              if (cloud.codeTarget != null)
                TextButton(
                  onPressed: () async {
                    final signedIn = await cloud.verifyCode(
                      codeController.text,
                    );
                    if (signedIn) codeController.clear();
                  },
                  child: const Text('登录'),
                ),
            ],
          ),
        ),
        const Padding(
          padding: EdgeInsets.fromLTRB(16, 4, 16, 0),
          child: Text(
            '验证码邮件由 Supabase 发送，内置邮件服务每小时限 2 封，邮件可能进入垃圾箱。登录状态保存在本机，之后无需重复登录。',
            style: TextStyle(fontSize: 12),
          ),
        ),
      ],
    ),
  );

  Widget _statusForm(CloudSync cloud) {
    final time = cloud.lastSyncedAt;
    final timeLabel = time == null
        ? ''
        : ' · ${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';
    final status = cloud.busy
        ? '正在同步…'
        : cloud.syncError != null
        ? cloud.syncError!
        : time == null
        ? '等待同步'
        : '已同步$timeLabel';
    return Column(
      children: [
        ListTile(
          leading: Icon(
            cloud.syncError == null
                ? Icons.cloud_done_outlined
                : Icons.cloud_off_outlined,
          ),
          title: Text(cloud.email!),
          subtitle: Text(status),
        ),
        Padding(
          padding: const EdgeInsets.only(right: 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(
                onPressed: cloud.busy ? null : () => cloud.syncNow(),
                child: const Text('立即同步'),
              ),
              TextButton(
                onPressed: () => _confirmSignOut(cloud),
                child: const Text('退出登录'),
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        const Padding(
          padding: EdgeInsets.all(16),
          child: Text(
            '登录后，待办、日程、笔记、Checklist、课表、完成状态与计时在本账号设备间自动同步；删除也会同步，不会因另一台设备的旧副本复活。系统日历来源按设备设置。退出登录保留本机数据，账户数据不变。首次在新设备登录会合并两端已有内容，请勿把存有本机数据的设备登录到他人账号。',
            style: TextStyle(fontSize: 12),
          ),
        ),
      ],
    );
  }

  Future<void> _confirmSignOut(CloudSync cloud) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('退出登录？'),
        content: const Text('本机数据保留，账户与其他设备不受影响；本机之后的修改不再同步。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('退出登录'),
          ),
        ],
      ),
    );
    if (confirmed == true) await cloud.signOut();
  }
}

class _LocalSyncSettings extends StatelessWidget {
  const _LocalSyncSettings({required this.localSync});
  final LocalFolderSync localSync;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: localSync,
    builder: (context, _) {
      final cloud = Theme.of(context).colorScheme;
      if (!localSync.initialized) {
        return const Padding(
          padding: EdgeInsets.all(20),
          child: Text('正在读取同步设置…'),
        );
      }
      if (!localSync.connected) {
        return Padding(
          padding: const EdgeInsets.fromLTRB(4, 4, 4, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ListTile(
                leading: const Icon(Icons.folder_shared_outlined),
                title: const Text('共享文件夹自动同步'),
                subtitle: const Text(
                  '选择与 Mikansei（或其它 Mikanseta 设备）相同的文件夹，之后自动合并，无需导入导出。',
                ),
              ),
              if (localSync.error != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
                  child: Text(
                    localSync.error!,
                    style: TextStyle(color: cloud.error),
                  ),
                ),
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton.icon(
                      onPressed: localSync.busy
                          ? null
                          : () => localSync.chooseFolder(),
                      icon: const Icon(Icons.folder_open),
                      label: const Text('选择共享文件夹'),
                    ),
                  ],
                ),
              ),
              const Padding(
                padding: EdgeInsets.fromLTRB(16, 4, 16, 0),
                child: Text(
                  'Apple 设备可以选 iCloud Drive 里的文件夹（例如原版 Mikansei 正在使用的同步文件夹）；要让安卓也一起同步，请选 Google Drive、OneDrive 等三端都能访问的云盘文件夹。',
                  style: TextStyle(fontSize: 12),
                ),
              ),
            ],
          ),
        );
      }
      final time = localSync.lastSyncedAt;
      final timeLabel = time == null
          ? ''
          : ' · ${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';
      final status = localSync.busy
          ? '正在同步…'
          : localSync.error != null
          ? localSync.error!
          : time == null
          ? '等待同步'
          : '已同步$timeLabel';
      return Column(
        children: [
          ListTile(
            leading: Icon(
              localSync.error == null
                  ? Icons.folder_shared
                  : Icons.folder_off_outlined,
            ),
            title: Text(localSync.folderLabel),
            subtitle: Text('${localSync.folderPath ?? ''}\n$status'),
            isThreeLine: true,
          ),
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: Wrap(
              alignment: WrapAlignment.end,
              children: [
                TextButton(
                  onPressed: localSync.busy ? null : () => localSync.syncNow(),
                  child: const Text('立即同步'),
                ),
                TextButton(
                  onPressed: localSync.busy
                      ? null
                      : () => localSync.chooseFolder(),
                  child: const Text('更换文件夹'),
                ),
                TextButton(
                  onPressed: localSync.busy
                      ? null
                      : () => _confirmDisconnect(context),
                  child: const Text('停止同步'),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          const Padding(
            padding: EdgeInsets.all(16),
            child: Text(
              '本机保存后约 2 秒写出同步文件，并每 30 秒检查一次；回到前台和手动“立即同步”也会触发。删除会同步，旧副本不会复活。同一账号的 Supabase 同步与本机同步可以同时使用。',
              style: TextStyle(fontSize: 12),
            ),
          ),
        ],
      );
    },
  );

  Future<void> _confirmDisconnect(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('停止本机同步？'),
        content: const Text('本机数据与同步文件夹中的已有记录都会保留，之后不再自动交换。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('停止同步'),
          ),
        ],
      ),
    );
    if (confirmed == true) await localSync.disconnect();
  }
}
