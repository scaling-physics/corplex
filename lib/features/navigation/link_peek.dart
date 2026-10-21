import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_quill/quill_delta.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/database_provider.dart';
import '../../l10n/l10n.dart';
import '../../theme/app_theme.dart';
import '../home/adaptive.dart';
import '../library/authors.dart';
import '../lock/note_lock_service.dart';
import '../notes/note_content.dart';
import '../notes/note_link_open.dart';
import '../notes/note_links.dart';
import '../notes/note_sections.dart';
import '../projects/readable_content.dart';
import 'nav_target.dart';

/// What a peek shows: a place, and for a note optionally one heading or
/// paragraph of it.
class PeekRequest {
  const PeekRequest(this.target, {this.heading, this.block});

  /// A peek for a note link (`corplex://note/<id>#heading=…`).
  factory PeekRequest.note(NoteLinkTarget t) =>
      PeekRequest(NoteTarget(t.noteId), heading: t.heading, block: t.block);

  final NavTarget target;
  final String? heading;
  final String? block;

  @override
  bool operator ==(Object other) =>
      other is PeekRequest &&
      other.target == target &&
      other.heading == heading &&
      other.block == block;

  @override
  int get hashCode => Object.hash(target, heading, block);
}

enum PeekKind { note, paper, locked, missing }

class PeekData {
  const PeekData(this.kind, {this.title = '', this.subtitle, this.body});

  final PeekKind kind;
  final String title;
  final String? subtitle;
  final String? body;
}

/// The text of [delta] (no embeds), tidied for a small card.
String peekText(Delta delta, {int maxChars = 600}) {
  final buffer = StringBuffer();
  for (final op in delta.toList()) {
    final data = op.data;
    if (op.isInsert && data is String) buffer.write(data);
  }
  final text = buffer
      .toString()
      .replaceAll(RegExp(r'[ \t]+\n'), '\n')
      .replaceAll(RegExp(r'\n{3,}'), '\n\n')
      .trim();
  if (text.length <= maxChars) return text;
  return '${text.substring(0, maxChars).trimRight()}…';
}

final linkPeekProvider = FutureProvider.autoDispose
    .family<PeekData, PeekRequest>((ref, request) async {
      final db = ref.read(databaseProvider);
      switch (request.target) {
        case NoteTarget(:final noteId):
          final note = await (db.select(
            db.notes,
          )..where((n) => n.id.equals(noteId))).getSingleOrNull();
          if (note == null) return const PeekData(PeekKind.missing);
          final body = await readableNoteContent(
            ref.read(noteLockServiceProvider),
            note.id,
            note.content,
          );
          if (body == null) {
            return PeekData(PeekKind.locked, title: note.title);
          }
          final delta = decodeNoteContent(body).toDelta();
          final link = NoteLinkTarget(
            noteId,
            heading: request.heading,
            block: request.block,
          );
          // A heading or paragraph that has gone falls back to the start.
          final part = sectionOf(delta, link) ?? sectionOf(delta, null);
          return PeekData(
            PeekKind.note,
            title: note.title,
            subtitle: request.heading,
            body: part == null ? '' : peekText(part),
          );
        case PaperTarget(:final paperId, :final page):
          final paper = await (db.select(
            db.papers,
          )..where((p) => p.id.equals(paperId))).getSingleOrNull();
          if (paper == null) return const PeekData(PeekKind.missing);
          return PeekData(
            PeekKind.paper,
            title: paper.title,
            subtitle: [
              if (paper.authors.trim().isNotEmpty)
                displayAuthors(paper.authors),
              if (paper.year != null) '${paper.year}',
            ].join(' · '),
            body: page == null ? null : '$page',
          );
        case ProjectTarget():
          return const PeekData(PeekKind.missing);
      }
    });

/// Opens what the card names (tapping the card).
void openPeekRequest(BuildContext context, WidgetRef ref, PeekRequest r) {
  switch (r.target) {
    case NoteTarget(:final noteId):
      unawaited(
        openNoteLink(
          context,
          ref,
          NoteLinkTarget(noteId, heading: r.heading, block: r.block),
        ),
      );
    case PaperTarget(:final paperId):
      openPaper(context, ref, paperId);
    case ProjectTarget():
      break;
  }
}

