import 'package:cached_network_image/cached_network_image.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../models/chat_message.dart';
import '../models/company.dart';
import '../models/project.dart';
import '../repositories/project_repository.dart';
import '../services/storage_service.dart';
import '../utils/auth_debug.dart';
import 'fullscreen_image_preview_screen.dart';

class ChatScreen extends StatefulWidget {
  const ChatScreen({
    super.key,
    required this.project,
    required this.company,
  });

  final Project project;
  final CompanyMember company;

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final _controller = TextEditingController();
  final _picker = ImagePicker();

  bool _uploadingImage = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final text = _controller.text.trim();

    if (text.isEmpty) {
      return;
    }

    _controller.clear();

    try {
      await context.read<ProjectRepository>().sendMessage(
            widget.project.id,
            text,
          );
    } catch (error) {
      _showMessage('Не удалось отправить сообщение: $error');
      _controller.text = text;
    }
  }

  Future<void> _openAttachSheet() async {
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_camera_outlined),
              title: const Text('Камера'),
              onTap: () => Navigator.of(sheetContext).pop(ImageSource.camera),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('Галерея'),
              onTap: () => Navigator.of(sheetContext).pop(ImageSource.gallery),
            ),
          ],
        ),
      ),
    );

    if (source != null) {
      await _sendImage(source);
    }
  }

  Future<void> _sendImage(ImageSource source) async {
    final repository = context.read<ProjectRepository>();
    final image = await _picker.pickImage(
      source: source,
      imageQuality: 85,
    );

    if (image == null) {
      return;
    }

    if (!mounted) {
      return;
    }

    FocusScope.of(context).unfocus();
    setState(() => _uploadingImage = true);

    try {
      final messageId = repository.createChatMessageId(widget.project.id);
      final bytes = await image.readAsBytes();

      final upload = await StorageService.instance.uploadChatImage(
        projectId: widget.project.id,
        messageId: messageId,
        bytes: bytes,
        contentType: image.mimeType ?? 'image/jpeg',
      );

      final caption = _controller.text.trim();
      _controller.clear();

      await repository.sendImageMessage(
        projectId: widget.project.id,
        messageId: messageId,
        downloadUrl: upload.downloadUrl,
        storagePath: upload.storagePath,
        text: caption,
      );

      _showMessage('Фото отправлено');
    } catch (error) {
      _showMessage('Не удалось отправить фото: $error');
    } finally {
      if (mounted) {
        setState(() => _uploadingImage = false);
      }
    }
  }

  void _openImagePreview(ChatMessage message) {
    final imageUrl = message.imageUrl;
    if (imageUrl == null || imageUrl.isEmpty) {
      return;
    }

    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => FullscreenImagePreviewScreen(
          imageUrl: imageUrl,
          title: 'Фото',
          details: [
            if (message.text.trim().isNotEmpty) message.text.trim(),
            DateFormat('dd.MM.yyyy HH:mm').format(message.createdAt),
          ],
        ),
      ),
    );
  }

  void _showMessage(String message) {
    if (!mounted) {
      return;
    }

    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  String _senderTitle(ChatMessage message) {
    final role = _roleLabelForSender(message.senderId);
    final storedName = _safePersonName(message.senderName);
    final projectName = _projectNameForSender(message.senderId);
    final name = storedName ?? projectName;

    if (name == null || name.isEmpty) {
      return role;
    }

    if (role == 'Пользователь' || _sameText(role, name)) {
      return name;
    }

    return '$role $name';
  }

  String _roleLabelForSender(String senderId) {
    if (senderId == widget.project.ownerId) {
      return 'Директор';
    }

    if (widget.project.managerIds.contains(senderId)) {
      return 'Прораб';
    }

    if (widget.project.workerIds.contains(senderId)) {
      return 'Подрядчик';
    }

    if (widget.project.clientIds.contains(senderId)) {
      return 'Заказчик';
    }

    if (senderId == widget.company.uid) {
      return widget.company.role.label;
    }

    return 'Пользователь';
  }

  String? _projectNameForSender(String senderId) {
    final managerName = _nameFromParallelLists(
      ids: widget.project.managerIds,
      names: widget.project.managerNames,
      senderId: senderId,
    );
    if (managerName != null) {
      return managerName;
    }

    final workerName = _nameFromParallelLists(
      ids: widget.project.workerIds,
      names: widget.project.workerNames,
      senderId: senderId,
    );
    if (workerName != null) {
      return workerName;
    }

    return _nameFromParallelLists(
      ids: widget.project.clientIds,
      names: widget.project.clientNames,
      senderId: senderId,
    );
  }

  String? _nameFromParallelLists({
    required List<String> ids,
    required List<String> names,
    required String senderId,
  }) {
    final index = ids.indexOf(senderId);
    if (index < 0 || index >= names.length) {
      return null;
    }

    return _safePersonName(names[index]);
  }

  String? _safePersonName(String rawName) {
    final name = rawName.trim();
    if (name.isEmpty || name == 'Пользователь' || _looksLikeEmail(name)) {
      return null;
    }

    return name;
  }

  bool _looksLikeEmail(String value) {
    final text = value.trim();
    return text.contains('@') && text.contains('.');
  }

  bool _sameText(String left, String right) {
    return left.trim().toLowerCase() == right.trim().toLowerCase();
  }

  @override
  Widget build(BuildContext context) {
    final currentUser = FirebaseAuth.instance.currentUser;
    AuthDebug.logUser('ChatScreen.build', currentUser);
    final uid = currentUser?.uid;
    final repository = context.read<ProjectRepository>();

    return Scaffold(
      appBar: AppBar(title: const Text('Чат')),
      body: Column(
        children: [
          Expanded(
            child: StreamBuilder<List<ChatMessage>>(
              stream: repository.watchMessages(widget.project.id),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }

                if (snapshot.hasError) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child:
                          Text('Не удалось загрузить чат: ${snapshot.error}'),
                    ),
                  );
                }

                final messages = snapshot.data ?? [];
                return ListView.builder(
                  key: PageStorageKey<String>('chat_${widget.project.id}'),
                  padding: const EdgeInsets.all(16),
                  itemCount: messages.length,
                  itemBuilder: (context, index) {
                    final message = messages[index];
                    final mine = message.senderId == uid;

                    return Align(
                      alignment:
                          mine ? Alignment.centerRight : Alignment.centerLeft,
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 320),
                        child: _ChatMessageCard(
                          message: message,
                          senderTitle: _senderTitle(message),
                          mine: mine,
                          onImageTap: () => _openImagePreview(message),
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  IconButton(
                    tooltip: 'Прикрепить фото',
                    onPressed: _uploadingImage ? null : _openAttachSheet,
                    icon: _uploadingImage
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.attach_file),
                  ),
                  Expanded(
                    child: TextField(
                      controller: _controller,
                      decoration: const InputDecoration(
                        hintText: 'Сообщение',
                        border: OutlineInputBorder(),
                      ),
                      minLines: 1,
                      maxLines: 4,
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton.filled(
                    onPressed: _uploadingImage ? null : _send,
                    icon: const Icon(Icons.send),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ChatMessageCard extends StatelessWidget {
  const _ChatMessageCard({
    required this.message,
    required this.senderTitle,
    required this.mine,
    required this.onImageTap,
  });

  final ChatMessage message;
  final String senderTitle;
  final bool mine;
  final VoidCallback onImageTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      color:
          mine ? Theme.of(context).colorScheme.primaryContainer : Colors.white,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              senderTitle,
              style: Theme.of(context).textTheme.labelMedium,
            ),
            const SizedBox(height: 6),
            if (message.isImage) ...[
              _ChatImagePreview(
                imageUrl: message.imageUrl,
                onTap: onImageTap,
              ),
              if (message.text.trim().isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(message.text),
              ],
            ] else
              Text(message.text),
            const SizedBox(height: 6),
            Text(
              DateFormat('dd.MM HH:mm').format(message.createdAt),
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}

class _ChatImagePreview extends StatelessWidget {
  const _ChatImagePreview({
    required this.imageUrl,
    required this.onTap,
  });

  final String? imageUrl;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final url = imageUrl;
    if (url == null || url.isEmpty) {
      return const AspectRatio(
        aspectRatio: 4 / 3,
        child: ColoredBox(
          color: Color(0xFFE5E7EB),
          child: Center(child: Icon(Icons.broken_image_outlined)),
        ),
      );
    }

    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: onTap,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: AspectRatio(
          aspectRatio: 4 / 3,
          child: CachedNetworkImage(
            imageUrl: url,
            fit: BoxFit.cover,
            memCacheWidth: 700,
            placeholder: (context, _) => const Center(
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            errorWidget: (context, _, __) => const ColoredBox(
              color: Color(0xFFE5E7EB),
              child: Center(child: Icon(Icons.broken_image_outlined)),
            ),
          ),
        ),
      ),
    );
  }
}
