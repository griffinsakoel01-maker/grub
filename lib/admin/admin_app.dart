import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../core/config.dart';
import '../core/theme.dart';
import '../models/catalog.dart';
import '../widgets/common.dart';

final _db = FirebaseFirestore.instance;
HttpsCallable _fn(String name) => FirebaseFunctions.instanceFor(region: AppConfig.functionsRegion).httpsCallable(name);

/// Only users whose ID token carries admin == true get past this gate.
/// Firestore/Storage rules enforce the same check server-side.
class AdminGate extends StatelessWidget {
  const AdminGate({super.key});
  @override
  Widget build(BuildContext context) => StreamBuilder<User?>(
        stream: FirebaseAuth.instance.idTokenChanges(),
        builder: (_, snap) {
          final u = snap.data;
          if (snap.connectionState == ConnectionState.waiting) return const Scaffold(body: LoadingView());
          if (u == null) return const _AdminLogin();
          return FutureBuilder<IdTokenResult>(
            future: u.getIdTokenResult(true),
            builder: (_, t) {
              if (!t.hasData) return const Scaffold(body: LoadingView(message: 'Checking permissions…'));
              if (t.data!.claims?['admin'] != true) {
                return Scaffold(
                  body: EmptyState(
                    emoji: '🔒',
                    title: 'Not an administrator',
                    message: '${u.email} does not have admin access.',
                    actionLabel: 'Sign out',
                    onAction: FirebaseAuth.instance.signOut,
                  ),
                );
              }
              return const AdminHome();
            },
          );
        },
      );
}

class _AdminLogin extends StatefulWidget {
  const _AdminLogin();
  @override
  State<_AdminLogin> createState() => _AdminLoginState();
}

class _AdminLoginState extends State<_AdminLogin> {
  final _e = TextEditingController();
  final _p = TextEditingController();
  String? _err;
  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: GrubColors.greenLight,
        body: Center(
          child: SizedBox(
            width: 380,
            child: SoftCard(
              padding: const EdgeInsets.all(28),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                const GrubLogo(height: 90),
                const SizedBox(height: 8),
                const Text('Admin dashboard', style: TextStyle(fontWeight: FontWeight.w700, color: GrubColors.greenDark)),
                const SizedBox(height: 20),
                TextField(controller: _e, decoration: const InputDecoration(labelText: 'Email')),
                const SizedBox(height: 10),
                TextField(controller: _p, obscureText: true, decoration: const InputDecoration(labelText: 'Password')),
                if (_err != null) Padding(padding: const EdgeInsets.only(top: 10), child: Text(_err!, style: const TextStyle(color: GrubColors.danger))),
                const SizedBox(height: 18),
                FilledButton(
                  onPressed: () async {
                    try {
                      await FirebaseAuth.instance.signInWithEmailAndPassword(email: _e.text.trim(), password: _p.text);
                    } catch (e) {
                      setState(() => _err = 'Sign-in failed. Check your details.');
                    }
                  },
                  child: const Text('Sign in'),
                ),
              ]),
            ),
          ),
        ),
      );
}

class AdminHome extends StatefulWidget {
  const AdminHome({super.key});
  @override
  State<AdminHome> createState() => _AdminHomeState();
}

class _AdminHomeState extends State<AdminHome> {
  int _i = 0;
  static const _sections = [
    (Icons.dashboard_outlined, 'Overview'),
    (Icons.inventory_2_outlined, 'Products'),
    (Icons.sell_outlined, 'Prices'),
    (Icons.store_outlined, 'Supermarkets'),
    (Icons.restaurant_menu, 'Recipes'),
    (Icons.fact_check_outlined, 'Price reports'),
    (Icons.category_outlined, 'Categories'),
    (Icons.flag_outlined, 'Reported content'),
    (Icons.admin_panel_settings_outlined, 'Admins'),
  ];

