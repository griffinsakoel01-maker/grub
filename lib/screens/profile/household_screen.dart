import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/i18n.dart';
import '../../core/theme.dart';
import '../../state/app_state.dart';
import '../../widgets/common.dart';

/// Create or join a household so everyone shares the same shopping lists.
class HouseholdScreen extends StatefulWidget {
  const HouseholdScreen({super.key});
  @override
  State<HouseholdScreen> createState() => _HouseholdScreenState();
}

class _HouseholdScreenState extends State<HouseholdScreen> {
  final _name = TextEditingController();
  final _code = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _name.dispose();
    _code.dispose();
    super.dispose();
  }

  Future<void> _run(Future<void> Function() f) async {
    setState(() => _busy = true);
    try {
      await f();
    } catch (e) {
      if (mounted) showSnack(context, e.toString().replaceFirst(RegExp(r'^.*?\] '), ''), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final h = s.household;
    return Scaffold(
      appBar: AppBar(title: const T('My household')),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        const T('Everyone in your household sees the same shopping list and can tick items as they buy.',
            style: TextStyle(color: GrubColors.muted)),
        const SizedBox(height: 16),
        if (!s.repo.supportsHouseholds)
          const SoftCard(child: T('Shared households need an online account.'))
        else if (h == null) ...[
          SoftCard(
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              const T('Create a household', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
              const SizedBox(height: 10),
              TextField(controller: _name, decoration: InputDecoration(labelText: tr('Household name'), hintText: 'Familia ya Mukoo')),
              const SizedBox(height: 10),
              FilledButton(
                onPressed: _busy
                    ? null
                    : () => _run(() => s.createHousehold(_name.text.trim().isEmpty ? tr('My household') : _name.text.trim())),
                child: const T('Create'),
              ),
            ]),
          ),
          const SizedBox(height: 12),
          SoftCard(
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              const T('Join with a code', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
              const SizedBox(height: 10),
              TextField(
                controller: _code,
                textCapitalization: TextCapitalization.characters,
                maxLength: 6,
                decoration: InputDecoration(labelText: tr('Enter the 6-letter code'), counterText: ''),
              ),
              const SizedBox(height: 10),
              OutlinedButton(
                onPressed: _busy ? null : () => _run(() => s.joinHousehold(_code.text.trim().toUpperCase())),
                child: const T('Join'),
              ),
            ]),
          ),
        ] else ...[
          SoftCard(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(h.name, style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 12),
              const T('Invite code', style: TextStyle(fontSize: 12, color: GrubColors.muted)),
              Row(children: [
                SelectableText(h.inviteCode,
                    style: const TextStyle(fontSize: 30, fontWeight: FontWeight.w800, letterSpacing: 6, color: GrubColors.greenDark)),
                IconButton(
                  icon: const Icon(Icons.copy),
                  onPressed: () {
                    Clipboard.setData(ClipboardData(text: h.inviteCode));
                    showSnack(context, 'Copied');
                  },
                ),
              ]),
              const SizedBox(height: 8),
              FilledButton.icon(
                icon: const Icon(Icons.chat),
                label: const T('Share code on WhatsApp'),
                onPressed: () => launchUrl(
                  Uri.parse('https://wa.me/?text=${Uri.encodeComponent('Join our ${h.name} shopping list on Grub 🛒\nOpen https://grub-kenya-4965c.web.app → Profile → My household → Join, and enter code ${h.inviteCode}')}'),
                  mode: LaunchMode.externalApplication,
                ),
              ),
            ]),
          ),
          const SectionHeader('Members'),
          for (final m in h.members)
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: CircleAvatar(
                backgroundColor: GrubColors.greenLight,
                child: Text((h.memberNames[m] ?? '?').isEmpty ? '?' : h.memberNames[m]!.substring(0, 1).toUpperCase()),
              ),
              title: Text(h.memberNames[m] ?? 'Member'),
              subtitle: m == h.ownerId ? const Text('Owner') : null,
            ),
          const SizedBox(height: 16),
          TextButton.icon(
            style: TextButton.styleFrom(foregroundColor: GrubColors.danger),
            icon: const Icon(Icons.logout),
            label: const T('Leave household'),
            onPressed: _busy ? null : () => _run(s.leaveHousehold),
          ),
        ],
      ]),
    );
  }
}
