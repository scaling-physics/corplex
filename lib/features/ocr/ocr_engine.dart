import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// A recognised word with its box as fractions (0..1) of the image/page,
/// origin top-left.
class OcrWord {
  const OcrWord(this.text, this.left, this.top, this.right, this.bottom);

  final String text;
  final double left, top, right, bottom;

  List<Object> toJson() => [text, left, top, right, bottom];

  factory OcrWord.fromJson(List<dynamic> j) => OcrWord(
    j[0] as String,
    (j[1] as num).toDouble(),
    (j[2] as num).toDouble(),
    (j[3] as num).toDouble(),
    (j[4] as num).toDouble(),
  );
}

class OcrLine {
  const OcrLine(this.text, this.words);

  final String text;
  final List<OcrWord> words;

  Map<String, Object> toJson() => {
    't': text,
    'w': [for (final w in words) w.toJson()],
  };

  factory OcrLine.fromJson(Map<String, dynamic> j) =>
      OcrLine(j['t'] as String, [
        for (final w in j['w'] as List<dynamic>)
          OcrWord.fromJson(w as List<dynamic>),
      ]);
}

/// What was recognised on one page.
class OcrPageText {
  const OcrPageText(this.lines);

  static const empty = OcrPageText([]);

  final List<OcrLine> lines;

  String get text => lines.map((l) => l.text).join('\n');
  Iterable<OcrWord> get words => lines.expand((l) => l.words);

  String toJsonString() => jsonEncode([for (final l in lines) l.toJson()]);

  factory OcrPageText.fromJsonString(String source) {
    try {
      return OcrPageText([
        for (final l in jsonDecode(source) as List<dynamic>)
          OcrLine.fromJson(l as Map<String, dynamic>),
      ]);
    } catch (_) {
      return empty;
    }
  }

  /// Words whose box overlaps [region] (fractions of the page), in reading
  /// order — for selecting and highlighting recognised text.
  List<OcrWord> wordsIn({
    required double left,
    required double top,
    required double right,
    required double bottom,
  }) => [
    for (final w in words)
      if (w.left < right && w.right > left && w.top < bottom && w.bottom > top)
        w,
  ];

  /// Boxes of every word containing [query] (case-insensitive), for search
  /// hits.
  List<OcrWord> find(String query) {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return const [];
    return [
      for (final w in words)
        if (w.text.toLowerCase().contains(q)) w,
    ];
  }
}

/// On-device text recognition. Fully offline: Apple Vision on iOS, ML Kit's
/// bundled Latin model on Android.
abstract class OcrEngine {
  Future<OcrPageText> recognize(Uint8List png);
}

/// Method-channel implementation (`corplex/ocr`).
class PlatformOcrEngine implements OcrEngine {
  const PlatformOcrEngine();

  static const _channel = MethodChannel('corplex/ocr');

  @override
  Future<OcrPageText> recognize(Uint8List png) async {
    final result = await _channel.invokeMethod<List<dynamic>>('recognize', {
      'image': png,
    });
    final lines = <OcrLine>[];
    for (final raw in result ?? const <dynamic>[]) {
      final line = Map<String, dynamic>.from(raw as Map);
      final words = <OcrWord>[
        for (final w in (line['words'] as List<dynamic>? ?? const []))
          _word(Map<String, dynamic>.from(w as Map)),
      ];
      final text = (line['text'] as String? ?? '').trim();
      if (text.isNotEmpty) lines.add(OcrLine(text, words));
    }
    return OcrPageText(lines);
  }

  OcrWord _word(Map<String, dynamic> w) => OcrWord(
    w['text'] as String,
    (w['left'] as num).toDouble().clamp(0.0, 1.0),
    (w['top'] as num).toDouble().clamp(0.0, 1.0),
    (w['right'] as num).toDouble().clamp(0.0, 1.0),
    (w['bottom'] as num).toDouble().clamp(0.0, 1.0),
  );
}

/// Tests override this with a fake.
final ocrEngineProvider = Provider<OcrEngine>(
  (ref) => const PlatformOcrEngine(),
);