  @override
  Widget build(BuildContext context) {
    final pages = <Widget>[
      const _Overview(),
      const _ProductsPage(),
      const _PricesPage(),
      const _SupermarketsPage(),
      const _RecipesPage(),
      const _ReportsPage(),
      const _CategoriesPage(),
      const _ContentReportsPage(),
      const _AdminsPage(),
    ];
    return Scaffold(
      body: Row(children: [
        NavigationRail(
          selectedIndex: _i,
          onDestinationSelected: (i) => setState(() => _i = i),
          extended: MediaQuery.sizeOf(context).width > 1100,
          leading: const Padding(padding: EdgeInsets.symmetric(vertical: 16), child: GrubLogo(height: 44, iconOnly: true)),
          trailing: Padding(
            padding: const EdgeInsets.only(top: 24),
            child: IconButton(tooltip: 'Sign out', icon: const Icon(Icons.logout), onPressed: FirebaseAuth.instance.signOut),
          ),
          indicatorColor: GrubColors.greenTint,
          destinations: [for (final s in _sections) NavigationRailDestination(icon: Icon(s.$1), label: Text(s.$2))],
        ),
        const VerticalDivider(width: 1),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Padding(padding: const EdgeInsets.fromLTRB(24, 20, 24, 8), child: Text(_sections[_i].$2, style: Theme.of(context).textTheme.headlineSmall)),
            Expanded(child: pages[_i]),
          ]),
        ),
      ]),
    );
  }
}

// ------------------------------------------------------------------ helpers
Future<String?> _uploadImage(String folder, String id) async {
  final file = await ImagePicker().pickImage(source: ImageSource.gallery, maxWidth: 1600, imageQuality: 82);
  if (file == null) return null;
  final bytes = await file.readAsBytes();
  final ref = FirebaseStorage.instance.ref('$folder/$id-${DateTime.now().millisecondsSinceEpoch}.jpg');
  await ref.putData(bytes, SettableMetadata(contentType: 'image/jpeg'));
  return ref.getDownloadURL();
}

String _slug(String s) => s.toLowerCase().trim().replaceAll(RegExp(r'[^a-z0-9]+'), '_').replaceAll(RegExp(r'^_|_$'), '');

Widget _field(TextEditingController c, String label, {bool number = false, int lines = 1, String? hint}) => Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: TextField(
        controller: c,
        maxLines: lines,
        keyboardType: number ? const TextInputType.numberWithOptions(decimal: true) : null,
        decoration: InputDecoration(labelText: label, hintText: hint),
      ),
    );

Future<bool> _confirm(BuildContext context, String msg) async =>
    await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        content: Text(msg),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Yes')),
        ],
      ),
    ) ??
    false;

/// Generic live table of a collection with search, add, edit and delete.
class _CollectionPage extends StatefulWidget {
  final String collection;
  final Query<Map<String, dynamic>> Function(CollectionReference<Map<String, dynamic>>)? query;
  final List<String> columns;
  final List<String> Function(String id, Map<String, dynamic> d) row;
  final Future<void> Function(BuildContext, String? id, Map<String, dynamic>? data) edit;
  const _CollectionPage({required this.collection, required this.columns, required this.row, required this.edit, this.query});
  @override
  State<_CollectionPage> createState() => _CollectionPageState();
}

