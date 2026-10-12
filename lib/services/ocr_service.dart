import 'dart:math' as math;

import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

import 'ocr_rows.dart';

/// On-device OCR using Google ML Kit (Android / iOS only).
///
/// Returns the receipt as one string with one line per *visual row*, which
/// is what [BillParser] expects ("name  qty  amount" on the same line).
class OcrService {
  Future<String> readText(String imagePath) async {
    final recognizer = TextRecognizer(script: TextRecognitionScript.latin);
    try {
      final result = await recognizer.processImage(InputImage.fromFilePath(imagePath));

      // Estimate how much the photo is tilted from the baseline of each line.
      final angles = <double>[];
      for (final block in result.blocks) {
        for (final line in block.lines) {
          final pts = line.cornerPoints;
          if (pts.length >= 2) {
            angles.add(math.atan2(
              (pts[1].y - pts[0].y).toDouble(),
              (pts[1].x - pts[0].x).toDouble(),
            ));
          }
        }
      }
      angles.sort();
      final tilt = angles.isEmpty ? 0.0 : angles[angles.length ~/ 2];
      final cosT = math.cos(tilt);
      final sinT = math.sin(tilt);

      // Rotate every word's position by -tilt so rows become horizontal,
      // then group words that share a row.
      final pieces = <OcrPiece>[];
      for (final block in result.blocks) {
        for (final line in block.lines) {
          for (final el in line.elements) {
            final c = el.boundingBox.center;
            final left = el.boundingBox.left;
            pieces.add(OcrPiece(
              el.text,
              left * cosT + c.dy * sinT, // rotated x (left edge)
              -c.dx * sinT + c.dy * cosT, // rotated y (vertical centre)
              el.boundingBox.height,
            ));
          }
        }
      }

      return groupIntoRows(pieces).join('\n');
    } finally {
      await recognizer.close();
    }
  }
}
