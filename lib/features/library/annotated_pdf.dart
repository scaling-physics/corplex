import 'dart:convert';
import 'dart:io' show ZLibCodec;
import 'dart:math' as math;
import 'dart:typed_data';

/// Writes Corplex's highlights and ink into a copy of a PDF as real
/// `/Highlight` and `/Ink` annotations, by appending a PDF *incremental
/// update* (new objects, a new xref section, a new trailer). The original
/// bytes are never touched, so the file stays valid for every reader and
/// the app stays dependency-free and testable without pdfium.
///
/// Handles classic xref tables, xref streams, hybrid files and objects
/// stored in object streams. Encrypted or structurally damaged PDFs raise
/// an [AnnotatedPdfException] with a message fit to show the reader.

class AnnotatedPdfException implements Exception {
  AnnotatedPdfException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// A text highlight: one `[left, top, right, bottom]` box per line, as
/// fractions of the page as displayed (rotation and crop applied).
class HighlightMark {
  const HighlightMark({
    required this.page,
    required this.rects,
    required this.rgb,
    this.comment,
  });

  /// 1-based.
  final int page;
  final List<List<double>> rects;
  final int rgb;
  final String? comment;
}

/// A freeform stroke: points as 0..1 fractions of the displayed page.
class InkMark {
  const InkMark({required this.page, required this.points, required this.rgb});
  final int page;
  final List<List<double>> points;
  final int rgb;
}

class AnnotatedPdfResult {
  AnnotatedPdfResult(this.bytes, this.written, this.skipped);
  final Uint8List bytes;
  final int written;

  /// Marks whose page doesn't exist in the file.
  final int skipped;
}

// ---------------------------------------------------------------------------
// Geometry

/// Converts positions on the *displayed* page (fractions from the top-left,
/// after /Rotate and cropping) into PDF user space.
class PageGeometry {
  PageGeometry({
    required this.x0,
    required this.y0,
    required this.x1,
    required this.y1,
    this.rotate = 0,
  });

  /// The visible box (CropBox clipped to MediaBox), normalised.
  final double x0, y0, x1, y1;

  /// Clockwise degrees, 0/90/180/270.
  final int rotate;

  double get width => x1 - x0;
  double get height => y1 - y0;
  bool get _turned => rotate == 90 || rotate == 270;
  double get displayWidth => _turned ? height : width;
  double get displayHeight => _turned ? width : height;

  List<double> toUser(double fx, double fy) {
    final u = fx * displayWidth, v = fy * displayHeight;
    switch (rotate) {
      case 90:
        return [x0 + v, y0 + u];
      case 180:
        return [x0 + width - u, y0 + v];
      case 270:
        return [x0 + width - v, y0 + height - u];
      default:
        return [x0 + u, y1 - v];
    }
  }
}

// ---------------------------------------------------------------------------
// PDF object model

class PdfName {
  const PdfName(this.value);
  final String value;
  @override
  bool operator ==(Object other) => other is PdfName && other.value == value;
  @override
  int get hashCode => value.hashCode;
}

class PdfStr {
  PdfStr(this.bytes);

  /// A PDF "text string": plain ASCII, else UTF-16BE with a byte-order mark.
  factory PdfStr.text(String s) {
    if (s.codeUnits.every((c) => c < 128)) return PdfStr(ascii.encode(s));
    final out = <int>[0xFE, 0xFF];
    for (final c in s.codeUnits) {
      out
        ..add(c >> 8)
        ..add(c & 0xFF);
    }
    return PdfStr(Uint8List.fromList(out));
  }
  final Uint8List bytes;
}

class PdfRef {
  const PdfRef(this.num, [this.gen = 0]);
  final int num, gen;
}

typedef PdfDict = Map<String, Object?>;

class _Lex {
  _Lex(this.b, [this.p = 0]);
  final Uint8List b;
  int p;

  static bool isWs(int c) =>
      c == 0 || c == 9 || c == 10 || c == 12 || c == 13 || c == 32;
  static bool isDelim(int c) =>
      c == 40 ||
      c == 41 ||
      c == 60 ||
      c == 62 ||
      c == 91 ||
      c == 93 ||
      c == 123 ||
      c == 125 ||
      c == 47 ||
      c == 37;
  static bool isRegular(int c) => !isWs(c) && !isDelim(c);

  Never fail([String what = 'unexpected data']) => throw AnnotatedPdfException(
    "This PDF's structure is damaged ($what), so it can't be annotated.",
  );

  void skip() {
    while (p < b.length) {
      final c = b[p];
      if (isWs(c)) {
        p++;
      } else if (c == 37) {
        while (p < b.length && b[p] != 10 && b[p] != 13) {
          p++;
        }
      } else {
        break;
      }
    }
  }

