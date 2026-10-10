import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../theme/app_theme.dart';
import 'review_schedule.dart';
import 'review_screen.dart';

/// One quiet, dismissible line ("3 highlights to revisit"). Renders nothing
/// unless the reader switched on "Remind me on the home screen" on the
/// review screen, something is due, and it wasn't dismissed today.
///
/// Intended placement: at the top of the Notes/Library list area on home,
/// above the lists.
class ReviewPrompt extends ConsumerWidget {
  const ReviewPrompt({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(reviewSettingsProvider);
    final count = ref.watch(dueReviewCountProvider);
    final show =
        settings.loaded &&
        settings.remind &&
        count > 0 &&
        !settings.promptDismissedToday;
    final theme = Theme.of(context);
    return AnimatedSize(
      duration: AppMotion.of(context, AppMotion.medium),
      curve: AppMotion.enter,
      alignment: Alignment.topCenter,
      child: !show
          ? const SizedBox(width: double.infinity)
          : Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 8, 0),
              child: Row(
                children: [
                  Expanded(
                    child: InkWell(
                      borderRadius: BorderRadius.circular(8),
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => const ReviewScreen(),
                        ),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        child: Text(
                          count == 1
                              ? '1 highlight to revisit'
                              : '$count highlights to revisit',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: theme.colorScheme.primary,
                          ),
                        ),
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, size: 18),
                    tooltip: 'Dismiss until tomorrow',
                    onPressed: settings.dismissPromptToday,
                  ),
                ],
              ),
            ),
    );
  }
}
