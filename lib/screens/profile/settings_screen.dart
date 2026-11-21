import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/config.dart';
import '../../core/theme.dart';
import '../../state/app_state.dart';
import '../../widgets/common.dart';
import '../../core/i18n.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final p = s.profile!;
    return Scaffold(
      appBar: AppBar(title: const T('Settings')),
      body: ListView(padding: const EdgeInsets.fromLTRB(16, 0, 16, 32), children: [
        const SectionHeader('Language'),
        SoftCard(
          child: SegmentedButton<String>(
            segments: const [ButtonSegment(value: 'en', label: Text('English')), ButtonSegment(value: 'sw', label: Text('Kiswahili'))],
            selected: {Lang.notifier.value},
            showSelectedIcon: false,
            onSelectionChanged: (v) => Lang.set(v.first),
          ),
        ),
        const SectionHeader('Notifications'),
        SoftCard(
          padding: EdgeInsets.zero,
          child: Column(children: [
            SwitchListTile(
              activeColor: GrubColors.green,
              title: const T('Reminders'),
              subtitle: const T('Shopping day and items about to expire'),
              value: p.notifications,
              onChanged: (v) => s.saveProfile(p.copyWith(notifications: v)),
            ),
          ]),
        ),
        const SectionHeader('Privacy'),
        SoftCard(
          padding: EdgeInsets.zero,
          child: Column(children: [
            SwitchListTile(
              activeColor: GrubColors.green,
              title: const T('Share prices I report anonymously'),
              subtitle: const T('Helps other families once the Grub team verifies them'),
              value: p.shareAnonymousPrices,
              onChanged: (v) => s.saveProfile(p.copyWith(shareAnonymousPrices: v)),
            ),
            const ListTile(
              leading: Icon(Icons.lock_outline),
              title: T('Your data'),
              subtitle: T('Your plans, lists, pantry and spending are private to your account. We never sell personal data.'),
            ),
          ]),
        ),
        const SectionHeader('Account security'),
        SoftCard(
          padding: EdgeInsets.zero,
          child: Column(children: [
            ListTile(
              leading: const Icon(Icons.password),
              title: const T('Change password'),
              subtitle: Text('We\'ll email a reset link to ${p.email}'),
              onTap: () async {
                try {
                  await s.auth.sendPasswordReset(p.email);
                  if (context.mounted) showSnack(context, 'Reset link sent to ${p.email}.');
                } catch (e) {
                  if (context.mounted) showSnack(context, 'Couldn\'t send the email. Try again later.', error: true);
                }
              },
            ),
            ListTile(
              leading: const Icon(Icons.cloud_done_outlined),
              title: const T('Sync'),
              subtitle: Text(s.isDemo ? 'Demo mode – data is stored on this device only' : 'Synced to your Grub account · works offline'),
            ),
          ]),
        ),
        const SectionHeader('About'),
        SoftCard(
          padding: EdgeInsets.zero,
          child: Column(children: [
            const ListTile(leading: Icon(Icons.info_outline), title: T('Prices'), subtitle: T('Prices are labelled Verified, User-submitted, Estimate or Demo. They may differ in store.')),
            ListTile(leading: const Icon(Icons.refresh), title: const T('Refresh recipes & prices'), onTap: () async {
              await s.refreshCatalog();
              if (context.mounted) showSnack(context, 'Updated.');
            }),
            ListTile(leading: const GrubLogo(height: 24, iconOnly: true), title: const Text('Grub 1.0.0'), subtitle: const Text(AppConfig.tagline)),
          ]),
        ),
        const SizedBox(height: 20),
        OutlinedButton.icon(onPressed: s.signOut, icon: const Icon(Icons.logout), label: const T('Sign out')),
        const SizedBox(height: 10),
        TextButton(
          onPressed: () async {
            final ok = await showDialog<bool>(
              context: context,
              builder: (ctx) => AlertDialog(
                title: const T('Delete account?'),
                content: const T('This permanently deletes your profile, meal plans, shopping lists, pantry and spending history. This cannot be undone.'),
                actions: [
                  TextButton(onPressed: () => Navigator.pop(ctx, false), child: const T('Cancel')),
                  TextButton(onPressed: () => Navigator.pop(ctx, true), child: const T('Delete', style: TextStyle(color: GrubColors.danger))),
                ],
              ),
            );
            if (ok != true) return;
            try {
              if (context.mounted) Navigator.of(context).popUntil((r) => r.isFirst);
              await s.deleteAccount();
            } catch (e) {
              if (context.mounted) showSnack(context, 'Couldn\'t delete the account. Sign in again and retry.', error: true);
            }
          },
          child: const T('Delete account', style: TextStyle(color: GrubColors.danger)),
        ),
      ]),
    );
  }
}