  String word() {
    skip();
    final s = p;
    while (p < b.length && isRegular(b[p])) {
      p++;
    }
    return ascii.decode(b.sublist(s, p), allowInvalid: true);
  }

  bool startsWith(String s) {
    if (p + s.length > b.length) return false;
    for (var i = 0; i < s.length; i++) {
      if (b[p + i] != s.codeUnitAt(i)) return false;
    }
    return true;
  }

  int readInt() {
    final w = word();
    return int.tryParse(w) ?? fail('expected a number');
  }

  Object? parse([int depth = 0]) {
    if (depth > 100) fail('nesting too deep');
    skip();
    if (p >= b.length) fail('unexpected end');
    final c = b[p];
    if (c == 47) return _name();
    if (c == 60) {
      if (p + 1 < b.length && b[p + 1] == 60) {
        p += 2;
        final d = <String, Object?>{};
        while (true) {
          skip();
          if (p >= b.length) fail('unterminated dictionary');
          if (startsWith('>>')) {
            p += 2;
            return d;
          }
          if (b[p] != 47) fail('bad dictionary key');
          final k = _name().value;
          d[k] = parse(depth + 1);
        }
      }
      return _hex();
    }
    if (c == 40) return _literal();
    if (c == 91) {
      p++;
      final l = <Object?>[];
      while (true) {
        skip();
        if (p >= b.length) fail('unterminated array');
        if (b[p] == 93) {
          p++;
          return l;
        }
        l.add(parse(depth + 1));
      }
    }
    final w = word();
    if (w.isEmpty) {
      p++; // never loop forever on a stray delimiter
      fail('stray character');
    }
    final i = int.tryParse(w);
    if (i != null) {
      final save = p;
      skip();
      final g = word();
      if (int.tryParse(g) != null) {
        skip();
        if (p < b.length &&
            b[p] == 82 &&
            (p + 1 >= b.length || !isRegular(b[p + 1]))) {
          p++;
          return PdfRef(i, int.parse(g));
        }
      }
      p = save;
      return i;
    }
    final d = double.tryParse(w);
    if (d != null) return d;
    switch (w) {
      case 'true':
        return true;
      case 'false':
        return false;
      case 'null':
        return null;
    }
    fail('unknown token "$w"');
  }

  PdfName _name() {
    p++;
    final out = <int>[];
    while (p < b.length && isRegular(b[p])) {
      if (b[p] == 35 && p + 2 < b.length) {
        final h = int.tryParse(
          ascii.decode(b.sublist(p + 1, p + 3)),
          radix: 16,
        );
        if (h != null) {
          out.add(h);
          p += 3;
          continue;
        }
      }
      out.add(b[p++]);
    }
    return PdfName(utf8.decode(out, allowMalformed: true));
  }

  PdfStr _hex() {
    p++;
    final out = <int>[];
    int? hi;
    while (p < b.length && b[p] != 62) {
      final v = int.tryParse(String.fromCharCode(b[p]), radix: 16);
      p++;
      if (v == null) continue;
      if (hi == null) {
        hi = v;
      } else {
        out.add(hi * 16 + v);
        hi = null;
      }
    }
    if (hi != null) out.add(hi * 16);
    p++;
    return PdfStr(Uint8List.fromList(out));
  }

  PdfStr _literal() {
    p++;
    var depth = 1;
    final out = <int>[];
    while (p < b.length) {
      final c = b[p++];
      if (c == 92 && p < b.length) {
        final e = b[p++];
        switch (e) {
          case 110:
            out.add(10);
          case 114:
            out.add(13);
          case 116:
            out.add(9);
          case 98:
            out.add(8);
          case 102:
            out.add(12);
          case 13:
            if (p < b.length && b[p] == 10) p++;
          case 10:
            break;
          default:
            if (e >= 48 && e <= 55) {
              var v = e - 48;
              for (var i = 0; i < 2 && p < b.length; i++) {
                if (b[p] >= 48 && b[p] <= 55) {
                  v = v * 8 + b[p++] - 48;
                } else {
                  break;
                }
              }
              out.add(v & 0xFF);
            } else {
              out.add(e);
            }
        }
      } else if (c == 40) {
        depth++;
        out.add(c);
      } else if (c == 41) {
        if (--depth == 0) return PdfStr(Uint8List.fromList(out));
        out.add(c);
      } else {
        out.add(c);
      }
    }
    fail('unterminated string');
  }
}

class _Obj {
  _Obj(this.value, this.stream);
  final Object? value;
  final Uint8List? stream;
}

class _XEntry {
  const _XEntry(this.type, this.a, this.b);
  final int type; // 0 free, 1 offset, 2 in object stream
  final int a, b;
}

class _Found {
  _Found(this.ref, this.dict, this.inherited);
  final PdfRef ref;
  final PdfDict dict;
  final PdfDict inherited;
}

// ---------------------------------------------------------------------------
// Reading

class _PdfDoc {
  _PdfDoc._(this.b);
  final Uint8List b;
  final entries = <int, _XEntry>{};
  final _cache = <int, Object?>{};
  final _objStms =
      <int, ({List<int> nums, List<int> offs, int first, Uint8List data})>{};
  PdfDict trailer = {};
  bool newestIsStream = false;
  int newestXref = 0;

