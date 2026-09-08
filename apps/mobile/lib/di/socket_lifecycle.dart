import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tradelens/di/market_di.dart';

/// Closes the socket [backgroundGrace] after the app leaves the foreground
/// and reopens it on return (spec, "Жизненный цикл").
///
/// The decision ("should be suspended") is kept separately from the socket,
/// so a source that finishes resolving while the app is already in the
/// background is suspended as soon as it appears.
class SocketLifecycle extends ConsumerStatefulWidget {
  const SocketLifecycle({
    required this.child,
    super.key,
    this.backgroundGrace = const Duration(seconds: 30),
  });

  final Widget child;
  final Duration backgroundGrace;

  @override
  ConsumerState<SocketLifecycle> createState() => _SocketLifecycleState();
}

class _SocketLifecycleState extends ConsumerState<SocketLifecycle> {
  late final AppLifecycleListener _listener;
  ProviderSubscription<AsyncValue<LiveMarket>>? _market;
  Timer? _suspendTimer;
  bool _shouldSuspend = false;

  @override
  void initState() {
    super.initState();
    _listener = AppLifecycleListener(
      onHide: _scheduleSuspend,
      onPause: _scheduleSuspend,
      onResume: _resume,
      onShow: _resume,
    );
    _market = ref.listenManual(liveMarketProvider, (_, _) => _apply());
  }

  @override
  void dispose() {
    _suspendTimer?.cancel();
    _market?.close();
    _listener.dispose();
    super.dispose();
  }

  void _scheduleSuspend() {
    _suspendTimer ??= Timer(widget.backgroundGrace, () {
      _suspendTimer = null;
      _shouldSuspend = true;
      _apply();
    });
  }

  void _resume() {
    _suspendTimer?.cancel();
    _suspendTimer = null;
    _shouldSuspend = false;
    _apply();
  }

  void _apply() {
    final ws = ref.read(liveMarketProvider).value?.ws;
    if (ws == null) return;
    if (_shouldSuspend) {
      ws.suspend();
    } else {
      ws.resume();
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
