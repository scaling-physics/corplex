import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../l10n/l10n.dart';
import 'retraction.dart';

/// On the paper screen: one quiet line per notice that updates this paper
/// ("Retracted on 12 March 2024 — see the notice"), a link to the notice's
/// DOI. Retractions and withdrawals use the error tone, corrections and
/// concerns a neutral one. Nothing at all without notices (or offline with
/// nothing cached).
class RetractionNotice extends ConsumerWidget {
  const RetractionNotice({super.key, required this.doi});

  final String doi;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notices =
        ref.watch(noticeCheckProvider(doi)).value ??
        ref.watch(cachedNoticesProvider(doi)).value ??
        const <UpdateNotice>[];
    if (notices.isEmpty) return const SizedBox.shrink();
    final c = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final n in notices.take(4))
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: _NoticeRow(notice: n, scheme: c),
            ),
        ],
      ),
    );
  }
}

class _NoticeRow extends StatelessWidget {
  const _NoticeRow({required this.notice, required this.scheme});

  final UpdateNotice notice;
  final ColorScheme scheme;

  @override
  Widget build(BuildContext context) {
    final serious = notice.kind.isSerious;
    final bg = serious ? scheme.errorContainer : scheme.surfaceContainerHighest;
    final fg = serious ? scheme.onErrorContainer : scheme.onSurfaceVariant;
    final text = notice.messageFor(
      context.l10n,
      Localizations.localeOf(context).toString(),
    );
    return Semantics(
      link: true,
      label: text,
      child: Material(
        color: bg,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () =>
              launchUrl(notice.link, mode: LaunchMode.externalApplication),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(
              children: [
                Icon(
                  serious
                      ? Icons.warning_amber_rounded
                      : Icons.info_outline_rounded,
                  size: 18,
                  color: fg,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    text,
                    style: Theme.of(context).textTheme.bodyMedium
                        ?.copyWith(color: fg),
                  ),
                ),
                Icon(Icons.open_in_new_rounded, size: 16, color: fg),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A small warning icon for the Library list, only for a paper whose
/// *cached* notices include a retraction or withdrawal. Reads the cache,
/// never the network.
class RetractionMarker extends ConsumerWidget {
  const RetractionMarker({super.key, required this.doi, this.size = 16});

  final String? doi;
  final double size;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final d = doi;
    if (d == null || d.trim().isEmpty) return const SizedBox.shrink();
    final serious = (ref.watch(cachedNoticesProvider(d)).value ?? const []).any(
      (n) => n.kind.isSerious,
    );
    if (!serious) return const SizedBox.shrink();
    return Tooltip(
      message: context.l10n.libraryNoticeRetracted,
      child: Icon(
        Icons.warning_amber_rounded,
        size: size,
        semanticLabel: context.l10n.libraryNoticeRetracted,
        color: Theme.of(context).colorScheme.error,
      ),
    );
  }
}
