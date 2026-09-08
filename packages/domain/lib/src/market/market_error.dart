import 'package:freezed_annotation/freezed_annotation.dart';

part 'market_error.freezed.dart';

/// Failures a source can report. Implements [Exception] so streams can
/// surface it through `addError` without wrapping.
/// The two network cases are deliberately
/// distinct: a confirmed geo-block (HTTP 451) moves to the next source,
/// while a timeout or 5xx is retried first (spec, "Гео-ограничения").
@freezed
sealed class MarketError with _$MarketError implements Exception {
  /// HTTP 451: the source confirmed it does not serve this region.
  const factory MarketError.regionBlocked({required String sourceId}) =
      RegionBlocked;

  /// Timeout, 5xx or a dead WebSocket: the source exists but does not answer.
  const factory MarketError.unavailable({
    required String sourceId,
    required String reason,
  }) = Unavailable;

  /// HTTP 429 with a retry hint, or 418 (IP ban) with the ban duration.
  const factory MarketError.rateLimited({
    required String sourceId,
    required Duration retryAfter,
  }) = RateLimited;

  /// The shared CoinGecko demo key ran out of monthly quota.
  const factory MarketError.quotaExhausted({required String sourceId}) =
      QuotaExhausted;

  /// No connectivity at all: DNS, socket, TLS.
  const factory MarketError.network({
    required String sourceId,
    required String reason,
  }) = NetworkFailure;

  /// The response did not match the expected shape.
  const factory MarketError.parse({
    required String sourceId,
    required String message,
  }) = ParseFailure;
}
