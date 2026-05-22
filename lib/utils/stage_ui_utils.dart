import 'package:flutter/material.dart';

/// StageUiUtils хранит UI-преобразования для этапов.
///
/// Модель RepairStage хранит цвет как int и иконку как String, потому что
/// Firestore должен получать простые сериализуемые значения. Этот helper
/// превращает эти значения обратно в Flutter Color и IconData.
class StageUiUtils {
  /// Палитра цветов для этапов.
  ///
  /// Пользователь выбирает цвет из фиксированных swatches. Это проще и
  /// стабильнее для MVP, чем полноценный color picker.
  static const colorPalette = <int>[
    0xFFEF4444,
    0xFFF59E0B,
    0xFF22C55E,
    0xFF0EA5E9,
    0xFF6366F1,
    0xFF8B5CF6,
    0xFF14B8A6,
    0xFFA16207,
    0xFF64748B,
    0xFF111827,
  ];

  /// Доступные иконки для этапов.
  ///
  /// В Firestore сохраняется только ключ map, например `plumbing`.
  static const iconNames = <String>[
    'construction',
    'electric_bolt',
    'plumbing',
    'texture',
    'format_paint',
    'format_color_fill',
    'floor',
    'grid_view',
    'layers',
    'cleaning_services',
  ];

  /// Превращает ARGB int из модели в Flutter Color.
  static Color colorFromInt(int value) {
    return Color(value);
  }

  /// Превращает строковое имя иконки из Firestore в Material IconData.
  ///
  /// Если в Firestore пришло неизвестное значение, возвращаем construction.
  /// Это defensive programming: UI не падает из-за старых или ручных данных.
  static IconData iconFromName(String name) {
    switch (name) {
      case 'electric_bolt':
        return Icons.electric_bolt;
      case 'plumbing':
        return Icons.plumbing;
      case 'texture':
        return Icons.texture;
      case 'format_paint':
        return Icons.format_paint;
      case 'format_color_fill':
        return Icons.format_color_fill;
      case 'floor':
        return Icons.square_foot;
      case 'grid_view':
        return Icons.grid_view;
      case 'layers':
        return Icons.layers;
      case 'cleaning_services':
        return Icons.cleaning_services;
      case 'construction':
      default:
        return Icons.construction;
    }
  }
}
