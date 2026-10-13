import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'domain.dart';
import 'store.dart';
import 'theme.dart';
import 'editor.dart';

const appVersion = '0.1.0 (1)';

class MikansetaApp extends StatelessWidget {
  const MikansetaApp({super.key, required this.store});
  final EntryStore store;
  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Mikanseta',
    debugShowCheckedModeBanner: false,
    theme: KraftTheme.build(Brightness.light),
    darkTheme: KraftTheme.build(Brightness.dark),
    locale: const Locale('zh', 'CN'),
    supportedLocales: const [Locale('zh', 'CN'), Locale('en')],
    localizationsDelegates: GlobalMaterialLocalizations.delegates,
    home: HomePage(store: store),
  );
}

class HomePage extends StatefulWidget {
  const HomePage({super.key, required this.store});
  final EntryStore store;
  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> with WidgetsBindingObserver {
  int page = 0;
  String query = '';
  String filter = '全部';
  DateTime selectedDate = dayOf(DateTime.now());
  DateTime month = DateTime(DateTime.now().year, DateTime.now().month);
  Timer? _refresh;
  final searchFocus = FocusNode();
  final searchController = TextEditingController();
  EntryStore get store => widget.store;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _refresh = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _refresh?.cancel();
    searchFocus.dispose();
    searchController.dispose();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) setState(() {});
  }

  Future<void> edit({Entry? entry, EntryKind? kind, DateTime? start}) async {
    if (store.readOnly) return;
    await showDialog<void>(
      context: context,
      builder: (context) =>
          EntryEditor(store: store, entry: entry, kind: kind, start: start),
    );
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
                    children: [
                      Text(
                        page == 0 ? 'Mikanseta' : titles[page],
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      if (page == 0)
                        Text(
                          '${dateLabel(DateTime.now(), time: false)} · 一件一件，慢慢完成',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                    ],
                  ),
                  actions: [
                    if (desktop && page != 4)
                      Padding(
                        padding: const EdgeInsets.only(right: 18),
                        child: Tooltip(
                          message: '添加事项',
                          child: FilledButton.icon(
                            onPressed: store.readOnly
                                ? null
                                : () => edit(
                                    kind: page == 3 ? EntryKind.note : null,
                                  ),
                            icon: const Icon(Icons.add),
                            label: const Text('添加事项'),
                          ),
                        ),
                      ),
                  ],
                ),
                bottomNavigationBar: desktop
                    ? null
                    : NavigationBar(
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
                floatingActionButton: !desktop && page != 4
                    ? FloatingActionButton(
                        tooltip: '添加事项',
                        onPressed: store.readOnly
                            ? null
                            : () => edit(
                                kind: page == 2
                                    ? EntryKind.schedule
                                    : page == 3
                                    ? EntryKind.note
                                    : null,
                              ),
                        child: const Icon(Icons.add),
                      )
                    : null,
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
                                  child: page == 2
                                      ? calendar(desktop)
                                      : page == 4
                                      ? settings()
                                      : taskPage(),
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
        '历史' => board.history,
        _ => board.visible,
      };
    }
    entries = entries.where((e) => e.matches(query)).toList();
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 100),
      children: [
        if (page == 0) ...[
          Row(
            children: [
              Expanded(
                child: metric(
                  '${board.open.length}',
                  '未完成',
                  Icons.radio_button_unchecked,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: metric('${board.overdue.length}', '已超时', Icons.schedule),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: metric(
                  '${board.finishedToday.length}',
                  '今日完成',
                  Icons.done,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (store.running case final Entry running) ...[
            Card(
              child: ListTile(
                leading: const Icon(Icons.timelapse),
                title: Text(
                  '正在做 ${running.title}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                subtitle: Text(
                  durationLabel(running.focusSeconds(now)),
                  style: const TextStyle(
                    fontFeatures: [FontFeature.tabularFigures()],
                    fontSize: 20,
                  ),
                ),
                trailing: IconButton(
                  tooltip: '暂停计时',
                  onPressed: store.readOnly
                      ? null
                      : () => store.focus(running.id),
                  icon: const Icon(Icons.pause_rounded),
                ),
                onTap: () => details(running),
              ),
            ),
            const SizedBox(height: 16),
          ],
        ],
        TextField(
          controller: searchController,
          focusNode: searchFocus,
          onChanged: (value) => setState(() => query = value),
          decoration: InputDecoration(
            hintText: '搜索事项、科目或提交平台',
            prefixIcon: const Icon(Icons.search),
            suffixIcon: query.isEmpty
                ? null
                : IconButton(
                    tooltip: '清除搜索',
                    icon: const Icon(Icons.close),
                    onPressed: () {
                      searchController.clear();
                      setState(() => query = '');
                    },
                  ),
          ),
        ),
        const SizedBox(height: 14),
        if (page == 1) ...[
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: ['全部', '已超时', '紧急', '历史']
                .map(
                  (label) => ChoiceChip(
                    label: Text(
                      label == '已超时' ? '$label ${board.overdue.length}' : label,
                    ),
                    selected: filter == label,
                    onSelected: (_) => setState(() => filter = label),
                  ),
                )
                .toList(),
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

  Widget metric(String value, String label, IconData icon) => Card(
    child: Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: Theme.of(context).colorScheme.primary),
          const SizedBox(height: 8),
          Text(
            value,
            style: Theme.of(context).textTheme.headlineSmall
                ?.copyWith(fontWeight: FontWeight.w700),
          ),
          Text(label, style: Theme.of(context).textTheme.bodySmall),
        ],
      ),
    ),
  );
  Widget calendar(bool desktop) {
    final lastDay = DateTime(month.year, month.month + 1, 0).day;
    final offset = month.weekday - 1;
    final items =
        store.entries.where((e) => e.isTask && e.onDay(selectedDate)).toList()
          ..sort(entryOrder);
    final monthView = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            IconButton(
              tooltip: '上个月',
              icon: const Icon(Icons.chevron_left),
              onPressed: () =>
                  setState(() => month = DateTime(month.year, month.month - 1)),
            ),
            Expanded(
              child: Center(
                child: Text(
                  '${month.year} 年 ${month.month} 月',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ),
            ),
            IconButton(
              tooltip: '下个月',
              icon: const Icon(Icons.chevron_right),
              onPressed: () =>
                  setState(() => month = DateTime(month.year, month.month + 1)),
            ),
            TextButton(
              onPressed: () => setState(() {
                selectedDate = dayOf(DateTime.now());
                month = DateTime(selectedDate.year, selectedDate.month);
              }),
              child: const Text('今天'),
            ),
          ],
        ),
        Row(
          children: ['一', '二', '三', '四', '五', '六', '日']
              .map(
                (d) => Expanded(
                  child: Center(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      child: Text(d),
                    ),
                  ),
                ),
              )
              .toList(),
        ),
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 7,
            mainAxisExtent: 54,
          ),
          itemCount: ((lastDay + offset + 6) ~/ 7) * 7,
          itemBuilder: (context, index) {
            final day = index - offset + 1;
            if (day < 1 || day > lastDay) return const SizedBox.shrink();
            final date = DateTime(month.year, month.month, day);
            final selected = sameDay(date, selectedDate);
            final hasEntries = store.entries.any(
              (e) => e.isTask && !e.completed && e.onDay(date),
            );
            final scheme = Theme.of(context).colorScheme;
            return Semantics(
              label: '${date.month} 月 $day 日${hasEntries ? '，有未完成事项' : ''}',
              button: true,
              selected: selected,
              child: InkWell(
                borderRadius: BorderRadius.circular(14),
                onTap: () => setState(() => selectedDate = date),
                onLongPress: store.readOnly
                    ? null
                    : () => edit(
                        kind: EntryKind.schedule,
                        start: DateTime(date.year, date.month, date.day, 9),
                      ),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  margin: const EdgeInsets.all(3),
                  decoration: BoxDecoration(
                    color: selected ? scheme.primary : Colors.transparent,
                    borderRadius: BorderRadius.circular(14),
                    border: sameDay(date, DateTime.now())
                        ? Border.all(color: scheme.primary)
                        : null,
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        '$day',
                        style: TextStyle(
                          color: selected ? scheme.onPrimary : scheme.onSurface,
                          fontWeight: selected
                              ? FontWeight.bold
                              : FontWeight.normal,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Container(
                        width: 4,
                        height: 4,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: hasEntries
                              ? selected
                                    ? scheme.onPrimary
                                    : scheme.primary
                              : Colors.transparent,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
        const SizedBox(height: 12),
        Text('长按日期，快速添加日程', style: Theme.of(context).textTheme.bodySmall),
      ],
    );
    final agenda = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                '${dateLabel(selectedDate, time: false)} 的安排',
                style: Theme.of(context).textTheme.titleLarge,
              ),
            ),
            IconButton(
              tooltip: '添加当天日程',
              onPressed: store.readOnly
                  ? null
                  : () => edit(
                      kind: EntryKind.schedule,
                      start: DateTime(
                        selectedDate.year,
                        selectedDate.month,
                        selectedDate.day,
                        9,
                      ),
                    ),
              icon: const Icon(Icons.add),
            ),
          ],
        ),
        if (items.isEmpty)
          const EmptyState(
            icon: Icons.event_available_outlined,
            title: '这一天没有安排',
            message: '长按日期，或者点 + 记下一段时间。',
          )
        else
          AnimatedEntryList(
            entries: items,
            now: store.clock(),
            store: store,
            onDetails: details,
            showGroups: false,
          ),
      ],
    );
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 100),
      child: desktop
          ? Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: monthView),
                const SizedBox(width: 32),
                Expanded(child: agenda),
              ],
            )
          : Column(children: [monthView, const SizedBox(height: 24), agenda]),
    );
  }

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
              Text('清单、作业、笔记、Checklist、DDL 排序、当天完成记录、日程起止时间、循环事项、专注计时、备份导入导出。'),
              SizedBox(height: 18),
              Text('后续接入', style: TextStyle(fontWeight: FontWeight.w700)),
              SizedBox(height: 6),
              Text('系统弹窗与闹钟提醒、课后登记、Apple 日历双向同步、小组件与实时活动、iCloud Drive 同步。'),
              SizedBox(height: 12),
              Text('本版的 DDL 是清单记录，暂不会发出系统提醒。以上原生能力仍可在 Mikansei 中使用。'),
            ],
          ),
        ),
      ),
      const SizedBox(height: 18),
      const Text('两个 App 的本地数据分别保存。导入备份会复制事项，不会自动共享修改。主题跟随系统切换浅色与深色。'),
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
  @override
  void initState() {
    super.initState();
    items = List.of(widget.entries);
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
  }

  void remove(int index, {Entry? replacement}) {
    final removed = replacement ?? items[index];
    items.removeAt(index);
    listKey.currentState?.removeItem(
      index,
      (context, animation) => transition(removed, animation, null),
      duration: motion,
    );
  }

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
              child: Text(
                heading,
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  color: heading == '已超时'
                      ? Theme.of(context).colorScheme.error
                      : null,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
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
    final when = entry.kind == EntryKind.schedule && entry.start != null
        ? '${dateLabel(entry.start!, time: !entry.allDay)}${entry.allDay ? ' 全天' : '–${clockLabel(entry.end!)}'}'
        : entry.due != null
        ? 'DDL ${dateLabel(entry.due!)}'
        : '未设截止时间';
    final details = [
      entry.kind.label,
      if (entry.priority > 0) priorities[entry.priority],
      if (entry.isTask) when,
      if (entry.category.isNotEmpty) entry.category,
      if (entry.platform.isNotEmpty) entry.platform,
      if (entry.location.isNotEmpty) entry.location,
      if (entry.steps.isNotEmpty)
        '${entry.steps.where((s) => s.done).length}/${entry.steps.length}',
      if (entry.repeatRule != 'never') repeatLabels[entry.repeatRule]!,
    ];
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onDetails,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(6, 8, 6, 8),
          child: Row(
            children: [
              if (entry.isTask)
                IconButton(
                  tooltip: entry.completed ? '恢复未完成' : '标记完成',
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
                  padding: const EdgeInsets.all(12),
                  child: Icon(Icons.notes, color: scheme.primary),
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
                    Text(
                      details.join(' · '),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: entry.overdue(now)
                            ? scheme.error
                            : scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              if (entry.isTask && !entry.completed)
                IconButton(
                  tooltip: entry.startedAt == null ? '开始计时' : '暂停计时',
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
                const SizedBox(width: 12),
            ],
          ),
        ),
      ),
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