  static _PdfDoc open(Uint8List input) {
    var start = -1;
    final head = input.length < 1024 ? input.length : 1024;
    for (var i = 0; i + 5 <= head; i++) {
      if (input[i] == 0x25 &&
          input[i + 1] == 0x50 &&
          input[i + 2] == 0x44 &&
          input[i + 3] == 0x46 &&
          input[i + 4] == 0x2D) {
        start = i;
        break;
      }
    }
    if (start < 0) {
      throw AnnotatedPdfException("This file isn't a PDF Corplex can read.");
    }
    final doc = _PdfDoc._(start == 0 ? input : input.sublist(start));
    doc._loadXrefs();
    if (doc.trailer.containsKey('Encrypt')) {
      throw AnnotatedPdfException(
        'This PDF is encrypted, so highlights can\'t be written into it.',
      );
    }
    return doc;
  }

  int _findStartXref() {
    const key = 'startxref';
    for (var i = b.length - key.length; i >= 0 && i > b.length - 8192; i--) {
      var ok = true;
      for (var j = 0; j < key.length; j++) {
        if (b[i + j] != key.codeUnitAt(j)) {
          ok = false;
          break;
        }
      }
      if (ok) {
        final lex = _Lex(b, i + key.length);
        return lex.readInt();
      }
    }
    throw AnnotatedPdfException(
      "This PDF's cross-reference table is missing, so it can't be annotated.",
    );
  }

  void _loadXrefs() {
    var off = _findStartXref();
    newestXref = off;
    final seen = <int>{};
    var first = true;
    while (seen.add(off)) {
      if (off < 0 || off >= b.length) {
        throw AnnotatedPdfException(
          "This PDF's cross-reference table is damaged, so it can't be annotated.",
        );
      }
      final lex = _Lex(b, off)..skip();
      PdfDict dict;
      if (lex.startsWith('xref')) {
        lex.p += 4;
        while (true) {
          lex.skip();
          if (lex.startsWith('trailer')) {
            lex.p += 7;
            break;
          }
          final s = lex.readInt(), n = lex.readInt();
          for (var i = 0; i < n; i++) {
            final o = lex.readInt(), g = lex.readInt();
            final f = lex.word();
            entries.putIfAbsent(
              s + i,
              () => f == 'n' ? _XEntry(1, o, g) : const _XEntry(0, 0, 0),
            );
          }
        }
        dict = _asDict(lex.parse());
        final xs = dict['XRefStm'];
        if (xs is int && seen.add(xs)) {
          _readXrefStream(_readAt(xs), merge: false);
        }
      } else {
        final obj = _readAt(off);
        dict = _readXrefStream(obj);
        if (first) newestIsStream = true;
      }
      if (first) {
        trailer = dict;
        first = false;
      }
      final prev = dict['Prev'];
      if (prev is int) {
        off = prev;
      } else if (prev is double) {
        off = prev.toInt();
      } else {
        break;
      }
    }
    if (trailer['Root'] is! PdfRef) {
      throw AnnotatedPdfException(
        "This PDF has no document catalog, so it can't be annotated.",
      );
    }
  }

  PdfDict _readXrefStream(_Obj obj, {bool merge = true}) {
    final dict = _asDict(obj.value);
    final raw = obj.stream;
    if (raw == null) {
      throw AnnotatedPdfException(
        "This PDF's cross-reference stream is damaged, so it can't be annotated.",
      );
    }
    final data = _decode(dict, raw);
    final w = (dict['W'] as List).map((e) => e as int).toList();
    final size = dict['Size'] as int;
    final index = dict['Index'] is List
        ? (dict['Index'] as List).map((e) => e as int).toList()
        : [0, size];
    final rowLen = w[0] + w[1] + w[2];
    var pos = 0;
    int field(int len) {
      var v = 0;
      for (var i = 0; i < len; i++) {
        v = (v << 8) | data[pos++];
      }
      return v;
    }

    for (var k = 0; k + 1 < index.length; k += 2) {
      for (var i = 0; i < index[k + 1]; i++) {
        if (pos + rowLen > data.length) break;
        final t = w[0] == 0 ? 1 : field(w[0]);
        final a = field(w[1]), c = field(w[2]);
        entries.putIfAbsent(index[k] + i, () => _XEntry(t, a, c));
      }
    }
    return dict;
  }

