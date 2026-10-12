/// A single recognised word plus where it sits on the photo.
class OcrPiece {
  const OcrPiece(this.text, this.x, this.y, this.height);

  final String text;

  /// Left edge of the word.
  final double x;

  /// Vertical centre of the word.
  final double y;

  final double height;
}

/// Rebuilds receipt rows from word positions.
///
/// ML Kit groups text into blocks (usually per column), so a receipt row such
/// as "Honey Milk   1   8.80   SV-" often arrives as three separate lines.
/// Here every word whose vertical centre is close to the row's centre is put
/// on the same row, then each row is read left to right.
List<String> groupIntoRows(List<OcrPiece> pieces) {
  if (pieces.isEmpty) return const [];

  final heights = pieces.map((p) => p.height).toList()..sort();
  final medianHeight = heights[heights.length ~/ 2];
  final tolerance = medianHeight * 0.6;

  final sorted = [...pieces]..sort((a, b) => a.y.compareTo(b.y));
  final rows = <List<OcrPiece>>[];

  for (final p in sorted) {
    List<OcrPiece>? bestRow;
    double bestDiff = double.infinity;

    for (final row in rows) {
      final avgY = row.map((e) => e.y).reduce((a, b) => a + b) / row.length;
      final diff = (p.y - avgY).abs();
      if (diff <= tolerance && diff < bestDiff) {
        bestDiff = diff;
        bestRow = row;
      }
    }

    if (bestRow != null) {
      bestRow.add(p);
    } else {
      rows.add([p]);
    }
  }

  // Ensure top-to-bottom reading order of rows
  rows.sort((a, b) {
    final ay = a.map((e) => e.y).reduce((x, y) => x + y) / a.length;
    final by = b.map((e) => e.y).reduce((x, y) => x + y) / b.length;
    return ay.compareTo(by);
  });

  return [
    for (final row in rows)
      (row..sort((a, b) => a.x.compareTo(b.x))).map((e) => e.text).join(' '),
  ];
}
