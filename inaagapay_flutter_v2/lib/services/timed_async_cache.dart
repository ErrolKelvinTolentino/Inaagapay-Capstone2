/// Bounded, expiring reads. Concurrent callers share a request; a failed read
/// is never cached, and invalidation prevents older requests repopulating it.
class TimedAsyncCache<T> {
  TimedAsyncCache(this.ttl);
  final Duration ttl;
  final _values = <String, ({DateTime at, T value})>{};
  final _pending = <String, Future<T>>{};
  int _generation = 0;

  T? peek(String key) {
    final entry = _values[key];
    if (entry == null || DateTime.now().difference(entry.at) >= ttl) {
      return null;
    }
    return entry.value;
  }

  Future<T> get(String key, Future<T> Function() fetch) {
    final value = peek(key);
    if (value != null) return Future.value(value);
    if (_pending.containsKey(key)) return _pending[key]!;
    final generation = _generation;
    late final Future<T> request;
    request = Future<T>.sync(fetch).then((value) {
      if (generation == _generation) {
        if (_values.length >= 12) _values.remove(_values.keys.first);
        _values[key] = (at: DateTime.now(), value: value);
      }
      return value;
    }).whenComplete(() {
      if (identical(_pending[key], request)) _pending.remove(key);
    });
    _pending[key] = request;
    return request;
  }

  void clear() {
    _generation++;
    _values.clear();
    _pending.clear();
  }
}
