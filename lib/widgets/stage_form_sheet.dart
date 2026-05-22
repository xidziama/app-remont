import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/repair_stage.dart';
import '../repositories/project_repository.dart';
import '../utils/stage_ui_utils.dart';

/// Bottom sheet для создания и редактирования этапа.
///
/// Виджет работает с typed-моделью RepairStage и ProjectRepository. Экран фото
/// не знает, как именно этап сохраняется в Firestore, а только получает готовый
/// результат после закрытия формы.
class StageFormSheet extends StatefulWidget {
  const StageFormSheet({
    super.key,
    required this.projectId,
    this.initialStage,
  });

  /// ID объекта, внутри которого создается/редактируется этап.
  final String projectId;

  /// Если initialStage null — создаем новый этап.
  /// Если не null — редактируем существующий.
  final RepairStage? initialStage;

  @override
  State<StageFormSheet> createState() => _StageFormSheetState();
}

class _StageFormSheetState extends State<StageFormSheet> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  late int _selectedColor;
  late String _selectedIcon;
  bool _saving = false;

  bool get _editing => widget.initialStage != null;

  @override
  void initState() {
    super.initState();

    final stage = widget.initialStage;

    // Заполняем форму значениями этапа при редактировании.
    // При создании нового этапа берем безопасные дефолты.
    _nameController = TextEditingController(text: stage?.name ?? '');
    _selectedColor = stage?.color ?? StageUiUtils.colorPalette.first;
    _selectedIcon = stage?.icon ?? StageUiUtils.iconNames.first;
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    setState(() => _saving = true);

    try {
      final repository = context.read<ProjectRepository>();
      final name = _nameController.text.trim();
      RepairStage result;

      if (_editing) {
        // При редактировании сохраняем тот же id этапа.
        // Фото уже ссылаются на этот id, поэтому их не нужно менять.
        result = widget.initialStage!.copyWith(
          name: name,
          color: _selectedColor,
          icon: _selectedIcon,
        );
        await repository.updateStage(widget.projectId, result);
      } else {
        // При создании репозиторий сам назначает id, sortOrder и createdAt.
        result = await repository.createStage(
          projectId: widget.projectId,
          name: name,
          color: _selectedColor,
          icon: _selectedIcon,
        );
      }

      if (mounted) {
        Navigator.of(context).pop(result);
      }
    } catch (error) {
      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Не удалось сохранить этап: $error')),
      );
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          left: 16,
          right: 16,
          top: 16,
          bottom: MediaQuery.of(context).viewInsets.bottom + 16,
        ),
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  _editing ? 'Редактировать этап' : 'Новый этап',
                  style: Theme.of(context)
                      .textTheme
                      .titleLarge
                      ?.copyWith(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _nameController,
                  decoration: const InputDecoration(
                    labelText: 'Название этапа',
                    prefixIcon: Icon(Icons.edit),
                  ),
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return 'Введите название этапа';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),
                Text(
                  'Цвет',
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    for (final colorValue in StageUiUtils.colorPalette)
                      _ColorButton(
                        colorValue: colorValue,
                        selected: colorValue == _selectedColor,
                        onTap: () {
                          setState(() => _selectedColor = colorValue);
                        },
                      ),
                  ],
                ),
                const SizedBox(height: 16),
                Text(
                  'Иконка',
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final iconName in StageUiUtils.iconNames)
                      ChoiceChip(
                        selected: iconName == _selectedIcon,
                        onSelected: (_) {
                          setState(() => _selectedIcon = iconName);
                        },
                        avatar: Icon(
                          StageUiUtils.iconFromName(iconName),
                          size: 18,
                        ),
                        label: const SizedBox.shrink(),
                      ),
                  ],
                ),
                const SizedBox(height: 20),
                FilledButton.icon(
                  onPressed: _saving ? null : _save,
                  icon: _saving
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.check),
                  label: Text(_saving ? 'Сохранение...' : 'Сохранить'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ColorButton extends StatelessWidget {
  const _ColorButton({
    required this.colorValue,
    required this.selected,
    required this.onTap,
  });

  final int colorValue;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = Color(colorValue);

    return InkWell(
      borderRadius: BorderRadius.circular(24),
      onTap: onTap,
      child: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
          border: Border.all(
            color: selected ? Colors.black : Colors.transparent,
            width: 3,
          ),
        ),
        child: selected
            ? const Icon(Icons.check, color: Colors.white)
            : const SizedBox.shrink(),
      ),
    );
  }
}
