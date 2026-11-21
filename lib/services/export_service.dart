import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:share_plus/share_plus.dart';

import '../models/catalog.dart';
import '../models/user_data.dart';

/// Share a list as text, or export it as a branded PDF.
class ExportService {
  static String asText(ShoppingList list, Map<String, Supermarket> shops) {
    final b = StringBuffer('🛒 ${list.name}\n');
    final shop = shops[list.supermarketId]?.name;
    if (shop != null) b.writeln('Shop: $shop');
    final byCat = <String, List<ShoppingItem>>{};
    for (final i in list.items) {
      byCat.putIfAbsent(i.category, () => []).add(i);
    }
    byCat.forEach((cat, items) {
      b.writeln('\n${productCategories[cat] ?? cat}');
      for (final i in items) {
        b.writeln('${i.purchased ? '☑' : '☐'} ${i.name} – ${i.quantityLabel} (${i.total.format()})');
      }
    });
    b.writeln('\nEstimated total: ${list.estimatedTotal.format()}');
    b.writeln('Budget: ${list.budget.format()} · Remaining: ${list.remaining.format()}');
    b.writeln('Prices are estimates. Planned with Grub – Plan meals. Shop smarter.');
    return b.toString();
  }

  static Future<void> share(ShoppingList list, Map<String, Supermarket> shops) =>
      Share.share(asText(list, shops), subject: list.name);

  static Future<void> exportPdf(ShoppingList list, Map<String, Supermarket> shops) async {
    final green = PdfColor.fromHex('#3DA832');
    final dark = PdfColor.fromHex('#145A1E');
    final light = PdfColor.fromHex('#EFF8EA');
    final doc = pw.Document(title: list.name, author: 'Grub');
    final byCat = <String, List<ShoppingItem>>{};
    for (final i in list.items) {
      byCat.putIfAbsent(i.category, () => []).add(i);
    }
    doc.addPage(pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(32),
      header: (_) => pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
        pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
          pw.Text('Grub', style: pw.TextStyle(fontSize: 26, fontWeight: pw.FontWeight.bold, color: green)),
          pw.Text('PLAN MEALS. SHOP SMARTER.', style: pw.TextStyle(fontSize: 9, color: dark, fontWeight: pw.FontWeight.bold)),
        ]),
        pw.Container(height: 2, color: green, margin: const pw.EdgeInsets.symmetric(vertical: 8)),
        pw.Text(list.name, style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold, color: dark)),
        pw.Text('${DateFormat('d MMM yyyy').format(list.createdAt)}'
            '${shops[list.supermarketId] != null ? ' · ${shops[list.supermarketId]!.name}' : ''}',
            style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey700)),
        pw.SizedBox(height: 12),
      ]),
      footer: (c) => pw.Text('Prices are estimates from Grub\'s price list and may differ in store. Page ${c.pageNumber}/${c.pagesCount}',
          style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey600)),
      build: (_) => [
        for (final e in byCat.entries) ...[
          pw.Container(
            color: light,
            padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 4),
            margin: const pw.EdgeInsets.only(top: 10, bottom: 4),
            child: pw.Text((productCategories[e.key] ?? e.key).toUpperCase(),
                style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold, color: dark)),
          ),
          pw.TableHelper.fromTextArray(
            headers: ['', 'Product', 'Quantity', 'Unit price', 'Total'],
            data: [
              for (final i in e.value)
                [i.purchased ? 'X' : '', i.name, i.quantityLabel, i.unitPrice.format(), i.total.format()]
            ],
            headerStyle: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold, color: PdfColors.white),
            headerDecoration: pw.BoxDecoration(color: dark),
            cellStyle: const pw.TextStyle(fontSize: 9),
            columnWidths: {0: const pw.FixedColumnWidth(18), 1: const pw.FlexColumnWidth(3), 2: const pw.FlexColumnWidth(2)},
            cellAlignments: {3: pw.Alignment.centerRight, 4: pw.Alignment.centerRight},
          ),
        ],
        pw.SizedBox(height: 16),
        pw.Container(
          padding: const pw.EdgeInsets.all(10),
          decoration: pw.BoxDecoration(border: pw.Border.all(color: green), borderRadius: pw.BorderRadius.circular(6)),
          child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.end, children: [
            pw.Text('Estimated total: ${list.estimatedTotal.format()}', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, color: dark)),
            pw.Text('Budget: ${list.budget.format()}   Remaining: ${list.remaining.format()}', style: const pw.TextStyle(fontSize: 10)),
          ]),
        ),
      ],
    ));
    final bytes = await doc.save();
    await Printing.sharePdf(bytes: bytes, filename: '${list.name.replaceAll(RegExp(r'[^A-Za-z0-9]+'), '_')}.pdf');
  }
}
