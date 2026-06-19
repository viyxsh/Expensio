import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';
import '../models/group_model.dart';
import '../services/services.dart';
import '../utils/app_theme.dart';

/// Deep link an invite code travels in (QR + share link). Handling it on open
/// is added with the scanner/deep-link slice.
String inviteLinkFor(String code) => 'expensio://join/$code';

/// Create (or refresh) a shareable invite code for [group] and present it.
/// Reusable from the Groups list, a group's detail, and the group editor.
/// Requires cloud mode. Invites live on the server so a second device can join.
Future<void> showInviteSheet(BuildContext context, GroupModel group) async {
  final messenger = ScaffoldMessenger.of(context);
  void snack(String m) =>
      messenger.showSnackBar(SnackBar(content: Text(m)));

  if (!Services.firebaseActive) {
    snack('Sign in to invite people across devices.');
    return;
  }

  String code;
  try {
    code = await Services.state.createInvite(group.id);
  } catch (_) {
    snack('Could not create an invite. Please try again.');
    return;
  }
  if (!context.mounted) return;

  final link = inviteLinkFor(code);
  final message =
      'Join my Expensio group "${group.name}". Tap: $link\n\nOr open Expensio → '
      'Groups → Join with code, and enter: $code';

  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: AppTheme.cardBg,
    shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
    builder: (ctx) => Padding(
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('Invite to ${group.name}',
              style:
                  const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
          const SizedBox(height: 4),
          const Text('Scan the QR or share the code. Expires in 7 days.',
              style: TextStyle(fontSize: 12, color: AppTheme.textSecondary)),
          const SizedBox(height: 18),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
            ),
            child: QrImageView(
              data: link,
              version: QrVersions.auto,
              size: 180,
              backgroundColor: Colors.white,
            ),
          ),
          const SizedBox(height: 18),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
            decoration: BoxDecoration(
              color: AppTheme.surface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppTheme.divider),
            ),
            child: Text(
              code,
              style: const TextStyle(
                fontSize: 26,
                fontWeight: FontWeight.w700,
                letterSpacing: 6,
                color: AppTheme.primary,
              ),
            ),
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () {
                    Clipboard.setData(ClipboardData(text: code));
                    snack('Code copied');
                  },
                  icon: const Icon(Icons.copy, size: 18),
                  label: const Text('Copy code'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: () => Share.share(message),
                  icon: const Icon(Icons.share, size: 18),
                  label: const Text('Share link'),
                ),
              ),
            ],
          ),
        ],
      ),
    ),
  );
}
