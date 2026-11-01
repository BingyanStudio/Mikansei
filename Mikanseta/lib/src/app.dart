import 'dart:async';

import 'package:flutter/foundation.dart';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'domain.dart';
import 'store.dart';
import 'haptics.dart';
import 'cloud_sync.dart';
import 'local_folder_sync.dart';
import 'note_editor_page.dart';
import 'planning_page.dart';
import 'theme.dart';
import 'editor.dart';
import 'android_system.dart';
import 'student_tools.dart';
import 'system_services.dart';
import 'pomodoro_store.dart';
import 'pomodoro_page.dart';
import 'focus_window.dart';
import 'entry_widgets.dart';
import 'workspace_ui.dart';

export 'entry_widgets.dart'
    show AnimatedEntryList, EntryDetails, EntryInspector, EntryTile, EmptyState;

const appVersion = '0.7.0 (18)';

class MikansetaApp extends StatelessWidget {
  const MikansetaApp({
    super.key,
    required this.store,
    this.focusStore,
    this.cloud,
    this.localSync,
  });
  final EntryStore store;
  final PomodoroStore? focusStore;
  final CloudSync? cloud;
  final LocalFolderSync? localSync;
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: store,
    builder: (context, _) => MaterialApp(
      title: 'Mikanseta',
      debugShowCheckedModeBanner: false,
      theme: MikanseiTheme.build(Brightness.light),
      darkTheme: MikanseiTheme.build(Brightness.dark),
      locale: const Locale('zh', 'CN'),
      supportedLocales: const [Locale('zh', 'CN'), Locale('en')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      navigatorObservers: [appRouteObserver],
      themeMode: switch (store.preferences["appearance"]) {
        "light" => ThemeMode.light,
        "dark" => ThemeMode.dark,
        _ => ThemeMode.system,
      },
      home: HomePage(
        store: store,
        focusStore: focusStore,
        cloud: cloud,
        localSync: localSync,
      ),
    ),
  );
}

