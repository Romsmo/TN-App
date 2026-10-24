import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../app_scope.dart';
import '../ui/theme.dart';
import 'common.dart';

/// Scans one QR code and returns its text; the camera image never leaves the device and nothing is stored. The text is
/// checked by the caller; it is not shown or logged here.
class JoinScanScreen extends StatefulWidget {
  const JoinScanScreen({super.key});

  @override
  State<JoinScanScreen> createState() => _JoinScanScreenState();
}

class _JoinScanScreenState extends State<JoinScanScreen> {
  final MobileScannerController _controller = MobileScannerController(
    formats: const [BarcodeFormat.qrCode],
    detectionSpeed: DetectionSpeed.noDuplicates,
  );
  bool _done = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onDetect(BarcodeCapture capture) {
    if (_done) return;
    for (final b in capture.barcodes) {
      final text = b.rawValue;
      if (text != null && text.isNotEmpty) {
        _done = true;
        Navigator.of(context).pop(text);
        return;
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Scaffold(
      appBar: AppBar(title: Text(context.t('join.scan.title'))),
      body: LockGuard(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(Space.lg),
              child: Text(context.t('join.scan.hint'), style: TnText.body.copyWith(color: c.textSecondary)),
            ),
            Expanded(
              child: MobileScanner(
                controller: _controller,
                onDetect: _onDetect,
                errorBuilder: (context, error) {
                  final denied = error.errorCode == MobileScannerErrorCode.permissionDenied;
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(Space.lg),
                      child: Semantics(
                        liveRegion: true,
                        child: Text(
                          context.t(denied ? 'join.scan.denied' : 'join.scan.failed'),
                          style: TnText.body.copyWith(color: c.danger),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