  PdfDict _asDict(Object? v) {
    if (v is PdfDict) return v;
    throw AnnotatedPdfException(
      "This PDF's structure is damaged, so it can't be annotated.",
    );
  }

  _Obj _readAt(int off, [int? expect]) {
    if (off < 0 || off >= b.length) {
      throw AnnotatedPdfException(
        "This PDF's cross-reference table is damaged, so it can't be annotated.",
      );
    }
    final lex = _Lex(b, off);
    final n = lex.readInt();
    lex.readInt();
    if (lex.word() != 'obj' || (expect != null && n != expect)) {
      throw AnnotatedPdfException(
        "This PDF's cross-reference table is damaged, so it can't be annotated.",
      );
    }
    final v = lex.parse();
    lex.skip();
    if (v is PdfDict && lex.startsWith('stream')) {
      lex.p += 6;
      if (lex.p < b.length && b[lex.p] == 13) lex.p++;
      if (lex.p < b.length && b[lex.p] == 10) lex.p++;
      final s = lex.p;
      var len = -1;
      final l = v['Length'];
      if (l is int) {
        len = l;
      } else if (l is PdfRef) {
        final r = resolve(l);
        if (r is int) len = r;
      }
      var end = -1;
      if (len >= 0 && s + len <= b.length) {
        final t = _Lex(b, s + len)..skip();
        if (t.startsWith('endstream')) end = s + len;
      }
      if (end < 0) {
        const key = 'endstream';
        for (var i = s; i + key.length <= b.length; i++) {
          if (b[i] == 0x65 && _Lex(b, i).startsWith(key)) {
            end = i;
            break;
          }
        }
        if (end < 0) lex.fail('stream has no end');
        while (end > s && (b[end - 1] == 10 || b[end - 1] == 13)) {
          end--;
        }
      }
      return _Obj(v, b.sublist(s, end));
    }
    return _Obj(v, null);
  }

  Uint8List _decode(PdfDict dict, Uint8List raw) {
    var filter = resolve(dict['Filter']);
    var parms = resolve(dict['DecodeParms']);
    if (filter is List) {
      if (filter.length > 1) throw _unsupported();
      filter = filter.isEmpty ? null : resolve(filter.first);
      if (parms is List) parms = parms.isEmpty ? null : resolve(parms.first);
    }
    if (filter == null) return raw;
    if (filter is! PdfName ||
        (filter.value != 'FlateDecode' && filter.value != 'Fl')) {
      throw _unsupported();
    }
    var data = Uint8List.fromList(ZLibCodec().decode(raw));
    if (parms is PdfDict) {
      final pred = resolve(parms['Predictor']);
      if (pred is int && pred > 1) {
        if (pred < 10) throw _unsupported();
        final cols = (resolve(parms['Columns']) as int?) ?? 1;
        final colors = (resolve(parms['Colors']) as int?) ?? 1;
        final bpc = (resolve(parms['BitsPerComponent']) as int?) ?? 8;
        data = _pngUnpredict(
          data,
          cols,
          ((colors * bpc) + 7) ~/ 8,
          colors * bpc * cols,
        );
      }
    }
    return data;
  }

  AnnotatedPdfException _unsupported() => AnnotatedPdfException(
    "This PDF uses a compression Corplex can't write into, so it can't be annotated.",
  );

  static Uint8List _pngUnpredict(
    Uint8List d,
    int cols,
    int bpp,
    int bitsPerRow,
  ) {
    final rowLen = (bitsPerRow + 7) ~/ 8;
    final rows = d.length ~/ (rowLen + 1);
    final out = Uint8List(rows * rowLen);
    for (var r = 0; r < rows; r++) {
      final f = d[r * (rowLen + 1)];
      final src = r * (rowLen + 1) + 1, dst = r * rowLen;
      for (var i = 0; i < rowLen; i++) {
        final x = d[src + i];
        final a = i >= bpp ? out[dst + i - bpp] : 0;
        final up = r > 0 ? out[dst - rowLen + i] : 0;
        final c = (r > 0 && i >= bpp) ? out[dst - rowLen + i - bpp] : 0;
        int v;
        switch (f) {
          case 1:
            v = x + a;
          case 2:
            v = x + up;
          case 3:
            v = x + ((a + up) >> 1);
          case 4:
            final p = a + up - c;
            final pa = (p - a).abs(), pb = (p - up).abs(), pc = (p - c).abs();
            v = x + ((pa <= pb && pa <= pc) ? a : (pb <= pc ? up : c));
          default:
            v = x;
        }
        out[dst + i] = v & 0xFF;
      }
    }
    return out;
  }

