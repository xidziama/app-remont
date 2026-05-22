/// Небольшие функции для работы с телефонами.
///
/// В production лучше подключить полноценную нормализацию номеров по стране.
/// Для MVP оставляем простое правило: убираем пробелы, скобки и дефисы.
class PhoneUtils {
  static String normalize(String phone) {
    return phone
        .replaceAll(' ', '')
        .replaceAll('(', '')
        .replaceAll(')', '')
        .replaceAll('-', '');
  }
}
