import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_contacts/flutter_contacts.dart';
import 'package:provider/provider.dart';

import '../models/participant.dart';
import '../models/project.dart';
import '../repositories/project_repository.dart';
import '../widgets/empty_state.dart';

class ParticipantsScreen extends StatelessWidget {
  const ParticipantsScreen({super.key, required this.project});

  final Project project;

  Future<void> _addFromContacts(BuildContext context) async {
    final repository = context.read<ProjectRepository>();

    // Сначала просим доступ к контактам. Без этого iOS/Android не дадут
    // прочитать телефонную книгу пользователя.
    if (!await FlutterContacts.requestPermission(readonly: true)) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Нет доступа к телефонной книге')),
        );
      }
      return;
    }

    // Открываем системный экран выбора контакта. Это привычно для пользователя
    // и не требует делать собственный список контактов в MVP.
    final contact = await FlutterContacts.openExternalPick();
    final phone = contact?.phones.isNotEmpty == true
        ? contact!.phones.first.number.replaceAll(' ', '')
        : null;

    if (contact == null || phone == null || phone.isEmpty) {
      return;
    }

    // Репозиторий сохранит исполнителя и добавит его номер в доступы объекта.
    await repository.addParticipantFromContact(
      projectId: project.id,
      name: contact.displayName,
      phoneNumber: phone,
    );
  }

  @override
  Widget build(BuildContext context) {
    final repository = context.read<ProjectRepository>();
    final currentUserId = FirebaseAuth.instance.currentUser?.uid;
    final isOwner = currentUserId == project.ownerId;

    return Scaffold(
      appBar: AppBar(title: const Text('Исполнители')),
      body: StreamBuilder<List<Participant>>(
        stream: repository.watchParticipants(project.id),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          final participants = snapshot.data ?? [];
          if (participants.isEmpty) {
            return const EmptyState(
              icon: Icons.groups,
              title: 'Участников нет',
              subtitle: 'Добавьте исполнителя из телефонной книги.',
            );
          }

          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: participants.length,
            separatorBuilder: (_, __) => const SizedBox(height: 8),
            itemBuilder: (context, index) {
              final participant = participants[index];
              return Card(
                child: ListTile(
                  leading: const CircleAvatar(child: Icon(Icons.person)),
                  title: Text(participant.name),
                  subtitle: Text(participant.phoneNumber),
                  trailing: Text(participant.role == 'owner' ? 'Владелец' : 'Исполнитель'),
                ),
              );
            },
          );
        },
      ),
      // Только владелец видит кнопку добавления исполнителей.
      // Это совпадает с Firestore rules: executor может видеть объект,
      // но не может менять список участников.
      floatingActionButton: isOwner
          ? FloatingActionButton.extended(
              onPressed: () => _addFromContacts(context),
              icon: const Icon(Icons.person_add),
              label: const Text('Добавить'),
            )
          : null,
    );
  }
}
