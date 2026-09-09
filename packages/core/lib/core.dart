/// Shared primitives for TradeLens: `Result`, `Logger`, `Decimal` re-export.
///
/// No Flutter dependency: this package is usable from pure Dart tooling.
library;

export 'package:decimal/decimal.dart' show Decimal, RationalExt;

export 'src/logger.dart';
export 'src/result.dart';
