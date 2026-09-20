import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/stage.dart';

/// Compact stage card for the project detail screen.
///
/// The card reads only Stage summary metadata. It does not load photos, receipt
/// documents or timeline events, so the project screen stays light.
class StageCard extends StatelessWidget {
  const StageCard({
    super.key,
    required this.stage,
    required this.onTap,
    this.selectionMode = false,
    this.selected = false,
    this.onSelectionChanged,
  });

  final Stage stage;
  final VoidCallback onTap;
  final bool selectionMode;
  final bool selected;
  final ValueChanged<bool>? onSelectionChanged;

  @override
  Widget build(BuildContext context) {
    final color = _statusColor(stage.status);

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: selectionMode
            ? () => onSelectionChanged?.call(!selected)
            : onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (selectionMode) ...[
                Checkbox(
                  value: selected,
                  onChanged: (value) {
                    onSelectionChanged?.call(value ?? false);
                  },
                ),
                const SizedBox(width: 4),
              ],
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Text(
                            stage.title,
                            style: Theme.of(context)
                                .textTheme
                                .titleMedium
                                ?.copyWith(fontWeight: FontWeight.w800),
                          ),
                        ),
                        const SizedBox(width: 8),
                        _StatusPill(status: stage.status, color: color),
                      ],
                    ),
                    if (stage.isCompleted && stage.completedAt != null) ...[
                      const SizedBox(height: 6),
                      Text(
                        DateFormat('dd.MM.yyyy').format(stage.completedAt!),
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: Colors.black54,
                            ),
                      ),
                    ],
                    const SizedBox(height: 12),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(99),
                      child: LinearProgressIndicator(
                        minHeight: 6,
                        value: stage.progress.clamp(0, 100).toDouble() / 100,
                        backgroundColor: color.withAlpha(31),
                        valueColor: AlwaysStoppedAnimation<Color>(color),
                      ),
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        _Counter(
                          icon: Icons.photo_library_outlined,
                          value: stage.photosCount.toString(),
                        ),
                        const SizedBox(width: 14),
                        _Counter(
                          icon: Icons.receipt_long,
                          value: stage.receiptsCount.toString(),
                        ),
                        const Spacer(),
                        if (!selectionMode) const Icon(Icons.chevron_right),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Color _statusColor(StageStatus status) {
    switch (status) {
      case StageStatus.notStarted:
        return const Color(0xFF64748B);
      case StageStatus.inProgress:
        return const Color(0xFF2563EB);
      case StageStatus.review:
        return const Color(0xFFF59E0B);
      case StageStatus.completed:
        return const Color(0xFF16A34A);
      case StageStatus.problem:
        return const Color(0xFFDC2626);
    }
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({
    required this.status,
    required this.color,
  });

  final StageStatus status;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: color.withAlpha(26),
        borderRadius: BorderRadius.circular(99),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        child: Text(
          status.label,
          style: TextStyle(
            color: color,
            fontSize: 12,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
    );
  }
}

class _Counter extends StatelessWidget {
  const _Counter({
    required this.icon,
    required this.value,
  });

  final IconData icon;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 18, color: Colors.black54),
        const SizedBox(width: 5),
        Text(value, style: Theme.of(context).textTheme.bodySmall),
      ],
    );
  }
}
