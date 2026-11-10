import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

import '../providers/draft_receipt_provider.dart';
import '../providers/router_provider.dart';
import '../providers/service_providers.dart';
import '../services/receipt_parser.dart';

/// S02 – Scan Receipt (FR-02 camera, FR-03 gallery, FR-04 OCR).
class ScanScreen extends ConsumerStatefulWidget {
  const ScanScreen({super.key});
  @override
  ConsumerState<ScanScreen> createState() => _ScanScreenState();
}

class _ScanScreenState extends ConsumerState<ScanScreen> {
  final _picker = ImagePicker();
  String? _imagePath;
  bool _busy = false;
  String? _error;

  Future<void> _pick(ImageSource source) async {
    setState(() => _error = null);
    try {
      // maxWidth keeps memory reasonable while leaving enough detail for OCR.
      final file = await _picker.pickImage(source: source, maxWidth: 2400, imageQuality: 95);
      if (file == null) return; // user cancelled
      setState(() => _busy = true);

      final path = await _keepPhoto(file);
      setState(() => _imagePath = path);

      final text = await ref.read(ocrServiceProvider).recognize(path);
      final parsed = ReceiptParser.parse(text);
      if (!mounted) return;

      ref.read(draftReceiptProvider.notifier).startFromParsed(parsed, imagePath: path);
      if (parsed.items.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('No items found. You can add them by hand on the next screen.'),
        ));
      }
      context.push(Routes.review);
    } on PlatformException catch (e) {
      // e.g. the user refused camera or photo permission.
      setState(() => _error = e.code.contains('access_denied')
          ? 'SnapSplit needs permission to use the camera/photos. '
              'Allow it in Settings → Apps → SnapSplit → Permissions.'
          : 'Could not open the camera or gallery (${e.message ?? e.code}).');
    } catch (e) {
      setState(() => _error = 'Could not read the receipt. Try a clearer photo, '
          'or enter the items manually. ($e)');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// image_picker returns a file in the CACHE folder, which Android may
  /// empty at any time. Copy it into the app's documents folder so the
  /// path saved with the receipt keeps working. (Later this is the one
  /// place to change to upload to Supabase Storage instead.)
  Future<String> _keepPhoto(XFile file) async {
    final dir = Directory(p.join((await getApplicationDocumentsDirectory()).path, 'receipts'));
    await dir.create(recursive: true);
    final dest = p.join(dir.path, '${const Uuid().v4()}${p.extension(file.path)}');
    await File(file.path).copy(dest);
    return dest;
  }

  void _manual() {
    ref.read(draftReceiptProvider.notifier).startEmpty();
    context.push(Routes.review);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Scan receipt')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: Container(
                decoration: BoxDecoration(
                  border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
                  borderRadius: BorderRadius.circular(12),
                ),
                clipBehavior: Clip.antiAlias,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    if (_imagePath != null)
                      Image.file(File(_imagePath!), fit: BoxFit.contain)
                    else
                      const Center(
                        child: Padding(
                          padding: EdgeInsets.all(24),
                          child: Text(
                            'Tips: lay the receipt flat, use good light and fit the '
                            'whole receipt in the frame.',
                            textAlign: TextAlign.center,
                          ),
                        ),
                      ),
                    if (_busy)
                      const ColoredBox(
                        color: Colors.black45,
                        child: Center(
                          child: Column(mainAxisSize: MainAxisSize.min, children: [
                            CircularProgressIndicator(),
                            SizedBox(height: 12),
                            Text('Reading receipt…', style: TextStyle(color: Colors.white)),
                          ]),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
              ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: _busy ? null : () => _pick(ImageSource.camera),
              icon: const Icon(Icons.photo_camera),
              label: const Text('Take photo'),
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: _busy ? null : () => _pick(ImageSource.gallery),
              icon: const Icon(Icons.photo_library),
              label: const Text('Choose from gallery'),
            ),
            TextButton(onPressed: _busy ? null : _manual, child: const Text('Enter items manually')),
          ],
        ),
      ),
    );
  }
}