/// Shows and hides one floating peek card: after a pointer has rested
/// [delay] on something, or at once for a long-press. The card stays while
/// the pointer is on it, and closes 250 ms after it leaves both, on Escape,
/// or on any press or scroll outside it.
class LinkPeekController {
  LinkPeekController({
    required this.context,
    this.delay = const Duration(milliseconds: 500),
  });

  /// The context whose overlay and providers are used; read each time.
  final BuildContext Function() context;
  final Duration delay;

  OverlayEntry? _entry;
  Timer? _in;
  Timer? _out;
  PeekRequest? _pending;
  PeekRequest? _shown;
  bool _overCard = false;
  bool _overSource = false;

  bool get isOpen => _entry != null;
  PeekRequest? get shown => _shown;

  /// The pointer is over [request]'s source at [anchor] (global).
  void hover(PeekRequest request, Rect anchor) {
    _overSource = true;
    _out?.cancel();
    if (_shown == request || _pending == request) return;
    _in?.cancel();
    if (_shown != null) close();
    _pending = request;
    _in = Timer(delay, () => show(request, anchor));
  }

  /// The pointer left the source (or moved off any link).
  void leave() {
    _overSource = false;
    _in?.cancel();
    _pending = null;
    _closeSoon();
  }

  void _closeSoon() {
    _out?.cancel();
    if (_entry == null || _overCard || _overSource) return;
    _out = Timer(const Duration(milliseconds: 250), () {
      if (!_overCard && !_overSource) close();
    });
  }

  void show(PeekRequest request, Rect anchor) {
    _in?.cancel();
    _pending = null;
    final ctx = context();
    if (!ctx.mounted) return;
    final overlay = Overlay.maybeOf(ctx, rootOverlay: true);
    if (overlay == null) return;
    close();
    _shown = request;
    _entry = OverlayEntry(
      builder: (_) => _PeekOverlay(
        request: request,
        anchor: anchor,
        onHover: (over) {
          _overCard = over;
          if (over) {
            _out?.cancel();
          } else {
            _closeSoon();
          }
        },
        onDismiss: close,
      ),
    );
    overlay.insert(_entry!);
    HardwareKeyboard.instance.addHandler(_key);
  }

  bool _key(KeyEvent event) {
    if (event is KeyDownEvent &&
        event.logicalKey == LogicalKeyboardKey.escape) {
      close();
      return true;
    }
    return false;
  }

  void close() {
    _in?.cancel();
    _out?.cancel();
    if (_entry != null) {
      HardwareKeyboard.instance.removeHandler(_key);
      _entry!.remove();
      _entry!.dispose();
      _entry = null;
    }
    _shown = null;
    _pending = null;
    _overCard = false;
  }

  void dispose() => close();
}

/// Wraps [child] so resting a mouse on it (500 ms) or long-pressing it
/// peeks at [request]. Renders nothing extra until then; no layout change.
class LinkPeek extends StatefulWidget {
  const LinkPeek({super.key, required this.request, required this.child});

  /// For the common case of a plain target.
  LinkPeek.target({
    Key? key,
    required NavTarget target,
    String? heading,
    String? block,
    required Widget child,
  }) : this(
         key: key,
         request: PeekRequest(target, heading: heading, block: block),
         child: child,
       );

  final PeekRequest request;
  final Widget child;

  @override
  State<LinkPeek> createState() => _LinkPeekState();
}

class _LinkPeekState extends State<LinkPeek> {
  late final _controller = LinkPeekController(context: () => context);

  Rect _anchor() {
    final box = context.findRenderObject();
    if (box is! RenderBox || !box.hasSize) return Rect.zero;
    return box.localToGlobal(Offset.zero) & box.size;
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (e) {
        if (e.kind == PointerDeviceKind.mouse) {
          _controller.hover(widget.request, _anchor());
        }
      },
      onExit: (_) => _controller.leave(),
      child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onLongPress: () => _controller.show(widget.request, _anchor()),
        child: widget.child,
      ),
    );
  }
}

