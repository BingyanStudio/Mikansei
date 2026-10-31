import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'pomodoro_store.dart';
import 'store.dart';

class PomodoroPage extends StatefulWidget {
  const PomodoroPage({
    super.key,
    required this.focus,
    required this.entries,
    required this.onOpenFloatingWindow,
  });

  final PomodoroStore focus;
  final EntryStore entries;
  final Future<void> Function() onOpenFloatingWindow;

  @override
  State<PomodoroPage> createState() => _PomodoroPageState();
}

class _PomodoroPageState extends State<PomodoroPage> {
  final subjectController = TextEditingController();
  PomodoroMode mode = PomodoroMode.countdown;
  int minutes = 25;
  String? linkedEntryID;
  String? formError;

  PomodoroStore get focus => widget.focus;

  @override
  void dispose() {
    subjectController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: focus,
    builder: (context, _) {
      final active = focus.active;
      final link = active == null
          ? null
          : widget.entries.find(active.linkedEntryID ?? '');
      final history = focus.history.take(30).toList();
      final desktopFloat =
          !kIsWeb &&
          (defaultTargetPlatform == TargetPlatform.windows ||
              defaultTargetPlatform == TargetPlatform.macOS);
      return ListView(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
        children: [
          if (active == null) ...[
            _summaryCard(context),
            const SizedBox(height: 16),
          ] else ...[
            _activeCard(context, active, link?.title, desktopFloat),
            const SizedBox(height: 16),
          ],
          if (focus.error != null)
            _messageCard(context, focus.error!, error: true),
          if (focus.saveError != null)
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: _messageCard(
                context,
                focus.saveError!,
                error: true,
                action: TextButton(
                  onPressed: focus.retrySave,
                  child: const Text('重试'),
                ),
              ),
            ),
          if (active == null) ...[
            _newSessionCard(context),
            const SizedBox(height: 16),
            _historyCard(context, history),
          ] else ...[
            _summaryCard(context),
            const SizedBox(height: 16),
            _historyCard(context, history),
          ],
        ],
      );
    },
  );

  Widget _summaryCard(BuildContext context) {
    final color = Theme.of(context).colorScheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 12),
        child: Column(
          children: [
            Row(
              children: [
                Expanded(
                  child: _metric(
                    focus.todayCompletedCount.toString(),
                    '今日完成',
                    Icons.check_circle_outline,
                  ),
                ),
                Container(
                  width: 1,
                  height: 42,
                  color: color.outline.withValues(alpha: .18),
                ),
                Expanded(
                  child: _metric(
                    _durationLabel(focus.todayRecordedSeconds),
                    '今日记录',
                    Icons.timelapse,
                  ),
                ),
                Container(
                  width: 1,
                  height: 42,
                  color: color.outline.withValues(alpha: .18),
                ),
                Expanded(
                  child: _metric(
                    focus.history.length.toString(),
                    '累计记录',
                    Icons.history,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              '今日统计按会话结束日期计算',
              style: Theme.of(context).textTheme.bodySmall
                  ?.copyWith(color: color.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }

  Widget _metric(String value, String label, IconData icon) => Column(
    children: [
      Icon(icon, size: 18, color: Theme.of(context).colorScheme.primary),
      const SizedBox(height: 6),
      Text(
        value,
        style: Theme.of(context).textTheme.titleMedium
            ?.copyWith(fontWeight: FontWeight.w700),
      ),
      const SizedBox(height: 2),
      Text(
        label,
        style: Theme.of(context).textTheme.bodySmall,
        textAlign: TextAlign.center,
      ),
    ],
  );

  Widget _newSessionCard(BuildContext context) {
    final color = Theme.of(context).colorScheme;
    final activeEntries = widget.entries.entries
        .where((entry) => entry.isTask && !entry.completed)
        .toList();
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('开始一段专注', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 6),
            Text(
              '每段专注都单独保存在本机，不会写入待办或云端清单。',
              style: Theme.of(context).textTheme.bodyMedium
                  ?.copyWith(color: color.onSurfaceVariant),
            ),
            const SizedBox(height: 20),
            TextField(
              controller: subjectController,
              maxLength: 120,
              textInputAction: TextInputAction.done,
              decoration: const InputDecoration(
                labelText: '专注主题（必填）',
                hintText: '例如：复习英语单词',
                prefixIcon: Icon(Icons.subject_outlined),
              ),
              onChanged: (_) => setState(() => formError = null),
            ),
            const SizedBox(height: 8),
            SegmentedButton<PomodoroMode>(
              segments: const [
                ButtonSegment(
                  value: PomodoroMode.countdown,
                  icon: Icon(Icons.hourglass_bottom),
                  label: Text('倒计时'),
                ),
                ButtonSegment(
                  value: PomodoroMode.countUp,
                  icon: Icon(Icons.timer_outlined),
                  label: Text('正计时'),
                ),
              ],
              selected: {mode},
              onSelectionChanged: (selected) =>
                  setState(() => mode = selected.first),
            ),
            if (mode == PomodoroMode.countdown) ...[
              const SizedBox(height: 20),
              Row(
                children: [
                  Text('时长', style: Theme.of(context).textTheme.titleSmall),
                  const Spacer(),
                  Text(
                    '$minutes 分钟',
                    style: Theme.of(context).textTheme.titleMedium
                        ?.copyWith(fontWeight: FontWeight.w700),
                  ),
                ],
              ),
              Slider(
                value: minutes.toDouble(),
                min: 1,
                max: 180,
                divisions: 179,
                label: '$minutes 分钟',
                onChanged: (value) => setState(() => minutes = value.round()),
              ),
              Wrap(
                spacing: 8,
                children: [15, 25, 45, 60]
                    .map(
                      (value) => ChoiceChip(
                        label: Text('$value 分钟'),
                        selected: minutes == value,
                        onSelected: (_) => setState(() => minutes = value),
                      ),
                    )
                    .toList(),
              ),
            ],
            if (activeEntries.isNotEmpty) ...[
              const SizedBox(height: 16),
              DropdownButtonFormField<String?>(
                initialValue: linkedEntryID,
                isExpanded: true,
                decoration: const InputDecoration(
                  labelText: '关联待办（可选）',
                  prefixIcon: Icon(Icons.link),
                ),
                items: [
                  const DropdownMenuItem<String?>(
                    value: null,
                    child: Text('不关联待办'),
                  ),
                  ...activeEntries.map(
                    (entry) => DropdownMenuItem<String?>(
                      value: entry.id,
                      child: Text(
                        entry.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
                ],
                onChanged: (value) => setState(() => linkedEntryID = value),
              ),
            ],
            if (formError != null) ...[
              const SizedBox(height: 10),
              Text(formError!, style: TextStyle(color: color.error)),
            ],
            const SizedBox(height: 18),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton.icon(
                onPressed: focus.loading || focus.readOnly
                    ? null
                    : () async {
                        if (subjectController.text.trim().isEmpty) {
                          setState(() => formError = '请先填写专注主题。');
                          return;
                        }
                        final started = await focus.start(
                          subject: subjectController.text,
                          mode: mode,
                          minutes: minutes,
                          linkedEntryID: linkedEntryID,
                        );
                        if (!started && mounted) {
                          setState(() => formError = '专注暂时无法开始，请检查本机保存状态。');
                        }
                      },
                icon: const Icon(Icons.play_arrow_rounded),
                label: const Text('开始专注'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _activeCard(
    BuildContext context,
    PomodoroRun run,
    String? linkedTitle,
    bool desktopFloat,
  ) => LayoutBuilder(
    builder: (context, constraints) {
      final color = Theme.of(context).colorScheme;
      final elapsed = focus.activeElapsedSeconds;
      final displayed = run.mode == PomodoroMode.countdown
          ? focus.activeRemainingSeconds.ceilToDouble()
          : elapsed.floorToDouble();
      final paused = run.runningSince == null;
      final wide = constraints.maxWidth >= 680;
      final clockSize = (constraints.maxWidth * .22).clamp(88.0, 176.0);
      return Card(
        color: color.primaryContainer,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(color: color.outline.withValues(alpha: .35)),
        ),
        child: SizedBox(
          height: wide ? 520 : 420,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 24, 24, 20),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  children: [
                    Row(
                      children: [
                        Icon(Icons.center_focus_strong, color: color.primary),
                        const SizedBox(width: 9),
                        Expanded(
                          child: Text(
                            run.subject,
                            style: Theme.of(context).textTheme.titleLarge
                                ?.copyWith(fontWeight: FontWeight.w700),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        Chip(
                          label: Text(
                            run.mode == PomodoroMode.countdown ? '倒计时' : '正计时',
                          ),
                        ),
                        if (desktopFloat)
                          IconButton(
                            tooltip: '打开浮动计时器',
                            onPressed: widget.onOpenFloatingWindow,
                            icon: const Icon(
                              Icons.picture_in_picture_alt_outlined,
                            ),
                          ),
                      ],
                    ),
                    if (linkedTitle != null)
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Padding(
                          padding: const EdgeInsets.only(left: 34, top: 2),
                          child: Text(
                            '关联待办 · $linkedTitle',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.bodySmall
                                ?.copyWith(color: color.onSurfaceVariant),
                          ),
                        ),
                      ),
                  ],
                ),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    _clockLabel(displayed),
                    style: Theme.of(context).textTheme.displayLarge?.copyWith(
                      fontFeatures: const [FontFeature.tabularFigures()],
                      fontSize: clockSize,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 2,
                    ),
                  ),
                ),
                Column(
                  children: [
                    Text(
                      paused
                          ? '已暂停 · 暂停时间不计入专注'
                          : run.mode == PomodoroMode.countdown
                          ? '剩余时间'
                          : '已专注',
                      style: Theme.of(context).textTheme.bodyMedium
                          ?.copyWith(color: color.onSurfaceVariant),
                    ),
                    if (run.mode == PomodoroMode.countdown && !paused)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(
                          '到时会自动结束并记录完成',
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(color: color.onSurfaceVariant),
                        ),
                      ),
                    const SizedBox(height: 16),
                    SizedBox(
                      width: (constraints.maxWidth - 48)
                          .clamp(0.0, 420.0)
                          .toDouble(),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          SizedBox(
                            height: 54,
                            child: FilledButton.icon(
                              onPressed: paused ? focus.resume : focus.pause,
                              icon: Icon(
                                paused
                                    ? Icons.play_arrow_rounded
                                    : Icons.pause_rounded,
                              ),
                              label: Text(paused ? '继续' : '暂停'),
                            ),
                          ),
                          const SizedBox(height: 10),
                          SizedBox(
                            height: 54,
                            child: OutlinedButton.icon(
                              onPressed: focus.finish,
                              icon: const Icon(Icons.stop_rounded),
                              label: const Text('结束并保存'),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      );
    },
  );

  Widget _historyCard(BuildContext context, List<PomodoroRecord> records) {
    final color = Theme.of(context).colorScheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 18, 18, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.history),
                const SizedBox(width: 8),
                Text('专注历史', style: Theme.of(context).textTheme.titleLarge),
                const Spacer(),
                Text(
                  '最近 ${records.length} 段',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
            const SizedBox(height: 10),
            if (records.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 24),
                child: Center(
                  child: Text(
                    '完成第一段专注后会显示在这里。',
                    style: TextStyle(color: color.onSurfaceVariant),
                  ),
                ),
              )
            else
              ...records.map((record) {
                final entry = widget.entries.find(
                  record.run.linkedEntryID ?? '',
                );
                return ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: CircleAvatar(
                    backgroundColor: record.outcome == 'completed'
                        ? color.primaryContainer
                        : color.surfaceContainer,
                    child: Icon(
                      record.outcome == 'completed' ? Icons.check : Icons.pause,
                      color: color.primary,
                    ),
                  ),
                  title: Text(
                    record.run.subject,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  subtitle: Text(
                    [
                      '${_dateLabel(record.endedAt)} · ${record.outcome == 'completed' ? '完成' : '提前结束'}',
                      if (entry != null) '关联 · ${entry.title}',
                    ].join('  ·  '),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  trailing: Text(
                    _durationLabel(record.durationSeconds),
                    style: Theme.of(context).textTheme.titleSmall
                        ?.copyWith(fontWeight: FontWeight.w700),
                  ),
                );
              }),
          ],
        ),
      ),
    );
  }

  Widget _messageCard(
    BuildContext context,
    String text, {
    bool error = false,
    Widget? action,
  }) => Card(
    color: error ? Theme.of(context).colorScheme.errorContainer : null,
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: [
          Expanded(child: Text(text)),
          ?action,
        ],
      ),
    ),
  );
}

String _clockLabel(double seconds) {
  final value = seconds.floor().clamp(0, 315360000);
  final hours = value ~/ 3600;
  final minutes = value ~/ 60 % 60;
  final remainder = value % 60;
  return hours > 0
      ? '${hours.toString().padLeft(2, '0')}:${minutes.toString().padLeft(2, '0')}:${remainder.toString().padLeft(2, '0')}'
      : '${(value ~/ 60).toString().padLeft(2, '0')}:${remainder.toString().padLeft(2, '0')}';
}

String _durationLabel(double seconds) {
  final value = seconds.floor().clamp(0, 315360000);
  final hours = value ~/ 3600;
  final minutes = value ~/ 60 % 60;
  if (value < 60) return '$value秒';
  return hours > 0 ? '$hours小时 $minutes分' : '${value ~/ 60}分钟';
}

String _dateLabel(double epoch) {
  final date = DateTime.fromMillisecondsSinceEpoch((epoch * 1000).round());
  final now = DateTime.now();
  final day =
      date.year == now.year && date.month == now.month && date.day == now.day
      ? '今天'
      : '${date.month}/${date.day}';
  return '$day ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
}
