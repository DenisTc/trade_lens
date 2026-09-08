/// Reference counts per stream name. The exchange subscription exists while
/// the count is above zero; the client decides *when* to send the commands.
final class SubscriptionRegistry {
  final Map<String, int> _counts = {};

  /// Streams with at least one listener.
  Set<String> get wanted => {
    for (final entry in _counts.entries)
      if (entry.value > 0) entry.key,
  };

  int count(String stream) => _counts[stream] ?? 0;

  bool get isEmpty => wanted.isEmpty;

  /// Returns the new count; `1` means the first listener just arrived.
  int add(String stream) => _counts[stream] = count(stream) + 1;

  /// Returns the new count; `0` means the last listener just left.
  int remove(String stream) {
    final next = count(stream) - 1;
    if (next <= 0) {
      _counts.remove(stream);
      return 0;
    }
    return _counts[stream] = next;
  }
}
