import '../utils/firestore_field_reader.dart';

/// ChatMessage описывает одно сообщение в чате объекта.
///
/// Сообщения лежат в subcollection:
/// `objects/{projectId}/messages/{messageId}`.
class ChatMessage {
  const ChatMessage({
    required this.id,
    required this.senderId,
    required this.senderName,
    required this.text,
    required this.createdAt,
  });

  /// ID документа сообщения.
  final String id;

  /// UID отправителя.
  final String senderId;

  /// Отображаемое имя отправителя. В MVP это телефон пользователя.
  final String senderName;

  /// Текст сообщения.
  final String text;

  /// Дата создания нужна для сортировки чата.
  final DateTime createdAt;

  /// Превращает сообщение в Map для записи в Firestore.
  Map<String, dynamic> toMap() {
    return {
      'senderId': senderId,
      'senderName': senderName,
      'text': text,
      'createdAt': createdAt.toIso8601String(),
    };
  }

  /// Создает ChatMessage из Firestore document.
  factory ChatMessage.fromMap(String id, Map<String, dynamic> map) {
    // Чат не должен ломаться из-за одного неполного сообщения.
    // Поэтому для каждого поля есть безопасное fallback-значение.
    return ChatMessage(
      id: id,
      senderId: FirestoreFieldReader.string(map, 'senderId'),
      senderName: FirestoreFieldReader.string(
        map,
        'senderName',
        fallback: 'Участник',
      ),
      text: FirestoreFieldReader.string(map, 'text'),
      createdAt: FirestoreFieldReader.dateTime(map, 'createdAt'),
    );
  }
}
