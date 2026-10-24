import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Capsule segmented control matching the native Mikansei picker: a soft
/// rounded container with the selected segment filled in the accent color.
class SegmentedStrip<T> extends StatelessWidget {
  const SegmentedStrip({
    super.key,
    required this.choices,
    required this.selection,
    required this.title,
    required this.onChanged,
    this.label,
    this.identifier,
    this.padding = const EdgeInsets.all(3),
  });

  final List<T> choices;
  final T selection;
  final String Function(T choice) title;
  final ValueChanged<T> onChanged;
  final String? label;
  final String Function(T choice)? identifier;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final content = Container(
      padding: padding,
      decoration: BoxDecoration(
        color: colors.surfaceContainer,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          for (final choice in choices)
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 1),
                child: _segment(context, choice),
              ),
            ),
        ],
      ),
    );
    if (label == null) return content;
    return Semantics(label: label, container: true, child: content);
  }

  Widget _segment(BuildContext context, T choice) {
    final colors = Theme.of(context).colorScheme;
    final selected = choice == selection;
    final segment = Material(
      key: identifier == null ? null : ValueKey(identifier!(choice)),
      color: selected ? colors.primary : Colors.transparent,
      borderRadius: BorderRadius.circular(11),
      child: InkWell(
        borderRadius: BorderRadius.circular(11),
        onTap: () {
          HapticFeedback.selectionClick();
          onChanged(choice);
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
          child: Text(
            title(choice),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 13,
              fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
              color: selected ? colors.onPrimary : colors.onSurfaceVariant,
            ),
          ),
        ),
      ),
    );
    return Semantics(button: true, selected: selected, child: segment);
  }
}
