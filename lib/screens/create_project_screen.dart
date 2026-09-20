import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/company.dart';
import '../models/project.dart';
import '../repositories/project_repository.dart';
import '../services/auth_service.dart';
import '../utils/auth_debug.dart';

class CreateProjectScreen extends StatefulWidget {
  const CreateProjectScreen({super.key, required this.company});

  final CompanyMember company;

  @override
  State<CreateProjectScreen> createState() => _CreateProjectScreenState();
}

class _CreateProjectScreenState extends State<CreateProjectScreen> {
  final _formKey = GlobalKey<FormState>();
  final _titleController = TextEditingController();
  final _addressController = TextEditingController();
  final _descriptionController = TextEditingController();

  ProjectStatus _status = ProjectStatus.inProgress;
  bool _saving = false;

  @override
  void dispose() {
    // Controllers hold native text-input resources. They must be disposed when
    // the screen is removed from the widget tree.
    _titleController.dispose();
    _addressController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  /// Creates a safe diagnostic string for the current Firebase user.
  ///
  /// We log UID, email, and isAnonymous because these fields are enough to
  /// understand whether Email Auth succeeded. We never log passwords or tokens.
  String _describeUserForDebug() {
    return AuthDebug.describeUser(AuthService.instance.currentUser);
  }

  /// Converts technical errors into a short message that is clear for the user.
  ///
  /// The repository throws UserNotAuthenticatedException before any Firestore
  /// write if FirebaseAuth.currentUser is null. Firestore itself can also return
  /// `unauthenticated`, so we map both cases to the same clean text.
  String _saveErrorMessage(Object error) {
    if (error is UserNotAuthenticatedException) {
      return error.message;
    }

    if (error is FirebaseException && error.code == 'unauthenticated') {
      return 'Пользователь не авторизован.';
    }

    return 'Не удалось создать объект: $error';
  }

  Future<void> _save() async {
    // The form validator catches empty required fields before any network call.
    if (!_formKey.currentState!.validate()) {
      return;
    }

    final currentUser = AuthService.instance.currentUser;
    debugPrint(
      '[CreateProjectScreen._save] currentUser=${_describeUserForDebug()}',
    );

    // If Auth has no current user, we stop here and do not attempt a Firestore
    // write. This avoids cloud_firestore/unauthenticated and gives the user a
    // direct explanation.
    if (currentUser == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Пользователь не авторизован.')),
      );
      return;
    }

    setState(() => _saving = true);

    try {
      await context.read<ProjectRepository>().createProject(
            title: _titleController.text.trim(),
            address: _addressController.text.trim(),
            description: _descriptionController.text.trim(),
            status: _status,
            company: widget.company,
          );

      if (mounted) {
        // ProjectListScreen listens to Firestore, so after a successful write we
        // only close the form. The list updates from the stream automatically.
        Navigator.of(context).pop();
      }
    } catch (error) {
      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_saveErrorMessage(error))),
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
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            TextFormField(
              controller: _titleController,
              decoration: const InputDecoration(labelText: 'Название'),
              validator: (value) => value == null || value.trim().isEmpty
                  ? 'Введите название'
                  : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _addressController,
              decoration: const InputDecoration(labelText: 'Адрес'),
              validator: (value) => value == null || value.trim().isEmpty
                  ? 'Введите адрес'
                  : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _descriptionController,
              minLines: 3,
              maxLines: 5,
              decoration: const InputDecoration(labelText: 'Описание'),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<ProjectStatus>(
              initialValue: _status,
              decoration: const InputDecoration(labelText: 'Статус'),
              items: const [
                ProjectStatus.inProgress,
                ProjectStatus.paused,
              ]
                  .map(
                    (status) => DropdownMenuItem(
                      value: status,
                      child: Text(status.label),
                    ),
                  )
                  .toList(),
              onChanged: _saving
                  ? null
                  : (value) {
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
