import 'package:sentry_flutter/sentry_flutter.dart';

/// Hosts whose requests carry a user secret. Breadcrumbs for them keep only
/// the origin and the status code.
const sensitiveHosts = {'api.anthropic.com'};

/// Header names that must never reach Sentry, on any host.
const secretHeaders = {'authorization', 'x-api-key', 'x-cg-demo-api-key'};

/// `beforeBreadcrumb` hook: strips query strings and secret headers so the
/// user's Claude API key cannot leak through HTTP breadcrumbs, even if a
/// future SDK version starts recording headers.
Breadcrumb? sanitizeBreadcrumb(Breadcrumb? breadcrumb, Hint hint) {
  if (breadcrumb == null) return null;
  final data = breadcrumb.data;
  if (data == null) return breadcrumb;

  final cleaned = Map<String, dynamic>.of(data)
    ..removeWhere((key, _) => secretHeaders.contains(key.toLowerCase()));

  for (final key in ['url', 'uri']) {
    final url = cleaned[key];
    if (url is String) cleaned[key] = redactUrl(url);
  }
  for (final key in ['headers', 'request_headers', 'response_headers']) {
    final headers = cleaned[key];
    if (headers is Map) {
      cleaned[key] = {
        for (final entry in headers.entries)
          if (!secretHeaders.contains('${entry.key}'.toLowerCase()))
            entry.key: entry.value,
      };
    }
  }
  return breadcrumb..data = cleaned;
}

/// Sensitive hosts lose path and query; everyone else loses only the query
/// (CoinGecko puts nothing secret in the query today, but it costs nothing).
String redactUrl(String raw) {
  final uri = Uri.tryParse(raw);
  if (uri == null || !uri.hasScheme) return raw;
  if (sensitiveHosts.contains(uri.host)) return '${uri.origin}/[redacted]';
  return uri.hasQuery
      ? uri.replace(query: '').toString().replaceAll('?', '')
      : raw;
}