class _PeekOverlay extends ConsumerWidget {
  const _PeekOverlay({
    required this.request,
    required this.anchor,
    required this.onHover,
    required this.onDismiss,
  });

  final PeekRequest request;
  final Rect anchor;
  final void Function(bool over) onHover;
  final VoidCallback onDismiss;

  static const width = 360.0;
  static const height = 240.0;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final screen = MediaQuery.sizeOf(context);
    final w = width.clamp(0.0, screen.width - 24);
    final left = anchor.left.clamp(12.0, screen.width - w - 12);
    final below =
        anchor.bottom + 6 + height < screen.height - 8 ||
        anchor.top < height + 14;
    final top = below
        ? anchor.bottom + 6
        : (anchor.top - 6 - height).clamp(8.0, screen.height);
    return Stack(
      children: [
        Positioned.fill(
          child: Listener(
            behavior: HitTestBehavior.translucent,
            onPointerDown: (_) => onDismiss(),
            onPointerSignal: (e) {
              // A wheel over the card scrolls it; elsewhere it dismisses.
              if (e is PointerScrollEvent) onDismiss();
            },
          ),
        ),
        Positioned(
          left: left,
          top: top,
          width: w,
          child: MouseRegion(
            onEnter: (_) => onHover(true),
            onExit: (_) => onHover(false),
            child: LinkPeekCard(
              request: request,
              onTap: () {
                onDismiss();
                openPeekRequest(context, ref, request);
              },
            ),
          ),
        ),
      ],
    );
  }
}

/// The card itself (also used directly in tests).
class LinkPeekCard extends ConsumerWidget {
  const LinkPeekCard({super.key, required this.request, this.onTap});

  final PeekRequest request;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final c = theme.colorScheme;
    final l10n = context.l10n;
    final data = ref.watch(linkPeekProvider(request));

    Widget content(PeekData d) {
      final title = d.kind == PeekKind.missing
          ? l10n.historyPeekMissing
          : d.title.trim().isEmpty
          ? l10n.commonUntitled
          : d.title.trim();
      final page = d.kind == PeekKind.paper && d.body != null
          ? l10n.historyPeekPage(int.tryParse(d.body!) ?? 0)
          : null;
      final String? body = switch (d.kind) {
        PeekKind.note => d.body!.isEmpty ? l10n.historyPeekEmpty : d.body,
        PeekKind.locked => l10n.historyPeekLocked,
        _ => null,
      };
      final sub = [
        if (d.subtitle != null && d.subtitle!.isNotEmpty) d.subtitle!,
        ?page,
      ].join(' · ');
      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              if (d.kind == PeekKind.locked) ...[
                Icon(Icons.lock_outline, size: 16, color: c.onSurfaceVariant),
                const SizedBox(width: 6),
              ],
              Expanded(
                child: Text(
                  title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: d.kind == PeekKind.missing
                        ? c.onSurfaceVariant
                        : null,
                  ),
                ),
              ),
            ],
          ),
          if (sub.isNotEmpty) ...[
            const SizedBox(height: 2),
            Text(
              sub,
              style: theme.textTheme.bodySmall?.copyWith(
                color: c.onSurfaceVariant,
              ),
            ),
          ],
          if (body != null) ...[
            const SizedBox(height: 8),
            Flexible(
              child: SingleChildScrollView(
                child: Text(
                  body,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: d.kind == PeekKind.locked
                        ? c.onSurfaceVariant
                        : null,
                  ),
                ),
              ),
            ),
          ],
        ],
      );
    }

    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: AppMotion.of(context, AppMotion.short),
      curve: AppMotion.enter,
      builder: (context, t, child) => Opacity(opacity: t, child: child),
      child: Material(
        key: const ValueKey('link-peek'),
        color: c.surfaceContainerHigh,
        elevation: 1,
        borderRadius: BorderRadius.circular(12),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(
              maxWidth: _PeekOverlay.width,
              maxHeight: _PeekOverlay.height,
            ),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: data.when(
                data: content,
                loading: () => const SizedBox(height: 24),
                error: (_, _) => content(const PeekData(PeekKind.missing)),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
