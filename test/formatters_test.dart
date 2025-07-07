import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';
// Helper function that simulates your time formatting logic
String formatRelativeTime(DateTime dateTime) {
  final now = DateTime.now();
  final difference = now.difference(dateTime);
  if (difference.inDays < 1) return 'Today';
  if (difference.inDays < 7) return '${difference.inDays} day${difference.inDays > 1 ? 's' : ''} ago';
  if (difference.inDays < 30) return '${(difference.inDays / 7).floor()} week${(difference.inDays / 7).floor() > 1 ? 's' : ''} ago';
  if (difference.inDays < 365) return '${(difference.inDays / 30).floor()} month${(difference.inDays / 30).floor() > 1 ? 's' : ''} ago';
  return DateFormat('dd/MM/yyyy').format(dateTime);
}
void main() {
  group('Date and Time Formatters', () {
    test('UT-03: Correctly formats a date from 3 days ago', () {
      final date = DateTime.now().subtract(const Duration(days: 3));
      expect(formatRelativeTime(date), '3 days ago');
    });
    test('UT-04: Correctly formats a date from 2 weeks ago', () {
      final date = DateTime.now().subtract(const Duration(days: 15));
      expect(formatRelativeTime(date), '2 weeks ago');
    });
    test('UT-05: Correctly formats a date from over a year ago', () {
      final date = DateTime.now().subtract(const Duration(days: 400));
      expect(formatRelativeTime(date), DateFormat('dd/MM/yyyy').format(date));
    });
  });
}