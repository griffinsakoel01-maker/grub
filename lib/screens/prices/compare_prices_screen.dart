import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/theme.dart';
import '../../models/catalog.dart';
import '../../services/calculation_service.dart';
import '../../state/app_state.dart';
import '../../widgets/common.dart';

/// Supermarket price comparison: whole basket per shop + single products.
class ComparePricesScreen extends StatefulWidget {
  final String? listId;
  const ComparePricesScreen({super.key, this.listId});
  @override
  State<ComparePricesScreen> createState() => _ComparePricesScreenState();
}

class _ComparePricesScreenState extends State<ComparePricesScreen> with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(length: 2, vsync: this);
  String _q = '';
  String? _productId;

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  Map<String, double> _toBuy(AppState s) {
    if (widget.listId != null) {
      final l = s.listById(widget.listId!);
      if (l != null) {
        final m = <String, double>{};
        for (final i in l.items.where((i) => i.productId.isNotEmpty)) {
          m[i.productId] = (m[i.productId] ?? 0) + i.requiredBase;
        }
        return m;
      }
    }
    final pl = s.plan;
    if (pl == null) return {};
    return s.planner.toBuyFor(pl.meals, s.pantryMap, pl.substitutions);
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    return Scaffold(
      appBar: AppBar(
        title: const Text('Compare prices'),
        actions: [
          IconButton(
            tooltip: 'Supermarkets near me',
            icon: const Icon(Icons.map_outlined),
            onPressed: () => launchUrl(
              Uri.parse('https://www.google.com/maps/search/?api=1&query=${Uri.encodeComponent('supermarket near ${s.profile?.county.isNotEmpty == true ? s.profile!.county : 'me'} Kenya')}'),
              mode: LaunchMode.externalApplication,
            ),
          ),
        ],
        bottom: TabBar(
          controller: _tabs,
          labelColor: GrubColors.greenDark,
          indicatorColor: GrubColors.green,
          tabs: const [Tab(text: 'My basket'), Tab(text: 'Single product')],
        ),
      ),
      body: TabBarView(controller: _tabs, children: [_basket(s), _product(s)]),
    );
  }

  Widget _basket(AppState s) {
    final toBuy = _toBuy(s);
    if (toBuy.isEmpty) {
      return const EmptyState(emoji: '🧺', title: 'Nothing to compare yet', message: 'Create a meal plan or a shopping list, then compare what it costs at each shop.');
    }
    final baskets = CalculationService.basketsBySupermarket(toBuy, s.catalog);
    final complete = baskets.where((b) => b.complete).toList();
    final cheapest = complete.isNotEmpty ? complete.first : (baskets.isNotEmpty ? baskets.first : null);
    final dearest = complete.isNotEmpty ? complete.last : null;
    final mix = CalculationService.costBasket(toBuy, s.catalog);
    final current = widget.listId != null ? s.listById(widget.listId!)?.supermarketId : s.plan?.supermarketId;

    return ListView(padding: const EdgeInsets.all(16), children: [
      if (s.catalog.hasOnlyDemoPrices) const DemoBanner(),
      const SizedBox(height: 10),
      if (cheapest != null && dearest != null && dearest.total > cheapest.total)
        SoftCard(
          color: GrubColors.greenLight,
          child: Row(children: [
            const Text('💰', style: TextStyle(fontSize: 28)),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                'Shopping at ${s.catalog.supermarkets[cheapest.supermarketId]?.name} could save you ${(dearest.total - cheapest.total).format()} '
                'compared with ${s.catalog.supermarkets[dearest.supermarketId]?.name}.',
                style: const TextStyle(fontWeight: FontWeight.w600, height: 1.35),
              ),
            ),
          ]),
        ),
      const SizedBox(height: 12),
      for (final b in baskets)
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: SoftCard(
            borderColor: b == cheapest ? GrubColors.green : null,
            child: Row(children: [
              _ShopDot(s.catalog.supermarkets[b.supermarketId]),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Flexible(child: Text(s.catalog.supermarkets[b.supermarketId]?.name ?? b.supermarketId, style: const TextStyle(fontWeight: FontWeight.w700))),
                    if (b == cheapest) ...[
                      const SizedBox(width: 6),
                      _tag('Cheapest'),
                    ],
                    if (current == b.supermarketId) ...[const SizedBox(width: 6), _tag('Selected', color: GrubColors.greenDark)],
                  ]),
                  Text(b.complete ? 'All ${b.lines.length} items priced' : '${b.missing.length} item(s) not stocked / no price',
                      style: TextStyle(fontSize: 12, color: b.complete ? GrubColors.muted : GrubColors.warning)),
                  if (cheapest != null && b != cheapest && b.complete && cheapest.complete)
                    Text('+${(b.total - cheapest.total).format()} vs cheapest', style: const TextStyle(fontSize: 12, color: GrubColors.danger)),
                ]),
              ),
              Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                Text(b.total.format(), style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
                TextButton(
                  style: TextButton.styleFrom(padding: EdgeInsets.zero, minimumSize: const Size(0, 30)),
                  onPressed: () => _select(s, b.supermarketId),
                  child: const Text('Shop here'),
                ),
              ]),
            ]),
          ),
        ),
      SoftCard(
        child: Row(children: [
          const EmojiTile('🔀'),
          const SizedBox(width: 12),
          const Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Mix & match', style: TextStyle(fontWeight: FontWeight.w700)),
              Text('Cheapest price for each item, any shop', style: TextStyle(fontSize: 12, color: GrubColors.muted)),
            ]),
          ),
          Text(mix.total.format(), style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
        ]),
      ),
      const SizedBox(height: 10),
      const Text('Totals include whole packages (e.g. a 2 kg packet even if you need 1.5 kg). Prices are labelled by source.',
          style: TextStyle(fontSize: 11, color: GrubColors.muted)),
    ]);
  }

  Widget _tag(String t, {Color color = GrubColors.green}) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(8)),
        child: Text(t, style: const TextStyle(fontSize: 10, color: Colors.white, fontWeight: FontWeight.w700)),
      );

  Future<void> _select(AppState s, String shopId) async {
    if (widget.listId != null) {
      final l = s.listById(widget.listId!);
      if (l != null) await s.saveList(l.copyWith(supermarketId: shopId));
    } else if (s.plan != null) {
      await s.setPlanSupermarket(shopId);
    }
    final p = s.profile;
    if (p != null && !p.preferredSupermarkets.contains(shopId)) {
      await s.saveProfile(p.copyWith(preferredSupermarkets: [shopId, ...p.preferredSupermarkets]));
    }
    if (mounted) showSnack(context, '${s.catalog.supermarkets[shopId]?.name} selected.');
  }

  Widget _product(AppState s) {
    final products = s.catalog.products.values.where((p) => _q.isEmpty || p.name.toLowerCase().contains(_q.toLowerCase())).toList()
      ..sort((a, b) => a.name.compareTo(b.name));
    final selected = _productId == null ? null : s.catalog.products[_productId];
    return Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
        child: TextField(
          decoration: const InputDecoration(hintText: 'Search a product (e.g. rice)', prefixIcon: Icon(Icons.search)),
          onChanged: (v) => setState(() {
            _q = v;
            _productId = null;
          }),
        ),
      ),
      Expanded(
        child: selected == null
            ? ListView(children: [
                for (final p in products)
                  ListTile(
                    leading: Text(p.emoji, style: const TextStyle(fontSize: 24)),
                    title: Text(p.name),
                    subtitle: Text('${s.catalog.pricesFor(p.id).length} prices'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => setState(() => _productId = p.id),
                  ),
              ])
            : _productTable(s, selected),
      ),
    ]);
  }

  Widget _productTable(AppState s, Product p) {
    final prices = s.catalog.pricesFor(p.id)..sort((a, b) => _perUnit(a).compareTo(_perUnit(b)));
    final cheapest = prices.isEmpty ? null : prices.first;
    return ListView(padding: const EdgeInsets.fromLTRB(16, 0, 16, 16), children: [
      Row(children: [
        EmojiTile(p.emoji, size: 52),
        const SizedBox(width: 12),
        Expanded(child: Text(p.name, style: Theme.of(context).textTheme.titleLarge)),
        TextButton(onPressed: () => setState(() => _productId = null), child: const Text('Change')),
      ]),
      const SizedBox(height: 12),
      if (prices.isEmpty) const Text('No prices recorded yet.'),
      for (final pr in prices)
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: SoftCard(
            borderColor: pr == cheapest ? GrubColors.green : null,
            padding: const EdgeInsets.all(12),
            child: Row(children: [
              _ShopDot(s.catalog.supermarkets[pr.supermarketId]),
              const SizedBox(width: 10),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(s.catalog.supermarkets[pr.supermarketId]?.name ?? pr.supermarketId, style: const TextStyle(fontWeight: FontWeight.w700)),
                  Text('${pr.packageLabel}${pr.brand.isNotEmpty && pr.brand != 'Generic' ? ' · ${pr.brand}' : ''}', style: const TextStyle(fontSize: 12, color: GrubColors.muted)),
                  const SizedBox(height: 4),
                  Row(children: [
                    PriceBadge(priceStatusKey(pr.status)),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text('Updated ${pr.lastUpdated.day}/${pr.lastUpdated.month}/${pr.lastUpdated.year} · ${pr.source}',
                          style: const TextStyle(fontSize: 10, color: GrubColors.muted), overflow: TextOverflow.ellipsis),
                    ),
                  ]),
                ]),
              ),
              Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                Text(pr.price.format(), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
                if (pr == cheapest)
                  const Text('Cheapest', style: TextStyle(fontSize: 11, color: GrubColors.green, fontWeight: FontWeight.w700))
                else if (cheapest != null && cheapest.packageSize == pr.packageSize)
                  Text('+${(pr.price - cheapest.price).format()}', style: const TextStyle(fontSize: 11, color: GrubColors.danger)),
              ]),
            ]),
          ),
        ),
    ]);
  }

  /// Price per base unit (cents) so different package sizes compare fairly.
  double _perUnit(PriceRecord p) => p.packageSize <= 0 ? p.price.cents.toDouble() : p.price.cents / p.packageSize;
}

class _ShopDot extends StatelessWidget {
  final Supermarket? shop;
  const _ShopDot(this.shop);
  @override
  Widget build(BuildContext context) {
    Color c;
    try {
      c = Color(int.parse((shop?.color ?? '#3DA832').replaceFirst('#', '0xFF')));
    } catch (_) {
      c = GrubColors.green;
    }
    return CircleAvatar(
      radius: 20,
      backgroundColor: c.withValues(alpha: 0.12),
      child: Text((shop?.name ?? '?').substring(0, 1), style: TextStyle(color: c, fontWeight: FontWeight.w800)),
    );
  }
}

