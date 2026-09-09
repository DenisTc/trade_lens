import 'package:meta/meta.dart';

/// Why a summary could not be produced. The UI maps each case to a hint
/// (spec: 401 "check the key", 429 "wait", network "retry").
@immutable
sealed class AiError implements Exception {
  const AiError();

  /// HTTP 401/403: the key is missing, revoked or lacks permission.
  const factory AiError.unauthorized() = AiUnauthorized;

  /// HTTP 429 or 529: try again later.
  const factory AiError.rateLimited({Duration? retryAfter}) = AiRateLimited;

  /// No connection, timeout, or a 5xx.
  const factory AiError.network(String reason) = AiNetwork;

  /// HTTP 400/404/413: the request itself is wrong (bad model id, too
  /// large). Not the user's fault; reported.
  const factory AiError.badRequest(String message) = AiBadRequest;

  /// The model declined (`stop_reason: refusal`).
  const factory AiError.refused() = AiRefused;

  /// The tool loop or token budget ran out before an answer.
  const factory AiError.budgetExceeded(String what) = AiBudgetExceeded;

  /// The stream ended mid-way or carried something unparsable.
  const factory AiError.invalidResponse(String reason) = AiInvalidResponse;

  /// The caller cancelled (left the screen).
  const factory AiError.cancelled() = AiCancelled;
}

final class AiUnauthorized extends AiError {
  const AiUnauthorized();
}

final class AiRateLimited extends AiError {
  const AiRateLimited({this.retryAfter});

  final Duration? retryAfter;
}

final class AiNetwork extends AiError {
  const AiNetwork(this.reason);

  final String reason;

  @override
  String toString() => 'AiNetwork($reason)';
}

final class AiBadRequest extends AiError {
  const AiBadRequest(this.message);

  final String message;

  @override
  String toString() => 'AiBadRequest($message)';
}

final class AiRefused extends AiError {
  const AiRefused();
}

final class AiBudgetExceeded extends AiError {
  const AiBudgetExceeded(this.what);

  final String what;

  @override
  String toString() => 'AiBudgetExceeded($what)';
}

final class AiInvalidResponse extends AiError {
  const AiInvalidResponse(this.reason);

  final String reason;

  @override
  String toString() => 'AiInvalidResponse($reason)';
}

final class AiCancelled extends AiError {
  const AiCancelled();
}

/// Maps an HTTP status (and the API's error body, when readable) to an
/// [AiError]. Retryable statuses become [AiRateLimited] or [AiNetwork].
AiError aiErrorForStatus(int status, {String? message, Duration? retryAfter}) =>
    switch (status) {
      401 || 403 => const AiError.unauthorized(),
      429 || 529 => AiError.rateLimited(retryAfter: retryAfter),
      >= 500 => AiError.network('HTTP $status'),
      _ => AiError.badRequest(message ?? 'HTTP $status'),
    };
