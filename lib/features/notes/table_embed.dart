import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:flutter_quill/quill_delta.dart';

import '../../l10n/l10n.dart';
import 'note_table.dart';

export 'note_table.dart' show tableEmbedType;

// ---------------------------------------------------------------------------
// Structure edits (pure; every one returns a new table).

extension NoteTableEdits on NoteTable {
  NoteTable insertRow(int at) {
    final r = [
      ...rows.map((r) => [...r]),
    ];
    r.insert(at.clamp(0, r.length), List.filled(columns, ''));
    return copyWith(rows: r);
  }

  NoteTable insertColumn(int at) {
    final i = at.clamp(0, columns);
    return copyWith(
      rows: [
        for (final r in rows) [...r]..insert(i, ''),
      ],
    );
  }

  NoteTable deleteRow(int at) {
    if (rows.length <= 1) return this;
    return copyWith(
      rows: [
        ...rows.map((r) => [...r]),
      ]..removeAt(at),
    );
  }

  NoteTable deleteColumn(int at) {
    if (columns <= 1) return this;
    return copyWith(
      rows: [
        for (final r in rows) [...r]..removeAt(at),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Insertion.

/// The offset of a table embed at or right after [offset], if any.
int? tableOffsetNear(Document doc, int offset) {
  for (final candidate in [offset, offset + 1]) {
    if (candidate < 0 || candidate >= doc.length) continue;
    final leaf = doc.querySegmentLeafNode(candidate).leaf;
    if (leaf is Embed &&
        leaf.value.type == tableEmbedType &&
        leaf.documentOffset == candidate) {
      return candidate;
    }
  }
  return null;
}

/// Tables just inserted, whose first cell should take focus once built.
final Expando<int> _focusRequests = Expando<int>('table focus');

/// Inserts a 3×3 table (header row) at the cursor on a line of its own —
/// the text around it stays on lines of its own — and focuses its first
/// cell. Returns where it landed.
int? insertTableAtCursor(QuillController controller, {VoidCallback? onQuiet}) {
  final doc = controller.document;
  final cursor = controller.selection.baseOffset;
  final at = (cursor < 0 || cursor > doc.length - 1 ? doc.length - 1 : cursor)
      .clamp(0, doc.length - 1);
  // Offsets match: an embed is one character in the plain text.
  final plain = doc.toPlainText();
  final lineStart = at == 0 || plain[at - 1] == '\n';
  final lineEnd = plain[at] == '\n';
  // Quill only adds the newlines around a block embed for videos.
  final delta = Delta()..retain(at);
  if (!lineStart) delta.insert('\n');
  delta.insert(
    CustomBlockEmbed(tableEmbedType, NoteTable.empty().encode()).toJson(),
  );
  if (!lineEnd) delta.insert('\n');
  final added = delta.length - at;
  final sel = controller.selection;
  TextSelection shifted(TextSelection s) => s.copyWith(
    baseOffset: s.baseOffset >= at ? s.baseOffset + added : s.baseOffset,
    extentOffset: s.extentOffset >= at
        ? s.extentOffset + added
        : s.extentOffset,
  );
  final landed = lineStart ? at : at + 1;
  _focusRequests[controller] = landed;
  controller.ignoreFocusOnTextChange = true;
  try {
    controller.compose(
      delta,
      sel.isValid ? shifted(sel) : const TextSelection.collapsed(offset: 0),
      ChangeSource.local,
    );
  } finally {
    controller.ignoreFocusOnTextChange = false;
  }
  onQuiet?.call();
  return tableOffsetNear(controller.document, landed);
}

// ---------------------------------------------------------------------------
// The embed.

class TableEmbedBuilder extends EmbedBuilder {
  const TableEmbedBuilder();

  @override
  String get key => tableEmbedType;

  @override
  bool get expanded => true;

  @override
  String toPlainText(Embed node) =>
      NoteTable.decode(node.value.data as String).plainText;

  @override
  Widget build(BuildContext context, EmbedContext embedContext) {
    if (embedContext.readOnly) {
      return _StaticTable(
        table: NoteTable.decode(embedContext.node.value.data as String),
        style: embedContext.textStyle,
      );
    }
    return _EditableTable(
      node: embedContext.node,
      controller: embedContext.controller,
      style: embedContext.textStyle,
    );
  }
}

const _minColumn = 88.0;
const _maxColumn = 260.0;

List<double> _columnWidths(
  NoteTable t,
  List<String> Function(int c) texts,
  double fontSize,
  double available,
) {
  final k = fontSize / 16;
  final widths = [
    for (var c = 0; c < t.columns; c++)
      (texts(c).fold<int>(0, (m, s) {
                    final longest = s
                        .split('\n')
                        .fold<int>(0, (a, l) => math.max(a, l.length));
                    return math.max(m, longest);
                  }) *
                  8.0 *
                  k +
              28)
          .clamp(_minColumn, _maxColumn),
  ];
  final total = widths.fold<double>(0, (a, b) => a + b);
  if (available.isFinite && total < available) {
    return [for (final w in widths) w * available / total];
  }
  return widths;
}

/// The grid, whether editable or not: [cell] makes each cell's content.
class _Grid extends StatefulWidget {
  const _Grid({
    super.key,
    required this.header,
    required this.widths,
    required this.rowCount,
    required this.cell,
  });

  final bool header;
  final List<double> widths;
  final int rowCount;
  final Widget Function(int row, int col) cell;

  @override
  State<_Grid> createState() => _GridState();
}

class _GridState extends State<_Grid> {
  final _scroll = ScrollController();

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final line = BorderSide(color: scheme.outlineVariant);
    final total = widget.widths.fold<double>(0, (a, b) => a + b);
    final table = Table(
      columnWidths: {
        for (var c = 0; c < widget.widths.length; c++)
          c: FixedColumnWidth(widget.widths[c]),
      },
      defaultVerticalAlignment: TableCellVerticalAlignment.fill,
      border: TableBorder(horizontalInside: line, verticalInside: line),
      children: [
        for (var r = 0; r < widget.rowCount; r++)
          TableRow(
            decoration: r == 0 && widget.header
                ? BoxDecoration(
                    color: scheme.surfaceContainerHighest.withValues(
                      alpha: 0.6,
                    ),
                  )
                : null,
            children: [
              for (var c = 0; c < widget.widths.length; c++) widget.cell(r, c),
            ],
          ),
      ],
    );
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        border: Border.fromBorderSide(line),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(9),
        child: SingleChildScrollView(
          controller: _scroll,
          scrollDirection: Axis.horizontal,
          child: SizedBox(width: total, child: table),
        ),
      ),
    );
  }
}

class _StaticTable extends StatelessWidget {
  const _StaticTable({required this.table, required this.style});

