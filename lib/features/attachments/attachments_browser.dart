import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../l10n/l10n.dart';
import '../../theme/context_menu.dart';
import '../../theme/mac_list_row.dart';
import '../../theme/motion_widgets.dart';
import '../audio/audio_playback.dart';
import '../home/adaptive.dart' show ReadableColumn;
import '../markup/image_markup_screen.dart';
import '../platform/mac_window.dart';
import '../platform/share_origin.dart';
import '../projects/open_from_page.dart';
import 'attachments_providers.dart';

/// Every image, recording, link and file attached to notes and papers, in
/// one place (View → Attachments ⌘3 on a Mac, Search → Attachments
/// elsewhere).
Future<void> showAttachmentsBrowser(BuildContext context) =>
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => const AttachmentsBrowserScreen()),
    );

class AttachmentsBrowserScreen extends ConsumerStatefulWidget {
  const AttachmentsBrowserScreen({
    super.key,
    this.embedded = false,
    this.onLeave,
  });

  /// Just the browser, no page around it: the Mac window shows it in place
  /// of the list and the pane, under its own toolbar row.
  final bool embedded;

  /// Called before "Show in note/paper" opens the item, so an embedded
  /// browser can step aside for the pane.
  final VoidCallback? onLeave;

  @override
  ConsumerState<AttachmentsBrowserScreen> createState() =>
      _AttachmentsBrowserScreenState();
}

