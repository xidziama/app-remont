import '../utils/firestore_field_reader.dart';

/// Тип фотографии внутри этапа.
///
/// receipt хранится в той же subcollection, что и остальные фото этапа, но UI
/// показывает его только во вкладке "Чеки".
enum PhotoType {
  before('before'),
  progress('progress'),
  after('after'),
  problem('problem'),
  receipt('receipt');

  const PhotoType(this.firestoreValue);

  final String firestoreValue;

  String get label {
    switch (this) {
      case PhotoType.before:
        return 'До';
      case PhotoType.progress:
        return 'В процессе';
      case PhotoType.after:
        return 'После';
      case PhotoType.problem:
        return 'Проблема';
      case PhotoType.receipt:
        return 'Чек';
    }
  }

  static PhotoType fromFirestore(String value) {
    return PhotoType.values.firstWhere(
      (type) => type.firestoreValue == value,
      orElse: () => PhotoType.progress,
    );
  }
}

/// Production-модель фотографии этапа.
///
/// Документ хранится по пути:
/// projects/{projectId}/stages/{stageId}/photos/{photoId}
///
/// В Firestore не хранится base64/blob. Здесь только ссылка на Firebase Storage
/// и легкие метаданные, которые нужны для UI и будущей аналитики.
class Photo {
  const Photo({
    required this.id,
    required this.projectId,
    required this.stageId,
    required this.type,
    required this.downloadUrl,
    required this.storagePath,
    required this.comment,
    required this.amount,
    this.expenseId,
    this.receiptCategory,
    this.receiptDate,
    this.isPaid = false,
    this.paidAt,
    this.paidBy,
    required this.uploadedBy,
    required this.createdAt,
    required this.width,
    required this.height,
    required this.sizeBytes,
    required this.isFavorite,
  });

  final String id;
  final String projectId;
  final String stageId;
  final PhotoType type;
  final String downloadUrl;
  final String storagePath;
  final String? comment;
  final double? amount;
  final String? expenseId;
  final String? receiptCategory;
  final DateTime? receiptDate;
  final bool isPaid;
  final DateTime? paidAt;
  final String? paidBy;
  final String uploadedBy;
  final DateTime createdAt;
  final int width;
  final int height;
  final int sizeBytes;
  final bool isFavorite;

  bool get isReceipt => type == PhotoType.receipt;

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'projectId': projectId,
      'stageId': stageId,
      'type': type.firestoreValue,
      'downloadUrl': downloadUrl,
      'storagePath': storagePath,
      'comment': comment,
      'amount': amount,
      'expenseId': expenseId,
      'receiptCategory': receiptCategory,
      'receiptDate': receiptDate?.toIso8601String(),
      'isPaid': isPaid,
      'paidAt': paidAt?.toIso8601String(),
      'paidBy': paidBy,
      'uploadedBy': uploadedBy,
      'createdAt': createdAt,
      'width': width,
      'height': height,
      'sizeBytes': sizeBytes,
      'isFavorite': isFavorite,
    };
  }

  factory Photo.fromMap(String id, Map<String, dynamic> map) {
    return Photo(
      id: id,
      projectId: FirestoreFieldReader.string(map, 'projectId'),
      stageId: FirestoreFieldReader.string(map, 'stageId'),
      type: PhotoType.fromFirestore(
        FirestoreFieldReader.string(map, 'type', fallback: 'progress'),
      ),
      downloadUrl: FirestoreFieldReader.string(map, 'downloadUrl'),
      storagePath: FirestoreFieldReader.string(map, 'storagePath'),
      comment: FirestoreFieldReader.nullableString(map, 'comment'),
      amount: map['amount'] == null
          ? null
          : FirestoreFieldReader.doubleValue(map, 'amount'),
      expenseId: FirestoreFieldReader.nullableString(map, 'expenseId'),
      receiptCategory: FirestoreFieldReader.nullableString(
        map,
        'receiptCategory',
      ),
      receiptDate: FirestoreFieldReader.nullableDateTime(map, 'receiptDate'),
      isPaid: FirestoreFieldReader.boolValue(map, 'isPaid'),
      paidAt: FirestoreFieldReader.nullableDateTime(map, 'paidAt'),
      paidBy: FirestoreFieldReader.nullableString(map, 'paidBy'),
      uploadedBy: FirestoreFieldReader.string(map, 'uploadedBy'),
      createdAt: FirestoreFieldReader.dateTime(map, 'createdAt'),
      width: FirestoreFieldReader.intValue(map, 'width'),
      height: FirestoreFieldReader.intValue(map, 'height'),
      sizeBytes: FirestoreFieldReader.intValue(map, 'sizeBytes'),
      isFavorite: FirestoreFieldReader.boolValue(map, 'isFavorite'),
    );
  }
}
