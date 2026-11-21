extension IterableX<T> on Iterable<T> {
  /// First element or null (named to avoid clashing with SDK/collection helpers).
  T? get maybeFirst {
    final it = iterator;
    return it.moveNext() ? it.current : null;
  }
}
