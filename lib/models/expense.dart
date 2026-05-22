import '../utils/firestore_field_reader.dart';

/// Категории расходов.
///
/// Enum позволяет показывать фиксированный список категорий в форме чека.
enum ExpenseCategory {
  materials,
  tools,
  labor,
  delivery,
  other;

  /// Название категории для интерфейса.
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
}

/// Expense описывает один расход или чек.
///
/// Фото чека хранится в Firebase Storage, а в Firestore лежит только receiptUrl.
class Expense {
  const Expense({
    required this.id,
    required this.amount,
    required this.category,
    required this.date,
    required this.createdBy,
    this.comment,
    this.receiptUrl,
  });

  /// ID документа расхода.
  final String id;

  /// Сумма расхода.
  final double amount;

  /// Категория расхода.
  final ExpenseCategory category;

  /// Дата покупки или оплаты.
  final DateTime date;

  /// UID пользователя, который добавил расход.
  final String createdBy;

  /// Комментарий пользователя.
  final String? comment;

  /// Ссылка на фото чека в Firebase Storage.
  final String? receiptUrl;

  /// Превращает расход в Map для Firestore.
  Map<String, dynamic> toMap() {
    return {
      'amount': amount,
      'category': category.name,
      'date': date.toIso8601String(),
      'createdBy': createdBy,
      'comment': comment,
      'receiptUrl': receiptUrl,
    };
  }

  /// Собирает Expense из Firestore document.
  factory Expense.fromMap(String id, Map<String, dynamic> map) {
    // Категория и дата могут отсутствовать в тестовых данных.
    // Безопасное чтение дает рабочие fallback-значения вместо runtime error.
    final categoryName = FirestoreFieldReader.string(map, 'category');

    return Expense(
      id: id,
      amount: FirestoreFieldReader.doubleValue(map, 'amount'),
      category: ExpenseCategory.values.firstWhere(
        (category) => category.name == categoryName,
        orElse: () => ExpenseCategory.other,
      ),
      date: FirestoreFieldReader.dateTime(map, 'date'),
      createdBy: FirestoreFieldReader.string(map, 'createdBy'),
      comment: FirestoreFieldReader.nullableString(map, 'comment'),
      receiptUrl: FirestoreFieldReader.nullableString(map, 'receiptUrl'),
    );
  }
}
