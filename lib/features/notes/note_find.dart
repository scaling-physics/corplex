import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_quill/flutter_quill.dart';

/// Where [query] occurs in [text], ignoring case: start offsets.
/// Offsets are document offsets, because the editor's plain text has one
/// character per embed (sketch, citation chip, maths), like the document.
List<int> findMatches(String text, String query) {
  if (query.isEmpty) return const [];
  final hay = text.toLowerCase();
  final needle = query.toLowerCase();
  final out = <int>[];
  for (var i = hay.indexOf(needle); i != -1; i = hay.indexOf(needle, i + 1)) {
    out.add(i);
  }
  return out;
}

/// Find (and replace) in the open note: ⌘F / ⌘G / ⇧⌘G on a Mac, ⋮ → Find
/// in note elsewhere. Selects each match in the editor; Replace changes
/// the current match, Replace all every one (one undo step each).
class NoteFindBar extends StatefulWidget {
  const NoteFindBar({
    super.key,
    required this.controller,
    required this.onClose,
    this.step,
  });

  final QuillController controller;
  final VoidCallback onClose;

  /// Lets the editor's ⌘G / ⇧⌘G move through matches: set by this bar to
  /// a function taking +1 or -1.
  final ValueNotifier<void Function(int)?>? step;

  @override
  State<NoteFindBar> createState() => _NoteFindBarState();
}

class _NoteFindBarState extends State<NoteFindBar> {
  final _query = TextEditingController();
  final _replacement = TextEditingController();
  final _focus = FocusNode();
  bool _replace = false;
  List<int> _matches = const [];
  int _current = -1;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_recount);
    widget.step?.value = _move;
    // autofocus doesn't take focus from the editor, which still has it
    // when ⌘F opens the bar; typing must go to the find field.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focus.requestFocus();
    });
    // Start from the selected text, as Notes does.
    final sel = widget.controller.selection;
    if (!sel.isCollapsed) {
      final text = widget.controller.document.toPlainText();
      final picked = text.substring(sel.start, sel.end);
      if (!picked.contains('\n')) _query.text = picked;
    }
    _recount();
  }

  @override
  void dispose() {
    widget.controller.removeListener(_recount);
    if (widget.step?.value == _move) widget.step?.value = null;
    _query.dispose();
    _replacement.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _recount() {
    final matches = findMatches(
      widget.controller.document.toPlainText(),
      _query.text,
    );
    if (!mounted) return;
    setState(() {
      _matches = matches;
      if (_current >= matches.length) _current = matches.isEmpty ? -1 : 0;
    });
  }

  void _move(int direction) {
    if (_matches.isEmpty) return;
    final n = _matches.length;
    final next = _current < 0
        ? (direction > 0 ? 0 : n - 1)
        : (_current + direction) % n;
    _select(next < 0 ? next + n : next);
  }

  void _select(int i) {
    setState(() => _current = i);
    final start = _matches[i];
    widget.controller.updateSelection(
      TextSelection(
        baseOffset: start,
        extentOffset: start + _query.text.length,
      ),
      ChangeSource.local,
    );
  }

  void _replaceOne() {
    if (_current < 0 || _matches.isEmpty) return _move(1);
    final start = _matches[_current];
    widget.controller.replaceText(
      start,
      _query.text.length,
      _replacement.text,
      TextSelection.collapsed(offset: start + _replacement.text.length),
    );
    _recount();
    if (_matches.isNotEmpty) _select(_current.clamp(0, _matches.length - 1));
  }

  void _replaceAll() {
    // Back to front, so earlier offsets stay valid.
    for (final start in _matches.reversed) {
      widget.controller.replaceText(
        start,
        _query.text.length,
        _replacement.text,
        null,
      );
    }
    _current = -1;
    _recount();
  }

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).colorScheme;
    final count = _query.text.isEmpty
        ? ''
        : _matches.isEmpty
        ? 'Not found'
        : '${_current < 0 ? 0 : _current + 1} of ${_matches.length}';
    InputDecoration field(String hint) => InputDecoration(
      hintText: hint,
      isDense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
    );
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.escape): widget.onClose,
        const SingleActivator(LogicalKeyboardKey.enter, shift: true): () =>
            _move(-1),
      },
      child: Material(
        color: c.surfaceContainerLow,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 6, 4, 6),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _query,
                      focusNode: _focus,
                      autofocus: true,
                      decoration: field('Find in note'),
                      textInputAction: TextInputAction.search,
                      onChanged: (_) {
                        _current = -1;
                        _recount();
                        if (_matches.isNotEmpty) _select(0);
                      },
                      onSubmitted: (_) {
                        _move(1);
                        _focus.requestFocus();
                      },
                    ),
                  ),
                  SizedBox(
                    width: 72,
                    child: Text(
                      count,
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                  IconButton(
                    tooltip: 'Previous',
                    icon: const Icon(Icons.keyboard_arrow_up),
                    onPressed: _matches.isEmpty ? null : () => _move(-1),
                  ),
                  IconButton(
                    tooltip: 'Next',
                    icon: const Icon(Icons.keyboard_arrow_down),
                    onPressed: _matches.isEmpty ? null : () => _move(1),
                  ),
                  IconButton(
                    tooltip: _replace ? 'Hide replace' : 'Replace',
                    icon: Icon(
                      _replace ? Icons.unfold_less : Icons.find_replace,
                    ),
                    onPressed: () => setState(() => _replace = !_replace),
                  ),
                  IconButton(
                    tooltip: 'Done',
                    icon: const Icon(Icons.close),
                    onPressed: widget.onClose,
                  ),
                ],
              ),
              if (_replace)
                Padding(
                  padding: const EdgeInsets.only(top: 6, right: 8),
                  child: Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _replacement,
                          decoration: field('Replace with'),
                          onSubmitted: (_) => _replaceOne(),
                        ),
                      ),
                      const SizedBox(width: 8),
                      TextButton(
                        onPressed: _matches.isEmpty ? null : _replaceOne,
                        child: const Text('Replace'),
                      ),
                      TextButton(
                        onPressed: _matches.isEmpty ? null : _replaceAll,
                        child: const Text('All'),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
