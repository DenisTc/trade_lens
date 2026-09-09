/// Routes a config button may open. Patterns are go_router paths with
/// `:param` segments (`/p/:symbol`); anything else, including full URLs,
/// is refused so a config cannot send the user off-app.
final class SduiRouteAllowlist {
  SduiRouteAllowlist(Iterable<String> patterns)
    : _patterns = [for (final p in patterns) _compile(p)];

  final List<RegExp> _patterns;

  bool allows(String route) {
    if (!route.startsWith('/') || route.contains('//')) return false;
    final path = route.split('?').first;
    return _patterns.any((p) => p.hasMatch(path));
  }

  static RegExp _compile(String pattern) {
    final parts = pattern
        .split('/')
        .map((s) => s.startsWith(':') ? '[A-Za-z0-9_-]+' : RegExp.escape(s));
    return RegExp('^${parts.join('/')}\$');
  }
}
