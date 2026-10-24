import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:tn_core/tn_core.dart';

import '../app_scope.dart';
import '../services/app_config.dart';
import '../ui/theme.dart';
import '../ui/widgets.dart';
import 'common.dart';

/// The text key for a rejected code. None of the texts names the code.
String joinProblemKey(JoinCodeProblem p) => switch (p) {
      JoinCodeProblem.notAJoinCode => 'join.error.notAJoinCode',
      JoinCodeProblem.tooLong => 'join.error.tooLong',
      JoinCodeProblem.newerVersion => 'join.error.newerVersion',
      JoinCodeProblem.badNode => 'join.error.badNode',
      JoinCodeProblem.duplicateParameter ||
      JoinCodeProblem.missingParameter ||
      JoinCodeProblem.badVersion ||
      JoinCodeProblem.badSeed ||
      JoinCodeProblem.badRoot ||
      JoinCodeProblem.badCheck =>
        'join.error.damaged',
    };

/// A readable text for an error code of the server's join handling (`join_code_revoked` and the others), or null.
String? joinServerErrorKey(String? code) {
  final c = code?.toLowerCase() ?? '';
  if (c.contains('join_code_revoked')) return 'join.error.revoked';
  if (c.contains('join_code_expired')) return 'join.error.expired';
  if (c.contains('join_code_exhausted')) return 'join.error.exhausted';
  if (c.contains('join_code_rate_limited')) return 'join.error.rateLimited';
  return null;
}

/// Checks a text and, if it is a join code, opens the confirmation page. Returns the text key of the problem, or null.
/// The text is never stored or shown.
String? openJoinConfirmation(BuildContext context, String text, {VoidCallback? onDone}) {
  final r = JoinCode.tryParse(text);
  if (r.code == null) return joinProblemKey(r.problem ?? JoinCodeProblem.notAJoinCode);
  Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => JoinConfirmScreen(code: r.code!, onDone: onDone)));
  return null;
}

/// Reads the clipboard only because the user tapped "Code einfügen".
Future<String?> pasteJoinCode(BuildContext context, {VoidCallback? onDone}) async {
  final data = await Clipboard.getData(Clipboard.kTextPlain);
  final text = data?.text;
  if (text == null || text.trim().isEmpty) return 'join.pasteEmpty';
  if (!context.mounted) return null;
  return openJoinConfirmation(context, text, onDone: onDone);
}

/// The confirmation before anything connects: address, fingerprint, a warning for a different network, the limits of a code.
/// A valid code never connects on its own.
class JoinConfirmScreen extends StatelessWidget {
  const JoinConfirmScreen({super.key, required this.code, this.onDone});
  final JoinCode code;

  /// Called after "Verbinden" or "Abbrechen" when there is no page below to return to (the app was opened by a link).
  final VoidCallback? onDone;

  void _finish(BuildContext context) {
    final nav = Navigator.of(context);
    if (nav.canPop()) {
      nav.pop();
    } else {
      onDone?.call();
    }
  }

  Future<void> _connect(BuildContext context) async {
    final app = context.app;
    final creds = code.credentials;
    final address = switch (normalizeServerAddress(code.address, allowInsecure: false)) {
      AddressOk(:final url) => url,
      _ => code.address,
    };
    await app.credentials.setJoined(AppCredentials(creds.clientId, creds.clientSecret), networkRootKey: code.rootKeyText);
    await app.settings.update((s) => s.copyWith(serverAddress: address));
    if (!context.mounted) return;
    final message = context.t('join.done', {'address': address});
    final messenger = ScaffoldMessenger.maybeOf(context);
    _finish(context);
    messenger?.showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final app = context.app;
    final c = context.colors;
    final builtIn = buildConfig.networkRootKey;
    final otherNetwork = code.rootKeyText != null && builtIn != null && builtIn.isNotEmpty && code.rootKeyText != builtIn;
    final fingerprint = code.rootFingerprint;
    return Scaffold(
      body: LockGuard(
        child: ListenableBuilder(
          listenable: app.settings,
          builder: (context, _) {
            final current = app.settings.value.serverAddress;
            return SubPage(
              title: context.t('join.confirm.title'),
              children: [
                CardSection(title: context.t('join.confirm.address'), children: [
                  Semantics(
                    label: '${context.t('join.confirm.address')}: ${code.node}',
                    child: ExcludeSemantics(
                      child: Text(code.node, style: TnText.title.copyWith(color: c.text, fontSize: 24), softWrap: true),
                    ),
                  ),
                  if (current != null && current.isNotEmpty) Hint(context.t('join.confirm.replace', {'address': current})),
                ]),
                CardSection(title: context.t('join.confirm.fingerprint'), children: [
                  if (fingerprint != null) ...[
                    Semantics(
                      label: fingerprint.split('-').join(', '),
                      child: ExcludeSemantics(
                        child: Text(fingerprint, style: TnText.title.copyWith(color: c.text, fontSize: 22, fontFamily: 'monospace', letterSpacing: 1.2)),
                      ),
                    ),
                    Hint(context.t('join.confirm.fingerprintHint')),
                  ] else
                    Hint(context.t('join.confirm.noRoot')),
                  if (otherNetwork) Notice(text: context.t('join.confirm.otherNetwork'), icon: Icons.warning_amber, color: c.warn),
                ]),
                Notice(text: context.t('join.confirm.limits'), icon: Icons.info_outline),
                const SizedBox(height: Space.md),
                PrimaryButton(label: context.t('join.confirm.connect'), onPressed: () => _connect(context)),
                const SizedBox(height: Space.sm),
                SoftButton(label: context.t('join.confirm.cancel'), onPressed: () => _finish(context)),
              ],
            );
          },
        ),
      ),
    );
  }
}
