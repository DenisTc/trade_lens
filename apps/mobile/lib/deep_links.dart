import 'package:sdui/sdui.dart';
import 'package:tradelens/router.dart';

/// Everything the app answers to from outside.
///
/// - `tradelens://p/BTCUSDT` — custom scheme, works with no domain and no
///   developer account, and is what the e2e test and the QR demo use;
/// - `https://denistc.github.io/trade_lens/p/BTCUSDT` — the same route as
///   an https link, verified by the files under `docs/.well-known`
///   (Universal Links on iOS, App Links on Android).
abstract final class DeepLinks {
  static const scheme = 'tradelens';
  static const host = 'denistc.github.io';

  /// GitHub Pages serves the site under the repository name.
  static const basePath = '/trade_lens';

  /// The same allowlist the server-driven buttons use: one place decides
  /// which routes the outside world may open.
  static final allowlist = SduiRouteAllowlist(AppRoutes.sduiAllowed);

  /// The in-app route for [uri], or null when the link is not ours or
  /// points at something we do not open from outside.
  ///
  /// The query string is dropped on purpose: a route is all we take from a
  /// link, so nothing from a URL can reach the app as a parameter.
  static String? routeFor(Uri uri) {
    // A link carries a route and nothing else: no credentials, no port,
    // no doubled separators to normalise our way out of.
    if (uri.userInfo.isNotEmpty || uri.hasPort) return null;
    if (uri.path.contains('//')) return null;
    final path = switch (uri.scheme) {
      // tradelens://p/BTCUSDT parses as host=p, path=/BTCUSDT; the
      // three-slash form puts everything in the path, and a bare
      // `tradelens://` carries nothing to open.
      scheme => uri.host.isEmpty ? uri.path : '/${uri.host}${uri.path}',
      'https' when uri.host == host => _stripBase(uri.path),
      _ => null,
    };
    if (path == null || path.isEmpty) return null;
    final normalised = path.length > 1 && path.endsWith('/')
        ? path.substring(0, path.length - 1)
        : path;
    return allowlist.allows(normalised) ? normalised : null;
  }

  static String? _stripBase(String path) {
    if (path == basePath || path == '$basePath/') return AppRoutes.markets;
    if (!path.startsWith('$basePath/')) return null;
    return path.substring(basePath.length);
  }

  /// The public link for a pair, for sharing and for the README.
  static Uri pairLink(String symbol) =>
      Uri.https(host, '$basePath${AppRoutes.pairPath(symbol)}');
}
