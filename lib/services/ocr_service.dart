import 'dart:ui' show Rect;

import 'package:flutter/foundation.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

/// A piece of OCR text and where it was on the image.
class OcrFragment {
  final String text;
  final Rect box;
  const OcrFragment(this.text, this.box);
}

/// Runs Google ML Kit text recognition on an image file (FR-04).
///
/// ML Kit runs fully on the device, so it works offline and the receipt
/// photo never leaves the phone.
class OcrService {
  final TextRecognizer _recognizer = TextRecognizer(script: TextRecognitionScript.latin);

  /// Returns the receipt text with one receipt row per line.
  Future<String> recognize(String imagePath) async {
    final result = await _recognizer.processImage(InputImage.fromFilePath(imagePath));
    final fragments = [
      for (final block in result.blocks)
        for (final line in block.lines) OcrFragment(line.text, line.boundingBox),
    ];
    final text = groupIntoRows(fragments);
    // Printed to the debug console so you can copy real receipts into tests.
    debugPrint('---- OCR rows ----\n$text\n------------------');
    return text;
  }

  /// ML Kit groups text into blocks, and on receipts the item names and the
  /// prices usually end up in DIFFERENT blocks (they are separate columns).
  /// To rebuild each printed row we put fragments whose vertical centres are
  /// close together on the same line, then sort each row left to right.
  @visibleForTesting
  static String groupIntoRows(List<OcrFragment> fragments) {
    final sorted = [...fragments]..sort((a, b) => a.box.center.dy.compareTo(b.box.center.dy));
    final rows = <List<OcrFragment>>[];
    for (final f in sorted) {
      final row = rows.isEmpty ? null : rows.last;
      if (row != null) {
        final ref = row.first.box;
        // Same row if the centres are within half a line height.
        final tolerance = (ref.height < f.box.height ? ref.height : f.box.height) / 2;
        if ((f.box.center.dy - ref.center.dy).abs() <= tolerance) {
          row.add(f);
          continue;
        }
      }
      rows.add([f]);
    }
    return rows.map((r) {
      r.sort((a, b) => a.box.left.compareTo(b.box.left));
      return r.map((f) => f.text).join('  ');
    }).join('\n');
  }

  /// Frees the native ML Kit resources.
  Future<void> dispose() => _recognizer.close();
}