  final NoteTable table;
  final TextStyle style;

  @override
  Widget build(BuildContext context) {
    final base = style.fontSize == null
        ? Theme.of(context).textTheme.bodyMedium!
        : style;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: LayoutBuilder(
        builder: (context, box) => _Grid(
          key: const ValueKey('table-static'),
          header: table.header,
          rowCount: table.rows.length,
          widths: _columnWidths(
            table,
            (c) => [for (final r in table.rows) r[c]],
            base.fontSize ?? 16,
            box.maxWidth,
          ),
          cell: (r, c) => Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            child: Text(
              table.rows[r][c],
              style: base.copyWith(
                fontWeight: r == 0 && table.header ? FontWeight.w700 : null,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

enum _TableAction {
  rowAbove,
  rowBelow,
  columnLeft,
  columnRight,
  deleteRow,
  deleteColumn,
  header,
  deleteTable;

  String label(AppLocalizations l10n) => switch (this) {
    rowAbove => l10n.tableAddRowAbove,
    rowBelow => l10n.tableAddRowBelow,
    columnLeft => l10n.tableAddColumnLeft,
    columnRight => l10n.tableAddColumnRight,
    deleteRow => l10n.tableDeleteRow,
    deleteColumn => l10n.tableDeleteColumn,
    header => l10n.tableHeaderRow,
    deleteTable => l10n.tableDeleteTable,
  };
}

// Letters the note editor binds to formatting; cells are plain text, so
// these do nothing there (copy, paste, undo etc. still work).
final _swallowed = {
  LogicalKeyboardKey.keyB,
  LogicalKeyboardKey.keyI,
  LogicalKeyboardKey.keyU,
  LogicalKeyboardKey.keyK,
  LogicalKeyboardKey.keyE,
  LogicalKeyboardKey.keyL,
  LogicalKeyboardKey.keyM,
  LogicalKeyboardKey.keyG,
  LogicalKeyboardKey.digit0,
  LogicalKeyboardKey.digit1,
  LogicalKeyboardKey.digit2,
  LogicalKeyboardKey.digit3,
  LogicalKeyboardKey.digit4,
  LogicalKeyboardKey.digit5,
  LogicalKeyboardKey.digit6,
  LogicalKeyboardKey.quote,
  LogicalKeyboardKey.backquote,
};

class _EditableTable extends StatefulWidget {
  const _EditableTable({
    required this.node,
    required this.controller,
    required this.style,
  });

  final Embed node;
  final QuillController controller;
  final TextStyle style;

  @override
  State<_EditableTable> createState() => _EditableTableState();
}

class _EditableTableState extends State<_EditableTable> {
  final _texts = <List<TextEditingController>>[];
  final _focus = <List<FocusNode>>[];
  final _retired = <ChangeNotifier>[];
  late String _lastData;
  late bool _header;
  late int _offset;
  Timer? _debounce;
  bool _dirty = false;
  int _row = 0;
  int _col = 0;
  bool _hadFocus = false;

  int get _rows => _texts.length;
  int get _cols => _texts.isEmpty ? 0 : _texts.first.length;

  @override
  void initState() {
    super.initState();
    _lastData = widget.node.value.data as String;
    _offset = widget.node.documentOffset;
    final t = NoteTable.decode(_lastData);
    _header = t.header;
    _fit(t);
    if (_focusRequests[widget.controller] == _offset) {
      _focusRequests[widget.controller] = null;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _focusCell(0, 0);
      });
    }
  }

  @override
  void didUpdateWidget(_EditableTable old) {
    super.didUpdateWidget(old);
    if (widget.node.parent != null) _offset = widget.node.documentOffset;
    final data = widget.node.value.data as String;
    if (data == _lastData) return;
    // Changed from outside (undo, sync, restore): take it, unless it is
    // what this table has just written.
    _lastData = data;
    final t = NoteTable.decode(data);
    _header = t.header;
    _debounce?.cancel();
    _dirty = false;
    _fit(t);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    if (_dirty) {
      final controller = widget.controller;
      final t = _current();
      final offset = _offset;
      scheduleMicrotask(() {
        try {
          _writeTo(controller, offset, t);
        } catch (_) {}
      });
    }
    for (final row in _focus) {
      for (final n in row) {
        n.removeListener(_focusChanged);
        n.dispose();
      }
    }
    for (final row in _texts) {
      for (final c in row) {
        c.dispose();
      }
    }
    for (final n in _retired) {
      n.dispose();
    }
    super.dispose();
  }

  /// Makes the controllers match [t] in size and (where different) text.
  void _fit(NoteTable t) {
    while (_texts.length > t.rows.length) {
      _retire(_texts.removeLast(), _focus.removeLast());
    }
    for (final row in _texts) {
      while (row.length > t.columns) {
        _retired.add(row.removeLast());
      }
    }
    for (final row in _focus) {
      while (row.length > t.columns) {
        _retired.add(row.removeLast()..removeListener(_focusChanged));
      }
    }
    for (var r = 0; r < t.rows.length; r++) {
      if (r >= _texts.length) {
        _texts.add([]);
        _focus.add([]);
      }
      while (_texts[r].length < t.columns) {
        _texts[r].add(TextEditingController());
        _focus[r].add(FocusNode()..addListener(_focusChanged));
      }
      for (var c = 0; c < t.columns; c++) {
        if (_texts[r][c].text != t.rows[r][c]) {
          _texts[r][c].value = TextEditingValue(
            text: t.rows[r][c],
            selection: TextSelection.collapsed(offset: t.rows[r][c].length),
          );
        }
      }
    }
    _row = _row.clamp(0, _rows - 1);
    _col = _col.clamp(0, _cols - 1);
  }

  void _retire(List<TextEditingController> t, List<FocusNode> f) {
    _retired.addAll(t);
    for (final n in f) {
      n.removeListener(_focusChanged);
    }
    _retired.addAll(f);
  }

  NoteTable _current() => NoteTable(
    rows: [
      for (final r in _texts) [for (final c in r) c.text],
    ],
    header: _header,
  );

  void _focusChanged() {
    var focused = false;
    for (var r = 0; r < _rows; r++) {
      for (var c = 0; c < _cols; c++) {
        if (_focus[r][c].hasFocus) {
          focused = true;
          _row = r;
          _col = c;
        }
      }
    }
    // Leaving a cell writes what was typed straight away.
    if (_hadFocus || !focused) _flush();
    _hadFocus = focused;
  }

  void _changed() {
    _dirty = true;
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), _flush);
  }

  void _flush() {
    _debounce?.cancel();
    _debounce = null;
    if (!_dirty) return;
    _dirty = false;
    _write(_current());
  }

  /// The table's offset in the document, if it is still there.
  int? _where() {
    final n = widget.node;
    final off = n.parent != null ? n.documentOffset : _offset;
    return tableOffsetNear(widget.controller.document, off) == off ? off : null;
  }

  void _write(NoteTable t) {
    final off = _where();
    if (off == null) return;
    if (_writeTo(widget.controller, off, t, last: _lastData)) {
      _lastData = t.encode();
      _offset = off;
    }
  }

  static bool _writeTo(
    QuillController controller,
    int off,
    NoteTable t, {
    String? last,
  }) {
    final data = t.encode();
    if (data == last) return false;
    if (tableOffsetNear(controller.document, off) != off) return false;
    controller.replaceText(
      off,
      1,
      CustomBlockEmbed(tableEmbedType, data),
      null,
      ignoreFocus: true,
    );
    return true;
  }

  void _focusCell(int r, int c, {bool selectAll = false, bool end = true}) {
    if (r < 0 || r >= _rows || c < 0 || c >= _cols) return;
    final ctrl = _texts[r][c];
    ctrl.selection = selectAll
        ? TextSelection(baseOffset: 0, extentOffset: ctrl.text.length)
        : TextSelection.collapsed(offset: end ? ctrl.text.length : 0);
    _focus[r][c].requestFocus();
  }

  /// Applies a structural change: written at once, the grid rebuilt.
  void _restructure(NoteTable t, {int? row, int? col}) {
    _debounce?.cancel();
    _dirty = false;
    _fit(t);
    _header = t.header;
    _write(t);
    setState(() {});
    if (row != null && col != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _focusCell(row, col);
      });
    }
  }

