import 'package:flutter_test/flutter_test.dart';
import 'package:vigiroad/core/config/app_config.dart';

void main() {
  test('valeurs par défaut sans --dart-define', () {
    final c = AppConfig.fromEnvironment();
    expect(c.environment, AppEnvironment.dev);
    expect(c.isProduction, isFalse);
    expect(c.platesSyncEnabled, isFalse);
    expect(Uri.parse(c.routingBaseUrl).isScheme('https'), isTrue);
    expect(Uri.parse(c.geocodingBaseUrl).isScheme('https'), isTrue);
    expect(c.userAgent, startsWith('VIGIROAD/'));
  });
}
