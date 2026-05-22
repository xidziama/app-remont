import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../models/chat_message.dart';
import '../models/project.dart';
import '../repositories/project_repository.dart';

class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key, required this.project});

  final Project project;

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final text = _controller.text.trim();

    // Пустые сообщения не отправляем, чтобы не засорять чат.
    if (text.isEmpty) {
      return;
    }

    _controller.clear();

    // Сохранение сообщения идет через репозиторий, который знает путь Firestore.
    await context.read<ProjectRepository>().sendMessage(widget.project.id, text);
  }

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    final repository = context.read<ProjectRepository>();

    return Scaffold(
      appBar: AppBar(title: const Text('Чат')),
      body: Column(
        children: [
          Expanded(
            child: StreamBuilder<List<ChatMessage>>(
              // Чат подписан на Firestore: новые сообщения появляются сразу.
              stream: repository.watchMessages(widget.project.id),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }

                final messages = snapshot.data ?? [];
                return ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: messages.length,
                  itemBuilder: (context, index) {
                    final message = messages[index];
                    final mine = message.senderId == uid;
                    return Align(
                      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 320),
                        child: Card(
                          color: mine
                              ? Theme.of(context).colorScheme.primaryContainer
                              : Colors.white,
                          child: Padding(
                            padding: const EdgeInsets.all(12),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  message.senderName,
                                  style: Theme.of(context).textTheme.labelMedium,
                                ),
                                const SizedBox(height: 4),
                                Text(message.text),
                                const SizedBox(height: 6),
                                Text(
                                  DateFormat('dd.MM HH:mm').format(message.createdAt),
                                  style: Theme.of(context).textTheme.bodySmall,
                                ),
                              ],
                            ),
                          ),
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
                children: [
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
                    onPressed: _send,
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
