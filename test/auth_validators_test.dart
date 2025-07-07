import 'package:flutter_test/flutter_test.dart';
// Helper function that simulates your password validation logic
String? validatePassword(String? value) {
  if (value == null || value.isEmpty) {
    return 'Password is required.';
  }
  if (value.length < 6) {
    return 'Password must be at least 6 characters.';
  }
  return null; // Return null if valid
}
void main() {
  // Group tests related to authentication validators
  group('Auth Validators', () {
    test('UT-09: Empty password returns error message', () {
      var result = validatePassword('');
      expect(result, 'Password is required.');
    });
    test('UT-10: Short password returns error message', () {
      var result = validatePassword('pass');
      expect(result, 'Password must be at least 6 characters.');
    });
    test('Valid password returns null (no error)', () {
      var result = validatePassword('Password123');
      expect(result, isNull);
    });

  });
}