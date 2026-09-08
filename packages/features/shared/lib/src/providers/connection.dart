import 'package:domain/domain.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'connection.g.dart';

/// Connection state of the live-data socket for the app-bar indicator.
/// The app overrides this with the WebSocket client's state stream; REST
/// fallback sources report [ConnectionStatus.idle].
@Riverpod(keepAlive: true)
Stream<ConnectionStatus> connectionStatus(Ref ref) =>
    Stream.value(ConnectionStatus.idle);
