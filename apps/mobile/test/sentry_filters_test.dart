import 'package:flutter_test/flutter_test.dart';
import 'package:sentry_flutter/sentry_flutter.dart';
import 'package:tradelens/observability/sentry_filters.dart';

void main() {
  final hint = Hint();

  test('Anthropic breadcrumbs keep only the origin and status', () {
    final crumb = Breadcrumb.http(
      url: Uri.parse('https://api.anthropic.com/v1/messages?beta=1'),
      method: 'POST',
      statusCode: 401,
    );

    final result = sanitizeBreadcrumb(crumb, hint)!;

    expect(result.data!['url'], 'https://api.anthropic.com/[redacted]');
    expect(result.data!['status_code'], 401);
    expect(result.data!['method'], 'POST');
  });

  test('secret headers are dropped wherever they appear', () {
    final crumb = Breadcrumb(
      category: 'http',
      data: {
        'url': 'https://api.coingecko.com/api/v3/simple/price?ids=bitcoin',
        'Authorization': 'Bearer sk-ant-secret',
        'headers': {'x-api-key': 'sk-ant-secret', 'accept': 'json'},
      },
    );

    final result = sanitizeBreadcrumb(crumb, hint)!;

    expect(result.data!.containsKey('Authorization'), isFalse);
    expect(result.data!['headers'], {'accept': 'json'});
    expect(
      result.data!['url'],
      'https://api.coingecko.com/api/v3/simple/price',
    );
    expect(result.data.toString(), isNot(contains('sk-ant')));
  });

  test('non-http breadcrumbs pass through untouched', () {
    final crumb = Breadcrumb(message: 'tapped summary', category: 'ui');
    expect(sanitizeBreadcrumb(crumb, hint), same(crumb));
    expect(sanitizeBreadcrumb(null, hint), isNull);
  });

  test('redactUrl leaves non-URL strings alone', () {
    expect(redactUrl('not a url'), 'not a url');
    expect(
      redactUrl('https://api.binance.com/api/v3/ping'),
      'https://api.binance.com/api/v3/ping',
    );
  });
}
