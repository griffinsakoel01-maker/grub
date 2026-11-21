import 'dart:convert';
import 'dart:typed_data';

import 'package:cloud_functions/cloud_functions.dart';

import '../core/config.dart';

class ReceiptItem {
  String text;
  int quantity;
  double unitPrice; // KSh per pack / piece
  double lineTotal;
  String? productId;
  double? packageSize; // product base unit
  String packageLabel;
  bool include;

  ReceiptItem({
    required this.text,
    required this.quantity,
    required this.unitPrice,
    required this.lineTotal,
    this.productId,
    this.packageSize,
    this.packageLabel = '',
    this.include = true,
  });

  factory ReceiptItem.fromMap(Map m) => ReceiptItem(
        text: m['text'] as String? ?? '',
        quantity: ((m['quantity'] as num?) ?? 1).round().clamp(1, 999).toInt(),
        unitPrice: ((m['unitPrice'] as num?) ?? 0).toDouble(),
        lineTotal: ((m['lineTotal'] as num?) ?? 0).toDouble(),
        productId: m['productId'] as String?,
        packageSize: (m['packageSize'] as num?)?.toDouble(),
        packageLabel: m['packageLabel'] as String? ?? '',
      );

  Map<String, dynamic> toMap() => {
        'text': text,
        'quantity': quantity,
        'unitPrice': unitPrice,
        'lineTotal': lineTotal,
        'productId': productId,
        'packageSize': packageSize,
        'packageLabel': packageLabel,
      };
}

class ReceiptScan {
  String? supermarketId;
  String shopName;
  String branch;
  DateTime date;
  double? total;
  final List<ReceiptItem> items;

  ReceiptScan({this.supermarketId, this.shopName = '', this.branch = '', required this.date, this.total, required this.items});

  double get itemsTotal => items.where((i) => i.include).fold(0.0, (a, i) => a + i.lineTotal);

  factory ReceiptScan.fromMap(Map m) => ReceiptScan(
        supermarketId: m['supermarketId'] as String?,
        shopName: m['shopName'] as String? ?? '',
        branch: m['branch'] as String? ?? '',
        date: DateTime.tryParse(m['date'] as String? ?? '') ?? DateTime.now(),
        total: (m['total'] as num?)?.toDouble(),
        items: ((m['items'] as List?) ?? const []).map((e) => ReceiptItem.fromMap(e as Map)).toList(),
      );
}

/// Talks to the scanReceipt / saveReceiptPrices Cloud Functions.
class ReceiptService {
  static FirebaseFunctions get _fn => FirebaseFunctions.instanceFor(region: AppConfig.functionsRegion);

  static Future<ReceiptScan> scan(Uint8List bytes, String mimeType) async {
    final res = await _fn
        .httpsCallable('scanReceipt', options: HttpsCallableOptions(timeout: const Duration(seconds: 90)))
        .call({'imageBase64': base64Encode(bytes), 'mimeType': mimeType});
    return ReceiptScan.fromMap(res.data as Map);
  }

  /// Shares confirmed prices; returns (saved, sentForReview).
  static Future<(int, int)> sharePrices(ReceiptScan r) async {
    if (r.supermarketId == null) return (0, 0);
    final res = await _fn.httpsCallable('saveReceiptPrices').call({
      'supermarketId': r.supermarketId,
      'branch': r.branch,
      'date': '${r.date.year.toString().padLeft(4, '0')}-${r.date.month.toString().padLeft(2, '0')}-${r.date.day.toString().padLeft(2, '0')}',
      'items': [for (final i in r.items.where((i) => i.include && i.productId != null)) i.toMap()],
    });
    final m = res.data as Map;
    return (((m['saved'] as num?) ?? 0).toInt(), ((m['review'] as num?) ?? 0).toInt());
  }
}
