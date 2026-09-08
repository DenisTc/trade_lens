import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tradelens/di/market_di.dart';

/// Closes the socket [backgroundGrace] after the app leaves the foreground
/// and reopens it on return (spec, "Жизненный цикл").
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
  Timer? _suspendTimer;

  @override
  void initState() {
    super.initState();
    _listener = AppLifecycleListener(
      onHide: _scheduleSuspend,
      onPause: _scheduleSuspend,
      onResume: _resume,
      onShow: _resume,
    );
  }

  @override
  void dispose() {
    _suspendTimer?.cancel();
    _listener.dispose();
    super.dispose();
  }

  void _scheduleSuspend() {
    _suspendTimer ??= Timer(widget.backgroundGrace, () {
      _suspendTimer = null;
      ref.read(liveMarketProvider).value?.ws?.suspend();
    });
  }

  void _resume() {
    _suspendTimer?.cancel();
    _suspendTimer = null;
    ref.read(liveMarketProvider).value?.ws?.resume();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
