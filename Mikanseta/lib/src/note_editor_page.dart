import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown/flutter_markdown.dart';

import 'domain.dart';
import 'store.dart';

/// Apple-Notes style full-page editor for 笔记. Tasks, schedules and homework
/// keep the dialog editor; only notes open this page, so an accidental tap
/// can no longer dismiss the editor — leaving requires 关闭 or back, and
/// unsaved changes ask first.
class NoteEditorPage extends StatefulWidget {
  const NoteEditorPage({
    super.key,
    required this.store,
    this.entry,
    this.isNew = false,
  });

  final EntryStore store;
  final Entry? entry;
  final bool isNew;

  @override
  State<NoteEditorPage> createState() => _NoteEditorPageState();
}

class _NoteEditorPageState extends State<NoteEditorPage> {
  late final Entry original;
  late final TextEditingController title;
  late final TextEditingController body;
  late final TextEditingController category;
  final List<TextEditingController> stepControllers = [];
  final List<bool> stepDone = [];
  bool saving = false;
  String? error;
  bool dirty = false;
  bool preview = false;

  @override
  void initState() {
    super.initState();
    final entry = widget.entry;
    original =
        entry ?? Entry.create(kind: EntryKind.note, now: widget.store.clock());
    title = TextEditingController(text: original.title);
    body = TextEditingController(text: original.body);
    category = TextEditingController(text: original.category);
    for (final step in original.steps) {
      stepControllers.add(TextEditingController(text: step.title));
      stepDone.add(step.done);
    }
    title.addListener(_markDirty);
    body.addListener(_markDirty);
    category.addListener(_markDirty);
  }

  @override
  void dispose() {
    title.dispose();
    body.dispose();
    category.dispose();
    for (final controller in stepControllers) {
      controller.dispose();
    }
    super.dispose();
  }

  void _markDirty() {
    if (!dirty) setState(() => dirty = true);
  }

  bool get _changed {
    if (title.text.trim() != original.title) return true;
    if (body.text != original.body) return true;
    if (category.text.trim() != original.category) return true;
    final steps = original.steps;
    if (stepControllers.length != steps.length) return true;
    for (var i = 0; i < steps.length; i++) {
      if (stepControllers[i].text != steps[i].title ||
          stepDone[i] != steps[i].done) {
        return true;
      }
    }
    return false;
  }

