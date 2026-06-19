import 'package:flutter/material.dart';
import '../data/repository.dart';
import '../services/services.dart';
import '../utils/app_theme.dart';

/// Result of the claim picker: [claimId] is the placeholder being taken over,
/// or null to join as a new member.
class _JoinChoice {
  final String? claimId;
  const _JoinChoice(this.claimId);
}

/// Extract an invite code from a raw value, accepts a bare code or an
/// `expensio://join/<code>` link (from a QR or deep link). Null if unusable.
String? parseInviteCode(String raw) {
  final s = raw.trim();
  if (s.isEmpty) return null;
  final uri = Uri.tryParse(s);
  if (uri != null && uri.scheme == 'expensio') {
    final segs = [uri.host, ...uri.pathSegments].where((x) => x.isNotEmpty);
    return segs.isEmpty ? null : segs.last.toUpperCase();
  }
  return s.toUpperCase();
}

/// Preview an invite, let the joiner claim a placeholder (or join fresh), then
/// join. Shared by manual code entry, QR scanning, and deep links. [rawCode]
/// may be a bare code or an invite link.
Future<void> runJoinFlow(BuildContext context, String rawCode) async {
  final messenger = ScaffoldMessenger.of(context);
  void snack(String m) => messenger.showSnackBar(SnackBar(content: Text(m)));

  if (!Services.firebaseActive) {
    snack('Sign in to join a shared group.');
    return;
  }
  final code = parseInviteCode(rawCode);
  if (code == null) {
    snack('Invalid invite code.');
    return;
  }

  try {
    final invite = await Services.state.getInvitePreview(code);
    if (!context.mounted) return;
    if (invite == null) {
      snack('Invalid invite code.');
      return;
    }
    if (invite.expired) {
      snack('This invite has expired.');
      return;
    }
    final choice = await _chooseClaim(context, invite);
    if (choice == null) return; // cancelled
    await Services.state.joinGroup(code, claimPlaceholderId: choice.claimId);
    snack('Joined "${invite.groupName}"');
  } on InviteException catch (e) {
    snack(e.message);
  } catch (_) {
    snack('Could not join. Please try again.');
  }
}

/// Ask whether the joiner is one of the group's placeholder members (claim that
/// slot) or a brand-new member. Returns null if cancelled.
Future<_JoinChoice?> _chooseClaim(BuildContext context, GroupInvite invite) {
  if (invite.claimable.isEmpty) {
    return showDialog<_JoinChoice>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Join "${invite.groupName}"?'),
        content: const Text(
            'You\'ll become a member and see this group\'s expenses.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, const _JoinChoice(null)),
              child: const Text('Join')),
        ],
      ),
    );
  }
  return showModalBottomSheet<_JoinChoice>(
    context: context,
    backgroundColor: AppTheme.cardBg,
    shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
    builder: (ctx) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(20, 20, 20, 4),
            child: Text('Which member are you?',
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
            child: Text(
              'Pick your name in "${invite.groupName}" to take over its '
              'expenses, or join as a new member.',
              style: const TextStyle(
                  fontSize: 12, color: AppTheme.textSecondary),
            ),
          ),
          ...invite.claimable.map((m) => ListTile(
                leading: CircleAvatar(
                  radius: 18,
                  backgroundColor: AppTheme.primary.withValues(alpha: 0.12),
                  child: Text(
                    m.name.isNotEmpty ? m.name[0].toUpperCase() : '?',
                    style: const TextStyle(
                        fontWeight: FontWeight.w700, color: AppTheme.primary),
                  ),
                ),
                title: Text(m.name),
                trailing: const Icon(Icons.chevron_right, size: 18),
                onTap: () => Navigator.pop(ctx, _JoinChoice(m.id)),
              )),
          const Divider(height: 1),
          ListTile(
            leading: const CircleAvatar(
              radius: 18,
              backgroundColor: AppTheme.surfaceMid,
              child: Icon(Icons.person_add_alt, size: 18),
            ),
            title: const Text('I\'m a new member'),
            trailing: const Icon(Icons.chevron_right, size: 18),
            onTap: () => Navigator.pop(ctx, const _JoinChoice(null)),
          ),
          const SizedBox(height: 8),
        ],
      ),
    ),
  );
}
