import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hvac_engine/hvac_engine.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'providers/share_providers.dart';

/// Shows a project as a QR code others can scan. It is a copy, not a live link.
class ProjectQrPage extends ConsumerWidget {
  final ProjectDoc doc;
  final VoidCallback onShareFile;
  const ProjectQrPage({super.key, required this.doc, required this.onShareFile});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final codeAsync = ref.watch(shareCodeProvider(doc));
    return Scaffold(
      appBar: AppBar(title: Text(doc.name)),
      body: codeAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, __) => const Center(child: Text('Could not create the code.')),
        data: (code) {
          final fits = fitsInQr(code);
          return ListView(
            padding: const EdgeInsets.all(20),
            children: [
              if (fits) ...[
                Center(
                  child: Semantics(
                    label: 'QR code for project ${doc.name}',
                    child: Container(
                      color: Colors.white,
                      padding: const EdgeInsets.all(16),
                      child: QrImageView(
                        data: code,
                        size: 280,
                        backgroundColor: Colors.white,
                        errorCorrectionLevel: QrErrorCorrectLevel.L,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                const Text(
                  'On the other device open Projects, then Import, then Scan QR code. '
                  'They get a copy of the project as it is now. Later edits are not synced.',
                ),
              ] else
                Text('This project is too large for a QR code (${code.length} characters). Share it as a file instead.'),
              const SizedBox(height: 16),
              Wrap(spacing: 8, runSpacing: 8, children: [
                FilledButton.icon(onPressed: onShareFile, icon: const Icon(Icons.ios_share), label: const Text('Share as file')),
                OutlinedButton.icon(
                  onPressed: () async {
                    await Clipboard.setData(ClipboardData(text: code));
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Code copied')));
                    }
                  },
                  icon: const Icon(Icons.copy),
                  label: const Text('Copy code'),
                ),
              ]),
            ],
          );
        },
      ),
    );
  }
}

/// Camera view that returns the first Ductletor code it sees.
class QrScanPage extends StatefulWidget {
  const QrScanPage({super.key});
  @override
  State<QrScanPage> createState() => _QrScanPageState();
}

class _QrScanPageState extends State<QrScanPage> {
  bool _done = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Scan project code')),
      body: Stack(children: [
        MobileScanner(
          onDetect: (capture) {
            if (_done) return;
            for (final b in capture.barcodes) {
              final v = b.rawValue;
              if (v != null && v.startsWith('DUCT1:')) {
                _done = true;
                Navigator.pop(context, v);
                return;
              }
            }
          },
          errorBuilder: (context, error, child) => const Center(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: Text('The camera is not available. Allow camera access in Settings, or use Paste code instead.'),
            ),
          ),
        ),
        const Positioned(
          left: 16,
          right: 16,
          bottom: 24,
          child: Card(
            child: Padding(padding: EdgeInsets.all(12), child: Text('Point the camera at a Ductletor project QR code.')),
          ),
        ),
      ]),
    );
  }
}
