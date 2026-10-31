import 'package:ai_smart_healthcare/utils/validators.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('email', () {
    test('rejects empty and invalid', () {
      expect(Validators.email(''), isNotNull);
      expect(Validators.email('abc'), isNotNull);
      expect(Validators.email('a@b'), isNotNull);
    });
    test('accepts valid', () => expect(Validators.email(' ayesha@example.com '), isNull));
  });

  group('password', () {
    test('needs 8 chars, a letter and a number', () {
      expect(Validators.password('short1'), isNotNull);
      expect(Validators.password('password'), isNotNull);
      expect(Validators.password('12345678'), isNotNull);
      expect(Validators.password('Secure123'), isNull);
    });
  });

  test('confirm password must match', () {
    final check = Validators.confirmPassword(() => 'Secure123');
    expect(check('Secure124'), 'Passwords do not match');
    expect(check('Secure123'), isNull);
  });

  test('full name', () {
    expect(Validators.fullName(' '), isNotNull);
    expect(Validators.fullName('A'), isNotNull);
    expect(Validators.fullName('Ali'), isNull);
  });
}
