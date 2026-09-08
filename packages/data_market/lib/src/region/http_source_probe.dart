import 'package:core/core.dart';
import 'package:data_market/src/http/dio_factory.dart';
import 'package:data_market/src/http/spki_pinning.dart';
import 'package:data_market/src/region/source_probe.dart';
import 'package:data_market/src/region/ws_handshake.dart';
import 'package:dio/dio.dart';

/// Real probe: REST ping, then a WebSocket handshake when the candidate has
/// one. "REST 200 with a dead WS is not a success" (spec).
final class HttpSourceProbe implements SourceProbe {
  HttpSourceProbe({
    required this._wsHandshake,
    this.pins,
    this.restTimeout = const Duration(seconds: 5),
    this.wsTimeout = const Duration(seconds: 3),
    this.logger = const NoopLogger(),
    this._adapter,
  });

  final WsHandshake _wsHandshake;
  final HttpClientAdapter? _adapter;
  final PinSet? pins;
  final Duration restTimeout;
  final Duration wsTimeout;
  final Logger logger;

  @override
  Future<ProbeOutcome> probe(SourceCandidate candidate) async {
    final dio = createDio(
      baseUrl: candidate.restPing,
      pins: pins,
      timeout: restTimeout,
      retries: 0,
      adapter: _adapter,
    );
    try {
      await dio.getUri<Object?>(candidate.restPing);
    } on DioException catch (e) {
      final status = e.response?.statusCode;
      logger.info('probe ${candidate.id}: rest ${status ?? e.type.name}');
      return status == 451
          ? ProbeOutcome.regionBlocked
          : ProbeOutcome.unavailable;
    } finally {
      dio.close();
    }

    final ws = candidate.wsProbe;
    if (ws == null) return ProbeOutcome.ok;
    final alive = await _wsHandshake(ws, wsTimeout);
    logger.info('probe ${candidate.id}: ws ${alive ? 'ok' : 'silent'}');
    return alive ? ProbeOutcome.ok : ProbeOutcome.unavailable;
  }
}
