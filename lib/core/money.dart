import 'package:intl/intl.dart';

/// Money is stored as an integer number of Kenyan cents to avoid floating
/// point errors (KSh 1 = 100 cents). All arithmetic stays in integers.
class Money implements Comparable<Money> {
  final int cents;
  const Money(this.cents);
  const Money.zero() : cents = 0;
  factory Money.ksh(num shillings) => Money((shillings * 100).round());

  double get shillings => cents / 100;
  bool get isNegative => cents < 0;
  bool get isZero => cents == 0;

  Money operator +(Money o) => Money(cents + o.cents);
  Money operator -(Money o) => Money(cents - o.cents);
  Money operator *(int n) => Money(cents * n);
  Money operator -() => Money(-cents);
  bool operator <(Money o) => cents < o.cents;
  bool operator >(Money o) => cents > o.cents;
  bool operator <=(Money o) => cents <= o.cents;
  bool operator >=(Money o) => cents >= o.cents;

  /// Multiply by a fractional factor, rounding half-up to the nearest cent.
  Money scale(double factor) => Money((cents * factor).round());

  /// Integer division that keeps the total exact: returns [n] parts whose sum
  /// equals this amount (remainder cents go to the first parts).
  List<Money> split(int n) {
    if (n <= 0) return const [];
    final base = cents ~/ n;
    var rem = cents - base * n;
    return List.generate(n, (i) {
      final extra = rem > 0 ? 1 : 0;
      if (rem > 0) rem--;
      return Money(base + extra);
    });
  }

  static Money sum(Iterable<Money> items) => items.fold(const Money.zero(), (a, b) => a + b);

  static final _fmt = NumberFormat('#,##0', 'en_KE');
  static final _fmt2 = NumberFormat('#,##0.00', 'en_KE');

  /// "KSh 1,850" – shows cents only when there are any.
  String format({bool forceCents = false}) {
    final neg = cents < 0;
    final abs = cents.abs();
    final s = (forceCents || abs % 100 != 0) ? _fmt2.format(abs / 100) : _fmt.format(abs ~/ 100);
    return '${neg ? '-' : ''}KSh $s';
  }

  @override
  String toString() => format();
  @override
  int compareTo(Money other) => cents.compareTo(other.cents);
  @override
  bool operator ==(Object other) => other is Money && other.cents == cents;
  @override
  int get hashCode => cents.hashCode;
}
