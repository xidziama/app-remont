import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/project.dart';
import '../repositories/project_repository.dart';

class CreateProjectScreen extends StatefulWidget {
  const CreateProjectScreen({super.key});

  @override
  State<CreateProjectScreen> createState() => _CreateProjectScreenState();
}

class _CreateProjectScreenState extends State<CreateProjectScreen> {
  final _formKey = GlobalKey<FormState>();
  final _titleController = TextEditingController();
  final _addressController = TextEditingController();
  final _descriptionController = TextEditingController();
  ProjectStatus _status = ProjectStatus.active;
  bool _saving = false;

  @override
  void dispose() {
    // Каждый TextEditingController держит ресурсы ввода.
    // dispose() освобождает их, когда экран закрывается.
    _titleController.dispose();
    _addressController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    // Валидатор формы проверяет обязательные поля перед сохранением.
    if (!_formKey.currentState!.validate()) {
      return;
    }

    setState(() => _saving = true);

    try {
      // Репозиторий создает документ проекта и участника-владельца в Firestore.
      // Экран передает только данные формы, а путь коллекции `objects`
      // остается внутри ProjectRepository.
      await context.read<ProjectRepository>().createProject(
        title: _titleController.text.trim(),
        address: _addressController.text.trim(),
        description: _descriptionController.text.trim(),
        status: _status,
      );

      if (mounted) {
        // После успешного сохранения закрываем форму.
        // ProjectListScreen обновится сам, потому что слушает Firestore stream.
        Navigator.of(context).pop();
      }
    } catch (error) {
      if (!mounted) {
        return;
      }

      // Показываем ошибку сохранения прямо на экране.
      // Частые причины: не запущен Firebase emulator или не прошли rules.
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Не удалось создать объект: $error')),
      );
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Новый объект')),
      body: Form(
        // Form связывает поля и валидаторы.
        // Через _formKey мы запускаем проверку всех полей в _save().
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            TextFormField(
              controller: _titleController,
              decoration: const InputDecoration(
                labelText: 'Название',
              ),
              // Название обязательно: без него объект в списке будет непонятным.
              validator: (value) => value == null || value.trim().isEmpty
                  ? 'Введите название'
                  : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _addressController,
              decoration: const InputDecoration(
                labelText: 'Адрес',
              ),
              // Адрес обязателен, потому что ремонтный объект обычно привязан
              // к конкретной квартире, дому или помещению.
              validator: (value) => value == null || value.trim().isEmpty
                  ? 'Введите адрес'
                  : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _descriptionController,
              minLines: 3,
              maxLines: 5,
              decoration: const InputDecoration(
                labelText: 'Описание',
              ),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<ProjectStatus>(
              value: _status,
              decoration: const InputDecoration(
                labelText: 'Статус',
              ),
              items: ProjectStatus.values
                  .map(
                    (status) => DropdownMenuItem(
                      value: status,
                      child: Text(status.label),
                    ),
                  )
                  .toList(),
              onChanged: (value) {
                // Dropdown может вернуть null, если значение сброшено.
                // В нашем UI null не нужен, поэтому обновляем статус только
                // когда пришло реальное значение.
                if (value != null) {
                  setState(() => _status = value);
                }
              },
            ),
            const SizedBox(height: 20),
            FilledButton(
              onPressed: _saving ? null : _save,
              child: Text(_saving ? 'Сохранение...' : 'Создать объект'),
            ),
          ],
        ),
      ),
    );
  }
}