class _AttachmentsBrowserScreenState
    extends ConsumerState<AttachmentsBrowserScreen> {
  AttachmentKind? _kind;
  String _query = '';

  void _show(AttachmentEntry e) {
    widget.onLeave?.call();
    if (e.noteId != null) {
      openNoteFromPage(context, ref, e.noteId!);
    } else if (e.paperId != null) {
      openPaperFromPage(context, ref, e.paperId!);
    }
  }

  Future<void> _activate(AttachmentEntry e) async {
    final a = e.attachment;
    switch (e.kind) {
      case AttachmentKind.image:
        if (a.path == null) return;
        await Navigator.of(context).push(
          MaterialPageRoute<void>(
            fullscreenDialog: true,
            builder: (_) => AttachmentImageViewer(
              attachment: a,
              title: e.label,
              actions: [
                TextButton.icon(
                  onPressed: () {
                    Navigator.of(context).pop();
                    _show(e);
                  },
                  icon: const Icon(Icons.north_west, size: 18),
                  label: Text(
                    e.noteId != null
                        ? context.l10n.attachmentsShowInNote
                        : context.l10n.attachmentsShowInPaper,
                  ),
                ),
              ],
            ),
          ),
        );
      case AttachmentKind.audio:
        await ref.read(audioPlaybackProvider).open(a);
      case AttachmentKind.link:
        final uri = Uri.tryParse(a.url ?? '');
        if (uri != null) {
          await launchUrl(uri, mode: LaunchMode.externalApplication);
        }
      case AttachmentKind.file:
        await _share(e);
    }
  }

  Future<void> _share(AttachmentEntry e) async {
    final a = e.attachment;
    final origin = shareOrigin(context);
    final params = a.path != null && File(a.path!).existsSync()
        ? ShareParams(files: [XFile(a.path!)], sharePositionOrigin: origin)
        : (a.url != null
              ? ShareParams(
                  uri: Uri.tryParse(a.url!),
                  sharePositionOrigin: origin,
                )
              : null);
    if (params == null) return;
    await SharePlus.instance.share(params);
  }

  List<ContextMenuAction?> _actions(AttachmentEntry e) {
    final l10n = context.l10n;
    return [
      ContextMenuAction(
        label: e.noteId != null
            ? l10n.attachmentsShowInNote
            : l10n.attachmentsShowInPaper,
        icon: Icons.north_west,
        onSelected: () => _show(e),
      ),
      if (e.kind == AttachmentKind.image && e.attachment.path != null)
        ContextMenuAction(
          label: l10n.attachmentsMarkUp,
          icon: Icons.edit_outlined,
          onSelected: () => openImageMarkup(context, e.attachment),
        ),
      ContextMenuAction(
        label: l10n.commonShare,
        icon: Icons.ios_share,
        onSelected: () => _share(e),
      ),
      ContextMenuAction(
        label: l10n.attachmentsCopyName,
        icon: Icons.copy,
        onSelected: () => Clipboard.setData(ClipboardData(text: e.label)),
      ),
    ];
  }

  Future<void> _menuAt(AttachmentEntry e, Offset at) =>
      showContextMenuAt(context, at, _actions(e));

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final all = ref.watch(allAttachmentsProvider).value ?? const [];
    final kinds = [
      for (final k in AttachmentKind.values)
        if (all.any((e) => e.kind == k)) k,
    ];
    final kind = kinds.contains(_kind) ? _kind : null;
    final q = _query.trim().toLowerCase();
    final shown = [
      for (final e in all)
        if ((kind == null || e.kind == kind) &&
            (q.isEmpty ||
                e.label.toLowerCase().contains(q) ||
                e.parentName(l10n).toLowerCase().contains(q)))
          e,
    ];
    final mac = isDesktop(context);
    final images = [
      for (final e in shown)
        if (e.kind == AttachmentKind.image) e,
    ];
    final rows = [
      for (final e in shown)
        if (e.kind != AttachmentKind.image) e,
    ];

    final body = LayoutBuilder(
      builder: (context, box) {
        final side = mac ? macPanePadding(box.maxWidth) : 16.0;
        final width = mac ? box.maxWidth - 2 * side : box.maxWidth - 32;
        final cross = (width / (mac ? 170 : 130)).floor().clamp(2, 12);
        return CustomScrollView(
          slivers: [
            SliverPadding(
              padding: EdgeInsets.fromLTRB(side, 8, side, 8),
              sliver: SliverToBoxAdapter(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (all.length > 1)
                      TextField(
                        key: const ValueKey('attachments-search'),
                        decoration: InputDecoration(
                          hintText: l10n.attachmentsSearch,
                          prefixIcon: const Icon(Icons.search),
                        ),
                        onChanged: (v) => setState(() => _query = v),
                      ),
                    if (kinds.length > 1) ...[
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 8,
                        children: [
                          ChoiceChip(
                            label: Text(l10n.attachmentsAll),
                            selected: kind == null,
                            onSelected: (_) => setState(() => _kind = null),
                          ),
                          for (final k in kinds)
                            ChoiceChip(
                              label: Text(_kindLabel(l10n, k)),
                              selected: kind == k,
                              onSelected: (_) => setState(() => _kind = k),
                            ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ),
            if (shown.isEmpty)
              SliverFillRemaining(
                hasScrollBody: false,
                child: EmptyState(
                  icon: Icons.attach_file,
                  title: all.isEmpty
                      ? l10n.attachmentsEmptyTitle
                      : l10n.attachmentsNothingFound,
                  message: all.isEmpty
                      ? l10n.attachmentsEmptyMessage
                      : l10n.attachmentsNoMatch,
                ),
              ),
            if (images.isNotEmpty)
              SliverPadding(
                padding: EdgeInsets.fromLTRB(side, 8, side, 8),
                sliver: SliverGrid.builder(
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: cross,
                    mainAxisSpacing: 8,
                    crossAxisSpacing: 8,
                  ),
                  itemCount: images.length,
                  itemBuilder: (context, i) {
                    final e = images[i];
                    return _Thumb(
                      entry: e,
                      onTap: () => _activate(e),
                      onMenu: (at) => _menuAt(e, at),
                    );
                  },
                ),
              ),
            if (rows.isNotEmpty)
              SliverPadding(
                padding: EdgeInsets.symmetric(horizontal: mac ? side - 8 : 0),
                sliver: SliverList.builder(
                  itemCount: rows.length,
                  itemBuilder: (context, i) {
                    final e = rows[i];
                    return _Row(
                      entry: e,
                      mac: mac,
                      onTap: () => _activate(e),
                      onMenu: (at) => _menuAt(e, at),
                    );
                  },
                ),
              ),
            const SliverToBoxAdapter(child: SizedBox(height: 32)),
          ],
        );
      },
    );

    if (widget.embedded) return body;
    return Scaffold(
      appBar: AppBar(title: Text(l10n.attachmentsTitle)),
      body: mac ? body : ReadableColumn(child: body),
    );
  }
}

IconData _iconFor(AttachmentEntry e) => switch (e.kind) {
  AttachmentKind.image => Icons.image_outlined,
  AttachmentKind.audio => Icons.graphic_eq,
  AttachmentKind.link => Icons.link,
  AttachmentKind.file => Icons.attach_file,
};

String _kindLabel(AppLocalizations l10n, AttachmentKind k) => switch (k) {
  AttachmentKind.image => l10n.attachmentsKindImages,
  AttachmentKind.audio => l10n.attachmentsKindAudio,
  AttachmentKind.link => l10n.attachmentsKindLinks,
  AttachmentKind.file => l10n.attachmentsKindFiles,
};

String _date(BuildContext context, DateTime d) =>
    DateFormat.yMMMd(Localizations.localeOf(context).toString()).format(d);

class _Thumb extends StatelessWidget {
  const _Thumb({
    required this.entry,
    required this.onTap,
    required this.onMenu,
  });

  final AttachmentEntry entry;
  final VoidCallback onTap;
  final void Function(Offset) onMenu;

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).colorScheme;
    final path = entry.attachment.path;
    return Semantics(
      button: true,
      label: context.l10n.attachmentsImageFrom(
        entry.label,
        entry.parentName(context.l10n),
      ),
      child: GestureDetector(
        onTap: onTap,
        onSecondaryTapUp: (d) => onMenu(d.globalPosition),
        onLongPressStart: (d) => onMenu(d.globalPosition),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: ColoredBox(
            color: c.surfaceContainerHigh,
            child: path == null
                ? _placeholder(c)
                : Image.file(
                    File(path),
                    fit: BoxFit.cover,
                    cacheWidth: 400,
                    errorBuilder: (_, _, _) => _placeholder(c),
                  ),
          ),
        ),
      ),
    );
  }

  Widget _placeholder(ColorScheme c) => Center(
    child: Icon(Icons.image_not_supported_outlined, color: c.onSurfaceVariant),
  );
}

class _Row extends StatelessWidget {
  const _Row({
    required this.entry,
    required this.mac,
    required this.onTap,
    required this.onMenu,
  });

  final AttachmentEntry entry;
  final bool mac;
  final VoidCallback onTap;
  final void Function(Offset) onMenu;

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).colorScheme;
    final icon = Icon(_iconFor(entry), color: c.onSurfaceVariant, size: 22);
    final date = _date(context, entry.attachment.createdAt);
    final parent = entry.parentName(context.l10n);
    final child = mac
        ? MacListRow(
            leading: icon,
            title: Text(entry.label),
            subtitle: Text('$parent  ·  $date'),
            onTap: onTap,
          )
        : ListTile(
            leading: icon,
            title: Text(
              entry.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            subtitle: Text(
              '$parent  ·  $date',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            onTap: onTap,
            onLongPress: () {
              final box = context.findRenderObject() as RenderBox;
              onMenu(box.localToGlobal(box.size.center(Offset.zero)));
            },
          );
    return GestureDetector(
      behavior: HitTestBehavior.deferToChild,
      onSecondaryTapUp: (d) => onMenu(d.globalPosition),
      child: child,
    );
  }
}
