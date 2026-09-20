import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../models/expense.dart';
import '../models/photo.dart';
import '../models/stage.dart';
import '../repositories/project_repository.dart';
import '../services/storage_service.dart';

/// Bottom sheet for uploading a stage progress photo or a stage receipt.
///
/// The caller controls `allowedTypes`, so the same sheet can be reused safely:
/// - Progress tab passes before/progress/after/problem.
/// - Receipts tab passes only receipt, therefore the type picker is hidden.
///
/// Firestore metadata is created only after Firebase Storage upload succeeds.
/// This prevents broken photo documents that point to a file that was never
/// uploaded.
class StagePhotoUploadSheet extends StatefulWidget {
  const StagePhotoUploadSheet({
    super.key,
    required this.stage,
    required this.allowedTypes,
  });

  final Stage stage;
  final List<PhotoType> allowedTypes;

  @override
  State<StagePhotoUploadSheet> createState() => _StagePhotoUploadSheetState();
}

class _StagePhotoUploadSheetState extends State<StagePhotoUploadSheet> {
  final _commentController = TextEditingController();
  final _amountController = TextEditingController();
  final _picker = ImagePicker();

  ImageSource _source = ImageSource.gallery;
  XFile? _image;
  Uint8List? _previewBytes;
  late PhotoType _type;
  ExpenseCategory _category = ExpenseCategory.materials;
  DateTime _receiptDate = DateTime.now();
  bool _saving = false;

  bool get _isReceipt => _type == PhotoType.receipt;

  bool get _showTypePicker => widget.allowedTypes.length > 1;

  @override
  void initState() {
    super.initState();
    _type = widget.allowedTypes.isEmpty
        ? PhotoType.progress
        : widget.allowedTypes.first;
  }

  @override
  void dispose() {
    _commentController.dispose();
    _amountController.dispose();
    super.dispose();
  }