  Future<void> _close() async {
    if (_changed && mounted) {
      final discard = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('放弃未保存的修改？'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('继续编辑'),
            ),
            FilledButton.tonal(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('放弃修改'),
            ),
          ],
        ),
      );
      if (discard != true) return;
    }
    if (mounted) Navigator.pop(context);
  }

  Future<void> _save() async {
    if (saving) return;
    if (title.text.trim().isEmpty) {
      setState(() => error = '先写一个笔记标题。');
      return;
    }
    final steps = <Map<String, dynamic>>[
      for (var i = 0; i < stepControllers.length; i++)
        if (stepControllers[i].text.trim().isNotEmpty)
          StepItem(
            id: i < original.steps.length ? original.steps[i].id : null,
            title: stepControllers[i].text,
            done: stepDone[i],
          ).toJson(),
    ];
    final next = original.change({
      'title': title.text.trim(),
      'body': body.text,
      'category': category.text.trim(),
      'checklist': steps,
      'dueDate': null,
      'repeatRule': 'never',
      'reminder': null,
      'isCompleted': false,
      'completedAt': null,
      'startedAt': null,
      'elapsedSeconds': 0,
    }, now: widget.store.clock());
    setState(() {
      saving = true;
      error = null;
    });
    try {
      widget.store.save(next);
      await widget.store.settled;
      if (widget.store.saveFailed) {
        throw StateError('笔记暂未写入磁盘，请重试保存。');
      }
      HapticFeedback.lightImpact();
      if (mounted) Navigator.pop(context);
    } catch (exception) {
      if (mounted) {
        setState(() {
          saving = false;
          error = '无法保存：$exception';
        });
      }
    }
  }

  Future<void> _delete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('删除笔记？'),
        content: const Text('删除后通过同步与备份仍可能保留副本。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton.tonal(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    widget.store.delete(original.id);
    await widget.store.settled;
    if (mounted) Navigator.pop(context);
  }

  void _addStep() {
    setState(() {
      stepControllers.add(TextEditingController()..addListener(_markDirty));
      stepDone.add(false);
      dirty = true;
    });
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: false,
    onPopInvokedWithResult: (didPop, _) {
      if (!didPop) _close();
    },
    child: Scaffold(
      appBar: AppBar(
        title: Text(widget.entry == null || widget.isNew ? '新笔记' : '笔记'),
        leading: IconButton(
          tooltip: '关闭',
          onPressed: _close,
          icon: const Icon(Icons.close),
        ),
        actions: [
          if (widget.entry != null)
            IconButton(
              tooltip: '删除笔记',
              onPressed: saving ? null : _delete,
              icon: const Icon(Icons.delete_outline),
            ),
          // 预览只读 body 控制器，不改动内容，dirty 判定不受影响。
          IconButton(
            tooltip: preview ? '编辑' : '预览',
            onPressed: () => setState(() => preview = !preview),
            icon: Icon(preview ? Icons.visibility_off : Icons.visibility),
          ),
          Padding(
            padding: const EdgeInsets.only(right: 14),
            child: FilledButton.tonal(
              key: const ValueKey('note-save'),
              onPressed: saving ? null : _save,
              child: Text(saving ? '保存中…' : '保存'),
            ),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
        children: [
          TextField(
            key: const ValueKey('note-title'),
            controller: title,
            autofocus: widget.entry == null || widget.isNew,
            textInputAction: TextInputAction.next,
            style: TextStyle(
              fontSize: 26,
              fontWeight: FontWeight.w700,
              color: Theme.of(context).colorScheme.onSurface,
            ),
            decoration: const InputDecoration(
              hintText: '标题',
              border: InputBorder.none,
              enabledBorder: InputBorder.none,
              focusedBorder: InputBorder.none,
              filled: false,
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(top: 2, bottom: 6),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: category,
                    style: Theme.of(context).textTheme.bodySmall,
                    decoration: InputDecoration(
                      hintText: '分类（学习、生活、社团…）',
                      isCollapsed: true,
                      border: InputBorder.none,
                      enabledBorder: InputBorder.none,
                      focusedBorder: InputBorder.none,
                      filled: false,
                      hintStyle: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Text(
                  dateLabel(original.updatedAt),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
          if (preview)
            // 页面本身是 ListView 滚动视图；用 MarkdownBody 避免嵌套竖向
            // 滚动体，标题、清单与加粗随页面滚动一起可见。
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: MarkdownBody(data: body.text),
            )
          else
            TextField(
              key: const ValueKey('note-body'),
              controller: body,
              keyboardType: TextInputType.multiline,
              minLines: 8,
              maxLines: null,
              style: Theme.of(context).textTheme.bodyLarge,
              decoration: InputDecoration(
                hintText: '开始记录',
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                filled: false,
                hintStyle: Theme.of(context).textTheme.bodyLarge,
              ),
            ),
          const SizedBox(height: 8),
          for (var i = 0; i < stepControllers.length; i++)
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                IconButton(
                  tooltip: stepDone[i] ? '取消勾选' : '勾选',
                  onPressed: () {
                    setState(() {
                      stepDone[i] = !stepDone[i];
                      dirty = true;
                    });
                  },
                  icon: Icon(
                    stepDone[i] ? Icons.check_circle : Icons.circle_outlined,
                    size: 22,
                    color: stepDone[i]
                        ? Theme.of(context).colorScheme.primary
                        : Theme.of(context).colorScheme.outline,
                  ),
                ),
                Expanded(
                  child: TextField(
                    controller: stepControllers[i],
                    style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                      decoration: stepDone[i]
                          ? TextDecoration.lineThrough
                          : null,
                      color: stepDone[i]
                          ? Theme.of(context).colorScheme.onSurfaceVariant
                          : null,
                    ),
                    decoration: const InputDecoration(
                      isCollapsed: true,
                      border: InputBorder.none,
                      enabledBorder: InputBorder.none,
                      focusedBorder: InputBorder.none,
                      filled: false,
                    ),
                  ),
                ),
                IconButton(
                  tooltip: '删除清单项',
                  onPressed: () {
                    setState(() {
                      stepControllers.removeAt(i).dispose();
                      stepDone.removeAt(i);
                      dirty = true;
                    });
                  },
                  icon: Icon(
                    Icons.remove_circle_outline,
                    size: 20,
                    color: Theme.of(context).colorScheme.outline,
                  ),
                ),
              ],
            ),
          TextButton.icon(
            onPressed: _addStep,
            icon: const Icon(Icons.add, size: 20),
            label: const Text('添加清单项'),
          ),
          if (error != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
        ],
      ),
    ),
  );
}