class _CollectionPageState extends State<_CollectionPage> {
  String _q = '';
  @override
  Widget build(BuildContext context) {
    final col = _db.collection(widget.collection);
    final q = widget.query?.call(col) ?? col;
    return Column(children: [
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Row(children: [
          Expanded(child: TextField(decoration: const InputDecoration(hintText: 'Search', prefixIcon: Icon(Icons.search)), onChanged: (v) => setState(() => _q = v.toLowerCase()))),
          const SizedBox(width: 12),
          SizedBox(width: 140, child: FilledButton.icon(onPressed: () => widget.edit(context, null, null), icon: const Icon(Icons.add), label: const Text('Add'))),
        ]),
      ),
      Expanded(
        child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: q.snapshots(),
          builder: (_, snap) {
            if (snap.hasError) return Center(child: Text('Error: ${snap.error}'));
            if (!snap.hasData) return const LoadingView();
            final docs = snap.data!.docs.where((d) => _q.isEmpty || '${d.id} ${d.data()}'.toLowerCase().contains(_q)).toList();
            return SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: SizedBox(
                width: double.infinity,
                child: DataTable(
                  headingRowColor: WidgetStateProperty.all(GrubColors.greenLight),
                  columns: [for (final c in widget.columns) DataColumn(label: Text(c, style: const TextStyle(fontWeight: FontWeight.w700))), const DataColumn(label: Text(''))],
                  rows: [
                    for (final d in docs)
                      DataRow(cells: [
                        for (final v in widget.row(d.id, d.data())) DataCell(Text(v, overflow: TextOverflow.ellipsis)),
                        DataCell(Row(mainAxisSize: MainAxisSize.min, children: [
                          IconButton(icon: const Icon(Icons.edit_outlined), onPressed: () => widget.edit(context, d.id, d.data())),
                          IconButton(
                            icon: const Icon(Icons.delete_outline, color: GrubColors.danger),
                            onPressed: () async {
                              if (await _confirm(context, 'Delete ${d.id}?')) await d.reference.delete();
                            },
                          ),
                        ])),
                      ]),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    ]);
  }
}

Future<void> _editorDialog(BuildContext context, String title, Widget Function(StateSetter) body, Future<void> Function() onSave) => showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => AlertDialog(
          title: Text(title),
          content: SizedBox(width: 560, child: SingleChildScrollView(child: body(setS))),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
            FilledButton(
              style: FilledButton.styleFrom(minimumSize: const Size(120, 44)),
              onPressed: () async {
                try {
                  await onSave();
                  if (ctx.mounted) Navigator.pop(ctx);
                } catch (e) {
                  if (ctx.mounted) ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(content: Text('Save failed: $e')));
                }
              },
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );

// ------------------------------------------------------------------ overview
class _Overview extends StatefulWidget {
  const _Overview();
  @override
  State<_Overview> createState() => _OverviewState();
}

class _OverviewState extends State<_Overview> {
  late Future<Map<String, dynamic>> _f = _load();
  Future<Map<String, dynamic>> _load() async => Map<String, dynamic>.from((await _fn('adminStats').call()).data as Map);
  @override
  Widget build(BuildContext context) => FutureBuilder<Map<String, dynamic>>(
        future: _f,
        builder: (_, s) {
          if (s.hasError) return Center(child: Text('Could not load statistics: ${s.error}'));
          if (!s.hasData) return const LoadingView();
          final d = s.data!;
          final tiles = [
            ('👥', 'Users', d['users']),
            ('🗓️', 'Meal plans', d['mealPlans']),
            ('🛒', 'Shopping lists', d['shoppingLists']),
            ('🍲', 'Recipes', d['recipes']),
            ('📦', 'Products', d['products']),
            ('🏷️', 'Prices', d['prices']),
            ('✅', 'Verified prices', d['verifiedPrices']),
            ('📝', 'Pending reports', d['pendingReports']),
          ];
          return ListView(padding: const EdgeInsets.all(24), children: [
            Wrap(spacing: 16, runSpacing: 16, children: [
              for (final t in tiles)
                SizedBox(
                  width: 220,
                  child: SoftCard(
                    child: Row(children: [
                      EmojiTile(t.$1),
                      const SizedBox(width: 12),
                      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text('${t.$3 ?? 0}', style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w800)),
                        Text(t.$2, style: const TextStyle(color: GrubColors.muted)),
                      ]),
                    ]),
                  ),
                ),
            ]),
            const SizedBox(height: 16),
            Align(alignment: Alignment.centerLeft, child: TextButton.icon(onPressed: () => setState(() => _f = _load()), icon: const Icon(Icons.refresh), label: const Text('Refresh'))),
          ]);
        },
      );
}

// ------------------------------------------------------------------ products
class _ProductsPage extends StatelessWidget {
  const _ProductsPage();
  @override
  Widget build(BuildContext context) => _CollectionPage(
        collection: 'products',
        columns: const ['ID', 'Name', 'Category', 'Unit', 'Package'],
        row: (id, d) => [id, '${d['emoji'] ?? ''} ${d['name'] ?? ''}', '${d['category']}', '${d['unit']}', '${d['defaultPackageLabel'] ?? ''}'],
        edit: (ctx, id, d) => editProduct(ctx, id, d),
      );
}

Future<void> editProduct(BuildContext context, String? id, Map<String, dynamic>? d) {
  final name = TextEditingController(text: d?['name'] ?? '');
  final emoji = TextEditingController(text: d?['emoji'] ?? '🛒');
  final pkg = TextEditingController(text: '${d?['defaultPackageSize'] ?? 1}');
  final pkgLabel = TextEditingController(text: d?['defaultPackageLabel'] ?? '');
  final alts = TextEditingController(text: (d?['alternatives'] as List?)?.join(', ') ?? '');
  final shelf = TextEditingController(text: '${d?['shelfLifeDays'] ?? 0}');
  var category = (d?['category'] as String?) ?? 'vegetables';
  var unit = (d?['unit'] as String?) ?? 'pcs';
  final allergens = <String>{...List<String>.from(d?['allergens'] ?? const [])};
  final tags = <String>{...List<String>.from(d?['dietTags'] ?? const [])};
  var imageUrl = (d?['imageUrl'] as String?) ?? '';
  return _editorDialog(
    context,
    id == null ? 'New product' : 'Edit $id',
    (setS) => Column(mainAxisSize: MainAxisSize.min, children: [
      _field(name, 'Name'),
      Row(children: [
        Expanded(child: _field(emoji, 'Emoji / icon')),
        const SizedBox(width: 10),
        Expanded(
          child: DropdownButtonFormField<String>(
            value: productCategories.containsKey(category) ? category : null,
            decoration: const InputDecoration(labelText: 'Category'),
            items: [for (final e in productCategories.entries) DropdownMenuItem(value: e.key, child: Text(e.value))],
            onChanged: (v) => setS(() => category = v ?? category),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: DropdownButtonFormField<String>(
            value: unit,
            decoration: const InputDecoration(labelText: 'Base unit'),
            items: [for (final u in ['g', 'ml', 'pcs', 'bunch', 'packet']) DropdownMenuItem(value: u, child: Text(u))],
            onChanged: (v) => setS(() => unit = v ?? unit),
          ),
        ),
      ]),
      const SizedBox(height: 10),
      Row(children: [
        Expanded(child: _field(pkg, 'Default package size (base units)', number: true)),
        const SizedBox(width: 10),
        Expanded(child: _field(pkgLabel, 'Package label', hint: '2 kg packet')),
      ]),
      _field(alts, 'Cheaper alternatives (product ids, comma separated)'),
      _field(shelf, 'Shelf life (days)', number: true),
      Align(alignment: Alignment.centerLeft, child: Wrap(spacing: 6, children: [
        const Text('Allergens: '),
        for (final a in ['eggs', 'dairy', 'peanuts', 'gluten', 'fish', 'coconut', 'soy', 'sesame'])
          FilterChip(label: Text(a), selected: allergens.contains(a), onSelected: (v) => setS(() => v ? allergens.add(a) : allergens.remove(a))),
      ])),
      const SizedBox(height: 8),
      Align(alignment: Alignment.centerLeft, child: Wrap(spacing: 6, children: [
        const Text('Diet tags: '),
        for (final t in ['plant', 'meat', 'fish', 'dairy', 'egg'])
          FilterChip(label: Text(t), selected: tags.contains(t), onSelected: (v) => setS(() => v ? tags.add(t) : tags.remove(t))),
      ])),
      const SizedBox(height: 8),
      Row(children: [
        if (imageUrl.isNotEmpty) Image.network(imageUrl, height: 48),
        TextButton.icon(
          onPressed: () async {
            final url = await _uploadImage('products', id ?? _slug(name.text));
            if (url != null) setS(() => imageUrl = url);
          },
          icon: const Icon(Icons.image_outlined),
          label: Text(imageUrl.isEmpty ? 'Upload photo' : 'Replace photo'),
        ),
      ]),
    ]),
    () async {
      final docId = id ?? _slug(name.text);
      if (docId.isEmpty) throw 'Name is required';
      await _db.collection('products').doc(docId).set({
        'name': name.text.trim(),
        'emoji': emoji.text.trim(),
        'category': category,
        'unit': unit,
        'defaultPackageSize': double.tryParse(pkg.text) ?? 1,
        'defaultPackageLabel': pkgLabel.text.trim(),
        'alternatives': alts.text.split(',').map((e) => e.trim()).where((e) => e.isNotEmpty).toList(),
        'shelfLifeDays': int.tryParse(shelf.text) ?? 0,
        'allergens': allergens.toList(),
        'dietTags': tags.toList(),
        'imageUrl': imageUrl,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    },
  );
}

// ------------------------------------------------------------------ prices
class _PricesPage extends StatelessWidget {
  const _PricesPage();
  @override
  Widget build(BuildContext context) => _CollectionPage(
        collection: 'prices',
        columns: const ['Product', 'Supermarket', 'Package', 'Price', 'Status', 'Updated', 'Source'],
        row: (id, d) {
          final lu = d['lastUpdated'];
          final when = lu is Timestamp ? lu.toDate().toString().substring(0, 10) : '${lu ?? ''}'.split('T').first;
          return ['${d['productId']}', '${d['supermarketId']}', '${d['packageLabel'] ?? d['packageSize']}', 'KSh ${d['price']}', '${d['verificationStatus']}${d['active'] == false ? ' (hidden)' : ''}', when, '${d['source'] ?? ''}'];
        },
        edit: (ctx, id, d) => editPrice(ctx, id, d),
      );
}

Future<void> editPrice(BuildContext context, String? id, Map<String, dynamic>? d) async {
  final products = (await _db.collection('products').get()).docs;
  final shops = (await _db.collection('supermarkets').get()).docs;
  if (!context.mounted) return;
  var productId = d?['productId'] as String? ?? (products.isEmpty ? null : products.first.id);
  var shopId = d?['supermarketId'] as String? ?? (shops.isEmpty ? null : shops.first.id);
  var status = d?['verificationStatus'] as String? ?? 'verified';
  var active = d?['active'] as bool? ?? true;
  final brand = TextEditingController(text: d?['brand'] ?? '');
  final size = TextEditingController(text: '${d?['packageSize'] ?? ''}');
  final label = TextEditingController(text: d?['packageLabel'] ?? '');
  final price = TextEditingController(text: '${d?['price'] ?? ''}');
  final location = TextEditingController(text: d?['location'] ?? '');
  final source = TextEditingController(text: d?['source'] ?? 'Shelf price checked by Grub team');
  return _editorDialog(
    context,
    id == null ? 'New price' : 'Edit price',
    (setS) => Column(mainAxisSize: MainAxisSize.min, children: [
      DropdownButtonFormField<String>(
        value: productId,
        decoration: const InputDecoration(labelText: 'Product'),
        items: [for (final p in products) DropdownMenuItem(value: p.id, child: Text('${p.data()['emoji'] ?? ''} ${p.data()['name']}'))],
        onChanged: (v) => setS(() {
          productId = v;
          final pd = products.firstWhere((p) => p.id == v).data();
          if (size.text.isEmpty) size.text = '${pd['defaultPackageSize'] ?? ''}';
          if (label.text.isEmpty) label.text = '${pd['defaultPackageLabel'] ?? ''}';
        }),
      ),
      const SizedBox(height: 10),
      DropdownButtonFormField<String>(
        value: shopId,
        decoration: const InputDecoration(labelText: 'Supermarket'),
        items: [for (final s in shops) DropdownMenuItem(value: s.id, child: Text('${s.data()['name']}'))],
        onChanged: (v) => setS(() => shopId = v),
      ),
      const SizedBox(height: 10),
      Row(children: [
        Expanded(child: _field(size, 'Package size (base units)', number: true)),
        const SizedBox(width: 10),
        Expanded(child: _field(label, 'Package label', hint: '2 kg packet')),
      ]),
      Row(children: [
        Expanded(child: _field(price, 'Price (KSh)', number: true)),
        const SizedBox(width: 10),
        Expanded(child: _field(brand, 'Brand')),
      ]),
      _field(location, 'Location / branch'),
      _field(source, 'Source of the price'),
      DropdownButtonFormField<String>(
        value: status,
        decoration: const InputDecoration(labelText: 'Verification status'),
        items: const [
          DropdownMenuItem(value: 'verified', child: Text('Verified')),
          DropdownMenuItem(value: 'user_submitted', child: Text('User-submitted')),
          DropdownMenuItem(value: 'estimated', child: Text('Estimate')),
          DropdownMenuItem(value: 'demo', child: Text('Demo data')),
        ],
        onChanged: (v) => setS(() => status = v ?? status),
      ),
      SwitchListTile(value: active, onChanged: (v) => setS(() => active = v), title: const Text('Visible in app')),
    ]),
    () async {
      final p = double.tryParse(price.text);
      final sz = double.tryParse(size.text);
      if (productId == null || shopId == null || p == null || p <= 0 || sz == null || sz <= 0) throw 'Product, supermarket, size and price are required';
      final ref = id == null ? _db.collection('prices').doc() : _db.collection('prices').doc(id);
      await ref.set({
        'productId': productId,
        'supermarketId': shopId,
        'brand': brand.text.trim(),
        'packageSize': sz,
        'packageLabel': label.text.trim(),
        'price': p,
        'location': location.text.trim(),
        'source': source.text.trim(),
        'verificationStatus': status,
        'active': active,
        'lastUpdated': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    },
  );
}

// ------------------------------------------------------------------ supermarkets
class _SupermarketsPage extends StatelessWidget {
  const _SupermarketsPage();
  @override
  Widget build(BuildContext context) => _CollectionPage(
        collection: 'supermarkets',
        columns: const ['ID', 'Name', 'Location', 'Address'],
        row: (id, d) => [id, '${d['name']}', '${d['location'] ?? ''}', '${d['address'] ?? ''}'],
        edit: (ctx, id, d) {
          final name = TextEditingController(text: d?['name'] ?? '');
          final color = TextEditingController(text: d?['color'] ?? '#3DA832');
          final loc = TextEditingController(text: d?['location'] ?? '');
          final addr = TextEditingController(text: d?['address'] ?? '');
          return _editorDialog(
            ctx,
            id == null ? 'New supermarket' : 'Edit $id',
            (_) => Column(mainAxisSize: MainAxisSize.min, children: [_field(name, 'Name'), _field(color, 'Brand colour (hex)'), _field(loc, 'Location'), _field(addr, 'Address')]),
            () => _db.collection('supermarkets').doc(id ?? _slug(name.text)).set(
                {'name': name.text.trim(), 'color': color.text.trim(), 'location': loc.text.trim(), 'address': addr.text.trim()}, SetOptions(merge: true)),
          );
        },
      );
}

// ------------------------------------------------------------------ recipes
class _RecipesPage extends StatelessWidget {
  const _RecipesPage();
  @override
  Widget build(BuildContext context) => _CollectionPage(
        collection: 'recipes',
        columns: const ['ID', 'Name', 'Meal', 'Serves', 'Ingredients', 'Published'],
        row: (id, d) => [id, '${d['emoji'] ?? ''} ${d['name']}', '${d['category']}', '${d['servings']}', '${(d['ingredients'] as List?)?.length ?? 0}', d['published'] == true ? 'Yes' : 'No'],
        edit: (ctx, id, d) => editRecipe(ctx, id, d),
      );
}

Future<void> editRecipe(BuildContext context, String? id, Map<String, dynamic>? d) async {
  final products = (await _db.collection('products').orderBy('name').get()).docs;
  if (!context.mounted) return;
  final name = TextEditingController(text: d?['name'] ?? '');
  final emoji = TextEditingController(text: d?['emoji'] ?? '🍲');
  final desc = TextEditingController(text: d?['description'] ?? '');
  final prep = TextEditingController(text: '${d?['prepMinutes'] ?? 10}');
  final cook = TextEditingController(text: '${d?['cookMinutes'] ?? 20}');
  final serv = TextEditingController(text: '${d?['servings'] ?? 4}');
  final tags = TextEditingController(text: (d?['tags'] as List?)?.join(', ') ?? '');
  final steps = TextEditingController(text: (d?['instructions'] as List?)?.join('\n') ?? '');
  final n = Map<String, dynamic>.from(d?['nutrition'] ?? const {});
  final kcal = TextEditingController(text: '${n['kcal'] ?? ''}');
  final protein = TextEditingController(text: '${n['protein'] ?? ''}');
  final carbs = TextEditingController(text: '${n['carbs'] ?? ''}');
  final fat = TextEditingController(text: '${n['fat'] ?? ''}');
  var category = (d?['category'] as String?) ?? 'lunch';
  var published = d?['published'] as bool? ?? true;
  var imageUrl = (d?['imageUrl'] as String?) ?? '';
  final ings = <Map<String, dynamic>>[for (final i in (d?['ingredients'] as List?) ?? const []) Map<String, dynamic>.from(i as Map)];
  return _editorDialog(
    context,
    id == null ? 'New recipe' : 'Edit $id',
    (setS) => Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Expanded(flex: 3, child: _field(name, 'Name')),
        const SizedBox(width: 10),
        Expanded(child: _field(emoji, 'Emoji')),
        const SizedBox(width: 10),
        Expanded(
          flex: 2,
          child: DropdownButtonFormField<String>(
            value: category,
            decoration: const InputDecoration(labelText: 'Meal'),
            items: [for (final m in MealSlot.values) DropdownMenuItem(value: m.name, child: Text(mealSlotLabel(m)))],
            onChanged: (v) => setS(() => category = v ?? category),
          ),
        ),
      ]),
      _field(desc, 'Description', lines: 2),
      Row(children: [
        Expanded(child: _field(prep, 'Prep (min)', number: true)),
        const SizedBox(width: 8),
        Expanded(child: _field(cook, 'Cook (min)', number: true)),
        const SizedBox(width: 8),
        Expanded(child: _field(serv, 'Servings', number: true)),
      ]),
      _field(tags, 'Tags (vegan, vegetarian, quick, budget)'),
      const Text('Ingredients', style: TextStyle(fontWeight: FontWeight.w700)),
      for (var i = 0; i < ings.length; i++)
        Row(children: [
          Expanded(
            flex: 3,
            child: DropdownButton<String>(
              isExpanded: true,
              value: products.any((p) => p.id == ings[i]['productId']) ? ings[i]['productId'] as String : null,
              items: [for (final p in products) DropdownMenuItem(value: p.id, child: Text('${p.data()['name']}', overflow: TextOverflow.ellipsis))],
              onChanged: (v) => setS(() => ings[i]['productId'] = v),
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 80,
            child: TextFormField(
              initialValue: '${ings[i]['amount'] ?? ''}',
              decoration: const InputDecoration(hintText: 'Qty'),
              onChanged: (v) => ings[i]['amount'] = double.tryParse(v) ?? 0,
            ),
          ),
          const SizedBox(width: 8),
          DropdownButton<String>(
            value: ings[i]['unit'] as String? ?? 'g',
            items: [for (final u in ['g', 'kg', 'ml', 'l', 'pcs', 'bunch', 'packet', 'tbsp', 'tsp', 'cup']) DropdownMenuItem(value: u, child: Text(u))],
            onChanged: (v) => setS(() => ings[i]['unit'] = v),
          ),
          IconButton(icon: const Icon(Icons.close), onPressed: () => setS(() => ings.removeAt(i))),
        ]),
      TextButton.icon(
        onPressed: () => setS(() => ings.add({'productId': products.isEmpty ? '' : products.first.id, 'amount': 1.0, 'unit': 'pcs'})),
        icon: const Icon(Icons.add),
        label: const Text('Add ingredient'),
      ),
      _field(steps, 'Instructions (one step per line)', lines: 6),
      Row(children: [
        Expanded(child: _field(kcal, 'kcal / serving', number: true)),
        const SizedBox(width: 6),
        Expanded(child: _field(protein, 'Protein g', number: true)),
        const SizedBox(width: 6),
        Expanded(child: _field(carbs, 'Carbs g', number: true)),
        const SizedBox(width: 6),
        Expanded(child: _field(fat, 'Fat g', number: true)),
      ]),
      Row(children: [
        if (imageUrl.isNotEmpty) Image.network(imageUrl, height: 56),
        TextButton.icon(
          onPressed: () async {
            final url = await _uploadImage('recipes', id ?? _slug(name.text));
            if (url != null) setS(() => imageUrl = url);
          },
          icon: const Icon(Icons.photo_camera_outlined),
          label: Text(imageUrl.isEmpty ? 'Upload food photo' : 'Replace photo'),
        ),
        const Spacer(),
        const Text('Published'),
        Switch(value: published, onChanged: (v) => setS(() => published = v)),
      ]),
    ]),
    () async {
      final docId = id ?? _slug(name.text);
      if (docId.isEmpty) throw 'Name is required';
      final cleanIngs = ings.where((i) => (i['productId'] as String?)?.isNotEmpty == true && ((i['amount'] as num?) ?? 0) > 0).toList();
      if (cleanIngs.isEmpty) throw 'Add at least one ingredient';
      await _db.collection('recipes').doc(docId).set({
        'name': name.text.trim(),
        'emoji': emoji.text.trim(),
        'category': category,
        'description': desc.text.trim(),
        'prepMinutes': int.tryParse(prep.text) ?? 0,
        'cookMinutes': int.tryParse(cook.text) ?? 0,
        'servings': int.tryParse(serv.text) ?? 1,
        'tags': tags.text.split(',').map((e) => e.trim()).where((e) => e.isNotEmpty).toList(),
        'ingredients': cleanIngs,
        'instructions': steps.text.split('\n').map((e) => e.trim()).where((e) => e.isNotEmpty).toList(),
        if (kcal.text.isNotEmpty)
          'nutrition': {
            'kcal': int.tryParse(kcal.text) ?? 0,
            'protein': int.tryParse(protein.text) ?? 0,
            'carbs': int.tryParse(carbs.text) ?? 0,
            'fat': int.tryParse(fat.text) ?? 0,
          },
        'imageUrl': imageUrl,
        'published': published,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    },
  );
}

// ------------------------------------------------------------------ price reports
class _ReportsPage extends StatelessWidget {
  const _ReportsPage();
  @override
  Widget build(BuildContext context) => StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: _db.collection('priceReports').where('status', isEqualTo: 'pending').orderBy('createdAt', descending: true).snapshots(),
        builder: (_, snap) {
          if (snap.hasError) return Center(child: Text('Error: ${snap.error}'));
          if (!snap.hasData) return const LoadingView();
          final docs = snap.data!.docs;
          if (docs.isEmpty) return const EmptyState(emoji: '✅', title: 'No pending reports', message: 'User-submitted prices will appear here for approval.');
          return ListView(padding: const EdgeInsets.all(24), children: [
            for (final d in docs)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: SoftCard(
                  child: Row(children: [
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text('${d['productId']} at ${d['supermarketId']}', style: const TextStyle(fontWeight: FontWeight.w700)),
                        Text('KSh ${d['price']} for ${d['packageLabel'] ?? d['packageSize']} · ${d.data()['location'] ?? ''}', style: const TextStyle(color: GrubColors.muted)),
                      ]),
                    ),
                    TextButton(onPressed: () => _review(context, d.id, false, ''), child: const Text('Reject', style: TextStyle(color: GrubColors.danger))),
                    TextButton(onPressed: () => _review(context, d.id, true, 'user_submitted'), child: const Text('Approve as user-submitted')),
                    SizedBox(
                      width: 170,
                      child: FilledButton(
                        style: FilledButton.styleFrom(minimumSize: const Size(0, 42)),
                        onPressed: () => _review(context, d.id, true, 'verified'),
                        child: const Text('Approve as verified'),
                      ),
                    ),
                  ]),
                ),
              ),
          ]);
        },
      );

