import 'package:flutter/material.dart';

/// Универсальная заглушка для пустых списков.
///
/// Один виджет используется для объектов, участников, расходов и фото,
/// чтобы экраны выглядели одинаково и код не дублировался.
class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  /// Иконка быстро объясняет, какой раздел пуст.
  final IconData icon;

  /// Короткий заголовок пустого состояния.
  final String title;

  /// Подсказка, что пользователь может сделать дальше.
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 48, color: Theme.of(context).colorScheme.primary),
            const SizedBox(height: 16),
            // Заголовок центрируется, потому что пустой экран обычно один
            // на всю страницу и должен спокойно читаться.
            Text(
              title,
              style: Theme.of(context).textTheme.titleLarge,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            // Subtitle объясняет следующий шаг без отдельного tutorial screen.
            Text(
              subtitle,
              style: Theme.of(context).textTheme.bodyMedium,
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
