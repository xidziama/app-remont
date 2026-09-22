import '../utils/firestore_field_reader.dart';

enum ExpenseCategory {
  materials,
  tools,
  labor,
  delivery,
  other;

  String get label {
    switch (this) {
      case ExpenseCategory.materials:
        return 'Материалы';
      case ExpenseCategory.tools:
        return 'Инструменты';
      case ExpenseCategory.labor:
        return 'Работы';
      case ExpenseCategory.delivery:
        return 'Доставка';
      case ExpenseCategory.other:
        return 'Другое';
    }
  }

  static ExpenseCategory fromName(String value) {
    return ExpenseCategory.values.firstWhere(
      (category) => category.name == value,
      orElse: () => ExpenseCategory.other,
    );
  }
}

/// Full expense/receipt model.
///
/// Receipt images live in Yandex Object Storage. Firestore stores only
/// metadata and `receiptStoragePath` — `receiptUrl` is a legacy field kept
/// for reading old documents, new writes leave it `null` (see
/// StorageImage/PhotoUrlResolver: the download link is requested fresh on
/// display instead of being persisted).
class Expense {
  const Expense({
    required this.id,
    required this.projectId,
    required this.amount,
    required this.category,
    required this.date,
    required this.createdAt,
    required this.createdBy,
    required this.isPaid,
    this.stageId,
    this.stageTitle,
    this.comment,
    this.receiptUrl,
    this.receiptStoragePath,
    this.paidAt,
    this.paidBy,
  });

  final String id;
  final String projectId;
  final String? stageId;
  final String? stageTitle;
  final double amount;
  final ExpenseCategory category;
  final DateTime date;
  final DateTime createdAt;
  final String createdBy;
  final String? comment;
  final String? receiptUrl;
  final String? receiptStoragePath;
  final bool isPaid;
  final DateTime? paidAt;
  final String? paidBy;

  bool get hasStage => stageId != null && stageId!.isNotEmpty;

  String get displayStageTitle {
    final value = stageTitle;
    if (value == null || value.isEmpty) {
      return 'Иное';
    }

    return value;
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'projectId': projectId,
      'stageId': stageId,
      'stageTitle': stageTitle ?? 'Иное',
      'amount': amount,
      'category': category.name,
      'date': date.toIso8601String(),
      'createdAt': createdAt.toIso8601String(),
      'createdBy': createdBy,
      'comment': comment,
      'receiptUrl': receiptUrl,
      'receiptPhotoUrl': receiptUrl,
      'downloadUrl': receiptUrl,
      'storagePath': receiptStoragePath,
      'receiptStoragePath': receiptStoragePath,
      'isPaid': isPaid,
      'paidAt': paidAt?.toIso8601String(),
      'paidBy': paidBy,
    };
  }

  factory Expense.fromMap(String id, Map<String, dynamic> map) {
    final receiptUrl = FirestoreFieldReader.nullableString(map, 'receiptUrl') ??
        FirestoreFieldReader.nullableString(map, 'downloadUrl') ??
        FirestoreFieldReader.nullableString(map, 'receiptPhotoUrl');

    final storagePath =
        FirestoreFieldReader.nullableString(map, 'receiptStoragePath') ??
            FirestoreFieldReader.nullableString(map, 'storagePath');

    return Expense(
      id: id,
      projectId: FirestoreFieldReader.string(map, 'projectId'),
      stageId: FirestoreFieldReader.nullableString(map, 'stageId'),
      stageTitle: FirestoreFieldReader.nullableString(map, 'stageTitle'),
      amount: FirestoreFieldReader.doubleValue(map, 'amount'),
      category: ExpenseCategory.fromName(
        FirestoreFieldReader.string(map, 'category'),
      ),
      date: FirestoreFieldReader.dateTime(map, 'date'),
      createdAt: FirestoreFieldReader.dateTime(map, 'createdAt'),
      createdBy: FirestoreFieldReader.string(map, 'createdBy'),
      comment: FirestoreFieldReader.nullableString(map, 'comment'),
      receiptUrl: receiptUrl,
      receiptStoragePath: storagePath,
      isPaid: FirestoreFieldReader.boolValue(map, 'isPaid'),
      paidAt: FirestoreFieldReader.nullableDateTime(map, 'paidAt'),
      paidBy: FirestoreFieldReader.nullableString(map, 'paidBy'),
    );
  }
}
