import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/money.dart';
import '../../core/theme.dart';
import '../../models/user_data.dart';
import '../../state/app_state.dart';
import '../../widgets/common.dart';
import 'expense_history_screen.dart';

/// Grocery expense tracker: budget vs actual, weekly & monthly charts, savings.
class BudgetTrackingScreen extends StatefulWidget {
  const BudgetTrackingScreen({super.key});
  @override
  State<BudgetTrackingScreen> createState() => _BudgetTrackingScreenState();
}

class _BudgetTrackingScreenState extends State<BudgetTrackingScreen> {
  bool _monthly = false;

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final p = s.profile!;
    final withEstimate = s.expenses.where((e) => e.estimated != null).toList();
    final saved = Money.sum(withEstimate.map((e) => e.estimated! - e.amount));
    final buckets = _monthly ? _months(s.expenses) : _weeks(s.expenses);

    return Scaffold(
      appBar: AppBar(title: const Text('Budget tracking')),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: GrubColors.green,
        foregroundColor: Colors.white,
        onPressed: () => showAddExpense(context),
        icon: const Icon(Icons.add),
        label: const Text('Add purchase'),
      ),
      body: ListView(padding: const EdgeInsets.fromLTRB(16, 0, 16, 96), children: [
        SoftCard(child: BudgetProgress(budget: p.budget, spent: s.spentThisPeriod, label: '${budgetFrequencyLabel(p.budgetFrequency)} grocery budget')),
        const SizedBox(height: 12),
        Row(children: [
          Expanded(child: _stat('Actual spending', s.spentThisPeriod.format())),
          const SizedBox(width: 10),
          Expanded(
            child: _stat(saved.isNegative ? 'Over estimates' : 'Saved vs estimates', (saved.isNegative ? -saved : saved).format(),
                color: saved.isNegative ? GrubColors.danger : GrubColors.green),
          ),
        ]),
        const SizedBox(height: 16),
        Row(children: [
          Text(_monthly ? 'Monthly spending' : 'Weekly spending', style: Theme.of(context).textTheme.titleLarge),
          const Spacer(),
          SegmentedButton<bool>(
            segments: const [ButtonSegment(value: false, label: Text('Weeks')), ButtonSegment(value: true, label: Text('Months'))],
            selected: {_monthly},
            showSelectedIcon: false,
            onSelectionChanged: (v) => setState(() => _monthly = v.first),
          ),
        ]),
        const SizedBox(height: 12),
        SoftCard(
          padding: const EdgeInsets.fromLTRB(8, 20, 16, 8),
          child: SizedBox(height: 220, child: s.expenses.isEmpty ? const Center(child: Text('No purchases recorded yet', style: TextStyle(color: GrubColors.muted))) : _chart(buckets, p)),
        ),
        const SizedBox(height: 8),
        Text('Dashed line: your budget for each ${_monthly ? 'month' : 'week'}.', style: const TextStyle(fontSize: 11, color: GrubColors.muted)),
        SectionHeader('Recent purchases', action: 'See all', onAction: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const ExpenseHistoryScreen()))),
        if (s.expenses.isEmpty)
          const Text('Finish a shopping list or tap "Add purchase" to record what you spent.', style: TextStyle(color: GrubColors.muted)),
        for (final e in s.expenses.take(5)) ExpenseTile(expense: e),
      ]),
    );
  }

  Widget _stat(String k, String v, {Color color = GrubColors.ink}) => SoftCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(k, style: const TextStyle(fontSize: 12, color: GrubColors.muted)),
          const SizedBox(height: 4),
          FittedBox(child: Text(v, style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: color))),
        ]),
      );

  List<(String, Money)> _weeks(List<Expense> ex) {
    final now = DateTime.now();
    final monday = DateTime(now.year, now.month, now.day).subtract(Duration(days: now.weekday - 1));
    return [
      for (var i = 5; i >= 0; i--)
        () {
          final start = monday.subtract(Duration(days: 7 * i));
          final end = start.add(const Duration(days: 7));
          return ('${start.day}/${start.month}', Money.sum(ex.where((e) => !e.date.isBefore(start) && e.date.isBefore(end)).map((e) => e.amount)));
        }(),
    ];
  }

  List<(String, Money)> _months(List<Expense> ex) {
    final now = DateTime.now();
    const names = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    return [
      for (var i = 5; i >= 0; i--)
        () {
          final start = DateTime(now.year, now.month - i, 1);
          final end = DateTime(start.year, start.month + 1, 1);
          return (names[start.month - 1], Money.sum(ex.where((e) => !e.date.isBefore(start) && e.date.isBefore(end)).map((e) => e.amount)));
        }(),
    ];
  }

  Widget _chart(List<(String, Money)> data, UserProfile p) {
    final periodBudget = _monthly
        ? Money((p.budget.cents * 30 / _days(p)).round())
        : Money((p.budget.cents * 7 / _days(p)).round());
    final maxY = math.max(periodBudget.shillings, data.map((e) => e.$2.shillings).fold<double>(0, (a, b) => math.max(a, b))) * 1.2 + 1;
    return BarChart(
      BarChartData(
        maxY: maxY,
        gridData: const FlGridData(show: false),
        borderData: FlBorderData(show: false),
        extraLinesData: ExtraLinesData(horizontalLines: [
          HorizontalLine(y: periodBudget.shillings, color: GrubColors.orange, strokeWidth: 1.5, dashArray: [6, 4]),
        ]),
        titlesData: FlTitlesData(
          topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 44,
              getTitlesWidget: (v, meta) => Text(v >= 1000 ? '${(v / 1000).toStringAsFixed(v % 1000 == 0 ? 0 : 1)}k' : v.toInt().toString(),
                  style: const TextStyle(fontSize: 10, color: GrubColors.muted)),
            ),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              getTitlesWidget: (v, meta) {
                final i = v.toInt();
                if (i < 0 || i >= data.length) return const SizedBox();
                return Padding(padding: const EdgeInsets.only(top: 6), child: Text(data[i].$1, style: const TextStyle(fontSize: 10, color: GrubColors.muted)));
              },
            ),
          ),
        ),
        barGroups: [
          for (var i = 0; i < data.length; i++)
            BarChartGroupData(x: i, barRods: [
              BarChartRodData(
                toY: data[i].$2.shillings,
                width: 18,
                color: data[i].$2 > periodBudget ? GrubColors.danger : GrubColors.green,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(6)),
              ),
            ]),
        ],
      ),
    );
  }

  int _days(UserProfile p) => switch (p.budgetFrequency) {
        BudgetFrequency.daily => 1,
        BudgetFrequency.weekly => 7,
        BudgetFrequency.biweekly => 14,
        BudgetFrequency.monthly => 30,
        BudgetFrequency.custom => math.max(1, p.customBudgetDays),
      };
}
