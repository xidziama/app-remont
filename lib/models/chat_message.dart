import '../utils/firestore_field_reader.dart';

/// Type of a project chat message.
///
/// The enum is stored as a short string in Firestore. This keeps the database
/// readable in Firebase Console and lets the UI render text and image messages
/// through the same ChatMessage model.
enum ChatMessageType {
  text('text'),
  image('image');

  const ChatMessageType(this.firestoreValue);

  final String firestoreValue;

  /// Converts a Firestore string into a typed enum value.
  ///
  /// Old messages do not have `type`, so the safe fallback is `text`.
  static ChatMessageType fromFirestore(String value) {
    return ChatMessageType.values.firstWhere(
      (type) => type.firestoreValue == value,
      orElse: () => ChatMessageType.text,
    );
  }
}

/// One message in the project chat.
///
/// Text and image messages share the same collection:
/// `projects/{projectId}/messages/{messageId}`.
///
/// Image bytes are never stored in Firestore. Firestore stores only the
/// storage path (`storagePath`) — the download URL is no longer persisted
/// (see StorageImage/PhotoUrlResolver), a fresh one is requested on display.
/// The real file lives in Yandex Object Storage at
/// `projects/{projectId}/chat/{messageId}.jpg`.
class ChatMessage {
  const ChatMessage({
    required this.id,
    required this.senderId,
    required this.senderName,
    required this.text,
    required this.type,
    required this.createdAt,
    this.imageUrl,
    this.storagePath,
  });

  /// Firestore document id.
  final String id;

  /// Firebase Auth uid of the sender.
  final String senderId;

  /// Human-readable sender name. In Email/Password auth this is usually email.
  final String senderName;

  /// Text message body or optional image caption.
  final String text;

  /// Tells the UI whether to render text or image preview.
  final ChatMessageType type;

  /// Creation date used for chat ordering.
  final DateTime createdAt;

  /// Устаревшее поле: presigned-ссылка на момент отправки. Больше не
  /// используется для показа (см. StorageImage) — новые сообщения пишут
  /// сюда `null`. Оставлено для чтения старых записей.
  final String? imageUrl;

  /// Ключ файла в Yandex Object Storage — по нему запрашивается свежая
  /// ссылка на показ и делается удаление.
  final String? storagePath;

  bool get isImage => type == ChatMessageType.image;

  /// Converts the model into Firestore-friendly data.
  Map<String, dynamic> toMap() {
    return {
      'senderId': senderId,
      'senderName': senderName,
      'text': text,
      'type': type.firestoreValue,
      'imageUrl': imageUrl,
      'storagePath': storagePath,
      'createdAt': createdAt.toIso8601String(),
    };
  }

  /// Creates a safe model from Firestore data.
  ///
  /// Every field has a fallback because emulator data can be created manually
  /// and older documents may not contain the new image-related fields.
  factory ChatMessage.fromMap(String id, Map<String, dynamic> map) {
    return ChatMessage(
      id: id,
      senderId: FirestoreFieldReader.string(map, 'senderId'),
      senderName: FirestoreFieldReader.string(
        map,
        'senderName',
        fallback: 'Участник',
      ),
      text: FirestoreFieldReader.string(map, 'text'),
      type: ChatMessageType.fromFirestore(
        FirestoreFieldReader.string(map, 'type', fallback: 'text'),
      ),
      createdAt: FirestoreFieldReader.dateTime(map, 'createdAt'),
      imageUrl: FirestoreFieldReader.nullableString(map, 'imageUrl'),
      storagePath: FirestoreFieldReader.nullableString(map, 'storagePath'),
    );
  }
}
