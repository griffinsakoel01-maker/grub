import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/config.dart';
import '../../core/theme.dart';
import '../../state/app_state.dart';
import '../../widgets/common.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final p = s.profile!;
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(padding: const EdgeInsets.fromLTRB(16, 0, 16, 32), children: [
        const SectionHeader('Notifications'),
        SoftCard(
          padding: EdgeInsets.zero,
          child: Column(children: [
            SwitchListTile(
              activeColor: GrubColors.green,
              title: const Text('Reminders'),
              subtitle: const Text('Shopping day and items about to expire'),
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
              title: const Text('Share prices I report anonymously'),
              subtitle: const Text('Helps other families once the Grub team verifies them'),
              value: p.shareAnonymousPrices,
              onChanged: (v) => s.saveProfile(p.copyWith(shareAnonymousPrices: v)),
            ),
            const ListTile(
              leading: Icon(Icons.lock_outline),
              title: Text('Your data'),
              subtitle: Text('Your plans, lists, pantry and spending are private to your account. We never sell personal data.'),
            ),
          ]),
        ),
        const SectionHeader('Account security'),
        SoftCard(
          padding: EdgeInsets.zero,
          child: Column(children: [
            ListTile(
              leading: const Icon(Icons.password),
              title: const Text('Change password'),
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
              title: const Text('Sync'),
              subtitle: Text(s.isDemo ? 'Demo mode – data is stored on this device only' : 'Synced to your Grub account · works offline'),
            ),
          ]),
        ),
        const SectionHeader('About'),
        SoftCard(
          padding: EdgeInsets.zero,
          child: Column(children: [
            const ListTile(leading: Icon(Icons.info_outline), title: Text('Prices'), subtitle: Text('Prices are labelled Verified, User-submitted, Estimate or Demo. They may differ in store.')),
            ListTile(leading: const Icon(Icons.refresh), title: const Text('Refresh recipes & prices'), onTap: () async {
              await s.refreshCatalog();
              if (context.mounted) showSnack(context, 'Updated.');
            }),
            ListTile(leading: const GrubLogo(height: 24, iconOnly: true), title: const Text('Grub 1.0.0'), subtitle: const Text(AppConfig.tagline)),
          ]),
        ),
        const SizedBox(height: 20),
        OutlinedButton.icon(onPressed: s.signOut, icon: const Icon(Icons.logout), label: const Text('Sign out')),
        const SizedBox(height: 10),
        TextButton(
          onPressed: () async {
            final ok = await showDialog<bool>(
              context: context,
              builder: (ctx) => AlertDialog(
                title: const Text('Delete account?'),
                content: const Text('This permanently deletes your profile, meal plans, shopping lists, pantry and spending history. This cannot be undone.'),
                actions: [
                  TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
                  TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Delete', style: TextStyle(color: GrubColors.danger))),
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
          child: const Text('Delete account', style: TextStyle(color: GrubColors.danger)),
        ),
      ]),
    );
  }
}
