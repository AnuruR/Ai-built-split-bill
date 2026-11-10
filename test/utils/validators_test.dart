import 'package:flutter_test/flutter_test.dart';
import 'package:snapsplit/utils/validators.dart';

void main() {
  test('email', () {
    expect(Validators.email(''), isNotNull);
    expect(Validators.email('abc'), isNotNull);
    expect(Validators.email('a@b'), isNotNull);
    expect(Validators.email('a b@c.lk'), isNotNull);
    expect(Validators.email(' student@ruh.ac.lk '), isNull);
  });
  test('password: 8 characters is the boundary', () {
    expect(Validators.password(''), isNotNull);
    expect(Validators.password('1234567'), isNotNull);
    expect(Validators.password('12345678'), isNull);
  });
  test('confirm password', () {
    expect(Validators.confirmPassword('abc', 'abd'), isNotNull);
    expect(Validators.confirmPassword('abc', 'abc'), isNull);
  });
  test('required text', () {
    expect(Validators.requiredText('  ', 'x'), 'Enter x');
    expect(Validators.requiredText('Amal', 'x'), isNull);
  });
}
