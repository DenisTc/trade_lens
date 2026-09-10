import 'dart:async';

import 'package:app_links/app_links.dart';
import 'package:core/core.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tradelens/deep_links.dart';
import 'package:tradelens/router.dart';

/// Opens the route a link points at: the one the app was launched with and
/// every link that arrives while it runs.
///
/// A link that is not ours, or points at a route outside the allowlist, is
/// ignored: the app stays where it is instead of navigating somewhere the
/// link author chose.
class DeepLinkLifecycle extends ConsumerStatefulWidget {
  const DeepLinkLifecycle({
    required this.child,
    super.key,
    this.links,
    this.logger = const NoopLogger(),
  });

  final Widget child;

  /// Injected in tests; the plugin is used when null.
  final Stream<Uri>? links;
  final Logger logger;

  @override
  ConsumerState<DeepLinkLifecycle> createState() => _DeepLinkLifecycleState();
}

class _DeepLinkLifecycleState extends ConsumerState<DeepLinkLifecycle> {
  StreamSubscription<Uri>? _subscription;

  @override
  void initState() {
    super.initState();
    // `uriLinkStream` replays the launch link, so one subscription covers
    // both the cold start and later links.
    final links = widget.links ?? AppLinks().uriLinkStream;
    _subscription = links.listen(
      _open,
      onError: (Object e) => widget.logger.warn('deep link stream failed', e),
    );
  }

  @override
  void dispose() {
    unawaited(_subscription?.cancel());
    super.dispose();
  }

  void _open(Uri uri) {
    final route = DeepLinks.routeFor(uri);
    if (route == null) {
      widget.logger.warn('deep link ignored: $uri');
      return;
    }
    widget.logger.info('deep link → $route');
    ref.read(routerProvider).go(route);
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
