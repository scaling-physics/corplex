// ignore: unused_import
import 'package:intl/intl.dart' as intl;

import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get aliasesAdd => 'Add an alias';

  @override
  String aliasesAlso(String names) {
    return 'Also: $names';
  }

  @override
  String get aliasesMenu => 'Aliases…';

  @override
  String get aliasesMenuHint => 'Other names, found by [[ and in mentions';

  @override
  String get aliasesTitle => 'Aliases';

  @override
  String get attachmentsAddPodcastLink => 'Add podcast link';

  @override
  String get attachmentsAll => 'All';

  @override
  String get attachmentsAudio => 'Audio';

  @override
  String get attachmentsAudioHint =>
      'A NotebookLM audio overview, lecture or podcast file';

  @override
  String get attachmentsCopyName => 'Copy name';

  @override
  String get attachmentsEmptyMessage =>
      'Images, recordings, links and files you attach to notes and papers appear here.';

  @override
  String get attachmentsEmptyTitle => 'No attachments yet';

  @override
  String get attachmentsFile => 'File';

  @override
  String get attachmentsImage => 'Image';

  @override
  String attachmentsImageFrom(String name, String parent) {
    return 'Image $name, from $parent';
  }

  @override
  String get attachmentsKindAudio => 'Audio';

  @override
  String get attachmentsKindFiles => 'Files';

  @override
  String get attachmentsKindImages => 'Images';

  @override
  String get attachmentsKindLinks => 'Links';

  @override
  String get attachmentsMarkUp => 'Mark up';

  @override
  String get attachmentsNoMatch => 'No attachment matches.';

  @override
  String get attachmentsNothingFound => 'Nothing found';

  @override
  String get attachmentsPodcastLink => 'Podcast link';

  @override
  String get attachmentsPodcastLinkHint =>
      'A NotebookLM share link or audio URL';

  @override
  String get attachmentsPodcastLinkNote =>
      'Direct audio links (.mp3, .m4a…) play here. NotebookLM share links open in the browser — to listen and timestamp inside Corplex, download the audio overview and add it as Audio.';

  @override
  String get attachmentsRecordAudio => 'Record audio';

  @override
  String get attachmentsSearch => 'Search attachments';

  @override
  String get attachmentsShowInNote => 'Show in note';

  @override
  String get attachmentsShowInPaper => 'Show in paper';

  @override
  String get attachmentsTitle => 'Attachments';

  @override
  String get attachmentsUntitledPaper => 'Untitled paper';

  @override
  String get attachmentsVoiceNote => 'A voice note';

  @override
  String get attachmentsVoiceNoteTranscribed =>
      'A voice note, transcribed on this device';

  @override
  String get audioBack10 => 'Back 10 seconds';

  @override
  String get audioChannelName => 'Audio playback';

  @override
  String get audioClosePlayer => 'Close player';

  @override
  String get audioForward30 => 'Forward 30 seconds';

  @override
  String get audioMark => 'Mark';

  @override
  String get audioNotSynced =>
      'This recording hasn\'t synced to this device yet.';

  @override
  String get audioPause => 'Pause';

  @override
  String get audioPlay => 'Play';

  @override
  String get audioPlayFailed => 'Couldn\'t play this recording.';

  @override
  String get authConfirmEmail =>
      'Check your email to confirm your account, then sign in.';

  @override
  String get authCreateAccount => 'Create account';

  @override
  String get authCreateIntro =>
      'Your notes stay on this device and sync to your other devices once you\'re signed in.';

  @override
  String get authCreateTitle => 'Create your account';

  @override
  String get authEmail => 'Email';

  @override
  String get authInvalidEmail => 'Enter a valid email address.';

  @override
  String get authNoAccount => 'Don\'t have an account? Sign up';

  @override
  String get authOffline =>
      'Could not reach the server. Check your connection and try again.';

  @override
  String get authPassword => 'Password';

  @override
  String get authPasswordHelper => 'At least 6 characters';

  @override
  String get authShortPassword => 'Password must be at least 6 characters.';

  @override
  String get authSignIn => 'Sign in';

  @override
  String get authSignInIntro =>
      'Sign in to sync your notes and papers across your devices.';

  @override
  String authUnknown(String type) {
    return 'Something went wrong ($type). Try again.';
  }

  @override
  String get authWelcomeBack => 'Welcome back';

  @override
  String get calloutsCommand => 'Callout';

  @override
  String get calloutsCommandHint =>
      'Set a passage apart as a note, tip or warning';

  @override
  String calloutsLabel(String type) {
    return 'Callout: $type';
  }

  @override
  String get calloutsPickTitle => 'Callout type';

  @override
  String get calloutsRemove => 'Remove callout';

  @override
  String get calloutsTypeBug => 'Bug';

  @override
  String get calloutsTypeCaution => 'Caution';

  @override
  String get calloutsTypeDanger => 'Danger';

  @override
  String get calloutsTypeExample => 'Example';

  @override
  String get calloutsTypeImportant => 'Important';

  @override
  String get calloutsTypeInfo => 'Info';

  @override
  String get calloutsTypeNote => 'Note';

  @override
  String get calloutsTypeQuestion => 'Question';

  @override
  String get calloutsTypeSuccess => 'Success';

  @override
  String get calloutsTypeTip => 'Tip';

  @override
  String get calloutsTypeTodo => 'To do';

  @override
  String get calloutsTypeWarning => 'Warning';

  @override
  String get commentsAddComment => 'Add comment';

  @override
  String get commentsComment => 'Comment';

  @override
  String get commentsDeleted => 'Comment deleted';

  @override
  String get commentsEditComment => 'Edit comment';

  @override
  String get commentsEmpty => 'Select a passage, then choose Add comment.';

  @override
  String get commentsFromHint => 'e.g. Supervisor';

  @override
  String get commentsFromOptional => 'From (optional)';

  @override
  String get commentsNothingOpen => 'Nothing open.';

  @override
  String get commentsOnSelection => 'Comment on the selection';

  @override
  String commentsOpenCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count open comments',
      one: '1 open comment',
    );
    return '$_temp0';
  }

  @override
  String get commentsOptions => 'Comment options';

  @override
  String get commentsPassageChanged => 'Passage changed';

  @override
  String get commentsReopen => 'Reopen';

  @override
  String get commentsResolve => 'Resolve';

  @override
  String get commentsSelectAPassage => 'Select a passage to comment on';

  @override
  String commentsShowResolved(int count) {
    return 'Show resolved ($count)';
  }

  @override
  String get commentsTitle => 'Comments';

  @override
  String get commentsUnlockToAdd => 'Unlock your notes to add a comment.';

  @override
  String get commonAdd => 'Add';

  @override
  String get commonCancel => 'Cancel';

  @override
  String get commonClose => 'Close';

  @override
  String get commonCopied => 'Copied';

  @override
  String get commonCopy => 'Copy';

  @override
  String get commonDelete => 'Delete';

  @override
  String get commonDone => 'Done';

  @override
  String get commonEdit => 'Edit';

  @override
  String get commonImportPdf => 'Import PDF';

  @override
  String get commonLess => 'Less';

  @override
  String get commonLibrary => 'Library';

  @override
  String get commonLocked => 'Locked';

  @override
  String get commonMore => 'More';

  @override
  String get commonMoveToTrash => 'Move to trash';

  @override
  String get commonNewNote => 'New note';

  @override
  String get commonNotes => 'Notes';

  @override
  String get commonOk => 'OK';

  @override
  String get commonOpen => 'Open';

  @override
  String get commonProjects => 'Projects';

  @override
  String get commonRemove => 'Remove';

  @override
  String get commonRename => 'Rename';

  @override
  String get commonSave => 'Save';

  @override
  String get commonSearch => 'Search';

  @override
  String get commonSettings => 'Settings';

  @override
  String get commonShare => 'Share';

  @override
  String get commonTrash => 'Trash';

  @override
  String get commonTryAgain => 'Try again';

  @override
  String get commonUndo => 'Undo';

  @override
  String get commonUntitled => 'Untitled';

  @override
  String get cslAddStyle => 'Add a style…';

  @override
  String get cslAutomatic => 'Automatic';

  @override
  String cslAutomaticWith(String language) {
    return 'Automatic ($language)';
  }

  @override
  String get cslCitationLanguage => 'Citation language';

  @override
  String cslCitationLanguageRow(String language) {
    return 'Citation language: $language';
  }

  @override
  String get cslProblemDependent =>
      'This style is a small variant that points to a parent style. Import the parent style instead.';

  @override
  String get cslProblemNoBibliography =>
      'That style has no bibliography section, so it can\'t format reference lists.';

  @override
  String get cslProblemNoInfo => 'That style has no title or ID block.';

  @override
  String get cslProblemNoLayout =>
      'That style is missing its layout, so it can\'t format references.';

  @override
  String get cslProblemNoTitle => 'That style has no title.';

  @override
  String get cslProblemNotStyle =>
      'That file isn\'t a citation style (.csl) file.';

  @override
  String get cslProblemNotXml =>
      'That file isn\'t valid XML, so it can\'t be a citation style.';

  @override
  String get cslProblemTooLarge => 'That file is too large to be a style.';

  @override
  String cslProblemUndefinedMacro(String name) {
    return 'That style uses an undefined macro \"$name\".';
  }

  @override
  String get cslProblemUnreadable => 'Couldn\'t read that file.';

  @override
  String get cslProblemWrongVersion => 'Only CSL 1.0 styles are supported.';

  @override
  String get cslReferenceStyle => 'Reference style';

  @override
  String get cslStyleCantBeUsed => 'That style can\'t be used';

  @override
  String get dailyFolder => 'Folder';

  @override
  String get dailyKeyTodaysNote => 'Today\'s note';

  @override
  String get dailyNext => 'Next day\'s note';

  @override
  String get dailyNoEarlier => 'No earlier daily note';

  @override
  String get dailyNoLater => 'No later daily note';

  @override
  String get dailyNone => 'None';

  @override
  String get dailyPrevious => 'Previous day\'s note';

  @override
  String get dailySettingsSubtitle => 'Template and folder for today\'s note';

  @override
  String get dailySettingsTitle => 'Daily notes';

  @override
  String get dailyTemplate => 'Template';

  @override
  String get dailyTemplateHint =>
      'Use a note as a template (note menu) to choose one here.';

  @override
  String get dailyTodaysNote => 'Today\'s note';

  @override
  String get dataNewerVersion =>
      'This backup was made by a newer version of Corplex. Update the app first.';

  @override
  String get dataNotABackup => 'That file isn’t a Corplex backup.';

  @override
  String get dataUnsupportedVersion =>
      'This backup is from an unsupported version.';

  @override
  String get editorAddBibliography => 'Add bibliography';

  @override
  String get editorAddPaperAndCite => 'Add this paper and cite it?';

  @override
  String get editorAddToProject => 'Add to project';

  @override
  String editorAddedReferences(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Added $count references',
      one: 'Added 1 reference',
    );
    return '$_temp0';
  }

  @override
  String get editorAttach => 'Attach audio, image or file';

  @override
  String get editorBibliographyHint =>
      'A reference list of what this note cites';

  @override
  String get editorCiteHint => 'Or type [@ while writing';

  @override
  String get editorCmdAttach => 'Attach';

  @override
  String get editorCmdAttachHint => 'Audio, an image or a file';

  @override
  String get editorCmdBibliography => 'Add bibliography';

  @override
  String get editorCmdBibliographyHint =>
      'A reference list of what this note cites';

  @override
  String get editorCmdChecklist => 'Checklist';

  @override
  String get editorCmdChecklistHint => 'Tick-box items';

  @override
  String get editorCmdCite => 'Cite a paper';

  @override
  String get editorCmdCiteHint => 'Insert a citation from your library';

  @override
  String get editorCmdDictate => 'Dictate';

  @override
  String get editorCmdDictateHint => 'Speak instead of typing';

  @override
  String get editorCmdDraw => 'Draw';

  @override
  String get editorCmdDrawHint => 'A sketch, with a pen or finger';

  @override
  String get editorCmdEquation => 'Equation';

  @override
  String get editorCmdEquationHint => 'LaTeX maths, or type \$\$';

  @override
  String get editorCmdFigure => 'Figure caption';

  @override
  String get editorCmdFigureHint => 'A numbered figure caption for this line';

  @override
  String get editorCmdHeading => 'Heading';

  @override
  String get editorCmdHeadingHint => 'Make this line a heading';

  @override
  String get editorCmdInsertTable => 'Table';

  @override
  String get editorCmdInsertTableHint => 'Rows and columns, 3 by 3 to start';

  @override
  String get editorCmdLink => 'Link to a note';

  @override
  String get editorCmdLinkHint => 'Or type [[';

  @override
  String get editorCmdRefer => 'Refer to a figure or table';

  @override
  String get editorCmdReferHint =>
      'Insert its number, kept right as things move';

  @override
  String get editorCmdTable => 'Table caption';

  @override
  String get editorCmdTableHint => 'A numbered table caption for this line';

  @override
  String get editorCmdTemplate => 'Literature note template';

  @override
  String get editorCmdTemplateHint => 'Summary, method, findings, critique';

  @override
  String get editorCmdVoice => 'Voice note';

  @override
  String get editorCmdVoiceHint => 'Record a thought as you read';

  @override
  String get editorDraw => 'Draw';

  @override
  String editorEditDate(String date, String time) {
    return '$date at $time';
  }

  @override
  String get editorExport => 'Export';

  @override
  String get editorExportHint => 'Markdown, Word or PDF, with references';

  @override
  String get editorFindInNote => 'Find in note';

  @override
  String get editorImageTapToEnlarge => 'Image, tap to enlarge';

  @override
  String get editorLinkPaper => 'Link a paper';

  @override
  String get editorLinkToNote => 'Link to a note';

  @override
  String get editorLinkToNoteHint => 'Or type [[ while writing';

  @override
  String get editorLinkedFrom => 'Linked from';

  @override
  String get editorLockHint => 'Needs your notes password to open';

  @override
  String get editorLockedTapToLock => 'Locked — tap to lock now';

  @override
  String get editorLookupUnreachable =>
      'Couldn\'t reach the lookup service. The link is unchanged.';

  @override
  String get editorMoveToFolder => 'Move to folder';

  @override
  String get editorNoCitations =>
      'No citations to list yet. Type [@ to cite a paper.';

  @override
  String editorNoPaperFound(String id) {
    return 'No paper found for $id.';
  }

  @override
  String get editorNoteLockedFiles =>
      'Note locked. Attached files (images, audio, PDFs) aren\'t encrypted — only the note\'s text and sketches.';

  @override
  String get editorPaperRemoved => 'That paper was removed.';

  @override
  String get editorPrint => 'Print…';

  @override
  String get editorRecordingRemoved => 'That recording was removed.';

  @override
  String get editorSelectPassage => 'Select the passage to comment on.';

  @override
  String get editorStartWriting => 'Start writing…';

  @override
  String get editorStyleBody => 'Body text';

  @override
  String get editorStyleHeading => 'Heading';

  @override
  String get editorStyleHighlight => 'Highlight';

  @override
  String get editorStyleMonospaced => 'Monospaced';

  @override
  String get editorStyleQuote => 'Quote';

  @override
  String get editorStyleStrike => 'Strikethrough';

  @override
  String get editorStyleSubheading => 'Subheading';

  @override
  String get editorStyleTable => 'Table';

  @override
  String get editorStyleTitle => 'Title';

  @override
  String get editorTags => 'Tags';

  @override
  String get editorTemplate => 'Literature note template';

  @override
  String get editorTemplateHint => 'Summary, method, findings, critique';

  @override
  String get editorTextStyle => 'Text style';

  @override
  String editorTipBold(String shortcut) {
    return 'Bold $shortcut';
  }

  @override
  String editorTipBulleted(String shortcut) {
    return 'Bulleted list $shortcut';
  }

  @override
  String editorTipChecklist(String shortcut) {
    return 'Checklist $shortcut';
  }

  @override
  String editorTipHighlight(String shortcut) {
    return 'Highlight $shortcut';
  }

  @override
  String editorTipItalic(String shortcut) {
    return 'Italic $shortcut';
  }

  @override
  String editorTipNumbered(String shortcut) {
    return 'Numbered list $shortcut';
  }

  @override
  String editorTipUnderline(String shortcut) {
    return 'Underline $shortcut';
  }

  @override
  String get editorTitleHint => 'Title';

  @override
  String get editorTypewriter => 'Typewriter scrolling';

  @override
  String get editorTypewriterHint => 'Keep the line you type centred';

  @override
  String get editorWordCount => 'Word count';

  @override
  String get editorWordCountHint => 'And reading time';

  @override
  String get exportCitationsAndReferences => 'Citations and references';

  @override
  String get exportCouldntCreateFile => 'Couldn\'t create that file.';

  @override
  String get exportFormatLatex => 'LaTeX (Overleaf)';

  @override
  String get exportFormatMarkdown => 'Markdown';

  @override
  String get exportFormatPdf => 'PDF';

  @override
  String get exportFormatWord => 'Word document';

  @override
  String get exportUnlockNoteToContinue => 'Unlock this note to continue.';

  @override
  String get exportUnlockNotesToContinue =>
      'Unlock your locked notes to continue.';

  @override
  String findCount(int current, int total) {
    return '$current of $total';
  }

  @override
  String get findHideReplace => 'Hide replace';

  @override
  String get findNext => 'Next';

  @override
  String get findNotFound => 'Not found';

  @override
  String get findPrevious => 'Previous';

  @override
  String get findReplace => 'Replace';

  @override
  String get findReplaceAll => 'All';

  @override
  String get findReplaceWith => 'Replace with';

  @override
  String get foldCollapseAll => 'Collapse all sections';

  @override
  String get foldCollapseSection => 'Collapse section';

  @override
  String get foldExpandAll => 'Expand all sections';

  @override
  String get foldExpandSection => 'Expand section';

  @override
  String get foldShowSection => 'Show section';

  @override
  String get footnotesCommand => 'Footnote';

  @override
  String get footnotesCommandHint => 'A note at the foot of the page';

  @override
  String get footnotesEditTitle => 'Footnote';

  @override
  String get footnotesHint => 'Write the footnote';

  @override
  String footnotesLabel(String number) {
    return 'Footnote $number';
  }

  @override
  String footnotesStatsInFootnotes(String count) {
    return '+$count in footnotes';
  }

  @override
  String get graphCouldntDraw => 'Couldn’t draw the map';

  @override
  String get graphEmptyMessage =>
      'Link notes to each other or to papers, or cite a paper with [@, and the connections appear here.';

  @override
  String get graphHideUnconnected => 'Hide unconnected items';

  @override
  String get graphLockedNote => 'Locked note';

  @override
  String get graphMap => 'Map';

  @override
  String get graphNothingConnected => 'Nothing connected';

  @override
  String get graphNothingToMap => 'Nothing to map yet';

  @override
  String get graphShowUnconnected => 'Show unconnected items';

  @override
  String get graphTryAgainInAMoment => 'Try again in a moment.';

  @override
  String get graphUntitledPaper => 'Untitled paper';

  @override
  String get highlightsAddComment => 'Add a comment';

  @override
  String get highlightsAddCommentMenu => 'Add a comment…';

  @override
  String get highlightsButter => 'Butter highlight';

  @override
  String get highlightsDelete => 'Delete highlight';

  @override
  String get highlightsEditCommentMenu => 'Edit comment…';

  @override
  String get highlightsEmptyMessage =>
      'Select text in a PDF and choose Highlight; it will collect here.';

  @override
  String get highlightsEmptyTitle => 'No highlights yet';

  @override
  String get highlightsHighlight => 'Highlight';

  @override
  String get highlightsMist => 'Mist highlight';

  @override
  String get highlightsNoMatches => 'No matches.';

  @override
  String get highlightsQuoteToNote => 'Quote to note';

  @override
  String get highlightsRevisit => 'Revisit highlights';

  @override
  String get highlightsRose => 'Rose highlight';

  @override
  String get highlightsSage => 'Sage highlight';

  @override
  String get highlightsSearchHint => 'Search your highlights';

  @override
  String get highlightsSelectHint =>
      'Select text on a page, then tap Highlight.';

  @override
  String get highlightsTooltip => 'Highlights';

  @override
  String get homeAttachments => 'Attachments';

  @override
  String homeCountItems(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count items',
      one: '1 item',
      zero: 'No items',
    );
    return '$_temp0';
  }

  @override
  String homeCountNotes(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count notes',
      one: '1 note',
      zero: 'No notes',
    );
    return '$_temp0';
  }

  @override
  String homeCountPapers(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count papers',
      one: '1 paper',
      zero: 'No papers',
    );
    return '$_temp0';
  }

  @override
  String get homeImportFirstPaper => 'Import your first paper';

  @override
  String get homeImportPdfTooltip => 'Import PDF (⌘O)';

  @override
  String get homeNewNoteTooltip => 'New Note (⌘N)';

  @override
  String get homePickNote => 'Pick a note, or start a new one.';

  @override
  String get homePickPaper => 'Pick a paper to read, annotate and cite.';

  @override
  String get homeSearchSubtitle => 'Notes, papers and highlights';

  @override
  String get homeShowAttachments => 'Show Attachments';

  @override
  String get homeShowSidebarTooltip => 'Show Sidebar (⌃⌘S)';

  @override
  String get homeStepHighlightText =>
      'Press and hold on the text, then Highlight or Quote to note.';

  @override
  String get homeStepHighlightTitle => 'Highlight as you read';

  @override
  String get homeStepImportText =>
      'A PDF from Files. Its title, authors and year fill in by themselves.';

  @override
  String get homeStepImportTitle => 'Import a paper';

  @override
  String get homeStepWriteText =>
      'In a note, type / for tools, or [@ to cite a paper.';

  @override
  String get homeStepWriteTitle => 'Write and cite';

  @override
  String get homeWelcome => 'Welcome to Corplex';

  @override
  String get homeWelcomeSubtitle =>
      'Read, annotate, take notes and cite in one place.';

  @override
  String get inkBlue => 'Blue';

  @override
  String get inkClay => 'Clay';

  @override
  String get inkColor => 'Ink color';

  @override
  String get inkColour => 'Colour';

  @override
  String get inkConvertToText => 'Convert to text';

  @override
  String get inkDrawHere => 'Draw here';

  @override
  String get inkDrawWithFingers => 'Draw with fingers';

  @override
  String get inkDrawing => 'Drawing';

  @override
  String get inkDuplicate => 'Duplicate';

  @override
  String get inkEraser => 'Eraser';

  @override
  String get inkExpand => 'Expand';

  @override
  String get inkFingersDraw =>
      'Fingers draw (tap to scroll with fingers instead)';

  @override
  String get inkFingersScroll => 'Fingers scroll (tap to draw with fingers)';

  @override
  String get inkGraphite => 'Graphite';

  @override
  String get inkHighlighter => 'Highlighter';

  @override
  String get inkMoreOptions => 'More drawing options';

  @override
  String get inkMoreSpace => 'More space';

  @override
  String get inkNoHandwriting => 'No handwriting found';

  @override
  String get inkPaste => 'Paste';

  @override
  String get inkPen => 'Pen';

  @override
  String get inkRedo => 'Redo';

  @override
  String get inkSage => 'Sage';

  @override
  String get inkScrollWithFingers => 'Scroll with fingers';

  @override
  String get inkSelect => 'Select';

  @override
  String get inkTapToDraw => 'Tap to draw';

  @override
  String get inkThickness => 'Line thickness';

  @override
  String get libraryAddById => 'Add by DOI or arXiv ID';

  @override
  String get libraryAddByIdHint =>
      '10.1038/nature14539, arXiv:1706.03762 or PMID: 9500320';

  @override
  String get libraryAddToProject => 'Add to project…';

  @override
  String libraryAddedPapers(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count papers',
      one: '1 paper',
    );
    return 'Added $_temp0';
  }

  @override
  String get libraryAll => 'All';

  @override
  String get libraryAllHighlights => 'All highlights';

  @override
  String get libraryAllHighlightsHint => 'Across every paper';

  @override
  String get libraryAlreadyInLibrary => 'Already in your library.';

  @override
  String libraryAlreadyInLibraryCount(int count) {
    return '$count already in your library';
  }

  @override
  String get libraryCitationCopied => 'Citation copied';

  @override
  String get libraryCitationsAdded => 'Added to your library.';

  @override
  String get libraryCitationsCitedBy => 'Cited by';

  @override
  String get libraryCitationsInLibrary => 'In your library';

  @override
  String get libraryCitationsLoadMore => 'Load more';

  @override
  String get libraryCitationsLoadMoreFailed =>
      'Couldn’t load more. Try again online.';

  @override
  String get libraryCitationsLoading => 'Loading…';

  @override
  String libraryCitationsMoreNotShown(int count) {
    return '$count more not shown.';
  }

  @override
  String get libraryCitationsNoCiting => 'No citing papers found.';

  @override
  String get libraryCitationsNoReferences => 'No references listed.';

  @override
  String get libraryCitationsNotFound =>
      'OpenAlex has no record of this paper.';

  @override
  String get libraryCitationsReferences => 'References';

  @override
  String get libraryCitationsRefresh => 'Refresh';

  @override
  String get libraryCitationsRefreshFailed =>
      'Couldn’t refresh. Try again online.';

  @override
  String get libraryCitationsRetry => 'Retry';

  @override
  String get libraryCitationsTitle => 'References · Cited by';

  @override
  String get libraryCitationsUnreachable =>
      'Couldn’t reach OpenAlex. Try again online.';

  @override
  String get libraryCopyCitation => 'Copy citation';

  @override
  String get libraryEmptyMessage =>
      'Tap Import PDF to add a paper, or link one from a note.';

  @override
  String get libraryEmptyTitle => 'Your library is empty';

  @override
  String libraryError(String error) {
    return 'Something went wrong: $error';
  }

  @override
  String get libraryExportBibtex => 'Export as BibTeX';

  @override
  String libraryFoundDetails(String title) {
    return 'Found the details for “$title”';
  }

  @override
  String get libraryImportReferences => 'Import references';

  @override
  String get libraryImportReferencesHint =>
      'BibTeX, RIS or CSL JSON (Zotero, Mendeley)';

  @override
  String get libraryImportZotero => 'Import from Zotero…';

  @override
  String get libraryIsEmpty => 'Your library is empty.';

  @override
  String get libraryLocatorChapter => 'Chapter';

  @override
  String get libraryLocatorFigure => 'Figure';

  @override
  String get libraryLocatorLine => 'Line';

  @override
  String get libraryLocatorNote => 'Note';

  @override
  String get libraryLocatorPage => 'Page';

  @override
  String get libraryLocatorParagraph => 'Paragraph';

  @override
  String get libraryLocatorSection => 'Section';

  @override
  String get libraryLocatorVolume => 'Volume';

  @override
  String get libraryLookingUp => 'Looking it up…';

  @override
  String libraryLooksDuplicate(String title) {
    return 'Looks like “$title” is already here.';
  }

  @override
  String get libraryLookupUnreachable =>
      'Couldn\'t reach the lookup service. Try again online.';

  @override
  String get libraryNoMatches => 'No matches';

  @override
  String get libraryNoMatchesHint => 'Try a different title or author.';

  @override
  String libraryNoPaperFound(String id) {
    return 'No paper found for $id.';
  }

  @override
  String get libraryNoReferencesFound => 'No references found in that file.';

  @override
  String get libraryNotAnIdentifier =>
      'That doesn\'t look like a DOI, arXiv or PubMed ID.';

  @override
  String get libraryNoticeConcern => 'Expression of concern issued';

  @override
  String get libraryNoticeCorrected => 'Corrected';

  @override
  String get libraryNoticeDatePattern => 'd MMMM y';

  @override
  String libraryNoticeOn(String kind, String date) {
    return '$kind on $date — see the notice';
  }

  @override
  String get libraryNoticeRetracted => 'Retracted';

  @override
  String libraryNoticeUndated(String kind) {
    return '$kind — see the notice';
  }

  @override
  String get libraryNoticeWithdrawn => 'Withdrawn';

  @override
  String get libraryOpenPdf => 'Open PDF';

  @override
  String get librarySearchPapers => 'Search papers';

  @override
  String get libraryShowAttachments => 'Show Attachments';

  @override
  String get libraryStatusDone => 'Done';

  @override
  String get libraryStatusReading => 'Reading';

  @override
  String get libraryStatusToRead => 'To read';

  @override
  String get linksCmdEmbed => 'Embed a note';

  @override
  String get linksCmdEmbedHint => 'Show another note here, live. Or type ![[';

  @override
  String get linksEmbedANote => 'Embed a note…';

  @override
  String get linksEmbedEmpty => 'Empty note';

  @override
  String get linksEmbedLocked => 'Locked';

  @override
  String get linksEmbedMissing => 'Note not found';

  @override
  String linksEmbedOpen(String title) {
    return 'Open $title';
  }

  @override
  String get linksEmbedSectionMissing => 'Section not found';

  @override
  String get linksEmbedShowAll => 'Show all';

  @override
  String get linksEmbedShowLess => 'Show less';

  @override
  String get linksHeadingsOf => 'Headings';

  @override
  String get linksLinkMention => 'Link';

  @override
  String linksMentionLinked(String title) {
    return 'Linked in “$title”';
  }

  @override
  String get linksNoHeadings => 'No headings in this note';

  @override
  String get linksNoParagraphs => 'No paragraphs in this note';

  @override
  String get linksParagraphUnavailable => 'Couldn\'t mark that paragraph';

  @override
  String get linksPartsLocked => 'A locked note can only be linked as a whole.';

  @override
  String get linksToParagraph => 'Link to a paragraph';

  @override
  String get linksToParagraphHint => 'Or type Title#^';

  @override
  String linksUnlinkedMentions(int count) {
    return 'Unlinked mentions ($count)';
  }

  @override
  String get listAddToProject => 'Add to project…';

  @override
  String get listAll => 'All';

  @override
  String get listCreate => 'Create';

  @override
  String get listDeleteFolderEllipsis => 'Delete folder…';

  @override
  String get listDeleteFolderMessage =>
      'Notes inside will be unfiled, not deleted.';

  @override
  String listDeleteFolderTitle(String name) {
    return 'Delete “$name”?';
  }

  @override
  String get listDeleteTagEllipsis => 'Delete tag…';

  @override
  String get listDeleteTagMessage => 'This removes the tag from every note.';

  @override
  String listDeleteTagTitle(String name) {
    return 'Delete “#$name”?';
  }

  @override
  String get listDuplicate => 'Duplicate';

  @override
  String get listFolderName => 'Folder name';

  @override
  String get listFolderOrTag => 'Folder or tag';

  @override
  String get listLockNote => 'Lock note';

  @override
  String get listNewFolder => 'New folder';

  @override
  String get listNewTag => 'New tag';

  @override
  String get listNoNotesMessage =>
      'Tap New note to capture your first thought.';

  @override
  String get listNoNotesTitle => 'No notes yet';

  @override
  String get listNothingHereMessage =>
      'Notes you add while this filter is on land here.';

  @override
  String get listNothingHereTitle => 'Nothing here yet';

  @override
  String get listPinToTop => 'Pin to top';

  @override
  String get listPinned => 'Pinned';

  @override
  String get listPrevious30Days => 'Previous 30 Days';

  @override
  String get listPrevious7Days => 'Previous 7 Days';

  @override
  String get listRemoveLock => 'Remove lock';

  @override
  String listSomethingWentWrong(String error) {
    return 'Something went wrong: $error';
  }

  @override
  String get listTagName => 'Tag name';

  @override
  String get listToday => 'Today';

  @override
  String get listUnpin => 'Unpin';

  @override
  String get listYesterday => 'Yesterday';

  @override
  String get lockBiometricFaceTouch => 'Face ID / Touch ID';

  @override
  String get lockBiometricFingerprint => 'fingerprint';

  @override
  String get lockBiometricGeneric => 'biometrics';

  @override
  String get lockBiometricReason => 'Unlock your locked notes';

  @override
  String get lockBiometricSubtitle => 'Open locked notes without typing';

  @override
  String get lockBiometricTouch => 'Touch ID';

  @override
  String get lockChangePassword => 'Change password';

  @override
  String get lockChangeTitle => 'Change notes password';

  @override
  String get lockConfirm => 'Confirm';

  @override
  String get lockContinue => 'Continue';

  @override
  String get lockCurrentPassword => 'Current password';

  @override
  String get lockCurrentWrong => 'The current password is wrong.';

  @override
  String get lockEarlierPassword => 'This note uses an earlier notes password';

  @override
  String get lockEnterPassword => 'Enter your notes password.';

  @override
  String get lockEnterToTurnOn => 'Enter your notes password to turn this on.';

  @override
  String get lockForgottenWarning =>
      'If you forget this password, locked notes can\'t be recovered — not by you, and not by us.';

  @override
  String lockHint(String hint) {
    return 'Hint: $hint';
  }

  @override
  String get lockHintHelper => 'Shown on the lock screen. Not the password!';

  @override
  String get lockHintOptional => 'Hint (optional)';

  @override
  String get lockLockedNote => 'This note is locked';

  @override
  String lockMinLength(int count) {
    return 'Use at least $count characters.';
  }

  @override
  String get lockMismatch => 'The passwords don\'t match.';

  @override
  String get lockNewMismatch => 'The new passwords don\'t match.';

  @override
  String get lockNewPassword => 'New password';

  @override
  String get lockNotNow => 'Not now';

  @override
  String get lockNotesPassword => 'Notes password';

  @override
  String get lockNow => 'Lock now';

  @override
  String get lockNowSubtitle => 'Locked notes ask for the password again';

  @override
  String lockOfferBody(String name) {
    return 'Open locked notes with $name instead of typing the password. The password still works.';
  }

  @override
  String lockOfferTitle(String name) {
    return 'Use $name to unlock?';
  }

  @override
  String get lockPassword => 'Password';

  @override
  String get lockPasswordChanged => 'Notes password changed';

  @override
  String get lockResetBody =>
      'You\'ll choose a new password for notes you lock from now on.\n\nNotes already locked stay locked under the old password. Without it they can\'t be opened — not by you, and not by us. If you remember the old password later, entering it opens them again.';

  @override
  String get lockResetDialogTitle => 'Reset the notes password?';

  @override
  String get lockResetItem => 'Reset password…';

  @override
  String get lockResetItemSubtitle => 'For a forgotten password';

  @override
  String get lockResetPassword => 'Reset password';

  @override
  String get lockResetTitle => 'Reset notes password';

  @override
  String get lockSetPassword => 'Set password';

  @override
  String get lockSetTitle => 'Set a notes password';

  @override
  String get lockShowHint => 'Show hint';

  @override
  String get lockUnlock => 'Unlock';

  @override
  String get lockUnlockToContinue => 'Unlock your locked notes to continue.';

  @override
  String lockUseBiometric(String name) {
    return 'Use $name';
  }

  @override
  String get lockWrongPassword => 'Wrong password';

  @override
  String get macAllNotes => 'All Notes';

  @override
  String get macAllPapers => 'All Papers';

  @override
  String get macCreate => 'Create';

  @override
  String get macDeleteFolder => 'Delete Folder…';

  @override
  String get macDeleteTag => 'Delete Tag…';

  @override
  String get macFolderNameHint => 'Folder name';

  @override
  String get macHideSidebarTooltip => 'Hide Sidebar (⌃⌘S)';

  @override
  String get macKeyActualSize => 'Actual size';

  @override
  String get macKeyAddComment => 'Add comment';

  @override
  String get macKeyAttachments => 'Attachments';

  @override
  String get macKeyBack => 'Back';

  @override
  String get macKeyBlockQuote => 'Block quote';

  @override
  String get macKeyBody => 'Body';

  @override
  String get macKeyBold => 'Bold';

  @override
  String get macKeyBulletedList => 'Bulleted list';

  @override
  String get macKeyChecklist => 'Checklist';

  @override
  String get macKeyCitePaper => 'Cite a paper';

  @override
  String get macKeyCloseDialog => 'Close a dialog or menu';

  @override
  String get macKeyCloseWindow => 'Close window';

  @override
  String get macKeyDefaultInterface => 'Default interface size';

  @override
  String get macKeyDuplicateNote => 'Duplicate note';

  @override
  String get macKeyFindInDocument => 'Find in document';

  @override
  String get macKeyFindNext => 'Find next';

  @override
  String get macKeyFindPrevious => 'Find previous';

  @override
  String get macKeyHeading => 'Heading';

  @override
  String get macKeyHighlight => 'Highlight';

  @override
  String get macKeyImportPdf => 'Import PDF';

  @override
  String get macKeyItalic => 'Italic';

  @override
  String get macKeyLargerInterface => 'Larger interface';

  @override
  String get macKeyLibrary => 'Library';

  @override
  String get macKeyLinkNote => 'Link to a note';

  @override
  String get macKeyMonospaced => 'Monospaced';

  @override
  String get macKeyMoveThroughList => 'Move through a list';

  @override
  String get macKeyMoveToTrash => 'Move to Trash';

  @override
  String get macKeyNewNote => 'New note';

  @override
  String get macKeyNextColumn => 'Next or previous column';

  @override
  String get macKeyNotes => 'Notes';

  @override
  String get macKeyNumberedList => 'Numbered list';

  @override
  String get macKeyOpenSelected => 'Open the selected item';

  @override
  String get macKeyPrint => 'Print';

  @override
  String get macKeyQuickNote => 'Quick note from anywhere';

  @override
  String get macKeySearch => 'Search';

  @override
  String get macKeySettings => 'Settings';

  @override
  String get macKeyShortcuts => 'Keyboard shortcuts';

  @override
  String get macKeySidebar => 'Show or hide the sidebar';

  @override
  String get macKeySmallerInterface => 'Smaller interface';

  @override
  String get macKeyStrikethrough => 'Strikethrough';

  @override
  String get macKeySubheading => 'Subheading';

  @override
  String get macKeyTable => 'Table';

  @override
  String get macKeyTitle => 'Title';

  @override
  String get macKeyUnderline => 'Underline';

  @override
  String get macKeyZoomIn => 'Zoom in';

  @override
  String get macKeyZoomOut => 'Zoom out';

  @override
  String get macMoreMenu => 'More…';

  @override
  String get macNewFolderTitle => 'New folder';

  @override
  String get macNewFolderTooltip => 'New Folder';

  @override
  String get macOpenProjectPage => 'Open Project Page';

  @override
  String get macRenameFolder => 'Rename Folder…';

  @override
  String get macRenameFolderTitle => 'Rename folder';

  @override
  String macSectionCollapsed(String title) {
    return '$title, collapsed';
  }

  @override
  String macSectionExpanded(String title) {
    return '$title, expanded';
  }

  @override
  String get macShortcutsFormatting => 'Notes & Formatting';

  @override
  String get macShortcutsGeneral => 'General';

  @override
  String get macShortcutsNavigation => 'Navigation';

  @override
  String get macShortcutsReader => 'Library & Reader';

  @override
  String get macShortcutsTitle => 'Keyboard Shortcuts';

  @override
  String get macTags => 'Tags';

  @override
  String get markupMarkUp => 'Mark up';

  @override
  String get markupOpenFailed => 'Couldn\'t open this image.';

  @override
  String get markupSaveFailed => 'Couldn\'t save the marks.';

  @override
  String get matrixAddDefaults => 'Add method, sample, findings';

  @override
  String get matrixAddStudyColumns => 'Add study columns';

  @override
  String get matrixAddTheme => 'Add a theme';

  @override
  String get matrixAllNotHereYet => 'All the ones not here yet';

  @override
  String get matrixAlreadyAColumn => 'Already a column';

  @override
  String get matrixCellHint => 'What does this paper say?';

  @override
  String get matrixColumnFindings => 'Findings';

  @override
  String get matrixColumnMethod => 'Method';

  @override
  String get matrixColumnSample => 'Sample';

  @override
  String get matrixCopiedAsMarkdown => 'Table copied as Markdown';

  @override
  String get matrixCopyAsMarkdown => 'Copy as Markdown';

  @override
  String get matrixDeleteColumn => 'Delete column';

  @override
  String get matrixDeleteTheme => 'Delete theme and its notes';

  @override
  String get matrixEmptyMessage =>
      'Add the themes you are comparing — method, sample, findings — and fill in what each paper says.';

  @override
  String get matrixEmptyTitle => 'Compare papers side by side';

  @override
  String get matrixExport => 'Export';

  @override
  String get matrixFromHighlights => 'From your highlights';

  @override
  String get matrixFromStudyDetails => 'From study details';

  @override
  String get matrixNewTheme => 'New theme';

  @override
  String get matrixNoPapers => 'No papers in this project';

  @override
  String get matrixNoPapersMessage =>
      'Add papers to it from their screens, then compare them here.';

  @override
  String get matrixPapersKeepDetails => 'Papers keep their study details';

  @override
  String get matrixRenameTheme => 'Rename theme';

  @override
  String get matrixSeparateWithSemicolon => 'Separate with ;';

  @override
  String get matrixShare => 'Share…';

  @override
  String matrixShareSubject(String project) {
    return '$project matrix';
  }

  @override
  String get mdImportAction => 'Import Markdown or Obsidian vault';

  @override
  String get mdImportActionSubtitle => 'A folder, .md files or a zip';

  @override
  String get mdImportChooseTitle => 'Import Markdown';

  @override
  String get mdImportDoneTitle => 'Import finished';

  @override
  String get mdImportFiles => 'Markdown files';

  @override
  String get mdImportFolder => 'A folder (an Obsidian vault)';

  @override
  String get mdImportNothing => 'No Markdown notes were found there.';

  @override
  String mdImportProgress(int done, int total) {
    return 'Importing $done of $total…';
  }

  @override
  String get mdImportReadFailed => 'That couldn\'t be read.';

  @override
  String get mdImportReading => 'Reading files…';

  @override
  String mdImportSummaryAttachments(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count attachments copied',
      one: '1 attachment copied',
    );
    return '$_temp0';
  }

  @override
  String mdImportSummaryFailed(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count notes couldn\'t be saved',
      one: '1 note couldn\'t be saved',
    );
    return '$_temp0';
  }

  @override
  String mdImportSummaryNotes(int notes) {
    String _temp0 = intl.Intl.pluralLogic(
      notes,
      locale: localeName,
      other: '$notes notes imported',
      one: '1 note imported',
      zero: 'No notes imported',
    );
    return '$_temp0';
  }

  @override
  String mdImportSummarySkipped(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count skipped (already here, locked, or paper pages)',
      one: '1 skipped (already here, locked, or a paper page)',
    );
    return '$_temp0';
  }

  @override
  String mdImportSummaryUnresolved(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count links matched nothing and were left as text',
      one: '1 link matched nothing and was left as text',
    );
    return '$_temp0';
  }

  @override
  String get mdImportZip => 'A zip of Markdown files';

  @override
  String get notesAddTag => 'Add tag';

  @override
  String get notesBeforeRestoring => 'Before restoring';

  @override
  String get notesChangePage => 'Change page';

  @override
  String notesCitationLabel(String label) {
    return 'Citation $label';
  }

  @override
  String notesCitationMissingLabel(String marker) {
    return 'Citation $marker, paper not found';
  }

  @override
  String notesCitationNotInLibrary(String key) {
    return '@$key isn\'t in your library.';
  }

  @override
  String get notesCiteAPaper => 'Cite a paper';

  @override
  String get notesClear => 'Clear';

  @override
  String get notesCompare => 'Compare';

  @override
  String notesCompareChanged(
    String when,
    String words,
    int added,
    int removed,
  ) {
    return '$when · now has $words words · $added added, $removed removed';
  }

  @override
  String notesCompareSame(String when) {
    return '$when · the same as now';
  }

  @override
  String get notesCouldntAddFile => 'Couldn\'t add that file.';

  @override
  String get notesCouldntDuplicate => 'Couldn\'t duplicate that note.';

  @override
  String get notesCouldntPrint => 'Couldn\'t print that note.';

  @override
  String get notesCreate => 'Create';

  @override
  String get notesDropToAttach => 'Drop to attach';

  @override
  String get notesDuplicate => 'Duplicate';

  @override
  String get notesEquationEmpty => 'Tap to write an equation';

  @override
  String notesEquationLabel(String latex) {
    return 'Equation $latex';
  }

  @override
  String notesFigureCaptionLabel(String name) {
    return '$name caption';
  }

  @override
  String get notesFigureMissing => 'Figure ??';

  @override
  String notesFigureName(String number) {
    return 'Figure $number';
  }

  @override
  String notesFigureReferenceLabel(String name) {
    return 'Reference to $name';
  }

  @override
  String get notesFigureReferenceMissing => 'Reference to a missing figure';

  @override
  String get notesFiguresEmpty =>
      'No figures or tables yet. Type / and choose Figure caption or Table caption.';

  @override
  String get notesFolderName => 'Folder name';

  @override
  String get notesHighlightBlue => 'Blue';

  @override
  String get notesHighlightGreen => 'Green';

  @override
  String get notesHighlightPink => 'Pink';

  @override
  String get notesHighlightPurple => 'Purple';

  @override
  String get notesHighlightYellow => 'Yellow';

  @override
  String get notesImportAPdf => 'Import a PDF';

  @override
  String get notesLatexHint => 'LaTeX, e.g. x^2 + \\alpha';

  @override
  String get notesLatexInvalid =>
      'Not valid LaTeX yet. It is kept as you typed it.';

  @override
  String get notesLessThanAMinute => '< 1 min';

  @override
  String get notesLinkToANote => 'Link to a note…';

  @override
  String get notesLockNote => 'Lock note';

  @override
  String notesMinutes(int count) {
    return '$count min';
  }

  @override
  String get notesNewFolder => 'New folder';

  @override
  String notesNewNoteNamed(String title) {
    return 'New note “$title”';
  }

  @override
  String get notesNewTagName => 'New tag name';

  @override
  String get notesNoFolder => 'No folder';

  @override
  String get notesNoPapersFound => 'No papers found.';

  @override
  String get notesNoTagsYet => 'No tags yet.';

  @override
  String get notesNoteLocked => 'Note locked';

  @override
  String get notesNothingMatches => 'Nothing matches.';

  @override
  String get notesOpenPaper => 'Open paper';

  @override
  String get notesPage => 'Page';

  @override
  String get notesPageEllipsis => 'Page…';

  @override
  String get notesPageHint => '42 or 3–5';

  @override
  String notesPageShort(int page) {
    return 'p. $page';
  }

  @override
  String get notesPinToTop => 'Pin to top';

  @override
  String get notesPreview => 'Preview';

  @override
  String get notesRemoveHighlight => 'Remove highlight';

  @override
  String get notesRemoveLock => 'Remove lock';

  @override
  String get notesRenameVersion => 'Rename version';

  @override
  String get notesRestore => 'Restore';

  @override
  String get notesRestoreThisVersion => 'Restore this version';

  @override
  String notesRestoreVersionMessage(String label) {
    return 'The note goes back to this version. What is there now is saved first as “$label”.';
  }

  @override
  String get notesRestoreVersionTitle => 'Restore this version?';

  @override
  String get notesSaveAVersion => 'Save a version';

  @override
  String get notesSaveVersionNow => 'Save a version now';

  @override
  String get notesSavedVersion => 'Saved version';

  @override
  String get notesSearchFigures => 'Search figures and tables';

  @override
  String get notesSearchPapersToLink => 'Search papers to link';

  @override
  String get notesSentToSupervisor => 'Sent to supervisor';

  @override
  String get notesSet => 'Set';

  @override
  String get notesStatsCharacters => 'Characters';

  @override
  String get notesStatsCitations => 'Citations';

  @override
  String get notesStatsLinkedPapers => 'Linked papers';

  @override
  String get notesStatsParagraphs => 'Paragraphs';

  @override
  String get notesStatsReadingTime => 'Reading time';

  @override
  String get notesStatsWords => 'Words';

  @override
  String get notesTableMissing => 'Table ??';

  @override
  String notesTableName(String number) {
    return 'Table $number';
  }

  @override
  String get notesTemplateCritique => 'Critique';

  @override
  String get notesTemplateFindings => 'Findings';

  @override
  String get notesTemplateMethod => 'Method';

  @override
  String get notesTemplateSummary => 'Summary';

  @override
  String notesUnchangedLines(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count unchanged lines',
      one: '1 unchanged line',
    );
    return '$_temp0';
  }

  @override
  String get notesUnlock => 'Unlock';

  @override
  String get notesUnlockToCompare =>
      'Unlock this note to compare its versions.';

  @override
  String get notesUnlockToCompareOrRestore =>
      'Unlock this note to compare or restore versions.';

  @override
  String get notesUnlockToDuplicate => 'Unlock this note to duplicate it.';

  @override
  String get notesUnlockToPrint => 'Unlock this note to print it.';

  @override
  String get notesUnlockToRestore => 'Unlock the note to restore it.';

  @override
  String get notesUnpin => 'Unpin';

  @override
  String get notesVersionDeleted => 'Version deleted';

  @override
  String get notesVersionNameHint => 'Name (optional)';

  @override
  String get notesVersionOptions => 'Version options';

  @override
  String get notesVersionRestored => 'Version restored';

  @override
  String get notesVersions => 'Versions';

  @override
  String get notesVersionsEmptyMessage =>
      'A version is a saved copy of this note. One is kept automatically when a chapter goes to your supervisor, and you can save one any time.';

  @override
  String get notesVersionsEmptyTitle => 'No versions yet';

  @override
  String notesVersionsSince(String delta) {
    return '$delta since';
  }

  @override
  String notesVersionsWords(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count words',
      one: '1 word',
    );
    return '$_temp0';
  }

  @override
  String ocrReadingText(int percent) {
    return 'Reading text… $percent%';
  }

  @override
  String get ocrRecogniseText => 'Recognise text';

  @override
  String get ocrRecogniseTextHint => 'Search and highlight a scan';

  @override
  String get paperAbstract => 'Abstract';

  @override
  String get paperAddToProject => 'Add to project';

  @override
  String get paperAttachmentsEmpty =>
      'Podcasts, images, links or files for this paper.';

  @override
  String paperAttachmentsError(String error) {
    return 'Could not load attachments: $error';
  }

  @override
  String get paperAuthorsHelper => 'Separate authors with ;';

  @override
  String get paperAuthorsHint => 'Authors';

  @override
  String get paperCitation => 'Citation';

  @override
  String get paperCitationStyle => 'Citation style';

  @override
  String paperContinueReading(int page) {
    return 'Continue reading · p. $page';
  }

  @override
  String get paperDetails => 'Details';

  @override
  String get paperDownloadFileFailed =>
      'Couldn\'t download the file. Try again.';

  @override
  String get paperDownloadPdf => 'Download PDF';

  @override
  String get paperDownloadPdfFailed => 'Couldn\'t download the PDF. Try again.';

  @override
  String get paperDownloading => 'Downloading…';

  @override
  String get paperEditAuthors => 'Edit authors';

  @override
  String get paperEnterIdentifier => 'Enter a DOI, arXiv or PubMed ID first.';

  @override
  String get paperExportWithHighlights => 'Export with highlights';

  @override
  String get paperFilledIn => 'Filled in the missing details.';

  @override
  String get paperHighlights => 'Highlights';

  @override
  String get paperIdentifierLabel => 'DOI, arXiv or PubMed ID';

  @override
  String get paperLink => 'Link';

  @override
  String get paperLookUp => 'Look up';

  @override
  String get paperLookupUnreachable => 'Couldn\'t reach the lookup service.';

  @override
  String get paperMoreStyles => 'More…';

  @override
  String get paperNothingNew => 'Nothing new to fill in.';

  @override
  String get paperOpenInPubmed => 'Open in PubMed';

  @override
  String get paperOpenLink => 'Open link';

  @override
  String paperPageShort(int page) {
    return 'p. $page';
  }

  @override
  String get paperProject => 'Project';

  @override
  String get paperPubmedId => 'PubMed ID';

  @override
  String get paperReadWithNote => 'Read with a note';

  @override
  String get paperReferencedInNotes => 'Referenced in notes';

  @override
  String get paperTitleHint => 'Title';

  @override
  String get paperVenue => 'Journal or conference';

  @override
  String get paperYear => 'Year';

  @override
  String get platformUntitledPaper => 'Untitled paper';

  @override
  String platformWidgetPage(int page) {
    return 'p. $page';
  }

  @override
  String get projectsAbbrCopyAsText => 'Copy as text';

  @override
  String projectsAbbrDefined(int count) {
    return '$count defined';
  }

  @override
  String get projectsAbbrList => 'List';

  @override
  String get projectsAbbrListTitle => 'List of abbreviations';

  @override
  String projectsAbbrNeverSpelled(int count) {
    return 'Never spelled out ($count)';
  }

  @override
  String projectsAbbrToCheck(int count) {
    return '$count to check';
  }

  @override
  String projectsAbbrUsedBefore(String abbreviation) {
    return '$abbreviation is used before it\'s spelled out';
  }

  @override
  String get projectsAbbreviations => 'Abbreviations';

  @override
  String get projectsAddChapter => 'Add chapter';

  @override
  String get projectsBibliography => 'Bibliography';

  @override
  String projectsBibliographySubject(String project) {
    return '$project bibliography';
  }

  @override
  String get projectsBibliographySubtitle =>
      'All its papers, in a citation style';

  @override
  String get projectsChangeDate => 'Change date';

  @override
  String get projectsChangeDueDate => 'Change due date';

  @override
  String get projectsChangeStatus => 'Change status';

  @override
  String projectsChapterCitations(int chapter, int count) {
    return 'Ch. $chapter · $count×';
  }

  @override
  String get projectsChapterOptions => 'Chapter options';

  @override
  String get projectsChapters => 'Chapters';

  @override
  String projectsChaptersFinal(int finished, int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count chapters',
      one: '1 chapter',
    );
    return '$finished of $_temp0 final';
  }

  @override
  String get projectsChaptersLockedReason =>
      'Some chapters are locked. Unlock them to include them.';

  @override
  String get projectsCitations => 'Citations';

  @override
  String projectsCitedInChapters(int count) {
    return 'Cited in chapters ($count)';
  }

  @override
  String projectsCitedOutside(int count) {
    return 'Cited, not in this project ($count)';
  }

  @override
  String get projectsClearDate => 'Clear date';

  @override
  String get projectsClearDueDate => 'Clear due date';

  @override
  String get projectsCreateAndAdd => 'Create and add';

  @override
  String get projectsDatePattern => 'd MMMM';

  @override
  String get projectsDatePatternYear => 'd MMMM y';

  @override
  String projectsDaysAgo(int days) {
    String _temp0 = intl.Intl.pluralLogic(
      days,
      locale: localeName,
      other: '$days days ago',
      one: '1 day ago',
    );
    return '$_temp0';
  }

  @override
  String get projectsDeleteMessage =>
      'The papers and notes in it stay in your library; only the grouping goes away.';

  @override
  String get projectsDeleteProject => 'Delete project';

  @override
  String get projectsDeleteProjectSubtitle => 'Its papers and notes are kept';

  @override
  String projectsDeleteTitle(String name) {
    return 'Delete “$name”?';
  }

  @override
  String projectsDue(String date, String rest) {
    return 'Due $date · $rest';
  }

  @override
  String projectsDueToday(String date) {
    return 'Due today · $date';
  }

  @override
  String get projectsExportCancelledLocked =>
      'Export cancelled: chapters are locked.';

  @override
  String get projectsExportProject => 'Export project';

  @override
  String get projectsExportProjectSubtitle => 'Its notes as one document';

  @override
  String get projectsFigureTodo => 'Figure';

  @override
  String projectsHighlightCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count highlights',
      one: '1 highlight',
    );
    return '$_temp0';
  }

  @override
  String projectsInDays(int days) {
    String _temp0 = intl.Intl.pluralLogic(
      days,
      locale: localeName,
      other: '$days days',
      one: '1 day',
    );
    return '$_temp0';
  }

  @override
  String get projectsMap => 'Map';

  @override
  String get projectsNeedsCitation => 'Needs a citation';

  @override
  String get projectsNewProject => 'New project';

  @override
  String get projectsNoNotesYet => 'No notes in this project yet.';

  @override
  String get projectsNoPapersYet => 'No papers in this project yet.';

  @override
  String get projectsNoStatus => 'No status';

  @override
  String projectsNoteCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count notes',
      one: '1 note',
    );
    return '$_temp0';
  }

  @override
  String get projectsNothingYet => 'Nothing here yet';

  @override
  String get projectsNothingYetMessage =>
      'Use “Add to project” on a paper or a note to collect it here.';

  @override
  String get projectsOpenProject => 'Open project';

  @override
  String get projectsOpenProjectSubtitle =>
      'Its papers, notes and reading progress';

  @override
  String projectsPaperCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count papers',
      one: '1 paper',
    );
    return '$_temp0';
  }

  @override
  String get projectsPapers => 'Papers';

  @override
  String get projectsPickerIntro =>
      'A project groups the papers and notes for one review, chapter or paper you\'re writing.';

  @override
  String projectsReadNotCited(int count) {
    return 'Read but not cited ($count)';
  }

  @override
  String projectsReadProgress(int done, int total) {
    return '$done of $total read';
  }

  @override
  String get projectsRemoveFromProject => 'Remove from project';

  @override
  String get projectsRenameProject => 'Rename project';

  @override
  String get projectsSetDueDate => 'Set due date';

  @override
  String get projectsStatus => 'Status';

  @override
  String get projectsStatusDraft => 'Draft';

  @override
  String get projectsStatusFinal => 'Final';

  @override
  String get projectsStatusOutline => 'Outline';

  @override
  String get projectsStatusRead => 'Read';

  @override
  String get projectsStatusReading => 'Reading';

  @override
  String get projectsStatusRevised => 'Revised';

  @override
  String get projectsStatusToRead => 'To read';

  @override
  String get projectsStatusWithSupervisor => 'With supervisor';

  @override
  String get projectsSubmissionDate => 'Submission date';

  @override
  String get projectsSubmissionDateSubtitle => 'The submission date';

  @override
  String get projectsSynthesisMatrix => 'Synthesis matrix';

  @override
  String get projectsSynthesisMatrixSubtitle => 'Compare its papers by theme';

  @override
  String get projectsTodoWord => 'TODO';

  @override
  String projectsTodosTitle(int count) {
    return 'To do in the writing ($count)';
  }

  @override
  String get projectsWordTarget => 'Word target';

  @override
  String get projectsWordTargetHint => 'e.g. 8000';

  @override
  String projectsWords(int words) {
    final intl.NumberFormat wordsNumberFormat =
        intl.NumberFormat.decimalPattern(localeName);
    final String wordsString = wordsNumberFormat.format(words);

    String _temp0 = intl.Intl.pluralLogic(
      words,
      locale: localeName,
      other: '$wordsString words',
      one: '1 word',
    );
    return '$_temp0';
  }

  @override
  String projectsWordsOfTarget(int words, int target) {
    final intl.NumberFormat wordsNumberFormat =
        intl.NumberFormat.decimalPattern(localeName);
    final String wordsString = wordsNumberFormat.format(words);
    final intl.NumberFormat targetNumberFormat =
        intl.NumberFormat.decimalPattern(localeName);
    final String targetString = targetNumberFormat.format(target);

    return '$wordsString / $targetString words';
  }

  @override
  String get readAloudBack => 'Back to reading';

  @override
  String get readAloudFinished => 'Finished';

  @override
  String get readAloudNext => 'Next sentence';

  @override
  String get readAloudNoText => 'No text to read';

  @override
  String get readAloudPause => 'Pause';

  @override
  String get readAloudPlay => 'Play';

  @override
  String get readAloudPreparing => 'Preparing…';

  @override
  String get readAloudPrevious => 'Previous sentence';

  @override
  String get readAloudSpeed => 'Speed';

  @override
  String get readAloudStop => 'Stop reading';

  @override
  String get reviewCaughtUp => 'All caught up';

  @override
  String get reviewDismiss => 'Dismiss until tomorrow';

  @override
  String get reviewEmptyMessage =>
      'Highlights come back here a day after you make them, then less and less often.';

  @override
  String get reviewKeep => 'Keep';

  @override
  String get reviewLater => 'The ones you kept will return in a while.';

  @override
  String get reviewNothing => 'Nothing to revisit';

  @override
  String get reviewOpenInPaper => 'Open in paper';

  @override
  String reviewPosition(int current, int total) {
    return '$current of $total';
  }

  @override
  String reviewPrompt(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count highlights to revisit',
      one: '1 highlight to revisit',
    );
    return '$_temp0';
  }

  @override
  String reviewQuote(String quote) {
    return '“$quote”';
  }

  @override
  String get reviewRemind => 'Remind me on the home screen';

  @override
  String get reviewRemindHint => 'A single quiet line when something is due';

  @override
  String get reviewSkip => 'Skip';

  @override
  String reviewSource(String title, int page) {
    return '$title · p. $page';
  }

  @override
  String get reviewTitle => 'Revisit highlights';

  @override
  String get reviewTomorrow => 'They will come back tomorrow.';

  @override
  String get savedSearchDelete => 'Delete';

  @override
  String savedSearchDeleted(String name) {
    return 'Deleted “$name”';
  }

  @override
  String get savedSearchDialogTitle => 'Save search';

  @override
  String get savedSearchHeading => 'Saved searches';

  @override
  String get savedSearchNameLabel => 'Name';

  @override
  String get savedSearchRename => 'Rename';

  @override
  String get savedSearchRenameTitle => 'Rename search';

  @override
  String get savedSearchSave => 'Save this search';

  @override
  String get savedSearchSection => 'Saved Searches';

  @override
  String get savedSearchTipsBody =>
      '\"exact phrase\" and -word to leave a word out\ntag:name, folder:name, project:name\nin:notes, in:papers, in:highlights, in:pdfs\nis:pinned, is:template, is:daily\nPut - in front of any of these to exclude it. Use quotes for names with spaces: tag:\"deep learning\"';

  @override
  String get savedSearchTipsLink => 'Search tips';

  @override
  String get searchAttachments => 'Attachments';

  @override
  String get searchClear => 'Clear';

  @override
  String get searchEmptyMessage =>
      'Find a note, a paper, or a passage you highlighted.';

  @override
  String get searchEmptyTitle => 'Search everything';

  @override
  String get searchHint => 'Search notes, papers and highlights';

  @override
  String get searchIndexing => 'Indexing papers…';

  @override
  String get searchKindHighlights => 'Highlights';

  @override
  String get searchKindInPapers => 'In papers';

  @override
  String get searchKindPapers => 'Papers';

  @override
  String get searchMap => 'Map';

  @override
  String get searchNoMatches => 'No matches';

  @override
  String get searchNoMatchesHint => 'Try fewer or different words.';

  @override
  String searchPage(int page) {
    return 'p. $page';
  }

  @override
  String get settingsAppearance => 'Appearance';

  @override
  String get settingsBackUp => 'Back up to a file';

  @override
  String get settingsBackUpSubtitle => 'Notes, papers and files in one zip';

  @override
  String get settingsBackupFailed => 'Couldn\'t create the backup.';

  @override
  String get settingsBackupSubject => 'Corplex backup';

  @override
  String get settingsCantRestore => 'Can\'t restore';

  @override
  String get settingsClearAndSignOut => 'Clear and sign out';

  @override
  String get settingsClearTitle => 'Clear this device?';

  @override
  String settingsErasePending(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other:
          '$count changes on this device haven\'t synced and will be lost for good. Everything else is safe in your account.',
      one: '1 change on this device hasn\'t synced and will be lost for good. Everything else is safe in your account.',
    );
    return '$_temp0';
  }

  @override
  String get settingsEraseSafe =>
      'Notes, papers and files on this device will be removed. Everything is safe in your account.';

  @override
  String get settingsExport => 'Export';

  @override
  String get settingsExportBody =>
      'One Markdown file per note and paper, with links, highlights and a BibTeX file. Open the folder as an Obsidian vault.';

  @override
  String get settingsExportFailed => 'Couldn\'t create the export.';

  @override
  String get settingsExportLocked =>
      'Locked notes are exported as placeholders.';

  @override
  String get settingsExportMarkdown => 'Export as Markdown';

  @override
  String get settingsExportMarkdownSubtitle => 'A folder of notes for Obsidian';

  @override
  String get settingsExportSubject => 'Corplex notes (Markdown)';

  @override
  String get settingsIncludePdfs => 'Include PDFs';

  @override
  String get settingsIncludePdfsSubtitle => 'Makes the export much larger';

  @override
  String get settingsInterfaceSize => 'Interface size';

  @override
  String get settingsInterfaceSizeSubtitle => 'For large or ultrawide displays';

  @override
  String get settingsOnDemand => 'Download files when opened';

  @override
  String get settingsOnDemandSubtitle =>
      'Otherwise papers and audio download in the background.';

  @override
  String get settingsOneMoreStep => 'One more step';

  @override
  String get settingsPreparingBackup => 'Preparing backup…';

  @override
  String get settingsQuickNote => 'Quick note shortcut (⌃⌥N)';

  @override
  String get settingsQuickNoteSubtitle => 'Start a note from any app';

  @override
  String get settingsReadingNight => 'Night';

  @override
  String get settingsReadingPaper => 'Paper';

  @override
  String get settingsReadingSepia => 'Sepia';

  @override
  String get settingsReplace => 'Replace';

  @override
  String get settingsReplaceTitle => 'Replace this device\'s data?';

  @override
  String get settingsRestartToFinish =>
      'Close Corplex completely and open it again to finish restoring.';

  @override
  String get settingsRestoreAction => 'Restore';

  @override
  String settingsRestoreBody(String date, int notes, int papers) {
    String _temp0 = intl.Intl.pluralLogic(
      notes,
      locale: localeName,
      other: '$notes notes',
      one: '1 note',
    );
    String _temp1 = intl.Intl.pluralLogic(
      papers,
      locale: localeName,
      other: '$papers papers',
      one: '1 paper',
    );
    return 'From $date: $_temp0 and $_temp1.\n\nIt replaces what\'s on this device now. Your current library is kept aside in case you change your mind.';
  }

  @override
  String get settingsRestoreFromBackup => 'Restore from a backup';

  @override
  String get settingsRestoreTitle => 'Restore this backup?';

  @override
  String get settingsSignIn => 'Sign in';

  @override
  String get settingsSignInSubtitle => 'Sync your library across devices';

  @override
  String get settingsSignOut => 'Sign out';

  @override
  String get settingsSignOutClear => 'Sign out and clear this device';

  @override
  String get settingsSpellCheck => 'Check spelling while typing';

  @override
  String get settingsSyncFailed => 'Sync failed';

  @override
  String get settingsSyncNow => 'Sync now';

  @override
  String get settingsSyncOffline => 'Not syncing';

  @override
  String get settingsSyncSyncing => 'Syncing…';

  @override
  String get settingsSyncUpToDate => 'Up to date';

  @override
  String get settingsThemeAuto => 'Auto';

  @override
  String get settingsThemeDark => 'Dark';

  @override
  String get settingsThemeLight => 'Light';

  @override
  String settingsTrashCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count items',
      one: '1 item',
    );
    return '$_temp0';
  }

  @override
  String get settingsUseThisAccount => 'Use this account on this device';

  @override
  String get settingsUseThisAccountSubtitle =>
      'Replaces what\'s on this device with this account\'s data.';

  @override
  String get settingsWifiOnly => 'Send files on Wi-Fi only';

  @override
  String get settingsWifiOnlySubtitle =>
      'Notes always sync. Opening a file downloads it on any network.';

  @override
  String shareAddedToLibrary(String name) {
    return 'Added “$name” to your library';
  }

  @override
  String shareAttachTo(String name) {
    return 'Attach “$name” to…';
  }

  @override
  String get shareAudioAttached => 'Audio attached';

  @override
  String get shareNewNote => 'A new note';

  @override
  String get shareSavedAsNote => 'Saved as a note';

  @override
  String get shareSavedLink => 'Saved link as a note';

  @override
  String get spellIgnore => 'Ignore Spelling';

  @override
  String get spellIgnoreGrammar => 'Ignore Grammar';

  @override
  String get spellLearn => 'Learn Spelling';

  @override
  String get studyAdd => 'Add study details';

  @override
  String get studyChip => 'Study';

  @override
  String studyChipCount(int count) {
    return 'Study · $count';
  }

  @override
  String get studyClear => 'Clear';

  @override
  String get studyClearFilter => 'Clear study filter';

  @override
  String get studyDetails => 'Study details';

  @override
  String get studyFieldBrainRegions => 'Brain regions';

  @override
  String get studyFieldParadigm => 'Task / paradigm';

  @override
  String get studyFieldSampleSize => 'Sample size (n)';

  @override
  String get studyFieldSpecies => 'Species / model';

  @override
  String get studyFieldTechniques => 'Techniques';

  @override
  String get studyListHint => 'Press enter or comma to add';

  @override
  String get studyMinSampleSize => 'Minimum sample size (n)';

  @override
  String get syncAccountMismatch =>
      'This device holds data from a different account. Sign back in to that account to sync.';

  @override
  String get syncFilesIncomplete => 'Some files haven\'t synced yet.';

  @override
  String get syncGenericError =>
      'Couldn\'t sync. Your notes are safe on this device.';

  @override
  String get syncServerOutdated =>
      'Your sync server needs a database update. Run the newest files in supabase/migrations on your Supabase project.';

  @override
  String get tableAddColumnLeft => 'Add column left';

  @override
  String get tableAddColumnRight => 'Add column right';

  @override
  String get tableAddRowAbove => 'Add row above';

  @override
  String get tableAddRowBelow => 'Add row below';

  @override
  String get tableDeleteColumn => 'Delete column';

  @override
  String get tableDeleteRow => 'Delete row';

  @override
  String get tableDeleteTable => 'Delete table';

  @override
  String get tableHeaderRow => 'Header row';

  @override
  String get tableTooltip => 'Table';

  @override
  String get templatesInsert => 'Insert template';

  @override
  String get templatesInsertHint => 'Fill one of your templates in here';

  @override
  String get templatesLiterature => 'Literature note';

  @override
  String get templatesStopUsing => 'Stop using as template';

  @override
  String get templatesTitle => 'Templates';

  @override
  String get templatesUnlockReason => 'Unlock to use this template';

  @override
  String get templatesUntitled => 'Untitled template';

  @override
  String get templatesUse => 'Use as template';

  @override
  String trashDaysLeft(int days) {
    String _temp0 = intl.Intl.pluralLogic(
      days,
      locale: localeName,
      other: '$days days left',
      one: '1 day left',
    );
    return '$_temp0';
  }

  @override
  String get trashDeletingSoon => 'deleting soon';

  @override
  String get trashEmptyAction => 'Empty';

  @override
  String trashEmptyBody(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count items will be deleted for good.',
      one: '1 item will be deleted for good.',
    );
    return '$_temp0';
  }

  @override
  String trashEmptyMessage(int days) {
    String _temp0 = intl.Intl.pluralLogic(
      days,
      locale: localeName,
      other: '$days days',
      one: '1 day',
    );
    return 'Deleted notes and papers stay here for $_temp0.';
  }

  @override
  String get trashEmptyTitle => 'Empty the trash?';

  @override
  String get trashIsEmpty => 'Trash is empty';

  @override
  String trashKept(int days) {
    String _temp0 = intl.Intl.pluralLogic(
      days,
      locale: localeName,
      other: '$days days',
      one: '1 day',
    );
    return 'Kept for $_temp0, then deleted for good.';
  }

  @override
  String get trashKindNote => 'Note';

  @override
  String get trashKindPaper => 'Paper';

  @override
  String trashMovedToTrash(String label) {
    return '$label moved to trash';
  }

  @override
  String trashQuoted(String title) {
    return '“$title”';
  }

  @override
  String get trashRestore => 'Restore';

  @override
  String get trashRestored => 'Restored';

  @override
  String get viewerAboutThisPaper => 'About this paper';

  @override
  String get viewerCloseSearch => 'Close search';

  @override
  String get viewerContents => 'Contents';

  @override
  String get viewerDrawOnPage => 'Draw on the page';

  @override
  String get viewerExportDamaged =>
      'This PDF can’t be annotated: its structure is damaged or uses features Corplex can’t write into.';

  @override
  String get viewerExportEncrypted =>
      'This PDF is encrypted, so highlights can’t be written into it.';

  @override
  String get viewerExportFailed => 'Couldn’t export this PDF.';

  @override
  String get viewerExportNoPdf => 'This paper’s PDF isn’t on this device.';

  @override
  String get viewerExportNotPdf => 'This file isn’t a PDF Corplex can read.';

  @override
  String get viewerExportNothing =>
      'Nothing to export: the marks don’t match this PDF’s pages.';

  @override
  String get viewerFind => 'Find in document';

  @override
  String viewerFindCount(int current, int total) {
    return '$current of $total';
  }

  @override
  String viewerFindCountMore(int current, int total) {
    return '$current of $total+';
  }

  @override
  String get viewerFindNoMatches => 'No matches';

  @override
  String get viewerFindNoMatchesYet => 'No matches yet';

  @override
  String get viewerFindSearching => 'Searching…';

  @override
  String get viewerFocus => 'Focus';

  @override
  String get viewerFocusHint => 'Tap the page to bring back';

  @override
  String get viewerHighlightColour => 'Highlight colour';

  @override
  String get viewerNextMatch => 'Next match';

  @override
  String get viewerNightPage => 'Night page';

  @override
  String get viewerNoContents => 'This PDF has no table of contents.';

  @override
  String viewerNotesOn(String title) {
    return 'Notes on $title';
  }

  @override
  String viewerPageLong(int page) {
    return 'Page $page';
  }

  @override
  String viewerPagePill(int page, int count) {
    return '$page / $count';
  }

  @override
  String viewerPageShort(int page) {
    return 'p. $page';
  }

  @override
  String get viewerPageStrip => 'Page strip';

  @override
  String get viewerPaperPage => 'Paper page';

  @override
  String get viewerPreviousMatch => 'Previous match';

  @override
  String get viewerQuoteAdded => 'Added to your note';

  @override
  String get viewerQuoteNewNote => 'New note';

  @override
  String get viewerReadAloud => 'Read aloud';

  @override
  String get viewerReadAloudUnavailable =>
      'Reading aloud isn\'t available here';

  @override
  String get viewerRecentNotes => 'Recent notes';

  @override
  String get viewerSepiaPage => 'Sepia page';

  @override
  String get viewerShowPages => 'Show pages';

  @override
  String get viewerSnapPrompt => 'Drag around a figure or table';

  @override
  String get viewerSnapWholeView => 'Whole view';

  @override
  String get viewerSnapshot => 'Snapshot to a note';

  @override
  String get viewerSnapshotHint => 'For figures and tables';

  @override
  String get viewerStopDrawing => 'Stop drawing';

  @override
  String get viewerStopReadAloud => 'Stop reading aloud';

  @override
  String get viewerUnlockToAdd => 'Unlock the note to add to it.';

  @override
  String get viewerUnlockToQuote => 'Unlock the note to add this quote to it.';

  @override
  String get voiceDictate => 'Dictate';

  @override
  String get voiceFinishing => 'Finishing…';

  @override
  String get voiceMicDenied =>
      'Corplex needs the microphone to record. You can allow it in Settings.';

  @override
  String get voiceNoSpeechCaught => 'Didn’t catch any speech.';

  @override
  String get voiceNote => 'Voice note';

  @override
  String voiceNoteTitle(String date) {
    return 'Voice note, $date';
  }

  @override
  String get voiceOpenSettings => 'Open Settings';

  @override
  String get voiceRecordingUnavailable =>
      'Recording isn’t available here, so nothing was recorded.';

  @override
  String get voiceSavedAllowSpeech =>
      'Saved the audio. Allow Speech Recognition to get text too.';

  @override
  String get voiceSavedCantTranscribe =>
      'Saved the audio. This device can’t transcribe it offline.';

  @override
  String get voiceSavedNoSpeech => 'Saved. No speech was heard.';

  @override
  String get voiceSavingTranscribing => 'Saving and transcribing…';

  @override
  String get voiceStartRecording => 'Start recording';

  @override
  String get voiceStopRecording => 'Stop recording';

  @override
  String get zoteroApiKey => 'API key';

  @override
  String get zoteroBadKey =>
      'Zotero didn\'t accept that user ID and key. Check both, and that the key is allowed to read your library.';

  @override
  String get zoteroConnect => 'Connect';

  @override
  String get zoteroConnectTitle => 'Connect to Zotero';

  @override
  String get zoteroEnterBoth => 'Enter both your user ID and an API key.';

  @override
  String get zoteroEverything => 'Everything';

  @override
  String get zoteroEverythingHint => 'Every item; collections become projects';

  @override
  String get zoteroForgetKey => 'Forget key';

  @override
  String get zoteroImport => 'Import';

  @override
  String zoteroImportFailed(String message) {
    return '$message\nWhat was imported before this stays in your library.';
  }

  @override
  String get zoteroImportTitle => 'Import from Zotero';

  @override
  String get zoteroImporting => 'Importing';

  @override
  String zoteroImportingItem(String title) {
    return 'Importing “$title”';
  }

  @override
  String get zoteroKeyHelp =>
      'Create a read-only key at zotero.org/settings/keys (Create new private key, allow library access only). Your user ID is shown on the same page. They stay on this device, in secure storage, and are never synced or backed up.';

  @override
  String get zoteroNotFound =>
      'Zotero couldn\'t find that library. Check the user ID (the number on zotero.org/settings/keys).';

  @override
  String get zoteroOffline =>
      'Couldn\'t reach Zotero. Check your connection and try again.';

  @override
  String get zoteroOpenKeys => 'Open zotero.org/settings/keys';

  @override
  String zoteroProgress(int done, int total) {
    return '$done of $total';
  }

  @override
  String get zoteroRateLimited =>
      'Zotero is asking for a pause. Try again in a few minutes.';

  @override
  String get zoteroReadingAttachments => 'Reading attachments and annotations…';

  @override
  String get zoteroReadingItems => 'Reading items…';

  @override
  String get zoteroReadingLibrary => 'Reading your Zotero library…';

  @override
  String get zoteroServerProblem => 'Zotero had a problem. Try again later.';

  @override
  String zoteroServerProblemDetail(String detail) {
    return 'Zotero had a problem ($detail). Try again later.';
  }

  @override
  String get zoteroSomeCollections => 'Only some collections';

  @override
  String get zoteroSomethingWrong => 'Something went wrong.';

  @override
  String get zoteroStopped => 'Stopped';

  @override
  String get zoteroStopping => 'Stopping…';

  @override
  String zoteroSummaryAlreadyIn(int count) {
    return '$count already in your library';
  }

  @override
  String zoteroSummaryDone(String summary) {
    return '$summary.';
  }

  @override
  String zoteroSummaryMain(int papers, int pdfs, int highlights, int projects) {
    String _temp0 = intl.Intl.pluralLogic(
      papers,
      locale: localeName,
      other: '$papers papers',
      one: '1 paper',
    );
    String _temp1 = intl.Intl.pluralLogic(
      pdfs,
      locale: localeName,
      other: '$pdfs PDFs',
      one: '1 PDF',
    );
    String _temp2 = intl.Intl.pluralLogic(
      highlights,
      locale: localeName,
      other: '$highlights highlights',
      one: '1 highlight',
    );
    String _temp3 = intl.Intl.pluralLogic(
      projects,
      locale: localeName,
      other: '$projects projects',
      one: '1 project',
    );
    return 'Imported $_temp0, $_temp1, $_temp2 into $_temp3';
  }

  @override
  String zoteroSummaryNotes(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count notes',
      one: '1 note',
    );
    return '$_temp0 added';
  }

  @override
  String zoteroSummaryPdfsFailed(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count PDFs',
      one: '1 PDF',
    );
    return '$_temp0 couldn\'t be downloaded';
  }

  @override
  String zoteroSummarySkipped(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count items',
      one: '1 item',
    );
    return '$_temp0 skipped';
  }

  @override
  String zoteroSummaryStopped(String summary) {
    return 'Stopped. $summary.';
  }

  @override
  String get zoteroTitle => 'Zotero';

  @override
  String get zoteroUserId => 'User ID';

  @override
  String get zoteroUserIdNumber =>
      'The user ID is a number, not your username.';
}