  /// Opens camera or gallery depending on the selected source.
  ///
  /// The picked file is kept in memory only for preview and upload. It is not
  /// written into Firestore as base64/blob.
  Future<void> _pickImage() async {
    final image = await _picker.pickImage(
      source: _source,
      imageQuality: 85,
    );

    if (image == null) {
      return;
    }

    final bytes = await image.readAsBytes();

    if (!mounted) {
      return;
    }

    setState(() {
      _image = image;
      _previewBytes = bytes;
    });
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

  /// Parses receipt amount from user input.
  ///
  /// Users often type comma as decimal separator, so we normalize it to dot
  /// before parsing.
  double? _readReceiptAmount() {
    if (!_isReceipt) {
      return null;
    }

    return double.tryParse(_amountController.text.replaceAll(',', '.'));
  }

  Future<void> _pickReceiptDate() async {
    final result = await showDatePicker(
      context: context,
      initialDate: _receiptDate,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );

    if (result != null && mounted) {
      setState(() => _receiptDate = result);
    }
  }

  Future<void> _save() async {
    final bytes = _previewBytes;
    final image = _image;

    if (bytes == null || image == null) {
      _showMessage('Выберите изображение.');
      return;
    }

    final amount = _readReceiptAmount();
    if (_isReceipt && (amount == null || amount <= 0)) {
      _showMessage('Введите сумму чека.');
      return;
    }

    FocusScope.of(context).unfocus();
    setState(() => _saving = true);

    try {
      final repository = context.read<ProjectRepository>();
      final photoId = _isReceipt
          ? repository.createExpenseId(widget.stage.projectId)
          : repository.createStagePhotoId(
              projectId: widget.stage.projectId,
              stageId: widget.stage.id,
            );

      final upload = await StorageService.instance.uploadStagePhoto(
        projectId: widget.stage.projectId,
        stageId: widget.stage.id,
        photoId: photoId,
        bytes: bytes,
        contentType: image.mimeType ?? 'image/jpeg',
      );
      if (_isReceipt) {
        await repository.addExpense(
          widget.stage.projectId,
          Expense(
            id: photoId,
            projectId: widget.stage.projectId,
            stageId: widget.stage.id,
            stageTitle: widget.stage.title,
            amount: amount ?? 0,
            category: _category,
            date: _receiptDate,
            createdAt: DateTime.now(),
            createdBy: repository.currentUserId,
            isPaid: false,
            comment: _commentController.text.trim().isEmpty
                ? null
                : _commentController.text.trim(),
            receiptUrl: upload.downloadUrl,
            receiptStoragePath: upload.storagePath,
          ),
        );
      } else {
        final size = await _readImageSize(bytes);

        await repository.addStagePhoto(
          Photo(
            id: photoId,
            projectId: widget.stage.projectId,
            stageId: widget.stage.id,
            type: _type,
            downloadUrl: upload.downloadUrl,
            storagePath: upload.storagePath,
            comment: _commentController.text.trim().isEmpty
                ? null
                : _commentController.text.trim(),
            amount: amount,
            uploadedBy: repository.currentAuthorName,
            createdAt: DateTime.now(),
            width: size.width,
            height: size.height,
            sizeBytes: upload.sizeBytes,
            isFavorite: false,
          ),
        );
      }

      if (!mounted) {
        return;
      }

      final messenger = ScaffoldMessenger.of(context);
      Navigator.of(context).pop();
      messenger.showSnackBar(
        SnackBar(content: Text(_isReceipt ? 'Чек добавлен' : 'Фото добавлено')),
      );
    } catch (error) {
      _showMessage('Не удалось загрузить фото: $error');
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }

  void _showMessage(String message) {
    if (!mounted) {
      return;
    }

    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final title = _isReceipt ? 'Добавить чек' : 'Добавить фото';

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
                title,
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
              ),
              const SizedBox(height: 16),
              Text(
                'Источник',
                style: Theme.of(context).textTheme.labelLarge,
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                children: [
                  ChoiceChip(
                    label: const Text('Галерея'),
                    selected: _source == ImageSource.gallery,
                    onSelected: _saving
                        ? null
                        : (_) => setState(() => _source = ImageSource.gallery),
                  ),
                  ChoiceChip(
                    label: const Text('Камера'),
                    selected: _source == ImageSource.camera,
                    onSelected: _saving
                        ? null
                        : (_) => setState(() => _source = ImageSource.camera),
                  ),
                ],
              ),
              const SizedBox(height: 12),
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
                              Text('Фото'),
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
              if (_showTypePicker) ...[
                const SizedBox(height: 12),
                DropdownButtonFormField<PhotoType>(
                  initialValue: _type,
                  decoration: const InputDecoration(
                    labelText: 'Тип фото',
                    prefixIcon: Icon(Icons.photo_outlined),
                  ),
                  items: [
                    for (final type in widget.allowedTypes)
                      DropdownMenuItem(
                        value: type,
                        child: Text(type.label),
                      ),
                  ],
                  onChanged: _saving
                      ? null
                      : (value) {
                          if (value != null) {
                            setState(() => _type = value);
                          }
                        },
                ),
              ],
              if (_isReceipt) ...[
                const SizedBox(height: 12),
                TextField(
                  controller: _amountController,
                  enabled: !_saving,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: const InputDecoration(
                    labelText: 'Сумма',
                    prefixIcon: Icon(Icons.payments_outlined),
                  ),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<ExpenseCategory>(
                  initialValue: _category,
                  decoration: const InputDecoration(
                    labelText: 'Категория',
                    prefixIcon: Icon(Icons.category_outlined),
                  ),
                  items: [
                    for (final category in ExpenseCategory.values)
                      DropdownMenuItem(
                        value: category,
                        child: Text(category.label),
                      ),
                  ],
                  onChanged: _saving
                      ? null
                      : (value) {
                          if (value != null) {
                            setState(() => _category = value);
                          }
                        },
                ),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: _saving ? null : _pickReceiptDate,
                  icon: const Icon(Icons.calendar_month_outlined),
                  label: Text(DateFormat('dd.MM.yyyy').format(_receiptDate)),
                ),
              ],
              const SizedBox(height: 12),
              TextField(
                controller: _commentController,
                enabled: !_saving,
                minLines: 2,
                maxLines: 4,
                decoration: const InputDecoration(
                  labelText: 'Комментарий',
                  prefixIcon: Icon(Icons.notes_outlined),
                ),
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
                    : const Icon(Icons.cloud_upload_outlined),
                label: Text(_saving ? 'Загрузка...' : 'Сохранить'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