  Future<void> _review(BuildContext context, String id, bool approve, String status) async {
    try {
      await _fn('reviewPriceReport').call({'reportId': id, 'approve': approve, 'status': status});
    } catch (e) {
      if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed: $e')));
    }
  }
}

// ------------------------------------------------------------------ categories
class _CategoriesPage extends StatelessWidget {
  const _CategoriesPage();
  @override
  Widget build(BuildContext context) => _CollectionPage(
        collection: 'categories',
        columns: const ['ID', 'Display name', 'Sort'],
        row: (id, d) => [id, '${d['name']}', '${d['sort'] ?? ''}'],
        edit: (ctx, id, d) {
          final name = TextEditingController(text: d?['name'] ?? '');
          final sort = TextEditingController(text: '${d?['sort'] ?? 0}');
          return _editorDialog(
            ctx,
            id == null ? 'New category' : 'Edit $id',
            (_) => Column(mainAxisSize: MainAxisSize.min, children: [_field(name, 'Display name'), _field(sort, 'Sort order', number: true)]),
            () => _db.collection('categories').doc(id ?? _slug(name.text)).set({'name': name.text.trim(), 'sort': int.tryParse(sort.text) ?? 0}, SetOptions(merge: true)),
          );
        },
      );
}

// ------------------------------------------------------------------ content reports
class _ContentReportsPage extends StatelessWidget {
  const _ContentReportsPage();
  @override
  Widget build(BuildContext context) => StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: _db.collection('contentReports').snapshots(),
        builder: (_, snap) {
          if (!snap.hasData) return const LoadingView();
          final docs = snap.data!.docs;
          if (docs.isEmpty) return const EmptyState(emoji: '🙌', title: 'Nothing reported', message: 'Reports about recipes or prices from users appear here.');
          return ListView(padding: const EdgeInsets.all(24), children: [
            for (final d in docs)
              ListTile(
                title: Text('${d.data()['type'] ?? 'report'}: ${d.data()['targetId'] ?? ''}'),
                subtitle: Text('${d.data()['reason'] ?? ''}'),
                trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                  if (d.data()['resolved'] != true) TextButton(onPressed: () => d.reference.update({'resolved': true}), child: const Text('Mark resolved')),
                  IconButton(icon: const Icon(Icons.delete_outline), onPressed: () => d.reference.delete()),
                ]),
              ),
          ]);
        },
      );
}