class HomePage extends StatefulWidget {
  const HomePage({
    super.key,
    required this.store,
    this.focusStore,
    this.cloud,
    this.localSync,
  });
  final EntryStore store;
  final PomodoroStore? focusStore;
  final CloudSync? cloud;
  final LocalFolderSync? localSync;
  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> with WidgetsBindingObserver {
  static const _tasksPage = 0;
  static const _schedulePage = 1;
  static const _notesPage = 2;
  static const _settingsPage = 3;
  static const _focusPage = 4;
  static const _coursesPage = 5;
  int page = 0;
  int previousPrimaryPage = _tasksPage;
  EntryKind previousAddContext = EntryKind.task;
  final pageAddContexts = <int, EntryKind>{_tasksPage: EntryKind.task};
  EntryKind addContext = EntryKind.task;
  String? selectedEntryID;
  Timer? _refresh;
  final taskSearchFocus = FocusNode();
  final notesSearchFocus = FocusNode();
  bool calendarSyncing = false;
  bool editing = false;
  bool readingRoutes = false;
  bool drainingEntryRoutes = false;
  bool popupVisible = false;
  final pendingPopups = <Map<String, dynamic>>[];
  final handledPopups = <String>{};
  bool initialCalendarSync = false;
  bool focusRoutesReady = false;
  final pendingFocusRoutes = <Map<String, dynamic>>[];
  final pendingEntryRouteIDs = <String>[];
  int scheduleFocusRouteRevision = 0;
  PomodoroStore? _fallbackFocusStore;
  String? calendarSyncError;
  EntryStore get store => widget.store;
  PomodoroStore get focus => widget.focusStore ?? _fallbackFocusStore!;
  CloudSync? get cloud => widget.cloud;
  LocalFolderSync? get localSync => widget.localSync;

  void selectPrimaryPage(int next) {
    setState(() {
      if (page < 3) pageAddContexts[page] = addContext;
      page = next;
      previousPrimaryPage = next;
      selectedEntryID = null;
      addContext =
          pageAddContexts[next] ??
          switch (next) {
            _schedulePage => EntryKind.schedule,
            _notesPage => EntryKind.note,
            _ => EntryKind.task,
          };
    });
  }

  void openAuxiliaryPage(int next) {
    if (page < 3) {
      previousPrimaryPage = page;
      previousAddContext = addContext;
    }
    setState(() {
      page = next;
      selectedEntryID = null;
    });
  }

  void returnToPrimaryPage() {
    setState(() {
      page = previousPrimaryPage;
      addContext = pageAddContexts[previousPrimaryPage] ?? previousAddContext;
    });
  }

  void setAddContext(EntryKind kind) {
    setState(() {
      addContext = kind;
      pageAddContexts[page] = kind;
    });
  }

  Future<void> openEntry(Entry entry) async {
    final current = store.find(entry.id);
    if (current == null) return;
    if (store.readOnly && current.kind == EntryKind.note) {
      await details(current);
      return;
    }
    if (MediaQuery.sizeOf(context).width >= 1100) {
      setState(() => selectedEntryID = current.id);
    } else {
      await edit(entry: current);
    }
  }

  Future<void> openEntryFromRoute(Entry entry) async {
    final destination = switch (entry.kind) {
      EntryKind.note => _notesPage,
      EntryKind.schedule => _schedulePage,
      _ => _tasksPage,
    };
    if (page != destination) selectPrimaryPage(destination);
    await openEntry(entry);
  }

  Future<void> drainPendingEntryRoutes() async {
    if (!mounted || editing || drainingEntryRoutes) return;
    drainingEntryRoutes = true;
    try {
      while (mounted && !editing && pendingEntryRouteIDs.isNotEmpty) {
        final id = pendingEntryRouteIDs.removeAt(0);
        final entry = store.find(id);
        if (entry != null) await openEntryFromRoute(entry);
      }
    } finally {
      drainingEntryRoutes = false;
      if (mounted && !editing && pendingEntryRouteIDs.isNotEmpty) {
        unawaited(drainPendingEntryRoutes());
      }
    }
  }

  @override
  void initState() {
    super.initState();
    if (widget.focusStore == null) {
      _fallbackFocusStore = PomodoroStore(MemoryPomodoroStorage());
      unawaited(_fallbackFocusStore!.load());
    }
    WidgetsBinding.instance.addObserver(this);
    store.addListener(onStoreReady);
    focus.addListener(onFocusChanged);
    FocusWindowBridge.setActionHandler(handleFocusWindowAction);
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
    _refresh = Timer.periodic(const Duration(minutes: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    store.removeListener(onStoreReady);
    focus.removeListener(onFocusChanged);
    FocusWindowBridge.setActionHandler(null);
    NativeStorage.channel.setMethodCallHandler(null);
    _refresh?.cancel();
    taskSearchFocus.dispose();
    notesSearchFocus.dispose();
    WidgetsBinding.instance.removeObserver(this);
    _fallbackFocusStore?.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      setState(() {});
      focus.refresh();
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
        if (url?.host == 'pomodoro') {
          if (focus.loading) {
            pendingFocusRoutes.add(route);
          } else {
            await handlePomodoroRoute(url!);
          }
          continue;
        }
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
              if (editing) {
                if (!pendingEntryRouteIDs.contains(id)) {
                  pendingEntryRouteIDs.add(id);
                }
              } else {
                await openEntryFromRoute(e);
              }
            }
          }
        } else if (url?.host == "new") {
          final kind =
              EntryKind.values
                  .where((value) => value.name == url?.queryParameters['kind'])
                  .firstOrNull ??
              EntryKind.task;
          selectPrimaryPage(
            kind == EntryKind.note
                ? _notesPage
                : kind == EntryKind.schedule
                ? _schedulePage
                : _tasksPage,
          );
          await edit(kind: kind);
        } else if (url?.host == "today" || url?.host == "tasks") {
          if (url?.host == 'today') scheduleFocusRouteRevision++;
          selectPrimaryPage(url?.host == "tasks" ? _tasksPage : _schedulePage);
        }
      }
    } catch (_) {
      /* A platform without routes keeps the shared UI usable. */
    } finally {
      readingRoutes = false;
    }
  }

  void onFocusChanged() {
    if (defaultTargetPlatform == TargetPlatform.windows ||
        defaultTargetPlatform == TargetPlatform.macOS) {
      FocusWindowBridge.updateQuietly(focus.widgetSnapshot);
    }
    if (!focus.loading && !focusRoutesReady) {
      focusRoutesReady = true;
      unawaited(processPendingFocusRoutes());
    }
  }

  Future<void> processPendingFocusRoutes() async {
    if (focus.loading || !mounted || pendingFocusRoutes.isEmpty) return;
    final routes = List<Map<String, dynamic>>.from(pendingFocusRoutes);
    pendingFocusRoutes.clear();
    for (final route in routes) {
      final url = Uri.tryParse(route['url'] as String? ?? '');
      if (url?.host == 'pomodoro') await handlePomodoroRoute(url!);
    }
  }

  Future<void> handlePomodoroRoute(Uri url) async {
    final action = url.queryParameters['action'] ?? '';
    final session = url.queryParameters['session'];
    if (action == 'open' && session == null) {
      if (mounted) openAuxiliaryPage(_focusPage);
    } else if (session != null && session == focus.active?.id) {
      await focus.handleRoute(action: action, sessionID: session);
      if (mounted) openAuxiliaryPage(_focusPage);
    }
  }

  Future<void> handleFocusWindowAction(Map<String, dynamic> action) async {
    final name = action['action'] as String? ?? '';
    final session = action['session'] as String?;
    if (name == 'open') {
      if (session == null || session == focus.active?.id) {
        if (mounted) openAuxiliaryPage(_focusPage);
      }
      return;
    }
    if (session == null || session != focus.active?.id) return;
    await focus.handleRoute(action: name, sessionID: session);
    if (mounted) openAuxiliaryPage(_focusPage);
  }

  Future<void> openFocusWindow() async {
    try {
      await FocusWindowBridge.show(focus.widgetSnapshot);
    } catch (error) {
      if (mounted) message('浮动计时器无法打开：$error');
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
    if (store.loading || editing || (store.readOnly && entry == null)) return;
    // Notes open a full Apple-Notes style page instead of the dialog editor;
    // every other kind keeps the dialog.
    final isNote = entry?.kind == EntryKind.note || kind == EntryKind.note;
    if (isNote) {
      editing = true;
      try {
        await Navigator.of(context, rootNavigator: true).push(
          MaterialPageRoute<void>(
            fullscreenDialog: true,
            builder: (context) => NoteEditorPage(
              store: store,
              entry: entry,
              isNew: entry == null,
            ),
          ),
        );
      } finally {
        editing = false;
        if (mounted) syncCalendar();
        if (mounted) unawaited(drainPendingEntryRoutes());
      }
      return;
    }
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
      if (mounted) unawaited(drainPendingEntryRoutes());
    }
  }

  Future<void> details(Entry entry) async {
    if (entry.kind == EntryKind.note && !store.readOnly) {
      await edit(entry: store.find(entry.id));
      return;
    }
    await showDialog<void>(
      context: context,
      builder: (context) => EntryDetails(
        store: store,
        id: entry.id,
        onEdit: () => edit(entry: store.find(entry.id)),
      ),
    );
  }

  Future<void> openPlanning() async {
    await Navigator.of(context, rootNavigator: true).push(
      MaterialPageRoute<void>(
        fullscreenDialog: true,
        builder: (context) => PlanningPage(
          store: store,
          onDetails: details,
          onEdit: (entry) {
            final current = store.find(entry.id);
            if (current != null) edit(entry: current);
          },
        ),
      ),
    );
  }

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
              final kind = switch (page) {
                _tasksPage => addContext,
                _schedulePage => EntryKind.schedule,
                _notesPage => EntryKind.note,
                _ => EntryKind.task,
              };
              if (!store.readOnly) edit(kind: kind);
              return null;
            },
          ),
          SearchIntent: CallbackAction<SearchIntent>(
            onInvoke: (_) {
              if (page == _tasksPage || page == _notesPage) {
                (page == _tasksPage ? taskSearchFocus : notesSearchFocus)
                    .requestFocus();
              }
              return null;
            },
          ),
        },
        child: Focus(
          autofocus: true,
          child: LayoutBuilder(
            builder: (context, bounds) {
              final desktop = bounds.maxWidth >= 760;
              final wideDesktop = bounds.maxWidth >= 1100;
              const railPages = [
                _tasksPage,
                _schedulePage,
                _notesPage,
                _coursesPage,
                _focusPage,
                _settingsPage,
              ];
              const railTitles = ['待办', '日程', '笔记', '课表', '专注', '设置'];
              const railIcons = [
                Icons.checklist_rounded,
                Icons.calendar_month_outlined,
                Icons.notes_rounded,
                Icons.school_outlined,
                Icons.center_focus_strong,
                Icons.tune_rounded,
              ];
              final title = switch (page) {
                _tasksPage => '待办',
                _schedulePage => '日程',
                _notesPage => '笔记',
                _settingsPage => '设置',
                _focusPage => '专注',
                _coursesPage => '课表与下课登记',
                _ => '待办',
              };
              return PopScope<Object?>(
                canPop: page < _settingsPage,
                onPopInvokedWithResult: (didPop, _) {
                  if (!didPop && page >= _settingsPage) {
                    returnToPrimaryPage();
                  }
                },
                child: Scaffold(
                  appBar: AppBar(
                    leading: !desktop && page >= _settingsPage
                        ? IconButton(
                            key: const ValueKey('back-to-main'),
                            tooltip: '返回',
                            onPressed: returnToPrimaryPage,
                            icon: const Icon(Icons.arrow_back),
                          )
                        : null,
                    title: Text(title),
                    actions: [
                      if (page < _settingsPage) ...[
                        IconButton(
                          key: const ValueKey('settings-entry'),
                          tooltip: '设置',
                          onPressed: () => openAuxiliaryPage(_settingsPage),
                          icon: const Icon(Icons.tune_rounded),
                        ),
                        IconButton(
                          key: const ValueKey('focus-entry'),
                          tooltip: '专注',
                          onPressed: () => openAuxiliaryPage(_focusPage),
                          icon: const Icon(Icons.center_focus_strong),
                        ),
                      ],
                      if (page == _focusPage && desktop)
                        ListenableBuilder(
                          listenable: focus,
                          builder: (context, _) => focus.active == null
                              ? const SizedBox.shrink()
                              : IconButton(
                                  key: const ValueKey('focus-floating-window'),
                                  tooltip: '打开浮动计时器',
                                  onPressed: openFocusWindow,
                                  icon: const Icon(
                                    Icons.picture_in_picture_alt_outlined,
                                  ),
                                ),
                        ),
                      if (page < _settingsPage)
                        Padding(
                          padding: const EdgeInsets.only(right: 12),
                          child: desktop
                              ? FilledButton.icon(
                                  key: const ValueKey('add-entry'),
                                  onPressed: store.readOnly
                                      ? null
                                      : () => edit(kind: addContext),
                                  icon: const Icon(Icons.add),
                                  label: const Text('添加事项'),
                                )
                              : IconButton.filled(
                                  key: const ValueKey('add-entry'),
                                  tooltip: '添加事项',
                                  onPressed: store.readOnly
                                      ? null
                                      : () => edit(kind: addContext),
                                  icon: const Icon(Icons.add),
                                ),
                        ),
                    ],
                  ),
                  bottomNavigationBar: !desktop && page < _settingsPage
                      ? NavigationBar(
                          key: const ValueKey('main-tab-navigation'),
                          selectedIndex: page,
                          onDestinationSelected: selectPrimaryPage,
                          destinations: const [
                            NavigationDestination(
                              key: ValueKey('main-tab-tasks'),
                              icon: Icon(Icons.checklist_rounded),
                              label: '待办',
                            ),
                            NavigationDestination(
                              key: ValueKey('main-tab-schedule'),
                              icon: Icon(Icons.calendar_month_outlined),
                              label: '日程',
                            ),
                            NavigationDestination(
                              key: ValueKey('main-tab-notes'),
                              icon: Icon(Icons.notes_rounded),
                              label: '笔记',
                            ),
                          ],
                        )
                      : null,
                  body: Row(
                    children: [
                      if (desktop)
                        NavigationRail(
                          selectedIndex: railPages.indexOf(page),
                          onDestinationSelected: (index) {
                            final next = railPages[index];
                            if (next < _settingsPage) {
                              selectPrimaryPage(next);
                            } else {
                              openAuxiliaryPage(next);
                            }
                          },
                          labelType: NavigationRailLabelType.all,
                          destinations: List.generate(
                            railPages.length,
                            (index) => NavigationRailDestination(
                              icon: Icon(
                                railIcons[index],
                                key: ValueKey(
                                  'desktop-tab-${railPages[index]}',
                                ),
                              ),
                              label: Text(railTitles[index]),
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
                                child: Center(
                                  child: CircularProgressIndicator(),
                                ),
                              )
                            else
                              Expanded(
                                child: Center(
                                  child: ConstrainedBox(
                                    constraints: BoxConstraints(
                                      maxWidth: wideDesktop ? 1500 : 900,
                                    ),
                                    child: workspacePage(
                                      wideDesktop: wideDesktop,
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ),
    ),
  );

  Widget workspacePage({required bool wideDesktop}) {
    final mainPage = page < 3 ? page : previousPrimaryPage;
    final primaryPages = <Widget>[
      TickerMode(
        enabled: mainPage == _tasksPage,
        child: TaskWorkspacePage(
          key: const ValueKey('tasks-workspace'),
          store: store,
          searchFocus: taskSearchFocus,
          onEdit: (entry) => edit(entry: store.find(entry.id)),
          onOpen: openEntry,
          onDetails: details,
          onAdd: (kind) => edit(kind: kind),
          onContextChanged: setAddContext,
        ),
      ),
      TickerMode(
        enabled: mainPage == _schedulePage,
        child: ScheduleWorkspacePage(
          key: const ValueKey('schedule-workspace'),
          store: store,
          focusRouteRevision: scheduleFocusRouteRevision,
          onEdit: (entry) => edit(entry: store.find(entry.id)),
          onOpen: openEntry,
          onDetails: details,
          onAdd: (kind) => edit(kind: kind),
          onCreateOnDate: (start, end) =>
              edit(kind: EntryKind.schedule, start: start, end: end),
          onContextChanged: setAddContext,
          onPlanning: openPlanning,
        ),
      ),
      TickerMode(
        enabled: mainPage == _notesPage,
        child: NotesWorkspacePage(
          key: const ValueKey('notes-workspace'),
          store: store,
          searchFocus: notesSearchFocus,
          onEdit: (entry) => edit(entry: store.find(entry.id)),
          onOpen: openEntry,
          onDetails: details,
          onAdd: (kind) => edit(kind: kind),
        ),
      ),
    ];
    final primaryContent = IndexedStack(
      index: mainPage,
      children: primaryPages,
    );
    final selected = page < 3 && selectedEntryID != null
        ? store.find(selectedEntryID!)
        : null;
    final mainWorkspace = Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Flexible(
          flex: wideDesktop ? 0 : 1,
          fit: wideDesktop ? FlexFit.loose : FlexFit.tight,
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: wideDesktop ? 430 : double.infinity,
            ),
            child: primaryContent,
          ),
        ),
        if (wideDesktop) ...[
          VerticalDivider(
            width: 1,
            color: Theme.of(context).colorScheme.outline.withValues(alpha: .2),
          ),
          Expanded(
            child: selected == null
                ? const Center(
                    child: EmptyState(
                      icon: Icons.checklist_rounded,
                      title: '选一件事，开始做',
                      message: '清单在左侧，详情在这里。',
                    ),
                  )
                : EntryInspector(
                    entry: selected,
                    store: store,
                    onEdit: () => edit(entry: store.find(selected.id)),
                    onDetails: () => details(selected),
                  ),
          ),
        ],
      ],
    );

    return IndexedStack(
      index: page < 3 ? 0 : page - _settingsPage + 1,
      children: [
        TickerMode(enabled: page < 3, child: mainWorkspace),
        TickerMode(enabled: page == _settingsPage, child: settings()),
        TickerMode(
          enabled: page == _focusPage,
          child: PomodoroPage(
            focus: focus,
            entries: store,
            onOpenFloatingWindow: openFocusWindow,
          ),
        ),
        TickerMode(
          enabled: page == _coursesPage,
          child: CoursesPage(store: store),
        ),
      ],
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
              const Text('Mikansei 的 Flutter 版本'),
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
            child: Text('当前版本暂未启用账户同步。'),
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
