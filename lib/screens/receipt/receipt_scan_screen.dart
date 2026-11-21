import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../../core/money.dart';
import '../../core/theme.dart';
import '../../models/catalog.dart';
import '../../services/receipt_service.dart';
import '../../state/app_state.dart';
import '../../widgets/common.dart';
import '../../core/i18n.dart';

/// Snap a shop receipt → Grub reads it → you check it → spending, pantry and
/// real shop prices are all updated at once.
class ReceiptScanScreen extends StatefulWidget {
  const ReceiptScanScreen({super.key});
  @override
  State<ReceiptScanScreen> createState() => _ReceiptScanScreenState();
}

class _ReceiptScanScreenState extends State<ReceiptScanScreen> {
  XFile? _photo;
  bool _busy = false;
  String? _error;
  ReceiptScan? _scan;
  final _total = TextEditingController();
  final _branch = TextEditingController();
  bool _toPantry = true;
  bool _share = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _share = context.read<AppState>().profile?.shareAnonymousPrices ?? true;
  }

  Future<void> _pick(ImageSource src) async {
    final f = await ImagePicker().pickImage(source: src, maxWidth: 1600, imageQuality: 78);
    if (f == null) return;
    setState(() {
      _photo = f;
      _busy = true;
      _error = null;
      _scan = null;
    });
    try {
      final bytes = await f.readAsBytes();
      final scan = await ReceiptService.scan(bytes, f.mimeType ?? 'image/jpeg');
      if (!mounted) return;
      final shops = context.read<AppState>().catalog.supermarkets;
      if (scan.supermarketId != null && !shops.containsKey(scan.supermarketId)) scan.supermarketId = null;
      _total.text = (scan.total ?? scan.itemsTotal).toStringAsFixed(0);
      _branch.text = scan.branch;
      setState(() => _scan = scan);
    } catch (e) {
      final msg = e.toString();
      setState(() => _error = msg.contains('] ') ? msg.split('] ').last : 'Could not read the receipt. Check your internet and try a clearer photo.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Money _grubEstimate(AppState s, ReceiptScan r) {
    var total = const Money.zero();
    for (final i in r.items.where((i) => i.include && i.productId != null && (i.packageSize ?? 0) > 0)) {
      total += s.estimateFor(i.productId!, i.packageSize! * i.quantity, r.supermarketId ?? '') ?? Money.ksh(i.lineTotal);
    }
    return total;
  }

  Future<void> _save() async {
    final s = context.read<AppState>();
    final r = _scan!;
    r.branch = _branch.text.trim();
    final paid = double.tryParse(_total.text.replaceAll(',', '')) ?? r.itemsTotal;
    setState(() => _saving = true);
    try {
      final result = await s.saveReceipt(r, paid: Money.ksh(paid), estimate: _grubEstimate(s, r), addToPantry: _toPantry, sharePrices: _share);
      if (!mounted) return;
      Navigator.pop(context);
      showSnack(context, result);
    } catch (e) {
      if (mounted) showSnack(context, 'Could not save. Please try again.', error: true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    return Scaffold(
      appBar: AppBar(title: const T('Scan a receipt')),
      body: s.isDemo
          ? const EmptyState(
              emoji: '🧾',
              title: 'Needs the online version',
              message: 'Receipt scanning works when Grub is connected to the internet and signed in to your account.',
            )
          : _scan != null
              ? _review(s, _scan!)
              : _start(),
      bottomNavigationBar: _scan == null
          ? null
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                child: FilledButton(
                  onPressed: _saving ? null : _save,
                  child: Text(_saving ? 'Saving…' : 'Save receipt'),
                ),
              ),
            ),
    );
  }

  Widget _start() => ListView(padding: const EdgeInsets.all(20), children: [
        const SizedBox(height: 10),
        const EmojiTile('🧾', size: 84),
        const SizedBox(height: 16),
        T('Snap your shop receipt', textAlign: TextAlign.center, style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: 8),
        const Text(
          'Grub reads every item and price, records what you spent, adds the food to your pantry and – if you agree – shares the shelf prices so other families get real prices.',
          textAlign: TextAlign.center,
          style: TextStyle(color: GrubColors.muted, height: 1.4),
        ),
        const SizedBox(height: 24),
        if (_busy) ...[
          const LoadingView(message: 'Reading your receipt…'),
          const SizedBox(height: 12),
          const T('This takes about 10 seconds.', textAlign: TextAlign.center, style: TextStyle(color: GrubColors.muted, fontSize: 12)),
        ] else ...[
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 14),
              child: SoftCard(color: const Color(0xFFFDECEC), child: Text(_error!, style: const TextStyle(color: GrubColors.danger))),
            ),
          FilledButton.icon(onPressed: () => _pick(ImageSource.camera), icon: const Icon(Icons.photo_camera), label: const T('Take a photo')),
          const SizedBox(height: 10),
          OutlinedButton.icon(onPressed: () => _pick(ImageSource.gallery), icon: const Icon(Icons.photo_library_outlined), label: const T('Choose from gallery')),
          const SizedBox(height: 18),
          const T('Tips: lay the receipt flat, fill the screen, good light. Long receipts: fold or take the photo from a bit further.',
              textAlign: TextAlign.center, style: TextStyle(color: GrubColors.muted, fontSize: 12)),
        ],
        if (_photo != null && _busy) const SizedBox(height: 8),
      ]);

  Widget _review(AppState s, ReceiptScan r) {
    final shops = s.catalog.shops;
    final matched = r.items.where((i) => i.include && i.productId != null).length;
    final estimate = _grubEstimate(s, r);
    final paid = double.tryParse(_total.text.replaceAll(',', '')) ?? r.itemsTotal;
    return ListView(padding: const EdgeInsets.fromLTRB(16, 0, 16, 24), children: [
      SoftCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          DropdownButtonFormField<String>(
            value: r.supermarketId,
            decoration: InputDecoration(labelText: tr('Shop')),
            items: [
              for (final sm in shops) DropdownMenuItem(value: sm.id, child: Text(sm.name)),
            ],
            onChanged: (v) => setState(() => r.supermarketId = v),
          ),
          if (r.supermarketId == null && r.shopName.isNotEmpty)
            Padding(padding: const EdgeInsets.only(top: 4), child: Text('Receipt says: ${r.shopName}', style: const TextStyle(fontSize: 12, color: GrubColors.muted))),
          const SizedBox(height: 10),
          Row(children: [
            Expanded(child: TextField(controller: _branch, decoration: InputDecoration(labelText: tr('Branch (optional)')))),
            const SizedBox(width: 10),
            Expanded(
              child: InkWell(
                onTap: () async {
                  final d = await showDatePicker(context: context, firstDate: DateTime(2024), lastDate: DateTime.now(), initialDate: r.date.isAfter(DateTime.now()) ? DateTime.now() : r.date);
                  if (d != null) setState(() => r.date = d);
                },
                child: InputDecorator(decoration: InputDecoration(labelText: tr('Date')), child: Text('${r.date.day}/${r.date.month}/${r.date.year}')),
              ),
            ),
          ]),
          const SizedBox(height: 10),
          TextField(
            controller: _total,
            keyboardType: TextInputType.number,
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(labelText: tr('Total paid'), prefixText: 'KSh '),
          ),
        ]),
      ),
      if (matched > 0)
        SoftCard(
          color: GrubColors.greenLight,
          child: Text(
            'Grub\'s estimate for the $matched food items: ${estimate.format()}. '
            'Saving this receipt makes future estimates closer to what you really pay.',
            style: const TextStyle(height: 1.4),
          ),
        ),
      const SizedBox(height: 6),
      Text('${r.items.length} lines found · tap an item to fix it', style: const TextStyle(color: GrubColors.muted, fontSize: 12)),
      const SizedBox(height: 6),
      for (final i in r.items) _itemRow(s, r, i),
      const SizedBox(height: 8),
      SwitchListTile(
        contentPadding: EdgeInsets.zero,
        activeColor: GrubColors.green,
        value: _toPantry,
        onChanged: (v) => setState(() => _toPantry = v),
        title: const T('Add food items to my pantry'),
      ),
      SwitchListTile(
        contentPadding: EdgeInsets.zero,
        activeColor: GrubColors.green,
        value: _share,
        onChanged: (v) => setState(() => _share = v),
        title: const T('Share these shelf prices (anonymously)'),
        subtitle: const T('Only product, shop, branch, price and date are shared – never your name or the photo.'),
      ),
      if ((paid - r.itemsTotal).abs() > 1)
        Text('Items add up to KSh ${r.itemsTotal.toStringAsFixed(0)} – check for missed lines or discounts.',
            style: const TextStyle(color: GrubColors.warning, fontSize: 12)),
    ]);
  }

  Widget _itemRow(AppState s, ReceiptScan r, ReceiptItem i) {
    final p = i.productId == null ? null : s.catalog.products[i.productId];
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: SoftCard(
        padding: const EdgeInsets.all(10),
        color: i.include ? Colors.white : const Color(0xFFF5F5F5),
        onTap: () => _edit(s, i),
        child: Row(children: [
          Checkbox(value: i.include, activeColor: GrubColors.green, onChanged: (v) => setState(() => i.include = v ?? true)),
          EmojiTile(p?.emoji ?? '🛒', size: 36),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(i.text, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600)),
              Text(
                p == null ? 'Not matched (won\'t update pantry or prices)' : '${p.name.split(' (').first} · ${i.packageLabel.isEmpty ? 'size?' : i.packageLabel}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 12, color: p == null ? GrubColors.warning : GrubColors.muted),
              ),
            ]),
          ),
          Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Text('KSh ${i.lineTotal.toStringAsFixed(i.lineTotal % 1 == 0 ? 0 : 2)}', style: const TextStyle(fontWeight: FontWeight.w700)),
            if (i.quantity > 1) Text('${i.quantity} × ${i.unitPrice.toStringAsFixed(0)}', style: const TextStyle(fontSize: 11, color: GrubColors.muted)),
          ]),
        ]),
      ),
    );
  }

  Future<void> _edit(AppState s, ReceiptItem i) async {
    final products = s.catalog.products.values.toList()..sort((a, b) => a.name.compareTo(b.name));
    String? pid = i.productId;
    final qty = TextEditingController(text: '${i.quantity}');
    final unit = TextEditingController(text: i.unitPrice.toStringAsFixed(i.unitPrice % 1 == 0 ? 0 : 2));
    final size = TextEditingController(text: i.packageSize == null ? '' : i.packageSize!.toStringAsFixed(0));
    final label = TextEditingController(text: i.packageLabel);
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) {
          final p = pid == null ? null : s.catalog.products[pid];
          return Padding(
            padding: EdgeInsets.fromLTRB(20, 0, 20, 20 + MediaQuery.viewInsetsOf(ctx).bottom),
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Text(i.text, style: Theme.of(ctx).textTheme.titleMedium),
              const SizedBox(height: 12),
              DropdownButtonFormField<String?>(
                value: pid,
                isExpanded: true,
                decoration: InputDecoration(labelText: tr('This item is…')),
                items: [
                  const DropdownMenuItem<String?>(value: null, child: T('Not food / don\'t track')),
                  for (final pr in products) DropdownMenuItem<String?>(value: pr.id, child: Text('${pr.emoji} ${pr.name}')),
                ],
                onChanged: (v) => setS(() => pid = v),
              ),
              const SizedBox(height: 10),
              Row(children: [
                Expanded(child: TextField(controller: qty, keyboardType: TextInputType.number, decoration: InputDecoration(labelText: tr('How many')))),
                const SizedBox(width: 10),
                Expanded(
                  child: TextField(
                    controller: unit,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: InputDecoration(labelText: tr('Price each'), prefixText: 'KSh '),
                  ),
                ),
              ]),
              if (p != null) ...[
                const SizedBox(height: 10),
                Row(children: [
                  Expanded(
                    child: TextField(
                      controller: size,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      decoration: InputDecoration(labelText: 'Pack size (${_unitWord(p)})'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(child: TextField(controller: label, decoration: InputDecoration(labelText: tr('Label'), hintText: '2 kg packet'))),
                ]),
              ],
              const SizedBox(height: 16),
              FilledButton(
                onPressed: () {
                  setState(() {
                    i.productId = pid;
                    i.quantity = int.tryParse(qty.text) ?? i.quantity;
                    i.unitPrice = double.tryParse(unit.text) ?? i.unitPrice;
                    i.lineTotal = i.unitPrice * i.quantity;
                    i.packageSize = double.tryParse(size.text);
                    i.packageLabel = label.text.trim();
                  });
                  Navigator.pop(ctx);
                },
                child: const T('Done'),
              ),
            ]),
          );
        },
      ),
    );
  }

  String _unitWord(Product p) => switch (p.unit.name) {
        'g' => 'grams',
        'ml' => 'ml',
        'bunch' => 'bunches',
        _ => 'pieces',
      };
}
