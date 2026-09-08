// Live check of the fallback chain from the current network.
//
//   dart run tool/probe_sources.dart
//
// Prints every probe outcome and the resolver's decision. Run it from a
// US VPN before release to record the region-fallback behaviour in the
// README (spec, "Критерии готовности"). Not a test: it touches the network.
import 'dart:io';

import 'package:core/core.dart';
import 'package:data_market/data_market.dart';

Future<void> main() async {
  final logger = PrintLogger(tag: 'probe', sink: stdout.writeln);
  final resolver = RegionResolver(
    probe: HttpSourceProbe(
      wsHandshake: ioWsHandshake,
      pins: tradeLensPins,
      logger: logger,
    ),
    candidates: defaultCandidates(),
    fallback: coinGeckoFallback,
    logger: logger,
  );
  final resolution = await resolver.resolve();
  stdout
    ..writeln()
    ..writeln('source:    ${resolution.sourceId} (${resolution.candidateId})')
    ..writeln('reason:    ${resolution.reason.name}')
    ..writeln('outcomes:  ${resolution.outcomes}');
}
