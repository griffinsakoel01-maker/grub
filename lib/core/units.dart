/// Unit handling. Every product has a *base unit* (g, ml, pcs, bunch,
/// packet). Recipe and pantry quantities may be entered in friendlier units
/// and are converted to the base unit for all maths.
enum BaseUnit { g, ml, pcs, bunch, packet }

BaseUnit baseUnitFrom(String s) {
  switch (s) {
    case 'g':
      return BaseUnit.g;
    case 'ml':
      return BaseUnit.ml;
    case 'bunch':
      return BaseUnit.bunch;
    case 'packet':
      return BaseUnit.packet;
    default:
      return BaseUnit.pcs;
  }
}

class Units {
  /// Units a user may type for each base unit.
  static const inputUnits = <BaseUnit, List<String>>{
    BaseUnit.g: ['g', 'kg', 'tbsp', 'tsp'],
    BaseUnit.ml: ['ml', 'l', 'tbsp', 'tsp', 'cup'],
    BaseUnit.pcs: ['pcs'],
    BaseUnit.bunch: ['bunch'],
    BaseUnit.packet: ['packet'],
  };

  /// Converts [amount] given in [unit] to the product's [base] unit.
  /// Spoon measures of dry goods are approximated at 1 g/ml.
  static double toBase(double amount, String unit, BaseUnit base) {
    switch (unit) {
      case 'kg':
      case 'l':
        return amount * 1000;
      case 'tbsp':
        return amount * 15;
      case 'tsp':
        return amount * 5;
      case 'cup':
        return amount * 250;
      default:
        return amount; // g, ml, pcs, bunch, packet
    }
  }

  /// Human friendly display: 1500 g → "1.5 kg", 250 ml → "250 ml", 3 pcs → "3".
  static String display(double amount, BaseUnit base) {
    String n(double v) {
      if ((v - v.roundToDouble()).abs() < 0.01) return v.round().toString();
      return v.toStringAsFixed(v < 10 ? 2 : 1).replaceAll(RegExp(r'\.?0+$'), '');
    }

    switch (base) {
      case BaseUnit.g:
        return amount >= 1000 ? '${n(amount / 1000)} kg' : '${n(amount)} g';
      case BaseUnit.ml:
        return amount >= 1000 ? '${n(amount / 1000)} litres' : '${n(amount)} ml';
      case BaseUnit.pcs:
        return '${n(amount)} pcs';
      case BaseUnit.bunch:
        return '${n(amount)} ${amount == 1 ? 'bunch' : 'bunches'}';
      case BaseUnit.packet:
        return '${n(amount)} ${amount == 1 ? 'packet' : 'packets'}';
    }
  }

  /// Display a recipe quantity in the unit it was written in (after scaling).
  static String displayIn(double amountInUnit, String unit) {
    String n(double v) {
      if ((v - v.roundToDouble()).abs() < 0.01) return v.round().toString();
      return v.toStringAsFixed(2).replaceAll(RegExp(r'\.?0+$'), '');
    }

    switch (unit) {
      case 'g':
        return amountInUnit >= 1000 ? '${n(amountInUnit / 1000)} kg' : '${n(amountInUnit)} g';
      case 'ml':
        return amountInUnit >= 1000 ? '${n(amountInUnit / 1000)} litres' : '${n(amountInUnit)} ml';
      case 'pcs':
        return n(amountInUnit);
      case 'bunch':
        return '${n(amountInUnit)} ${amountInUnit == 1 ? 'bunch' : 'bunches'}';
      default:
        return '${n(amountInUnit)} $unit';
    }
  }
}
