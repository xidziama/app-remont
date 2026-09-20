import 'package:flutter/material.dart';

import '../models/repair_stage.dart';
import '../utils/stage_ui_utils.dart';

/// Компактный chip этапа.
///
/// Используется в фильтрах, карточках фото и списках этапов. Один общий виджет
/// помогает держать внешний вид этапов одинаковым во всем приложении.
class RepairStageChip extends StatelessWidget {
  const RepairStageChip({
    super.key,
    required this.stage,
    this.selected = false,
    this.onTap,
  });

  /// Этап, который нужно показать.
  final RepairStage stage;

  /// Флаг выбранного состояния для фильтра.
  final bool selected;

  /// Callback для клика. Если null, chip становится просто декоративным.
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final color = StageUiUtils.colorFromInt(stage.color);
    final foreground = selected ? Colors.white : color;

    return ActionChip(
      onPressed: onTap,
      backgroundColor: selected ? color : color.withAlpha(26),
      side: BorderSide(color: color.withAlpha(89)),
      avatar: Icon(
        StageUiUtils.iconFromName(stage.icon),
        color: foreground,
        size: 18,
      ),
      label: Text(
        stage.name,
        overflow: TextOverflow.ellipsis,
      ),
      labelStyle: TextStyle(
        color: foreground,
        fontWeight: FontWeight.w700,
      ),
    );
  }
}