  Object? resolve(Object? v) {
    var n = 0;
    while (v is PdfRef) {
      if (++n > 32) return null;
      v = getObject(v.num);
    }
    return v;
  }

  Object? getObject(int num) {
    if (_cache.containsKey(num)) return _cache[num];
    final e = entries[num];
    Object? v;
    if (e == null || e.type == 0) {
      v = null;
    } else if (e.type == 1) {
      v = _readAt(e.a, num).value;
    } else {
      final os = _objStm(e.a);
      final i = os.nums.indexOf(num);
      if (i < 0) {
        v = null;
      } else {
        v = _Lex(os.data, os.first + os.offs[i]).parse();
      }
    }
    return _cache[num] = v;
  }

  ({List<int> nums, List<int> offs, int first, Uint8List data}) _objStm(int n) {
    return _objStms[n] ??= () {
      final e = entries[n];
      if (e == null || e.type != 1) {
        throw AnnotatedPdfException(
          "This PDF's object streams are damaged, so it can't be annotated.",
        );
      }
      final obj = _readAt(e.a, n);
      final dict = _asDict(obj.value);
      final data = _decode(dict, obj.stream!);
      final count = resolve(dict['N']) as int;
      final first = resolve(dict['First']) as int;
      final lex = _Lex(data);
      final nums = <int>[], offs = <int>[];
      for (var i = 0; i < count; i++) {
        nums.add(lex.readInt());
        offs.add(lex.readInt());
      }
      return (nums: nums, offs: offs, first: first, data: data);
    }();
  }

  int get nextObjectNumber {
    var m = (trailer['Size'] is int) ? trailer['Size'] as int : 0;
    for (final k in entries.keys) {
      if (k + 1 > m) m = k + 1;
    }
    return m;
  }

  _Found? findPage(int pageNumber) {
    final root = resolve(trailer['Root']);
    if (root is! PdfDict) return null;
    var remaining = pageNumber - 1;
    if (remaining < 0) return null;

    _Found? walk(Object? nodeV, PdfDict inh, int depth) {
      if (depth > 64) return null;
      final node = resolve(nodeV);
      if (node is! PdfDict) return null;
      final inh2 = {...inh};
      for (final k in const ['MediaBox', 'CropBox', 'Rotate']) {
        if (node.containsKey(k)) inh2[k] = node[k];
      }
      final kids = resolve(node['Kids']);
      final type = node['Type'];
      if (kids is List && !(type is PdfName && type.value == 'Page')) {
        for (final kid in kids) {
          final kn = resolve(kid);
          if (kn is PdfDict && kn['Kids'] != null) {
            final c = resolve(kn['Count']);
            if (c is int && c <= remaining) {
              remaining -= c;
              continue;
            }
          }
          final r = walk(kid, inh2, depth + 1);
          if (r != null) return r;
        }
        return null;
      }
      if (remaining == 0 && nodeV is PdfRef) {
        return _Found(nodeV, node, inh2);
      }
      remaining--;
      return null;
    }

    return walk(root['Pages'], {}, 0);
  }

  List<double>? box(Object? v) {
    final a = resolve(v);
    if (a is! List || a.length < 4) return null;
    final n = <double>[];
    for (final e in a.take(4)) {
      final r = resolve(e);
      if (r is! num) return null;
      n.add(r.toDouble());
    }
    return [
      math.min(n[0], n[2]),
      math.min(n[1], n[3]),
      math.max(n[0], n[2]),
      math.max(n[1], n[3]),
    ];
  }