  void _next(int r, int c, {required bool back}) {
    if (back) {
      if (c > 0) return _focusCell(r, c - 1, selectAll: true);
      if (r > 0) return _focusCell(r - 1, _cols - 1, selectAll: true);
      return;
    }
    if (c < _cols - 1) return _focusCell(r, c + 1, selectAll: true);
    if (r < _rows - 1) return _focusCell(r + 1, 0, selectAll: true);
    // Tab in the last cell adds a row.
    _restructure(_current().insertRow(_rows), row: _rows, col: 0);
  }

  KeyEventResult _key(int r, int c, KeyEvent event) {
    if (event is KeyUpEvent) return KeyEventResult.ignored;
    final key = event.logicalKey;
    final keys = HardwareKeyboard.instance;
    final ctrl = _texts[r][c];
    final sel = ctrl.selection;
    final collapsed = sel.isValid && sel.isCollapsed;
    if (key == LogicalKeyboardKey.tab) {
      _next(r, c, back: keys.isShiftPressed);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.numpadEnter) {
      _vertical(r, c, keys.isShiftPressed ? -1 : 1);
      return KeyEventResult.handled;
    }
    if (!keys.isShiftPressed && !keys.isMetaPressed && !keys.isControlPressed) {
      if (collapsed && key == LogicalKeyboardKey.arrowUp && sel.start == 0) {
        _vertical(r, c, -1, end: false);
        return KeyEventResult.handled;
      }
      if (collapsed &&
          key == LogicalKeyboardKey.arrowDown &&
          sel.start == ctrl.text.length) {
        _vertical(r, c, 1);
        return KeyEventResult.handled;
      }
      if (collapsed && key == LogicalKeyboardKey.arrowLeft && sel.start == 0) {
        if (c > 0) {
          _focusCell(r, c - 1);
        } else if (r > 0) {
          _focusCell(r - 1, _cols - 1);
        }
        return KeyEventResult.handled;
      }
      if (collapsed &&
          key == LogicalKeyboardKey.arrowRight &&
          sel.start == ctrl.text.length) {
        if (c < _cols - 1) {
          _focusCell(r, c + 1, end: false);
        } else if (r < _rows - 1) {
          _focusCell(r + 1, 0, end: false);
        }
        return KeyEventResult.handled;
      }
    }
    if ((keys.isMetaPressed || keys.isControlPressed) &&
        _swallowed.contains(key)) {
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  void _vertical(int r, int c, int delta, {bool end = true}) {
    final to = r + delta;
    if (to < 0 || to >= _rows) return;
    _focusCell(to, c, end: end);
  }

  Future<void> _menu(Offset at) async {
    _flush();
    final overlay = Overlay.of(context).context.findRenderObject() as RenderBox;
    final t = _current();
    final choice = await showMenu<_TableAction>(
      context: context,
      position: RelativeRect.fromRect(
        at & const Size(1, 1),
        Offset.zero & overlay.size,
      ),
      items: [
        for (final a in _TableAction.values) ...[
          if (a == _TableAction.deleteRow || a == _TableAction.deleteTable)
            const PopupMenuDivider(),
          if (a == _TableAction.header)
            CheckedPopupMenuItem(
              value: a,
              checked: t.header,
              child: Text(a.label(context.l10n)),
            )
          else
            PopupMenuItem(
              value: a,
              enabled: switch (a) {
                _TableAction.deleteRow => t.rows.length > 1,
                _TableAction.deleteColumn => t.columns > 1,
                _ => true,
              },
              child: Text(a.label(context.l10n)),
            ),
        ],
      ],
    );
    if (choice == null || !mounted) return;
    final r = _row.clamp(0, _rows - 1);
    final c = _col.clamp(0, _cols - 1);
    switch (choice) {
      case _TableAction.rowAbove:
        _restructure(t.insertRow(r), row: r, col: c);
      case _TableAction.rowBelow:
        _restructure(t.insertRow(r + 1), row: r + 1, col: c);
      case _TableAction.columnLeft:
        _restructure(t.insertColumn(c), row: r, col: c);
      case _TableAction.columnRight:
        _restructure(t.insertColumn(c + 1), row: r, col: c + 1);
      case _TableAction.deleteRow:
        _restructure(
          t.deleteRow(r),
          row: math.min(r, t.rows.length - 2),
          col: c,
        );
      case _TableAction.deleteColumn:
        _restructure(
          t.deleteColumn(c),
          row: r,
          col: math.min(c, t.columns - 2),
        );
      case _TableAction.header:
        _restructure(t.copyWith(header: !t.header));
      case _TableAction.deleteTable:
        _deleteTable();
    }
  }

  void _deleteTable() {
    final off = _where();
    if (off == null) return;
    _debounce?.cancel();
    _dirty = false;
    final doc = widget.controller.document;
    final plain = doc.toPlainText();
    // Take its line with it, so no blank line is left behind.
    final ownLine = off + 1 < plain.length - 1 && plain[off + 1] == '\n';
    widget.controller.replaceText(off, ownLine ? 2 : 1, '', null);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final base = widget.style.fontSize == null
        ? Theme.of(context).textTheme.bodyMedium!
        : widget.style;
    final cellStyle = base.copyWith(
      color: scheme.onSurface,
      decoration: TextDecoration.none,
    );
    final model = NoteTable(
      rows: [
        for (final r in _texts) [for (final c in r) c.text],
      ],
      header: _header,
    );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: GestureDetector(
        onSecondaryTapDown: (d) => _menu(d.globalPosition),
        onLongPressStart: (d) => _menu(d.globalPosition),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Builder(
              builder: (handle) => IconButton(
                key: const ValueKey('table-menu'),
                tooltip: context.l10n.tableTooltip,
                visualDensity: VisualDensity.compact,
                iconSize: 18,
                constraints: const BoxConstraints.tightFor(
                  width: 28,
                  height: 24,
                ),
                padding: EdgeInsets.zero,
                color: scheme.onSurfaceVariant,
                icon: const Icon(Icons.drag_indicator),
                onPressed: () {
                  final box = handle.findRenderObject() as RenderBox;
                  _menu(box.localToGlobal(Offset(0, box.size.height)));
                },
              ),
            ),
            LayoutBuilder(
              builder: (context, box) => _Grid(
                key: const ValueKey('table-grid'),
                header: _header,
                rowCount: _rows,
                widths: _columnWidths(
                  model,
                  (c) => [for (final r in _texts) r[c].text],
                  cellStyle.fontSize ?? 16,
                  box.maxWidth,
                ),
                cell: (r, c) => _cell(r, c, cellStyle),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _cell(int r, int c, TextStyle style) {
    final bold = r == 0 && _header;
    return Listener(
      onPointerDown: (e) {
        if (e.buttons == kSecondaryButton) {
          _row = r;
          _col = c;
        }
      },
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => _focus[r][c].requestFocus(),
        child: Focus(
          canRequestFocus: false,
          onKeyEvent: (_, event) => _key(r, c, event),
          child: TextField(
            key: ValueKey('table-cell-$r-$c'),
            controller: _texts[r][c],
            focusNode: _focus[r][c],
            maxLines: null,
            keyboardType: TextInputType.text,
            textInputAction: TextInputAction.next,
            style: style.copyWith(fontWeight: bold ? FontWeight.w700 : null),
            cursorColor: Theme.of(context).colorScheme.primary,
            onChanged: (_) => _changed(),
            onSubmitted: (_) => _vertical(r, c, 1),
            decoration: const InputDecoration(
              isCollapsed: true,
              filled: false,
              border: InputBorder.none,
              enabledBorder: InputBorder.none,
              focusedBorder: InputBorder.none,
              contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            ),
          ),
        ),
      ),
    );
  }
}
