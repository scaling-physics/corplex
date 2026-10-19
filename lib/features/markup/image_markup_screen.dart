import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:drift/drift.dart' show Value;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/database.dart';
import '../../data/database_provider.dart';
import '../../l10n/l10n.dart';
import '../ink/ink_canvas.dart';
import '../ink/ink_model.dart';
import '../ink/ink_tools.dart';
import '../platform/mac_window.dart' show isDesktop;
import 'image_markup.dart';

/// Opens [ImageMarkupScreen]; true when marks were saved.
Future<bool> openImageMarkup(
  BuildContext context,
  Attachment attachment,
) async {
  final saved = await Navigator.of(context).push<bool>(
    MaterialPageRoute(
      fullscreenDialog: true,
      builder: (_) => ImageMarkupScreen(attachment: attachment),
    ),
  );
  return saved ?? false;
}

/// Full-screen image viewer (zoomable) with a "Mark up" pencil button.
/// [actions] adds more app-bar actions (e.g. "Show in note").
class AttachmentImageViewer extends ConsumerStatefulWidget {
  const AttachmentImageViewer({
    super.key,
    required this.attachment,
    this.title,
    this.actions = const [],
  });

  final Attachment attachment;
  final String? title;
  final List<Widget> actions;

  @override
  ConsumerState<AttachmentImageViewer> createState() =>
      _AttachmentImageViewerState();
}

class _AttachmentImageViewerState extends ConsumerState<AttachmentImageViewer> {
  late String _path = widget.attachment.path!;
  int _version = 0;

  Future<void> _markUp() async {
    final saved = await openImageMarkup(
      context,
      widget.attachment.copyWith(path: Value(_path)),
    );
    if (!saved || !mounted) return;
    final db = ref.read(databaseProvider);
    final fresh = await (db.select(
      db.attachments,
    )..where((t) => t.id.equals(widget.attachment.id))).getSingleOrNull();
    if (fresh?.path != null && mounted) {
      setState(() {
        _path = fresh!.path!;
        _version++;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: widget.title == null
            ? null
            : Text(widget.title!, overflow: TextOverflow.ellipsis),
        actions: [
          ...widget.actions,
          IconButton(
            icon: const Icon(Icons.edit_outlined),
            tooltip: context.l10n.markupMarkUp,
            onPressed: _markUp,
          ),
        ],
      ),
      body: InteractiveViewer(
        maxScale: 6,
        child: Center(
          child: Image.file(
            File(_path),
            key: ValueKey('$_path$_version'),
            errorBuilder: (_, _, _) =>
                const Icon(Icons.broken_image_outlined, size: 48),
          ),
        ),
      ),
    );
  }
}

/// Draw on an image attachment. Strokes live in image-width units over the
/// image fitted to the screen; Done saves a composite and points the
/// attachment at it (see image_markup.dart), Cancel changes nothing.
class ImageMarkupScreen extends ConsumerStatefulWidget {
  const ImageMarkupScreen({super.key, required this.attachment});

  final Attachment attachment;

  @override
  ConsumerState<ImageMarkupScreen> createState() => _ImageMarkupScreenState();
}

class _ImageMarkupScreenState extends ConsumerState<ImageMarkupScreen> {
  final _tools = InkTools();
  final _undo = <Sketch>[];
  final _redo = <Sketch>[];
  Sketch? _sketch;
  String? _original;
  bool _failed = false;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _tools.addListener(_changed);
    _load();
  }

  @override
  void dispose() {
    _tools.removeListener(_changed);
    _tools.dispose();
    super.dispose();
  }

  void _changed() => setState(() {});

  Future<void> _load() async {
    try {
      final src = await loadMarkupSource(widget.attachment.path!);
      final size = await imageSizeOf(src.originalPath);
      if (!mounted) return;
      setState(() {
        _original = src.originalPath;
        _sketch =
            src.sketch?.copyWith(aspect: size.height / size.width) ??
            Sketch(strokes: const [], aspect: size.height / size.width);
      });
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    }
  }

  void _begin() {
    _undo.add(_sketch!);
    _redo.clear();
  }

  void _undoLast() => setState(() {
    _redo.add(_sketch!);
    _sketch = _undo.removeLast();
  });

  void _redoLast() => setState(() {
    _undo.add(_sketch!);
    _sketch = _redo.removeLast();
  });

  Future<void> _done() async {
    if (_saving) return;
    final navigator = Navigator.of(context);
    if (_undo.isEmpty && widget.attachment.path != null) {
      // Nothing drawn or erased this time.
      navigator.pop(false);
      return;
    }
    setState(() => _saving = true);
    try {
      await saveImageMarkup(
        ref.read(databaseProvider),
        widget.attachment,
        originalPath: _original!,
        sketch: _sketch!,
      );
      if (mounted) navigator.pop(true);
    } catch (_) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(context.l10n.markupSaveFailed)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).colorScheme;
    final desktop = isDesktop(context);
    inkPolicy.mouseAlwaysDraws = desktop;
    final sketch = _sketch;

    return CallbackShortcuts(
      bindings: {
        for (final meta in const [true, false])
          SingleActivator(
            LogicalKeyboardKey.keyZ,
            meta: meta,
            control: !meta,
          ): () {
            if (_undo.isNotEmpty) _undoLast();
          },
        for (final meta in const [true, false])
          SingleActivator(
            LogicalKeyboardKey.keyZ,
            meta: meta,
            control: !meta,
            shift: true,
          ): () {
            if (_redo.isNotEmpty) _redoLast();
          },
      },
      child: Focus(
        autofocus: true,
        child: Scaffold(
          backgroundColor: c.surfaceContainerLow,
          appBar: AppBar(
            backgroundColor: c.surfaceContainerLow,
            leading: IconButton(
              icon: const Icon(Icons.close),
              tooltip: context.l10n.commonCancel,
              onPressed: () => Navigator.of(context).pop(false),
            ),
            actions: [
              IconButton(
                icon: const Icon(Icons.undo),
                tooltip: context.l10n.commonUndo,
                onPressed: _undo.isEmpty ? null : _undoLast,
              ),
              IconButton(
                icon: const Icon(Icons.redo),
                tooltip: context.l10n.inkRedo,
                onPressed: _redo.isEmpty ? null : _redoLast,
              ),
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: FilledButton.tonal(
                  onPressed: sketch == null || _saving ? null : _done,
                  child: Text(context.l10n.commonDone),
                ),
              ),
            ],
          ),
          body: _failed
              ? Center(child: Text(context.l10n.markupOpenFailed))
              : sketch == null
              ? const Center(child: CircularProgressIndicator())
              : Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
                  child: LayoutBuilder(
                    builder: (context, box) {
                      final w = box.maxWidth < box.maxHeight / sketch.aspect
                          ? box.maxWidth
                          : box.maxHeight / sketch.aspect;
                      return Center(
                        child: SizedBox(
                          width: w,
                          height: w * sketch.aspect,
                          child: Stack(
                            fit: StackFit.expand,
                            children: [
                              Image.file(File(_original!), fit: BoxFit.fill),
                              InkCanvas(
                                sketch: sketch,
                                policy: inkPolicy,
                                tool: _tools.inkTool,
                                color: _tools.color,
                                width: _tools.width,
                                erasing: _tools.erasing,
                                onGestureStart: _begin,
                                onChanged: (s) => setState(() => _sketch = s),
                                onPolicyChanged: () => setState(() {}),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
          floatingActionButtonLocation:
              FloatingActionButtonLocation.centerFloat,
          floatingActionButton: InkPalette(tools: _tools),
        ),
      ),
    );
  }
}