// ------------------------------------------------------------------ admins
class _AdminsPage extends StatefulWidget {
  const _AdminsPage();
  @override
  State<_AdminsPage> createState() => _AdminsPageState();
}

class _AdminsPageState extends State<_AdminsPage> {
  final _email = TextEditingController();
  String? _msg;
  Future<void> _set(bool admin) async {
    try {
      await _fn('setAdminRole').call({'email': _email.text.trim(), 'admin': admin});
      setState(() => _msg = admin ? '${_email.text} is now an admin.' : '${_email.text} is no longer an admin.');
    } catch (e) {
      setState(() => _msg = 'Failed: $e');
    }
  }

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.all(24),
        child: SizedBox(
          width: 480,
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Grant or remove administrator access. The person must already have a Grub account.'),
            const SizedBox(height: 12),
            TextField(controller: _email, decoration: const InputDecoration(labelText: 'Email')),
            const SizedBox(height: 12),
            Row(children: [
              SizedBox(width: 160, child: FilledButton(onPressed: () => _set(true), child: const Text('Make admin'))),
              const SizedBox(width: 10),
              SizedBox(width: 160, child: OutlinedButton(onPressed: () => _set(false), child: const Text('Remove admin'))),
            ]),
            if (_msg != null) Padding(padding: const EdgeInsets.only(top: 12), child: Text(_msg!)),
          ]),
        ),
      );
}
