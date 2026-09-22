import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../models/photo.dart';
import '../models/project.dart';
import '../models/repair_stage.dart';
import '../repositories/project_repository.dart';
import '../services/storage_service.dart';
import 'stage_form_sheet.dart';

/// Форма добавления фото.
///
/// Важное UX-правило: upload начинается только после того, как пользователь
/// выбрал фото, этап, дату и при необходимости ввел описание. Так в Firestore
/// не появляются "пустые" фото без этапа и метаданных.
class PhotoUploadSheet extends StatefulWidget {
  const PhotoUploadSheet({
    super.key,
    required this.project,
    required this.stages,
  });

  final Project project;
  final List<RepairStage> stages;

  @override
  State<PhotoUploadSheet> createState() => _PhotoUploadSheetState();
}

class _PhotoUploadSheetState extends State<PhotoUploadSheet> {
  final _descriptionController = TextEditingController();
  late final List<RepairStage> _localStages;
  XFile? _image;
  Uint8List? _previewBytes;
  String? _selectedStageId;
  DateTime _selectedDate = DateTime.now();
  bool _saving = false;

  @override
  void initState() {
    super.initState();

    // Делаем локальную копию этапов.
    // Это нужно, чтобы созданный прямо из формы новый этап сразу появился
    // в dropdown, не дожидаясь пересборки родительского StreamBuilder.
    _localStages = List<RepairStage>.from(widget.stages);

    // Если этапы уже есть, выбираем первый. Пользователь может изменить выбор.
    if (_localStages.isNotEmpty) {
      _selectedStageId = _localStages.first.id;
    }
  }

  @override
  void dispose() {
    _descriptionController.dispose();
    super.dispose();
  }

  Future<void> _pickImage() async {
    final image = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      imageQuality: 85,
    );

    if (image == null) {
      return;
    }

    // Читаем байты один раз: они нужны и для preview, и для upload.
    final bytes = await image.readAsBytes();

    setState(() {
      _image = image;
      _previewBytes = bytes;
    });
  }

  Future<void> _pickDate() async {
    final date = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );

    if (date != null) {
      setState(() => _selectedDate = date);
    }
  }

  Future<void> _createStage() async {
    final stage = await showModalBottomSheet<RepairStage>(
      context: context,
      isScrollControlled: true,
      builder: (_) => StageFormSheet(projectId: widget.project.id),
    );

    if (stage != null) {
      setState(() {
        _localStages.add(stage);
        _selectedStageId = stage.id;
      });
    }
  }

  /// Reads image dimensions for lightweight metadata.
  Future<({int width, int height})> _readImageSize(Uint8List bytes) async {
    final codec = await ui.instantiateImageCodec(bytes);
    final frame = await codec.getNextFrame();
    final image = frame.image;
    final size = (width: image.width, height: image.height);

    image.dispose();
    codec.dispose();

    return size;
  }

  Future<void> _save() async {
    final image = _image;
    final bytes = _previewBytes;
    final stageId = _selectedStageId;

    // Defensive validation: все обязательные части должны быть готовы до upload.
    if (image == null || bytes == null) {
      _showMessage('Выберите фото');
      return;
    }

    if (stageId == null || stageId.isEmpty) {
      _showMessage('Выберите или создайте этап');
      return;
    }

    setState(() => _saving = true);

    try {
      final repository = context.read<ProjectRepository>();
      final photoId = repository.createStagePhotoId(
        projectId: widget.project.id,
        stageId: stageId,
      );

      final upload = await StorageService.instance.uploadStagePhoto(
        projectId: widget.project.id,
        stageId: stageId,
        photoId: photoId,
        bytes: bytes,
        contentType: image.mimeType ?? 'image/jpeg',
      );
      final size = await _readImageSize(bytes);

      await repository.addStagePhoto(
        Photo(
          id: photoId,
          projectId: widget.project.id,
          stageId: stageId,
          type: PhotoType.progress,
          storagePath: upload.storagePath,
          comment: _descriptionController.text.trim().isEmpty
              ? null
              : _descriptionController.text.trim(),
          amount: null,
          uploadedBy: repository.currentAuthorName,
          createdAt: _selectedDate,
          width: size.width,
          height: size.height,
          sizeBytes: upload.sizeBytes,
          isFavorite: false,
        ),
      );

      if (mounted) {
        Navigator.of(context).pop();
      }
    } catch (error) {
      _showMessage('Не удалось загрузить фото: $error');
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }

  void _showMessage(String text) {
    if (!mounted) {
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(text)),
    );
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
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Добавить фото',
                style: Theme.of(context)
                    .textTheme
                    .titleLarge
                    ?.copyWith(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 16),
              InkWell(
                borderRadius: BorderRadius.circular(8),
                onTap: _saving ? null : _pickImage,
                child: AspectRatio(
                  aspectRatio: 16 / 9,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: const Color(0xFFE5E7EB)),
                    ),
                    child: _previewBytes == null
                        ? const Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.add_a_photo, size: 36),
                              SizedBox(height: 8),
                              Text('Выбрать фото'),
                            ],
                          )
                        : ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: Image.memory(
                              _previewBytes!,
                              fit: BoxFit.cover,
                            ),
                          ),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      initialValue: _selectedStageId,
                      decoration: const InputDecoration(
                        labelText: 'Этап работ',
                        prefixIcon: Icon(Icons.flag),
                      ),
                      items: [
                        for (final stage in _localStages)
                          DropdownMenuItem(
                            value: stage.id,
                            child: Text(stage.name),
                          ),
                      ],
                      onChanged: _saving
                          ? null
                          : (value) {
                              setState(() => _selectedStageId = value);
                            },
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton.filledTonal(
                    tooltip: 'Создать этап',
                    onPressed: _saving ? null : _createStage,
                    icon: const Icon(Icons.add),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _descriptionController,
                minLines: 2,
                maxLines: 4,
                decoration: const InputDecoration(
                  labelText: 'Описание',
                  hintText: 'Что сделано на этом этапе',
                  prefixIcon: Icon(Icons.notes),
                ),
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: _saving ? null : _pickDate,
                icon: const Icon(Icons.calendar_month),
                label: Text(DateFormat('dd.MM.yyyy').format(_selectedDate)),
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: _saving ? null : _save,
                icon: _saving
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.cloud_upload),
                label: Text(_saving ? 'Загрузка...' : 'Загрузить фото'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
