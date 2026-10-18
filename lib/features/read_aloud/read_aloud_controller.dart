import 'dart:async';

import 'package:flutter/foundation.dart';

import 'listening_text.dart';
import 'speaker.dart';

/// Reads a paper aloud, sentence by sentence, from a given page.
///
/// Sentences are queued a few ahead on the [Speaker] so there is no gap
/// between them, yet pausing and skipping stay precise: a skip drops the
/// queue and queues again from the new sentence.
class ReadAloudController extends ChangeNotifier {
  ReadAloudController({
    required this.speaker,
    required this.pageCount,
    required this.pageText,
    required this.startPage,
    this.lookAhead = 3,
  });

  final Speaker speaker;
  final int pageCount;

  /// Raw text of a 1-based page (text layer, or OCR for a scan).
  final Future<String> Function(int page) pageText;
  final int startPage;
  final int lookAhead;

  static const minRate = 0.8;
  static const maxRate = 2.0;

  List<Sentence> _sentences = const [];
  String? _language;
  int _index = 0;
  int _queued = 0; // next index to hand to the speaker
  int _generation = 0;
  bool _loading = true;
  bool _playing = false; // wants to be speaking (not paused)
  bool _stale = false; // the speaker's queue was dropped while paused
  bool _finished = false;
  bool _empty = false;
  bool _disposed = false;
  double _rate = 1;
  late int _lastPage = startPage;

  bool get loading => _loading;
  bool get playing => _playing;
  bool get finished => _finished;

  /// Nothing readable was found (a scan not recognised yet, say).
  bool get isEmpty => _empty;
  double get rate => _rate;

  /// The page being read (the start page until text is loaded).
  int get page => _sentences.isEmpty || _index >= _sentences.length
      ? _lastPage
      : _sentences[_index].page;
  Sentence? get current =>
      _index < _sentences.length ? _sentences[_index] : null;
  int get index => _index;
  int get sentenceCount => _sentences.length;

  /// Loads the text of every page and starts speaking.
  Future<void> start() async {
    final raw = <String>[];
    for (var p = 1; p <= pageCount; p++) {
      try {
        raw.add(await pageText(p));
      } catch (_) {
        raw.add('');
      }
      if (_disposed) return;
    }
    final cleaned = cleanPagesForListening(raw);
    _language = guessLanguage(cleaned.join(' '));
    _sentences = sentencesOf(cleaned);
    _index = _sentences.indexWhere((s) => s.page >= startPage);
    if (_index < 0) {
      // Started past the references: read from the end, i.e. nothing.
      _index = _sentences.length;
    }
    _queued = _index;
    _loading = false;
    _empty = _sentences.isEmpty;
    _lastPage = startPage;
    if (_empty || _index >= _sentences.length) {
      _finished = !_empty;
      notifyListeners();
      return;
    }
    _playing = true;
    notifyListeners();
    _pump();
  }

  void _pump() {
    if (_disposed || !_playing) return;
    while (_queued < _sentences.length && _queued - _index < lookAhead) {
      final i = _queued++;
      final gen = _generation;
      unawaited(
        speaker
            .speak(_sentences[i].text, rate: _rate, language: _language)
            .then((ok) => _spoken(i, gen, ok)),
      );
    }
  }

  void _spoken(int i, int gen, bool ok) {
    if (_disposed || gen != _generation) return;
    if (!ok) {
      // The speaker failed (not a skip: those change the generation).
      _playing = false;
      notifyListeners();
      return;
    }
    _index = i + 1;
    if (_index >= _sentences.length) {
      _playing = false;
      _finished = true;
      _lastPage = _sentences.last.page;
    } else {
      _lastPage = _sentences[_index].page;
    }
    notifyListeners();
    _pump();
  }

  Future<void> pause() async {
    if (!_playing || _loading) return;
    _playing = false;
    notifyListeners();
    await speaker.pause();
  }

  Future<void> resume() async {
    if (_playing || _loading || _empty) return;
    if (_finished) {
      // Play again from the start page.
      _finished = false;
      _index = _sentences.indexWhere((s) => s.page >= startPage);
      if (_index < 0) _index = 0;
      _stale = true;
    }
    _playing = true;
    notifyListeners();
    if (_stale) {
      _stale = false;
      await _restartFrom(_index);
    } else {
      await speaker.resume();
    }
  }

  Future<void> toggle() => _playing ? pause() : resume();

  Future<void> _restartFrom(int index) async {
    _generation++;
    await speaker.stop();
    if (_disposed) return;
    _index = index.clamp(0, _sentences.length);
    _queued = _index;
    if (_playing) _pump();
    notifyListeners();
  }

  /// Moves [delta] sentences (negative = back). Staying put while paused
  /// is fine: the new sentence is spoken on resume.
  Future<void> skip(int delta) async {
    if (_loading || _sentences.isEmpty) return;
    final target = (_index + delta).clamp(0, _sentences.length - 1);
    _finished = false;
    if (_playing) {
      await _restartFrom(target);
    } else {
      _generation++;
      _stale = true;
      _index = target;
      _queued = target;
      await speaker.stop();
      _lastPage = _sentences[_index].page;
      notifyListeners();
    }
  }

  /// Jumps to the first sentence on [page] (or the next page with text).
  Future<void> seekToPage(int page) async {
    final i = _sentences.indexWhere((s) => s.page >= page);
    if (i < 0) return;
    await skip(i - _index);
  }

  Future<void> setRate(double value) async {
    final r = value.clamp(minRate, maxRate).toDouble();
    if (r == _rate) return;
    _rate = r;
    notifyListeners();
    if (_loading || _finished || _sentences.isEmpty) return;
    // The queued sentences carry the old rate: re-queue from this one.
    if (_playing) {
      await _restartFrom(_index);
    } else {
      _generation++;
      _stale = true;
      _queued = _index;
      await speaker.stop();
    }
  }

  Future<void> stop() async {
    _generation++;
    _playing = false;
    await speaker.stop();
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _generation++;
    unawaited(speaker.stop());
    super.dispose();
  }
}
