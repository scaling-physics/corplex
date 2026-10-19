import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../../l10n/l10n.dart';
import '../library/citation_formatter.dart';
import 'citation_language.dart';
import 'csl_registry.dart';
import 'csl_style.dart';

/// Asks which reference style to use: every bundled CSL style, the
/// reader's own and "Add a style…" (imports a `.csl` file). The chosen
/// style is loaded before it is returned. Null if dismissed.
Future<CitationStyle?> pickCitationStyle(
  BuildContext context, {
  bool includeBibtex = false,
  String? title,
}) async {
  await CslRegistry.loadCustom();
  final choice = await CslRegistry.languageChoice();
  if (!context.mounted) return null;
  final picked = await showDialog<Object>(
    context: context,
    builder: (context) => _StylePickerDialog(
      includeBibtex: includeBibtex,
      title: title ?? context.l10n.cslReferenceStyle,
      initialChoice: choice,
    ),
  );
  if (picked is CitationStyle) {
    await picked.ensureLoaded();
    return picked;
  }
  if (picked == 'add' && context.mounted) {
    return importStyleFromFile(context);
  }
  return null;
}

class _StylePickerDialog extends StatefulWidget {
  const _StylePickerDialog({
    required this.includeBibtex,
    required this.title,
    required this.initialChoice,
  });

  final bool includeBibtex;
  final String title;
  final String? initialChoice;

  @override
  State<_StylePickerDialog> createState() => _StylePickerDialogState();
}

class _StylePickerDialogState extends State<_StylePickerDialog> {
  late String? _choice = widget.initialChoice;

  String _languageName(BuildContext context) {
    final l10n = context.l10n;
    if (_choice != null) return CitationLocales.labelFor(_choice!);
    final auto = CitationLocales.resolve(
      appLanguage: CslRegistry.appLanguage(),
    );
    return l10n.cslAutomaticWith(CitationLocales.labelFor(auto));
  }

  Future<void> _chooseLanguage() async {
    final picked = await showDialog<_LanguageChoice>(
      context: context,
      builder: (context) => _LanguageDialog(current: _choice),
    );
    if (picked == null) return;
    await CslRegistry.setLanguageChoice(picked.tag);
    if (mounted) setState(() => _choice = picked.tag);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    return SimpleDialog(
      title: Text(widget.title),
      children: [
        for (final s in CitationStyle.all)
          if (widget.includeBibtex || s != CitationStyle.bibtex)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(context, s),
              child: Text(s.label),
            ),
        const Divider(),
        SimpleDialogOption(
          onPressed: () => Navigator.pop(context, 'add'),
          child: Text(l10n.cslAddStyle),
        ),
        SimpleDialogOption(
          onPressed: _chooseLanguage,
          child: Text(
            l10n.cslCitationLanguageRow(_languageName(context)),
            style: Theme.of(context).textTheme.bodyMedium
                ?.copyWith(color: muted),
          ),
        ),
      ],
    );
  }
}

class _LanguageChoice {
  const _LanguageChoice(this.tag);
  final String? tag;
}

class _LanguageDialog extends StatelessWidget {
  const _LanguageDialog({required this.current});

  final String? current;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final auto = CitationLocales.resolve(
      appLanguage: CslRegistry.appLanguage(),
    );
    Widget row(String label, String? tag) => SimpleDialogOption(
      onPressed: () => Navigator.pop(context, _LanguageChoice(tag)),
      child: Row(
        children: [
          Expanded(child: Text(label)),
          if (current == tag) const Icon(Icons.check, size: 18),
        ],
      ),
    );
    return SimpleDialog(
      title: Text(l10n.cslCitationLanguage),
      children: [
        row(l10n.cslAutomaticWith(CitationLocales.labelFor(auto)), null),
        for (final l in CitationLocales.bundled) row(l.label, l.tag),
      ],
    );
  }
}

/// Lets the reader choose a `.csl` file and imports it. Shows a calm
/// message if it can't be used. Returns the new style, or null.
Future<CitationStyle?> importStyleFromFile(BuildContext context) async {
  final file = await FilePicker.pickFile(
    type: FileType.custom,
    allowedExtensions: ['csl', 'xml'],
  );
  final path = file?.path;
  if (path == null || !context.mounted) return null;
  try {
    final info = await CslRegistry.importFile(path);
    return CitationStyle.byName(info.name);
  } on CslFormatException catch (e) {
    if (context.mounted) await _notice(context, _messageFor(context, e));
  }
  return null;
}

Future<void> _notice(BuildContext context, String message) => showDialog<void>(
  context: context,
  builder: (context) => AlertDialog(
    title: Text(context.l10n.cslStyleCantBeUsed),
    content: Text(message),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: Text(context.l10n.commonOk),
      ),
    ],
  ),
);

/// [e]'s message in the app's language.
String _messageFor(BuildContext context, CslFormatException e) {
  final l10n = context.l10n;
  return switch (e.problem) {
    CslProblem.notXml => l10n.cslProblemNotXml,
    CslProblem.notStyle => l10n.cslProblemNotStyle,
    CslProblem.noInfo => l10n.cslProblemNoInfo,
    CslProblem.dependent => l10n.cslProblemDependent,
    CslProblem.wrongVersion => l10n.cslProblemWrongVersion,
    CslProblem.noLayout => l10n.cslProblemNoLayout,
    CslProblem.noBibliography => l10n.cslProblemNoBibliography,
    CslProblem.undefinedMacro => l10n.cslProblemUndefinedMacro(e.detail ?? ''),
    CslProblem.noTitle => l10n.cslProblemNoTitle,
    CslProblem.tooLarge => l10n.cslProblemTooLarge,
    CslProblem.unreadable => l10n.cslProblemUnreadable,
    null => e.message,
  };
}
