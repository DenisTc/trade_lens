import 'package:meta/meta.dart';

/// A value that is either a success ([Ok]) or a failure ([Err]).
///
/// Used at package boundaries instead of throwing: data sources return
/// `Result<Quote, MarketError>` and the UI renders both branches explicitly.
sealed class Result<T, E> {
  const Result();

  bool get isOk => this is Ok<T, E>;
  bool get isErr => this is Err<T, E>;

  T? get valueOrNull => switch (this) {
    Ok(:final value) => value,
    Err() => null,
  };

  E? get errorOrNull => switch (this) {
    Ok() => null,
    Err(:final error) => error,
  };

  Result<R, E> map<R>(R Function(T value) transform) => switch (this) {
    Ok(:final value) => Ok(transform(value)),
    Err(:final error) => Err(error),
  };

  Result<T, F> mapError<F>(F Function(E error) transform) => switch (this) {
    Ok(:final value) => Ok(value),
    Err(:final error) => Err(transform(error)),
  };

  Result<R, E> flatMap<R>(Result<R, E> Function(T value) transform) =>
      switch (this) {
        Ok(:final value) => transform(value),
        Err(:final error) => Err(error),
      };

  R when<R>({
    required R Function(T value) ok,
    required R Function(E error) err,
  }) => switch (this) {
    Ok(:final value) => ok(value),
    Err(:final error) => err(error),
  };
}

@immutable
final class Ok<T, E> extends Result<T, E> {
  const Ok(this.value);

  final T value;

  @override
  bool operator ==(Object other) => other is Ok<T, E> && other.value == value;

  @override
  int get hashCode => Object.hash(Ok, value);

  @override
  String toString() => 'Ok($value)';
}

@immutable
final class Err<T, E> extends Result<T, E> {
  const Err(this.error);

  final E error;

  @override
  bool operator ==(Object other) => other is Err<T, E> && other.error == error;

  @override
  int get hashCode => Object.hash(Err, error);

  @override
  String toString() => 'Err($error)';
}
