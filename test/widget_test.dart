import 'package:flutter_test/flutter_test.dart';
import 'package:nflight/core/bcbp.dart';

void main() {
  test('names are title-cased', () {
    expect(prettyName('IONESCU-POP/ANA MARIA MRS'), 'Ana Maria Ionescu-Pop');
  });
}