  PageGeometry geometry(_Found page) {
    final media = box(page.inherited['MediaBox']) ?? [0, 0, 612, 792];
    var crop = box(page.inherited['CropBox']) ?? media;
    final ix0 = math.max(crop[0], media[0]), iy0 = math.max(crop[1], media[1]);
    final ix1 = math.min(crop[2], media[2]), iy1 = math.min(crop[3], media[3]);
    crop = (ix1 > ix0 && iy1 > iy0) ? [ix0, iy0, ix1, iy1] : media;
    var rot = resolve(page.inherited['Rotate']);
    var r = rot is num ? rot.toInt() : 0;
    r = ((r % 360) + 360) % 360;
    if (r % 90 != 0) r = 0;
    return PageGeometry(
      x0: crop[0],
      y0: crop[1],
      x1: crop[2],
      y1: crop[3],
      rotate: r,
    );
  }
}

// ---------------------------------------------------------------------------
// Writing

void _put(BytesBuilder o, Object? v) {
  if (v == null) {
    o.add(ascii.encode('null'));
  } else if (v is bool) {
    o.add(ascii.encode(v ? 'true' : 'false'));
  } else if (v is int) {
    o.add(ascii.encode('$v'));
  } else if (v is double) {
    o.add(ascii.encode(_num(v)));
  } else if (v is PdfName) {
    o.add(ascii.encode(_nameText(v.value)));
  } else if (v is PdfStr) {
    o.add(ascii.encode('<'));
    for (final c in v.bytes) {
      o.add(ascii.encode(c.toRadixString(16).padLeft(2, '0')));
    }
    o.add(ascii.encode('>'));
  } else if (v is PdfRef) {
    o.add(ascii.encode('${v.num} ${v.gen} R'));
  } else if (v is List) {
    o.add(ascii.encode('['));
    for (var i = 0; i < v.length; i++) {
      if (i > 0) o.add(ascii.encode(' '));
      _put(o, v[i]);
    }
    o.add(ascii.encode(']'));
  } else if (v is Map) {
    o.add(ascii.encode('<<'));
    v.forEach((k, val) {
      o.add(ascii.encode(_nameText(k as String)));
      o.add(ascii.encode(' '));
      _put(o, val);
      o.add(ascii.encode(' '));
    });
    o.add(ascii.encode('>>'));
  } else {
    throw ArgumentError('cannot write $v');
  }
}

String _nameText(String s) {
  final sb = StringBuffer('/');
  for (final c in utf8.encode(s)) {
    if (c <= 32 || c >= 127 || c == 35 || _Lex.isDelim(c)) {
      sb.write('#${c.toRadixString(16).padLeft(2, '0')}');
    } else {
      sb.writeCharCode(c);
    }
  }
  return sb.toString();
}

String _num(num v) {
  if (v is int) return '$v';
  if (v == v.roundToDouble()) return v.toInt().toString();
  var s = v.toStringAsFixed(4);
  s = s.replaceFirst(RegExp(r'0+$'), '');
  return s.endsWith('.') ? s.substring(0, s.length - 1) : s;
}

String _rgb(int rgb) {
  final r = ((rgb >> 16) & 0xFF) / 255,
      g = ((rgb >> 8) & 0xFF) / 255,
      bl = (rgb & 0xFF) / 255;
  return '${_num(r)} ${_num(g)} ${_num(bl)}';
}

List<double> _rgbList(int rgb) => [
  ((rgb >> 16) & 0xFF) / 255,
  ((rgb >> 8) & 0xFF) / 255,
  (rgb & 0xFF) / 255,
];

String _pdfDate(DateTime t) {
  final u = t.toUtc();
  String two(int n) => n.toString().padLeft(2, '0');
  return 'D:${u.year.toString().padLeft(4, '0')}${two(u.month)}${two(u.day)}'
      '${two(u.hour)}${two(u.minute)}${two(u.second)}Z';
}

const double highlightOpacity = 0.45;
const double inkOpacity = 0.4;

/// Ink width as a fraction of the displayed page width (matches the viewer).
const double inkWidthFraction = 0.025;

class _Pending {
  _Pending(this.num, this.dict, [this.stream]);
  final int num;
  final PdfDict dict;
  final Uint8List? stream;
}

Uint8List writeAnnotatedPdfBytes(
  Uint8List pdf, {
  List<HighlightMark> highlights = const [],
  List<InkMark> ink = const [],
  DateTime? now,
}) => writeAnnotatedPdf(pdf, highlights: highlights, ink: ink, now: now).bytes;

AnnotatedPdfResult writeAnnotatedPdf(
  Uint8List pdf, {
  List<HighlightMark> highlights = const [],
  List<InkMark> ink = const [],
  DateTime? now,
}) {
  final doc = _PdfDoc.open(pdf);
  final date = _pdfDate(now ?? DateTime.now());
  final byPage = <int, ({List<HighlightMark> h, List<InkMark> i})>{};
  for (final h in highlights) {
    (byPage[h.page] ??= (h: [], i: [])).h.add(h);
  }
  for (final i in ink) {
    (byPage[i.page] ??= (h: [], i: [])).i.add(i);
  }

  var next = doc.nextObjectNumber;
  final objects = <_Pending>[];
  var written = 0, skipped = 0;

  for (final page in byPage.keys.toList()..sort()) {
    final marks = byPage[page]!;
    final found = doc.findPage(page);
    if (found == null) {
      skipped += marks.h.length + marks.i.length;
      continue;
    }
    final geo = doc.geometry(found);
    final refs = <Object?>[];
    final existing = doc.resolve(found.dict['Annots']);
    if (existing is List) refs.addAll(existing);

    PdfRef alloc(PdfDict d, [Uint8List? s]) {
      final n = next++;
      objects.add(_Pending(n, d, s));
      return PdfRef(n);
    }

    for (final h in marks.h) {
      final quads = <List<double>>[];
      for (final r in h.rects) {
        if (r.length < 4) continue;
        final tl = geo.toUser(r[0], r[1]);
        final tr = geo.toUser(r[2], r[1]);
        final bl = geo.toUser(r[0], r[3]);
        final br = geo.toUser(r[2], r[3]);
        quads.add([...tl, ...tr, ...bl, ...br]);
      }
      if (quads.isEmpty) continue;
      final xs = quads.expand((q) => [q[0], q[2], q[4], q[6]]);
      final ys = quads.expand((q) => [q[1], q[3], q[5], q[7]]);
      final rect = [
        xs.reduce(math.min),
        ys.reduce(math.min),
        xs.reduce(math.max),
        ys.reduce(math.max),
      ];
      final content = StringBuffer('/GS gs ${_rgb(h.rgb)} rg\n');
      for (final q in quads) {
        content.write(
          '${_num(q[0])} ${_num(q[1])} m ${_num(q[2])} ${_num(q[3])} l '
          '${_num(q[6])} ${_num(q[7])} l ${_num(q[4])} ${_num(q[5])} l h f\n',
        );
      }
      final ap = alloc({
        'Type': const PdfName('XObject'),
        'Subtype': const PdfName('Form'),
        'BBox': rect,
        'Resources': {
          'ExtGState': {
            'GS': {
              'Type': const PdfName('ExtGState'),
              'BM': const PdfName('Multiply'),
              'ca': highlightOpacity,
              'CA': highlightOpacity,
            },
          },
        },
      }, ascii.encode(content.toString()));
      final comment = h.comment?.trim();
      refs.add(
        alloc({
          'Type': const PdfName('Annot'),
          'Subtype': const PdfName('Highlight'),
          'Rect': rect,
          'QuadPoints': [for (final q in quads) ...q],
          'C': _rgbList(h.rgb),
          'CA': highlightOpacity,
          'F': 4,
          'T': PdfStr.text('Corplex'),
          'M': PdfStr.text(date),
          'P': found.ref,
          if (comment != null && comment.isNotEmpty)
            'Contents': PdfStr.text(comment),
          'AP': {'N': ap},
        }),
      );
      written++;
    }

    final width = inkWidthFraction * geo.displayWidth;
    for (final s in marks.i) {
      final pts = <double>[];
      for (final p in s.points) {
        if (p.length < 2) continue;
        pts.addAll(geo.toUser(p[0], p[1]));
      }
      if (pts.length < 4) continue;
      final xs = [for (var i = 0; i < pts.length; i += 2) pts[i]];
      final ys = [for (var i = 1; i < pts.length; i += 2) pts[i]];
      final pad = width / 2;
      final rect = [
        xs.reduce(math.min) - pad,
        ys.reduce(math.min) - pad,
        xs.reduce(math.max) + pad,
        ys.reduce(math.max) + pad,
      ];
      final content = StringBuffer(
        '/GS gs ${_rgb(s.rgb)} RG ${_num(width)} w 1 J 1 j\n',
      );
      for (var i = 0; i < pts.length; i += 2) {
        content.write(
          '${_num(pts[i])} ${_num(pts[i + 1])} ${i == 0 ? 'm' : 'l'} ',
        );
      }
      content.write('S\n');
      final ap = alloc({
        'Type': const PdfName('XObject'),
        'Subtype': const PdfName('Form'),
        'BBox': rect,
        'Resources': {
          'ExtGState': {
            'GS': {
              'Type': const PdfName('ExtGState'),
              'ca': inkOpacity,
              'CA': inkOpacity,
            },
          },
        },
      }, ascii.encode(content.toString()));
      refs.add(
        alloc({
          'Type': const PdfName('Annot'),
          'Subtype': const PdfName('Ink'),
          'Rect': rect,
          'InkList': [pts],
          'BS': {
            'Type': const PdfName('Border'),
            'W': width,
            'S': const PdfName('S'),
          },
          'C': _rgbList(s.rgb),
          'CA': inkOpacity,
          'F': 4,
          'T': PdfStr.text('Corplex'),
          'M': PdfStr.text(date),
          'P': found.ref,
          'AP': {'N': ap},
        }),
      );
      written++;
    }

    // Rewrite the page itself with the extended /Annots (same object number).
    objects.add(_Pending(found.ref.num, {...found.dict, 'Annots': refs}));
  }

  if (written == 0) {
    return AnnotatedPdfResult(pdf, 0, skipped);
  }

  final out = BytesBuilder(copy: false);
  out.add(doc.b);
  if (doc.b.isNotEmpty && doc.b.last != 10 && doc.b.last != 13) out.addByte(10);
  final offsets = <int, int>{};
  void emit(_Pending p) {
    offsets[p.num] = out.length;
    out.add(ascii.encode('${p.num} 0 obj\n'));
    if (p.stream != null) {
      _put(out, {...p.dict, 'Length': p.stream!.length});
      out.add(ascii.encode('\nstream\n'));
      out.add(p.stream!);
      out.add(ascii.encode('\nendstream'));
    } else {
      _put(out, p.dict);
    }
    out.add(ascii.encode('\nendobj\n'));
  }

  objects.forEach(emit);

  final trailerBase = <String, Object?>{
    'Root': doc.trailer['Root'],
    if (doc.trailer['Info'] != null) 'Info': doc.trailer['Info'],
    if (doc.trailer['ID'] != null) 'ID': doc.trailer['ID'],
    'Prev': doc.newestXref,
  };
  final nums = offsets.keys.toList()..sort();
  final xrefOffset = out.length;

  if (doc.newestIsStream) {
    final xnum = next++;
    offsets[xnum] = xrefOffset;
    final all = offsets.keys.toList()..sort();
    final index = <int>[];
    for (var i = 0; i < all.length;) {
      var j = i;
      while (j + 1 < all.length && all[j + 1] == all[j] + 1) {
        j++;
      }
      index
        ..add(all[i])
        ..add(j - i + 1);
      i = j + 1;
    }
    final data = BytesBuilder();
    for (final n in all) {
      final o = offsets[n]!;
      data.add([
        1,
        (o >> 24) & 0xFF,
        (o >> 16) & 0xFF,
        (o >> 8) & 0xFF,
        o & 0xFF,
        0,
        0,
      ]);
    }
    out.add(ascii.encode('$xnum 0 obj\n'));
    final bytes = data.takeBytes();
    _put(out, {
      'Type': const PdfName('XRef'),
      'Size': xnum + 1,
      ...trailerBase,
      'W': [1, 4, 2],
      'Index': index,
      'Length': bytes.length,
    });
    out.add(ascii.encode('\nstream\n'));
    out.add(bytes);
    out.add(ascii.encode('\nendstream\nendobj\n'));
  } else {
    out.add(ascii.encode('xref\n'));
    for (var i = 0; i < nums.length;) {
      var j = i;
      while (j + 1 < nums.length && nums[j + 1] == nums[j] + 1) {
        j++;
      }
      out.add(ascii.encode('${nums[i]} ${j - i + 1}\n'));
      for (var k = i; k <= j; k++) {
        out.add(
          ascii.encode(
            '${offsets[nums[k]]!.toString().padLeft(10, '0')} 00000 n \n',
          ),
        );
      }
      i = j + 1;
    }
    out.add(ascii.encode('trailer\n'));
    _put(out, {'Size': next, ...trailerBase});
    out.add(ascii.encode('\n'));
  }
  out.add(ascii.encode('startxref\n$xrefOffset\n%%EOF\n'));
  return AnnotatedPdfResult(out.takeBytes(), written, skipped);
}

// ---------------------------------------------------------------------------
// Reading back (used by tests, and handy for diagnostics)

/// An annotation found in a PDF, with its page (1-based) and raw dictionary.
class ReadAnnotation {
  ReadAnnotation(this.page, this.dict);
  final int page;
  final Map<String, Object?> dict;
  String get subtype => (dict['Subtype'] as PdfName).value;
}

List<ReadAnnotation> readAnnotations(Uint8List pdf, int pageCount) {
  final doc = _PdfDoc.open(pdf);
  final out = <ReadAnnotation>[];
  for (var p = 1; p <= pageCount; p++) {
    final f = doc.findPage(p);
    if (f == null) continue;
    final annots = doc.resolve(f.dict['Annots']);
    if (annots is! List) continue;
    for (final a in annots) {
      final d = doc.resolve(a);
      if (d is PdfDict) out.add(ReadAnnotation(p, d));
    }
  }
  return out;
}
