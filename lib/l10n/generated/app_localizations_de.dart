// ignore: unused_import
import 'package:intl/intl.dart' as intl;

import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for German (`de`).
class AppLocalizationsDe extends AppLocalizations {
  AppLocalizationsDe([String locale = 'de']) : super(locale);

  @override
  String get aliasesAdd => 'Alias hinzufügen';

  @override
  String aliasesAlso(String names) {
    return 'Auch: $names';
  }

  @override
  String get aliasesMenu => 'Aliase …';

  @override
  String get aliasesMenuHint =>
      'Andere Namen, gefunden über [[ und in Erwähnungen';

  @override
  String get aliasesTitle => 'Aliase';

  @override
  String get attachmentsAddPodcastLink => 'Podcast-Link hinzufügen';

  @override
  String get attachmentsAll => 'Alle';

  @override
  String get attachmentsAudio => 'Audio';

  @override
  String get attachmentsAudioHint =>
      'Eine NotebookLM-Audioübersicht, Vorlesung oder Podcast-Datei';

  @override
  String get attachmentsCopyName => 'Namen kopieren';

  @override
  String get attachmentsEmptyMessage =>
      'Bilder, Aufnahmen, Links und Dateien, die du an Notizen und Paper anhängst, erscheinen hier.';

  @override
  String get attachmentsEmptyTitle => 'Noch keine Anhänge';

  @override
  String get attachmentsFile => 'Datei';

  @override
  String get attachmentsImage => 'Bild';

  @override
  String attachmentsImageFrom(String name, String parent) {
    return 'Bild $name, aus $parent';
  }

  @override
  String get attachmentsKindAudio => 'Audio';

  @override
  String get attachmentsKindFiles => 'Dateien';

  @override
  String get attachmentsKindImages => 'Bilder';

  @override
  String get attachmentsKindLinks => 'Links';

  @override
  String get attachmentsMarkUp => 'Beschriften';

  @override
  String get attachmentsNoMatch => 'Kein Anhang passt.';

  @override
  String get attachmentsNothingFound => 'Nichts gefunden';

  @override
  String get attachmentsPodcastLink => 'Podcast-Link';

  @override
  String get attachmentsPodcastLinkHint =>
      'Ein NotebookLM-Link oder eine Audio-URL';

  @override
  String get attachmentsPodcastLinkNote =>
      'Direkte Audio-Links (.mp3, .m4a …) werden hier abgespielt. NotebookLM-Links öffnen sich im Browser. Um in Corplex zu hören und Zeitmarken zu setzen, lade die Audioübersicht herunter und füge sie als Audio hinzu.';

  @override
  String get attachmentsRecordAudio => 'Audio aufnehmen';

  @override
  String get attachmentsSearch => 'Anhänge durchsuchen';

  @override
  String get attachmentsShowInNote => 'In Notiz zeigen';

  @override
  String get attachmentsShowInPaper => 'Im Paper zeigen';

  @override
  String get attachmentsTitle => 'Anhänge';

  @override
  String get attachmentsUntitledPaper => 'Paper ohne Titel';

  @override
  String get attachmentsVoiceNote => 'Eine Sprachnotiz';

  @override
  String get attachmentsVoiceNoteTranscribed =>
      'Eine Sprachnotiz, auf diesem Gerät transkribiert';

  @override
  String get audioBack10 => '10 Sekunden zurück';

  @override
  String get audioChannelName => 'Audiowiedergabe';

  @override
  String get audioClosePlayer => 'Player schließen';

  @override
  String get audioForward30 => '30 Sekunden vor';

  @override
  String get audioMark => 'Marke';

  @override
  String get audioNotSynced =>
      'Diese Aufnahme wurde noch nicht auf dieses Gerät synchronisiert.';

  @override
  String get audioPause => 'Pause';

  @override
  String get audioPlay => 'Wiedergabe';

  @override
  String get audioPlayFailed =>
      'Diese Aufnahme konnte nicht abgespielt werden.';

  @override
  String get authConfirmEmail =>
      'Bestätige dein Konto über die E-Mail, die wir dir geschickt haben, und melde dich dann an.';

  @override
  String get authCreateAccount => 'Konto erstellen';

  @override
  String get authCreateIntro =>
      'Deine Notizen bleiben auf diesem Gerät und werden mit deinen anderen Geräten synchronisiert, sobald du angemeldet bist.';

  @override
  String get authCreateTitle => 'Konto erstellen';

  @override
  String get authEmail => 'E-Mail';

  @override
  String get authInvalidEmail => 'Gültige E-Mail-Adresse eingeben.';

  @override
  String get authNoAccount => 'Noch kein Konto? Registrieren';

  @override
  String get authOffline =>
      'Server nicht erreichbar. Verbindung prüfen und erneut versuchen.';

  @override
  String get authPassword => 'Passwort';

  @override
  String get authPasswordHelper => 'Mindestens 6 Zeichen';

  @override
  String get authShortPassword =>
      'Das Passwort muss mindestens 6 Zeichen haben.';

  @override
  String get authSignIn => 'Anmelden';

  @override
  String get authSignInIntro =>
      'Anmelden, um Notizen und Paper geräteübergreifend zu synchronisieren.';

  @override
  String authUnknown(String type) {
    return 'Etwas ist schiefgelaufen ($type). Bitte erneut versuchen.';
  }

  @override
  String get authWelcomeBack => 'Willkommen zurück';

  @override
  String get calloutsCommand => 'Hinweisbox';

  @override
  String get calloutsCommandHint =>
      'Eine Passage als Notiz, Tipp oder Warnung hervorheben';

  @override
  String calloutsLabel(String type) {
    return 'Hinweisbox: $type';
  }

  @override
  String get calloutsPickTitle => 'Art der Hinweisbox';

  @override
  String get calloutsRemove => 'Hinweisbox entfernen';

  @override
  String get calloutsTypeBug => 'Fehler';

  @override
  String get calloutsTypeCaution => 'Vorsicht';

  @override
  String get calloutsTypeDanger => 'Gefahr';

  @override
  String get calloutsTypeExample => 'Beispiel';

  @override
  String get calloutsTypeImportant => 'Wichtig';

  @override
  String get calloutsTypeInfo => 'Info';

  @override
  String get calloutsTypeNote => 'Notiz';

  @override
  String get calloutsTypeQuestion => 'Frage';

  @override
  String get calloutsTypeSuccess => 'Erfolg';

  @override
  String get calloutsTypeTip => 'Tipp';

  @override
  String get calloutsTypeTodo => 'Zu erledigen';

  @override
  String get calloutsTypeWarning => 'Warnung';

  @override
  String get commentsAddComment => 'Kommentar hinzufügen';

  @override
  String get commentsComment => 'Kommentar';

  @override
  String get commentsDeleted => 'Kommentar gelöscht';

  @override
  String get commentsEditComment => 'Kommentar bearbeiten';

  @override
  String get commentsEmpty =>
      'Eine Stelle auswählen, dann „Kommentar hinzufügen“ wählen.';

  @override
  String get commentsFromHint => 'z. B. Betreuer:in';

  @override
  String get commentsFromOptional => 'Von (optional)';

  @override
  String get commentsNothingOpen => 'Nichts offen.';

  @override
  String get commentsOnSelection => 'Auswahl kommentieren';

  @override
  String commentsOpenCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count offene Kommentare',
      one: '1 offener Kommentar',
    );
    return '$_temp0';
  }

  @override
  String get commentsOptions => 'Kommentaroptionen';

  @override
  String get commentsPassageChanged => 'Stelle geändert';

  @override
  String get commentsReopen => 'Wieder öffnen';

  @override
  String get commentsResolve => 'Erledigen';

  @override
  String get commentsSelectAPassage => 'Eine Stelle zum Kommentieren auswählen';

  @override
  String commentsShowResolved(int count) {
    return 'Erledigte anzeigen ($count)';
  }

  @override
  String get commentsTitle => 'Kommentare';

  @override
  String get commentsUnlockToAdd =>
      'Notizen entsperren, um einen Kommentar hinzuzufügen.';

  @override
  String get commonAdd => 'Hinzufügen';

  @override
  String get commonCancel => 'Abbrechen';

  @override
  String get commonClose => 'Schließen';

  @override
  String get commonCopied => 'Kopiert';

  @override
  String get commonCopy => 'Kopieren';

  @override
  String get commonDelete => 'Löschen';

  @override
  String get commonDone => 'Fertig';

  @override
  String get commonEdit => 'Bearbeiten';

  @override
  String get commonImportPdf => 'PDF importieren';

  @override
  String get commonLess => 'Weniger';

  @override
  String get commonLibrary => 'Bibliothek';

  @override
  String get commonLocked => 'Gesperrt';

  @override
  String get commonMore => 'Mehr';

  @override
  String get commonMoveToTrash => 'In den Papierkorb legen';

  @override
  String get commonNewNote => 'Neue Notiz';

  @override
  String get commonNotes => 'Notizen';

  @override
  String get commonOk => 'OK';

  @override
  String get commonOpen => 'Öffnen';

  @override
  String get commonProjects => 'Projekte';

  @override
  String get commonRemove => 'Entfernen';

  @override
  String get commonRename => 'Umbenennen';

  @override
  String get commonSave => 'Sichern';

  @override
  String get commonSearch => 'Suchen';

  @override
  String get commonSettings => 'Einstellungen';

  @override
  String get commonShare => 'Teilen';

  @override
  String get commonTrash => 'Papierkorb';

  @override
  String get commonTryAgain => 'Erneut versuchen';

  @override
  String get commonUndo => 'Widerrufen';

  @override
  String get commonUntitled => 'Ohne Titel';

  @override
  String get cslAddStyle => 'Stil hinzufügen…';

  @override
  String get cslAutomatic => 'Automatisch';

  @override
  String cslAutomaticWith(String language) {
    return 'Automatisch ($language)';
  }

  @override
  String get cslCitationLanguage => 'Zitiersprache';

  @override
  String cslCitationLanguageRow(String language) {
    return 'Zitiersprache: $language';
  }

  @override
  String get cslProblemDependent =>
      'Dieser Stil ist eine kleine Variante eines übergeordneten Stils. Importiere stattdessen den übergeordneten Stil.';

  @override
  String get cslProblemNoBibliography =>
      'Der Stil hat keinen Literaturverzeichnis-Abschnitt und kann keine Verzeichnisse formatieren.';

  @override
  String get cslProblemNoInfo => 'Dem Stil fehlt der Block mit Titel und ID.';

  @override
  String get cslProblemNoLayout =>
      'Dem Stil fehlt das Layout, daher kann er keine Literaturangaben formatieren.';

  @override
  String get cslProblemNoTitle => 'Der Stil hat keinen Titel.';

  @override
  String get cslProblemNotStyle =>
      'Die Datei ist keine Zitierstil-Datei (.csl).';

  @override
  String get cslProblemNotXml =>
      'Die Datei ist kein gültiges XML und kann daher kein Zitierstil sein.';

  @override
  String get cslProblemTooLarge => 'Die Datei ist zu groß für einen Stil.';

  @override
  String cslProblemUndefinedMacro(String name) {
    return 'Der Stil verwendet das nicht definierte Makro „$name“.';
  }

  @override
  String get cslProblemUnreadable => 'Die Datei konnte nicht gelesen werden.';

  @override
  String get cslProblemWrongVersion => 'Nur CSL-1.0-Stile werden unterstützt.';

  @override
  String get cslReferenceStyle => 'Zitierstil';

  @override
  String get cslStyleCantBeUsed => 'Dieser Stil lässt sich nicht verwenden';

  @override
  String get dailyFolder => 'Ordner';

  @override
  String get dailyKeyTodaysNote => 'Heutige Notiz';

  @override
  String get dailyNext => 'Notiz vom Folgetag';

  @override
  String get dailyNoEarlier => 'Keine frühere Tagesnotiz';

  @override
  String get dailyNoLater => 'Keine spätere Tagesnotiz';

  @override
  String get dailyNone => 'Keine';

  @override
  String get dailyPrevious => 'Notiz vom Vortag';

  @override
  String get dailySettingsSubtitle =>
      'Vorlage und Ordner für die heutige Notiz';

  @override
  String get dailySettingsTitle => 'Tagesnotizen';

  @override
  String get dailyTemplate => 'Vorlage';

  @override
  String get dailyTemplateHint =>
      'Markiere eine Notiz als Vorlage (Notizmenü), um hier eine auszuwählen.';

  @override
  String get dailyTodaysNote => 'Heutige Notiz';

  @override
  String get dataNewerVersion =>
      'Dieses Backup wurde mit einer neueren Version von Corplex erstellt. Aktualisiere zuerst die App.';

  @override
  String get dataNotABackup => 'Diese Datei ist kein Corplex-Backup.';

  @override
  String get dataUnsupportedVersion =>
      'Dieses Backup stammt aus einer nicht unterstützten Version.';

  @override
  String get editorAddBibliography => 'Literaturverzeichnis einfügen';

  @override
  String get editorAddPaperAndCite => 'Dieses Paper hinzufügen und zitieren?';

  @override
  String get editorAddToProject => 'Zu Projekt hinzufügen';

  @override
  String editorAddedReferences(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count Literaturangaben eingefügt',
      one: '1 Literaturangabe eingefügt',
    );
    return '$_temp0';
  }

  @override
  String get editorAttach => 'Audio, Bild oder Datei anhängen';

  @override
  String get editorBibliographyHint =>
      'Eine Liste dessen, was diese Notiz zitiert';

  @override
  String get editorCiteHint => 'Oder beim Schreiben [@ tippen';

  @override
  String get editorCmdAttach => 'Anhängen';

  @override
  String get editorCmdAttachHint => 'Audio, ein Bild oder eine Datei';

  @override
  String get editorCmdBibliography => 'Literaturverzeichnis einfügen';

  @override
  String get editorCmdBibliographyHint =>
      'Eine Liste dessen, was diese Notiz zitiert';

  @override
  String get editorCmdChecklist => 'Checkliste';

  @override
  String get editorCmdChecklistHint => 'Einträge zum Abhaken';

  @override
  String get editorCmdCite => 'Paper zitieren';

  @override
  String get editorCmdCiteHint => 'Zitation aus der Bibliothek einfügen';

  @override
  String get editorCmdDictate => 'Diktieren';

  @override
  String get editorCmdDictateHint => 'Sprechen statt tippen';

  @override
  String get editorCmdDraw => 'Zeichnen';

  @override
  String get editorCmdDrawHint => 'Eine Skizze, mit Stift oder Finger';

  @override
  String get editorCmdEquation => 'Formel';

  @override
  String get editorCmdEquationHint => 'LaTeX-Mathematik oder \$\$ tippen';

  @override
  String get editorCmdFigure => 'Abbildungsbeschriftung';

  @override
  String get editorCmdFigureHint =>
      'Nummerierte Abbildungsbeschriftung für diese Zeile';

  @override
  String get editorCmdHeading => 'Überschrift';

  @override
  String get editorCmdHeadingHint => 'Diese Zeile zur Überschrift machen';

  @override
  String get editorCmdInsertTable => 'Tabelle';

  @override
  String get editorCmdInsertTableHint => 'Zeilen und Spalten, zunächst 3 × 3';

  @override
  String get editorCmdLink => 'Mit Notiz verknüpfen';

  @override
  String get editorCmdLinkHint => 'Oder [[ tippen';

  @override
  String get editorCmdRefer => 'Auf Abbildung oder Tabelle verweisen';

  @override
  String get editorCmdReferHint =>
      'Die Nummer einfügen, bleibt beim Verschieben richtig';

  @override
  String get editorCmdTable => 'Tabellenbeschriftung';

  @override
  String get editorCmdTableHint =>
      'Nummerierte Tabellenbeschriftung für diese Zeile';

  @override
  String get editorCmdTemplate => 'Vorlage für Literaturnotiz';

  @override
  String get editorCmdTemplateHint =>
      'Zusammenfassung, Methode, Ergebnisse, Kritik';

  @override
  String get editorCmdVoice => 'Sprachnotiz';

  @override
  String get editorCmdVoiceHint => 'Einen Gedanken beim Lesen aufnehmen';

  @override
  String get editorDraw => 'Zeichnen';

  @override
  String editorEditDate(String date, String time) {
    return '$date um $time';
  }

  @override
  String get editorExport => 'Exportieren';

  @override
  String get editorExportHint =>
      'Markdown, Word oder PDF, mit Literaturangaben';

  @override
  String get editorFindInNote => 'In Notiz suchen';

  @override
  String get editorImageTapToEnlarge => 'Bild, zum Vergrößern tippen';

  @override
  String get editorLinkPaper => 'Paper verknüpfen';

  @override
  String get editorLinkToNote => 'Mit Notiz verknüpfen';

  @override
  String get editorLinkToNoteHint => 'Oder beim Schreiben [[ tippen';

  @override
  String get editorLinkedFrom => 'Verlinkt von';

  @override
  String get editorLockHint => 'Zum Öffnen ist das Notizen-Passwort nötig';

  @override
  String get editorLockedTapToLock => 'Gesperrt – tippen zum Sperren';

  @override
  String get editorLookupUnreachable =>
      'Der Suchdienst ist nicht erreichbar. Der Link bleibt unverändert.';

  @override
  String get editorMoveToFolder => 'In Ordner bewegen';

  @override
  String get editorNoCitations =>
      'Noch keine Zitationen zum Auflisten. Mit [@ ein Paper zitieren.';

  @override
  String editorNoPaperFound(String id) {
    return 'Kein Paper für $id gefunden.';
  }

  @override
  String get editorNoteLockedFiles =>
      'Notiz gesperrt. Angehängte Dateien (Bilder, Audio, PDFs) werden nicht verschlüsselt, nur Text und Skizzen der Notiz.';

  @override
  String get editorPaperRemoved => 'Dieses Paper wurde entfernt.';

  @override
  String get editorPrint => 'Drucken …';

  @override
  String get editorRecordingRemoved => 'Diese Aufnahme wurde entfernt.';

  @override
  String get editorSelectPassage => 'Passage zum Kommentieren auswählen.';

  @override
  String get editorStartWriting => 'Schreib los …';

  @override
  String get editorStyleBody => 'Fließtext';

  @override
  String get editorStyleHeading => 'Überschrift';

  @override
  String get editorStyleHighlight => 'Markieren';

  @override
  String get editorStyleMonospaced => 'Festbreite';

  @override
  String get editorStyleQuote => 'Zitat';

  @override
  String get editorStyleStrike => 'Durchgestrichen';

  @override
  String get editorStyleSubheading => 'Zwischenüberschrift';

  @override
  String get editorStyleTable => 'Tabelle';

  @override
  String get editorStyleTitle => 'Titel';

  @override
  String get editorTags => 'Tags';

  @override
  String get editorTemplate => 'Vorlage für Literaturnotiz';

  @override
  String get editorTemplateHint =>
      'Zusammenfassung, Methode, Ergebnisse, Kritik';

  @override
  String get editorTextStyle => 'Textstil';

  @override
  String editorTipBold(String shortcut) {
    return 'Fett $shortcut';
  }

  @override
  String editorTipBulleted(String shortcut) {
    return 'Aufzählung $shortcut';
  }

  @override
  String editorTipChecklist(String shortcut) {
    return 'Checkliste $shortcut';
  }

  @override
  String editorTipHighlight(String shortcut) {
    return 'Markieren $shortcut';
  }

  @override
  String editorTipItalic(String shortcut) {
    return 'Kursiv $shortcut';
  }

  @override
  String editorTipNumbered(String shortcut) {
    return 'Nummerierte Liste $shortcut';
  }

  @override
  String editorTipUnderline(String shortcut) {
    return 'Unterstrichen $shortcut';
  }

  @override
  String get editorTitleHint => 'Titel';

  @override
  String get editorTypewriter => 'Schreibmaschinen-Scrollen';

  @override
  String get editorTypewriterHint => 'Die aktuelle Zeile mittig halten';

  @override
  String get editorWordCount => 'Wortzahl';

  @override
  String get editorWordCountHint => 'Und Lesezeit';

  @override
  String get exportCitationsAndReferences =>
      'Zitationen und Literaturverzeichnis';

  @override
  String get exportCouldntCreateFile => 'Datei konnte nicht erstellt werden.';

  @override
  String get exportFormatLatex => 'LaTeX (Overleaf)';

  @override
  String get exportFormatMarkdown => 'Markdown';

  @override
  String get exportFormatPdf => 'PDF';

  @override
  String get exportFormatWord => 'Word-Dokument';

  @override
  String get exportUnlockNoteToContinue => 'Notiz entsperren, um fortzufahren.';

  @override
  String get exportUnlockNotesToContinue =>
      'Gesperrte Notizen entsperren, um fortzufahren.';

  @override
  String findCount(int current, int total) {
    return '$current von $total';
  }

  @override
  String get findHideReplace => 'Ersetzen ausblenden';

  @override
  String get findNext => 'Nächster Treffer';

  @override
  String get findNotFound => 'Nicht gefunden';

  @override
  String get findPrevious => 'Vorheriger Treffer';

  @override
  String get findReplace => 'Ersetzen';

  @override
  String get findReplaceAll => 'Alle';

  @override
  String get findReplaceWith => 'Ersetzen durch';

  @override
  String get foldCollapseAll => 'Alle Abschnitte einklappen';

  @override
  String get foldCollapseSection => 'Abschnitt einklappen';

  @override
  String get foldExpandAll => 'Alle Abschnitte ausklappen';

  @override
  String get foldExpandSection => 'Abschnitt ausklappen';

  @override
  String get foldShowSection => 'Abschnitt anzeigen';

  @override
  String get footnotesCommand => 'Fußnote';

  @override
  String get footnotesCommandHint => 'Eine Anmerkung am Seitenende';

  @override
  String get footnotesEditTitle => 'Fußnote';

  @override
  String get footnotesHint => 'Fußnote schreiben';

  @override
  String footnotesLabel(String number) {
    return 'Fußnote $number';
  }

  @override
  String footnotesStatsInFootnotes(String count) {
    return '+$count in Fußnoten';
  }

  @override
  String get graphCouldntDraw => 'Karte konnte nicht gezeichnet werden';

  @override
  String get graphEmptyMessage =>
      'Notizen miteinander oder mit Papern verknüpfen oder ein Paper mit [@ zitieren, dann erscheinen die Verbindungen hier.';

  @override
  String get graphHideUnconnected => 'Nicht verbundene Elemente ausblenden';

  @override
  String get graphLockedNote => 'Gesperrte Notiz';

  @override
  String get graphMap => 'Karte';

  @override
  String get graphNothingConnected => 'Nichts verbunden';

  @override
  String get graphNothingToMap => 'Noch nichts zum Darstellen';

  @override
  String get graphShowUnconnected => 'Nicht verbundene Elemente einblenden';

  @override
  String get graphTryAgainInAMoment => 'Gleich noch einmal versuchen.';

  @override
  String get graphUntitledPaper => 'Paper ohne Titel';

  @override
  String get highlightsAddComment => 'Kommentar hinzufügen';

  @override
  String get highlightsAddCommentMenu => 'Kommentar hinzufügen…';

  @override
  String get highlightsButter => 'Buttergelbe Markierung';

  @override
  String get highlightsDelete => 'Markierung löschen';

  @override
  String get highlightsEditCommentMenu => 'Kommentar bearbeiten…';

  @override
  String get highlightsEmptyMessage =>
      'Text in einem PDF auswählen und „Markieren“ wählen; die Markierungen sammeln sich hier.';

  @override
  String get highlightsEmptyTitle => 'Noch keine Markierungen';

  @override
  String get highlightsHighlight => 'Markieren';

  @override
  String get highlightsMist => 'Nebelgraue Markierung';

  @override
  String get highlightsNoMatches => 'Keine Treffer.';

  @override
  String get highlightsQuoteToNote => 'In Notiz zitieren';

  @override
  String get highlightsRevisit => 'Markierungen wiederholen';

  @override
  String get highlightsRose => 'Rosa Markierung';

  @override
  String get highlightsSage => 'Salbeigrüne Markierung';

  @override
  String get highlightsSearchHint => 'Markierungen durchsuchen';

  @override
  String get highlightsSelectHint =>
      'Text auf einer Seite auswählen und „Markieren“ tippen.';

  @override
  String get highlightsTooltip => 'Markierungen';

  @override
  String get historyBack => 'Zurück';

  @override
  String get historyForward => 'Vorwärts';

  @override
  String get historyKeyForward => 'Vorwärts';

  @override
  String get historyPeekEmpty => 'Noch nichts geschrieben';

  @override
  String get historyPeekLocked => 'Gesperrt';

  @override
  String get historyPeekMissing =>
      'Diese Notiz oder dieses Paper gibt es nicht mehr';

  @override
  String historyPeekPage(int page) {
    return 'S. $page';
  }

  @override
  String get historyPeekPaperNoAuthors => 'Keine Autor:innen';

  @override
  String get homeAttachments => 'Anhänge';

  @override
  String homeCountItems(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count Einträge',
      one: '1 Eintrag',
      zero: 'Keine Einträge',
    );
    return '$_temp0';
  }

  @override
  String homeCountNotes(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count Notizen',
      one: '1 Notiz',
      zero: 'Keine Notizen',
    );
    return '$_temp0';
  }

  @override
  String homeCountPapers(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count Paper',
      one: '1 Paper',
      zero: 'Keine Paper',
    );
    return '$_temp0';
  }

  @override
  String get homeImportFirstPaper => 'Erstes Paper importieren';

  @override
  String get homeImportPdfTooltip => 'PDF importieren (⌘O)';

  @override
  String get homeNewNoteTooltip => 'Neue Notiz (⌘N)';

  @override
  String get homePickNote => 'Notiz auswählen oder eine neue beginnen.';

  @override
  String get homePickPaper =>
      'Paper zum Lesen, Markieren und Zitieren auswählen.';

  @override
  String get homeSearchSubtitle => 'Notizen, Paper und Markierungen';

  @override
  String get homeShowAttachments => 'Anhänge anzeigen';

  @override
  String get homeShowSidebarTooltip => 'Seitenleiste einblenden (⌃⌘S)';

  @override
  String get homeStepHighlightText =>
      'Text gedrückt halten, dann „Markieren“ oder „In Notiz zitieren“ wählen.';

  @override
  String get homeStepHighlightTitle => 'Beim Lesen markieren';

  @override
  String get homeStepImportText =>
      'Ein PDF aus Dateien. Titel, Autor:innen und Jahr werden automatisch ergänzt.';

  @override
  String get homeStepImportTitle => 'Paper importieren';

  @override
  String get homeStepWriteText =>
      'In einer Notiz „/“ für Werkzeuge oder „[@“ zum Zitieren eines Papers eingeben.';

  @override
  String get homeStepWriteTitle => 'Schreiben und zitieren';

  @override
  String get homeWelcome => 'Willkommen bei Corplex';

  @override
  String get homeWelcomeSubtitle =>
      'Lesen, markieren, Notizen machen und zitieren an einem Ort.';

  @override
  String get inkBlue => 'Blau';

  @override
  String get inkClay => 'Ton';

  @override
  String get inkColor => 'Tintenfarbe';

  @override
  String get inkColour => 'Farbe';

  @override
  String get inkConvertToText => 'In Text umwandeln';

  @override
  String get inkDrawHere => 'Hier zeichnen';

  @override
  String get inkDrawWithFingers => 'Mit Fingern zeichnen';

  @override
  String get inkDrawing => 'Zeichnung';

  @override
  String get inkDuplicate => 'Duplizieren';

  @override
  String get inkEraser => 'Radierer';

  @override
  String get inkExpand => 'Vergrößern';

  @override
  String get inkFingersDraw =>
      'Finger zeichnen (tippen, um stattdessen mit Fingern zu scrollen)';

  @override
  String get inkFingersScroll =>
      'Finger scrollen (tippen, um mit Fingern zu zeichnen)';

  @override
  String get inkGraphite => 'Graphit';

  @override
  String get inkHighlighter => 'Textmarker';

  @override
  String get inkMoreOptions => 'Weitere Zeichenoptionen';

  @override
  String get inkMoreSpace => 'Mehr Platz';

  @override
  String get inkNoHandwriting => 'Keine Handschrift gefunden';

  @override
  String get inkPaste => 'Einsetzen';

  @override
  String get inkPen => 'Stift';

  @override
  String get inkRedo => 'Wiederholen';

  @override
  String get inkSage => 'Salbei';

  @override
  String get inkScrollWithFingers => 'Mit Fingern scrollen';

  @override
  String get inkSelect => 'Auswählen';

  @override
  String get inkTapToDraw => 'Zum Zeichnen tippen';

  @override
  String get inkThickness => 'Linienstärke';

  @override
  String get libraryAddById => 'Per DOI oder arXiv-ID hinzufügen';

  @override
  String get libraryAddByIdHint =>
      '10.1038/nature14539, arXiv:1706.03762 oder PMID: 9500320';

  @override
  String get libraryAddToProject => 'Zu Projekt hinzufügen …';

  @override
  String libraryAddedPapers(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count Paper',
      one: '1 Paper',
    );
    return '$_temp0 hinzugefügt';
  }

  @override
  String get libraryAll => 'Alle';

  @override
  String get libraryAllHighlights => 'Alle Markierungen';

  @override
  String get libraryAllHighlightsHint => 'Aus allen Paper';

  @override
  String get libraryAlreadyInLibrary => 'Bereits in deiner Bibliothek.';

  @override
  String libraryAlreadyInLibraryCount(int count) {
    return '$count bereits in der Bibliothek';
  }

  @override
  String get libraryCitationCopied => 'Zitation kopiert';

  @override
  String get libraryCitationsAdded => 'Zur Bibliothek hinzugefügt.';

  @override
  String get libraryCitationsCitedBy => 'Zitiert von';

  @override
  String get libraryCitationsInLibrary => 'In deiner Bibliothek';

  @override
  String get libraryCitationsLoadMore => 'Mehr laden';

  @override
  String get libraryCitationsLoadMoreFailed =>
      'Weitere konnten nicht geladen werden. Versuche es online erneut.';

  @override
  String get libraryCitationsLoading => 'Wird geladen …';

  @override
  String libraryCitationsMoreNotShown(int count) {
    return '$count weitere nicht angezeigt.';
  }

  @override
  String get libraryCitationsNoCiting => 'Keine zitierenden Paper gefunden.';

  @override
  String get libraryCitationsNoReferences =>
      'Keine Literaturangaben aufgeführt.';

  @override
  String get libraryCitationsNotFound => 'OpenAlex kennt dieses Paper nicht.';

  @override
  String get libraryCitationsReferences => 'Literaturangaben';

  @override
  String get libraryCitationsRefresh => 'Aktualisieren';

  @override
  String get libraryCitationsRefreshFailed =>
      'Aktualisieren nicht möglich. Versuche es online erneut.';

  @override
  String get libraryCitationsRetry => 'Erneut';

  @override
  String get libraryCitationsTitle => 'Literaturangaben · Zitiert von';

  @override
  String get libraryCitationsUnreachable =>
      'OpenAlex ist nicht erreichbar. Versuche es online erneut.';

  @override
  String get libraryCopyCitation => 'Zitation kopieren';

  @override
  String get libraryEmptyMessage =>
      'Tippe auf „PDF importieren“, um ein Paper hinzuzufügen, oder verknüpfe eines aus einer Notiz.';

  @override
  String get libraryEmptyTitle => 'Deine Bibliothek ist leer';

  @override
  String libraryError(String error) {
    return 'Etwas ist schiefgelaufen: $error';
  }

  @override
  String get libraryExportBibtex => 'Als BibTeX exportieren';

  @override
  String libraryFoundDetails(String title) {
    return 'Angaben zu „$title“ gefunden';
  }

  @override
  String get libraryImportReferences => 'Literaturangaben importieren';

  @override
  String get libraryImportReferencesHint =>
      'BibTeX, RIS oder CSL-JSON (Zotero, Mendeley)';

  @override
  String get libraryImportZotero => 'Aus Zotero importieren …';

  @override
  String get libraryIsEmpty => 'Deine Bibliothek ist leer.';

  @override
  String get libraryLocatorChapter => 'Kapitel';

  @override
  String get libraryLocatorFigure => 'Abbildung';

  @override
  String get libraryLocatorLine => 'Zeile';

  @override
  String get libraryLocatorNote => 'Anmerkung';

  @override
  String get libraryLocatorPage => 'Seite';

  @override
  String get libraryLocatorParagraph => 'Absatz';

  @override
  String get libraryLocatorSection => 'Abschnitt';

  @override
  String get libraryLocatorVolume => 'Band';

  @override
  String get libraryLookingUp => 'Wird gesucht …';

  @override
  String libraryLooksDuplicate(String title) {
    return '„$title“ scheint schon vorhanden zu sein.';
  }

  @override
  String get libraryLookupUnreachable =>
      'Der Suchdienst ist nicht erreichbar. Versuche es online erneut.';

  @override
  String get libraryNoMatches => 'Keine Treffer';

  @override
  String get libraryNoMatchesHint => 'Versuche einen anderen Titel oder Autor.';

  @override
  String libraryNoPaperFound(String id) {
    return 'Kein Paper für $id gefunden.';
  }

  @override
  String get libraryNoReferencesFound =>
      'In dieser Datei wurden keine Literaturangaben gefunden.';

  @override
  String get libraryNotAnIdentifier =>
      'Das sieht nicht nach einer DOI, arXiv- oder PubMed-ID aus.';

  @override
  String get libraryNoticeConcern => 'Bedenken veröffentlicht';

  @override
  String get libraryNoticeCorrected => 'Korrigiert';

  @override
  String get libraryNoticeDatePattern => 'd. MMMM y';

  @override
  String libraryNoticeOn(String kind, String date) {
    return '$kind am $date – siehe Hinweis';
  }

  @override
  String get libraryNoticeRetracted => 'Zurückgezogen';

  @override
  String libraryNoticeUndated(String kind) {
    return '$kind – siehe Hinweis';
  }

  @override
  String get libraryNoticeWithdrawn => 'Widerrufen';

  @override
  String get libraryOpenPdf => 'PDF öffnen';

  @override
  String get librarySearchPapers => 'Paper suchen';

  @override
  String get libraryShowAttachments => 'Anhänge zeigen';

  @override
  String get libraryStatusDone => 'Gelesen';

  @override
  String get libraryStatusReading => 'Am Lesen';

  @override
  String get libraryStatusToRead => 'Zu lesen';

  @override
  String get linksCmdEmbed => 'Notiz einbetten';

  @override
  String get linksCmdEmbedHint =>
      'Eine andere Notiz live hier anzeigen. Oder ![[ tippen';

  @override
  String get linksEmbedANote => 'Notiz einbetten …';

  @override
  String get linksEmbedEmpty => 'Leere Notiz';

  @override
  String get linksEmbedLocked => 'Gesperrt';

  @override
  String get linksEmbedMissing => 'Notiz nicht gefunden';

  @override
  String linksEmbedOpen(String title) {
    return '$title öffnen';
  }

  @override
  String get linksEmbedSectionMissing => 'Abschnitt nicht gefunden';

  @override
  String get linksEmbedShowAll => 'Alles anzeigen';

  @override
  String get linksEmbedShowLess => 'Weniger anzeigen';

  @override
  String get linksHeadingsOf => 'Überschriften';

  @override
  String get linksLinkMention => 'Verlinken';

  @override
  String linksMentionLinked(String title) {
    return 'In „$title“ verlinkt';
  }

  @override
  String get linksNoHeadings => 'Keine Überschriften in dieser Notiz';

  @override
  String get linksNoParagraphs => 'Keine Absätze in dieser Notiz';

  @override
  String get linksParagraphUnavailable =>
      'Dieser Absatz ließ sich nicht markieren';

  @override
  String get linksPartsLocked =>
      'Eine gesperrte Notiz lässt sich nur als Ganzes verlinken.';

  @override
  String get linksToParagraph => 'Auf einen Absatz verlinken';

  @override
  String get linksToParagraphHint => 'Oder Titel#^ tippen';

  @override
  String linksUnlinkedMentions(int count) {
    return 'Nicht verlinkte Erwähnungen ($count)';
  }

  @override
  String get listAddToProject => 'Zu Projekt hinzufügen…';

  @override
  String get listAll => 'Alle';

  @override
  String get listCreate => 'Anlegen';

  @override
  String get listDeleteFolderEllipsis => 'Ordner löschen…';

  @override
  String get listDeleteFolderMessage =>
      'Enthaltene Notizen werden nicht gelöscht, sondern keinem Ordner zugeordnet.';

  @override
  String listDeleteFolderTitle(String name) {
    return '„$name“ löschen?';
  }

  @override
  String get listDeleteTagEllipsis => 'Tag löschen…';

  @override
  String get listDeleteTagMessage => 'Der Tag wird von allen Notizen entfernt.';

  @override
  String listDeleteTagTitle(String name) {
    return '„#$name“ löschen?';
  }

  @override
  String get listDuplicate => 'Duplizieren';

  @override
  String get listFolderName => 'Ordnername';

  @override
  String get listFolderOrTag => 'Ordner oder Tag';

  @override
  String get listLockNote => 'Notiz sperren';

  @override
  String get listNewFolder => 'Neuer Ordner';

  @override
  String get listNewTag => 'Neuer Tag';

  @override
  String get listNoNotesMessage =>
      'Tippe auf Neue Notiz, um den ersten Gedanken festzuhalten.';

  @override
  String get listNoNotesTitle => 'Noch keine Notizen';

  @override
  String get listNothingHereMessage =>
      'Notizen, die du bei aktivem Filter anlegst, erscheinen hier.';

  @override
  String get listNothingHereTitle => 'Noch nichts hier';

  @override
  String get listPinToTop => 'Oben anheften';

  @override
  String get listPinned => 'Angeheftet';

  @override
  String get listPrevious30Days => 'Letzte 30 Tage';

  @override
  String get listPrevious7Days => 'Letzte 7 Tage';

  @override
  String get listRemoveLock => 'Sperre entfernen';

  @override
  String listSomethingWentWrong(String error) {
    return 'Etwas ist schiefgelaufen: $error';
  }

  @override
  String get listTagName => 'Tag-Name';

  @override
  String get listToday => 'Heute';

  @override
  String get listUnpin => 'Lösen';

  @override
  String get listYesterday => 'Gestern';

  @override
  String get lockBiometricFaceTouch => 'Face ID / Touch ID';

  @override
  String get lockBiometricFingerprint => 'Fingerabdruck';

  @override
  String get lockBiometricGeneric => 'Biometrie';

  @override
  String get lockBiometricReason => 'Gesperrte Notizen entsperren';

  @override
  String get lockBiometricSubtitle => 'Gesperrte Notizen ohne Tippen öffnen';

  @override
  String get lockBiometricTouch => 'Touch ID';

  @override
  String get lockChangePassword => 'Passwort ändern';

  @override
  String get lockChangeTitle => 'Notizen-Passwort ändern';

  @override
  String get lockConfirm => 'Bestätigen';

  @override
  String get lockContinue => 'Fortfahren';

  @override
  String get lockCurrentPassword => 'Aktuelles Passwort';

  @override
  String get lockCurrentWrong => 'Das aktuelle Passwort ist falsch.';

  @override
  String get lockEarlierPassword =>
      'Diese Notiz nutzt ein früheres Notizen-Passwort';

  @override
  String get lockEnterPassword => 'Notizen-Passwort eingeben.';

  @override
  String get lockEnterToTurnOn =>
      'Notizen-Passwort eingeben, um dies zu aktivieren.';

  @override
  String get lockForgottenWarning =>
      'Wenn du dieses Passwort vergisst, lassen sich gesperrte Notizen nicht wiederherstellen – weder von dir noch von uns.';

  @override
  String lockHint(String hint) {
    return 'Hinweis: $hint';
  }

  @override
  String get lockHintHelper =>
      'Wird auf dem Sperrbildschirm angezeigt. Nicht das Passwort.';

  @override
  String get lockHintOptional => 'Hinweis (optional)';

  @override
  String get lockLockedNote => 'Diese Notiz ist gesperrt';

  @override
  String lockMinLength(int count) {
    return 'Mindestens $count Zeichen verwenden.';
  }

  @override
  String get lockMismatch => 'Die Passwörter stimmen nicht überein.';

  @override
  String get lockNewMismatch => 'Die neuen Passwörter stimmen nicht überein.';

  @override
  String get lockNewPassword => 'Neues Passwort';

  @override
  String get lockNotNow => 'Jetzt nicht';

  @override
  String get lockNotesPassword => 'Notizen-Passwort';

  @override
  String get lockNow => 'Jetzt sperren';

  @override
  String get lockNowSubtitle =>
      'Gesperrte Notizen fragen wieder nach dem Passwort';

  @override
  String lockOfferBody(String name) {
    return 'Gesperrte Notizen mit $name öffnen, statt das Passwort einzutippen. Das Passwort funktioniert weiterhin.';
  }

  @override
  String lockOfferTitle(String name) {
    return 'Mit $name entsperren?';
  }

  @override
  String get lockPassword => 'Passwort';

  @override
  String get lockPasswordChanged => 'Notizen-Passwort geändert';

  @override
  String get lockResetBody =>
      'Du wählst ein neues Passwort für Notizen, die du ab jetzt sperrst.\n\nBereits gesperrte Notizen bleiben unter dem alten Passwort gesperrt. Ohne dieses lassen sie sich nicht öffnen – weder von dir noch von uns. Wenn dir das alte Passwort später wieder einfällt, öffnet es sie wieder.';

  @override
  String get lockResetDialogTitle => 'Notizen-Passwort zurücksetzen?';

  @override
  String get lockResetItem => 'Passwort zurücksetzen…';

  @override
  String get lockResetItemSubtitle => 'Bei vergessenem Passwort';

  @override
  String get lockResetPassword => 'Passwort zurücksetzen';

  @override
  String get lockResetTitle => 'Notizen-Passwort zurücksetzen';

  @override
  String get lockSetPassword => 'Passwort festlegen';

  @override
  String get lockSetTitle => 'Notizen-Passwort festlegen';

  @override
  String get lockShowHint => 'Hinweis zeigen';

  @override
  String get lockUnlock => 'Entsperren';

  @override
  String get lockUnlockToContinue =>
      'Gesperrte Notizen entsperren, um fortzufahren.';

  @override
  String lockUseBiometric(String name) {
    return '$name verwenden';
  }

  @override
  String get lockWrongPassword => 'Falsches Passwort';

  @override
  String get macAllNotes => 'Alle Notizen';

  @override
  String get macAllPapers => 'Alle Paper';

  @override
  String get macCreate => 'Anlegen';

  @override
  String get macDeleteFolder => 'Ordner löschen…';

  @override
  String get macDeleteTag => 'Tag löschen…';

  @override
  String get macFolderNameHint => 'Ordnername';

  @override
  String get macHideSidebarTooltip => 'Seitenleiste ausblenden (⌃⌘S)';

  @override
  String get macKeyActualSize => 'Originalgröße';

  @override
  String get macKeyAddComment => 'Kommentar hinzufügen';

  @override
  String get macKeyAttachments => 'Anhänge';

  @override
  String get macKeyBack => 'Zurück';

  @override
  String get macKeyBlockQuote => 'Zitatblock';

  @override
  String get macKeyBody => 'Fließtext';

  @override
  String get macKeyBold => 'Fett';

  @override
  String get macKeyBulletedList => 'Aufzählung';

  @override
  String get macKeyChecklist => 'Checkliste';

  @override
  String get macKeyCitePaper => 'Paper zitieren';

  @override
  String get macKeyCloseDialog => 'Dialog oder Menü schließen';

  @override
  String get macKeyCloseWindow => 'Fenster schließen';

  @override
  String get macKeyDefaultInterface => 'Standardgröße der Oberfläche';

  @override
  String get macKeyDuplicateNote => 'Notiz duplizieren';

  @override
  String get macKeyFindInDocument => 'Im Dokument suchen';

  @override
  String get macKeyFindNext => 'Nächster Treffer';

  @override
  String get macKeyFindPrevious => 'Vorheriger Treffer';

  @override
  String get macKeyHeading => 'Überschrift';

  @override
  String get macKeyHighlight => 'Markieren';

  @override
  String get macKeyImportPdf => 'PDF importieren';

  @override
  String get macKeyItalic => 'Kursiv';

  @override
  String get macKeyLargerInterface => 'Größere Oberfläche';

  @override
  String get macKeyLibrary => 'Bibliothek';

  @override
  String get macKeyLinkNote => 'Mit Notiz verknüpfen';

  @override
  String get macKeyMonospaced => 'Monospace';

  @override
  String get macKeyMoveThroughList => 'In einer Liste navigieren';

  @override
  String get macKeyMoveToTrash => 'In den Papierkorb legen';

  @override
  String get macKeyNewNote => 'Neue Notiz';

  @override
  String get macKeyNextColumn => 'Nächste oder vorherige Spalte';

  @override
  String get macKeyNotes => 'Notizen';

  @override
  String get macKeyNumberedList => 'Nummerierte Liste';

  @override
  String get macKeyOpenSelected => 'Ausgewählten Eintrag öffnen';

  @override
  String get macKeyPrint => 'Drucken';

  @override
  String get macKeyQuickNote => 'Schnellnotiz von überall';

  @override
  String get macKeySearch => 'Suchen';

  @override
  String get macKeySettings => 'Einstellungen';

  @override
  String get macKeyShortcuts => 'Tastaturkurzbefehle';

  @override
  String get macKeySidebar => 'Seitenleiste ein- oder ausblenden';

  @override
  String get macKeySmallerInterface => 'Kleinere Oberfläche';

  @override
  String get macKeyStrikethrough => 'Durchgestrichen';

  @override
  String get macKeySubheading => 'Zwischenüberschrift';

  @override
  String get macKeyTable => 'Tabelle';

  @override
  String get macKeyTitle => 'Titel';

  @override
  String get macKeyUnderline => 'Unterstrichen';

  @override
  String get macKeyZoomIn => 'Vergrößern';

  @override
  String get macKeyZoomOut => 'Verkleinern';

  @override
  String get macMoreMenu => 'Mehr…';

  @override
  String get macNewFolderTitle => 'Neuer Ordner';

  @override
  String get macNewFolderTooltip => 'Neuer Ordner';

  @override
  String get macOpenProjectPage => 'Projektseite öffnen';

  @override
  String get macRenameFolder => 'Ordner umbenennen…';

  @override
  String get macRenameFolderTitle => 'Ordner umbenennen';

  @override
  String macSectionCollapsed(String title) {
    return '$title, eingeklappt';
  }

  @override
  String macSectionExpanded(String title) {
    return '$title, ausgeklappt';
  }

  @override
  String get macShortcutsFormatting => 'Notizen & Formatierung';

  @override
  String get macShortcutsGeneral => 'Allgemein';

  @override
  String get macShortcutsNavigation => 'Navigation';

  @override
  String get macShortcutsReader => 'Bibliothek & Leser';

  @override
  String get macShortcutsTitle => 'Tastaturkurzbefehle';

  @override
  String get macTags => 'Tags';

  @override
  String get markupMarkUp => 'Anmerken';

  @override
  String get markupOpenFailed => 'Bild konnte nicht geöffnet werden.';

  @override
  String get markupSaveFailed => 'Anmerkungen konnten nicht gesichert werden.';

  @override
  String get matrixAddDefaults => 'Methode, Stichprobe, Ergebnisse hinzufügen';

  @override
  String get matrixAddStudyColumns => 'Studienspalten hinzufügen';

  @override
  String get matrixAddTheme => 'Thema hinzufügen';

  @override
  String get matrixAllNotHereYet => 'Alle, die noch fehlen';

  @override
  String get matrixAlreadyAColumn => 'Bereits eine Spalte';

  @override
  String get matrixCellHint => 'Was sagt dieses Paper?';

  @override
  String get matrixColumnFindings => 'Ergebnisse';

  @override
  String get matrixColumnMethod => 'Methode';

  @override
  String get matrixColumnSample => 'Stichprobe';

  @override
  String get matrixCopiedAsMarkdown => 'Tabelle als Markdown kopiert';

  @override
  String get matrixCopyAsMarkdown => 'Als Markdown kopieren';

  @override
  String get matrixDeleteColumn => 'Spalte löschen';

  @override
  String get matrixDeleteTheme => 'Thema mit Einträgen löschen';

  @override
  String get matrixEmptyMessage =>
      'Die Themen hinzufügen, die du vergleichst – Methode, Stichprobe, Ergebnisse – und eintragen, was jedes Paper sagt.';

  @override
  String get matrixEmptyTitle => 'Paper nebeneinander vergleichen';

  @override
  String get matrixExport => 'Exportieren';

  @override
  String get matrixFromHighlights => 'Aus deinen Markierungen';

  @override
  String get matrixFromStudyDetails => 'Aus den Studiendetails';

  @override
  String get matrixNewTheme => 'Neues Thema';

  @override
  String get matrixNoPapers => 'Keine Paper in diesem Projekt';

  @override
  String get matrixNoPapersMessage =>
      'Paper über ihre Seiten hinzufügen und hier vergleichen.';

  @override
  String get matrixPapersKeepDetails => 'Paper behalten ihre Studiendetails';

  @override
  String get matrixRenameTheme => 'Thema umbenennen';

  @override
  String get matrixSeparateWithSemicolon => 'Mit ; trennen';

  @override
  String get matrixShare => 'Teilen…';

  @override
  String matrixShareSubject(String project) {
    return 'Matrix „$project“';
  }

  @override
  String get mdImportAction => 'Markdown oder Obsidian-Vault importieren';

  @override
  String get mdImportActionSubtitle =>
      'Ein Ordner, .md-Dateien oder eine Zip-Datei';

  @override
  String get mdImportChooseTitle => 'Markdown importieren';

  @override
  String get mdImportDoneTitle => 'Import abgeschlossen';

  @override
  String get mdImportFiles => 'Markdown-Dateien';

  @override
  String get mdImportFolder => 'Ein Ordner (Obsidian-Vault)';

  @override
  String get mdImportNothing => 'Dort wurden keine Markdown-Notizen gefunden.';

  @override
  String mdImportProgress(int done, int total) {
    return '$done von $total werden importiert…';
  }

  @override
  String get mdImportReadFailed => 'Das konnte nicht gelesen werden.';

  @override
  String get mdImportReading => 'Dateien werden gelesen…';

  @override
  String mdImportSummaryAttachments(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count Anhänge kopiert',
      one: '1 Anhang kopiert',
    );
    return '$_temp0';
  }

  @override
  String mdImportSummaryFailed(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count Notizen konnten nicht gespeichert werden',
      one: '1 Notiz konnte nicht gespeichert werden',
    );
    return '$_temp0';
  }

  @override
  String mdImportSummaryNotes(int notes) {
    String _temp0 = intl.Intl.pluralLogic(
      notes,
      locale: localeName,
      other: '$notes Notizen importiert',
      one: '1 Notiz importiert',
      zero: 'Keine Notizen importiert',
    );
    return '$_temp0';
  }

  @override
  String mdImportSummarySkipped(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other:
          '$count übersprungen (schon vorhanden, gesperrt oder Paper-Seiten)',
      one: '1 übersprungen (schon vorhanden, gesperrt oder eine Paper-Seite)',
    );
    return '$_temp0';
  }

  @override
  String mdImportSummaryUnresolved(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count Links passten zu nichts und blieben Text',
      one: '1 Link passte zu nichts und blieb Text',
    );
    return '$_temp0';
  }

  @override
  String get mdImportZip => 'Eine Zip-Datei mit Markdown-Dateien';

  @override
  String get notesAddTag => 'Tag hinzufügen';

  @override
  String get notesBeforeRestoring => 'Vor dem Wiederherstellen';

  @override
  String get notesChangePage => 'Seite ändern';

  @override
  String notesCitationLabel(String label) {
    return 'Zitation $label';
  }

  @override
  String notesCitationMissingLabel(String marker) {
    return 'Zitation $marker, Paper nicht gefunden';
  }

  @override
  String notesCitationNotInLibrary(String key) {
    return '@$key ist nicht in der Bibliothek.';
  }

  @override
  String get notesCiteAPaper => 'Paper zitieren';

  @override
  String get notesClear => 'Entfernen';

  @override
  String get notesCompare => 'Vergleichen';

  @override
  String notesCompareChanged(
    String when,
    String words,
    int added,
    int removed,
  ) {
    return '$when · jetzt $words Wörter · $added hinzugefügt, $removed entfernt';
  }

  @override
  String notesCompareSame(String when) {
    return '$when · wie jetzt';
  }

  @override
  String get notesCouldntAddFile => 'Datei konnte nicht hinzugefügt werden.';

  @override
  String get notesCouldntDuplicate => 'Notiz konnte nicht dupliziert werden.';

  @override
  String get notesCouldntPrint => 'Notiz konnte nicht gedruckt werden.';

  @override
  String get notesCreate => 'Anlegen';

  @override
  String get notesDropToAttach => 'Zum Anhängen hier ablegen';

  @override
  String get notesDuplicate => 'Duplizieren';

  @override
  String get notesEquationEmpty => 'Tippen, um eine Formel zu schreiben';

  @override
  String notesEquationLabel(String latex) {
    return 'Formel $latex';
  }

  @override
  String notesFigureCaptionLabel(String name) {
    return 'Beschriftung $name';
  }

  @override
  String get notesFigureMissing => 'Abbildung ??';

  @override
  String notesFigureName(String number) {
    return 'Abbildung $number';
  }

  @override
  String notesFigureReferenceLabel(String name) {
    return 'Verweis auf $name';
  }

  @override
  String get notesFigureReferenceMissing => 'Verweis auf fehlende Abbildung';

  @override
  String get notesFiguresEmpty =>
      'Noch keine Abbildungen oder Tabellen. „/“ eingeben und Abbildungsbeschriftung oder Tabellenbeschriftung wählen.';

  @override
  String get notesFolderName => 'Ordnername';

  @override
  String get notesHighlightBlue => 'Blau';

  @override
  String get notesHighlightGreen => 'Grün';

  @override
  String get notesHighlightPink => 'Rosa';

  @override
  String get notesHighlightPurple => 'Violett';

  @override
  String get notesHighlightYellow => 'Gelb';

  @override
  String get notesImportAPdf => 'PDF importieren';

  @override
  String get notesLatexHint => 'LaTeX, z. B. x^2 + \\alpha';

  @override
  String get notesLatexInvalid =>
      'Noch kein gültiges LaTeX. Es bleibt, wie du es getippt hast.';

  @override
  String get notesLessThanAMinute => '< 1 Min.';

  @override
  String get notesLinkToANote => 'Mit Notiz verknüpfen…';

  @override
  String get notesLockNote => 'Notiz sperren';

  @override
  String notesMinutes(int count) {
    return '$count Min.';
  }

  @override
  String get notesNewFolder => 'Neuer Ordner';

  @override
  String notesNewNoteNamed(String title) {
    return 'Neue Notiz „$title“';
  }

  @override
  String get notesNewTagName => 'Name des neuen Tags';

  @override
  String get notesNoFolder => 'Kein Ordner';

  @override
  String get notesNoPapersFound => 'Keine Paper gefunden.';

  @override
  String get notesNoTagsYet => 'Noch keine Tags.';

  @override
  String get notesNoteLocked => 'Notiz gesperrt';

  @override
  String get notesNothingMatches => 'Nichts gefunden.';

  @override
  String get notesOpenPaper => 'Paper öffnen';

  @override
  String get notesPage => 'Seite';

  @override
  String get notesPageEllipsis => 'Seite…';

  @override
  String get notesPageHint => '42 oder 3–5';

  @override
  String notesPageShort(int page) {
    return 'S. $page';
  }

  @override
  String get notesPinToTop => 'Oben anheften';

  @override
  String get notesPreview => 'Vorschau';

  @override
  String get notesRemoveHighlight => 'Markierung entfernen';

  @override
  String get notesRemoveLock => 'Sperre aufheben';

  @override
  String get notesRenameVersion => 'Version umbenennen';

  @override
  String get notesRestore => 'Wiederherstellen';

  @override
  String get notesRestoreThisVersion => 'Diese Version wiederherstellen';

  @override
  String notesRestoreVersionMessage(String label) {
    return 'Die Notiz wird auf diese Version zurückgesetzt. Der aktuelle Stand wird vorher als „$label“ gesichert.';
  }

  @override
  String get notesRestoreVersionTitle => 'Diese Version wiederherstellen?';

  @override
  String get notesSaveAVersion => 'Version sichern';

  @override
  String get notesSaveVersionNow => 'Jetzt Version sichern';

  @override
  String get notesSavedVersion => 'Gesicherte Version';

  @override
  String get notesSearchFigures => 'Abbildungen und Tabellen suchen';

  @override
  String get notesSearchPapersToLink => 'Paper zum Verknüpfen suchen';

  @override
  String get notesSentToSupervisor => 'An Betreuer:in gesendet';

  @override
  String get notesSet => 'Setzen';

  @override
  String get notesStatsCharacters => 'Zeichen';

  @override
  String get notesStatsCitations => 'Zitationen';

  @override
  String get notesStatsLinkedPapers => 'Verknüpfte Paper';

  @override
  String get notesStatsParagraphs => 'Absätze';

  @override
  String get notesStatsReadingTime => 'Lesezeit';

  @override
  String get notesStatsWords => 'Wörter';

  @override
  String get notesTableMissing => 'Tabelle ??';

  @override
  String notesTableName(String number) {
    return 'Tabelle $number';
  }

  @override
  String get notesTemplateCritique => 'Kritik';

  @override
  String get notesTemplateFindings => 'Ergebnisse';

  @override
  String get notesTemplateMethod => 'Methode';

  @override
  String get notesTemplateSummary => 'Zusammenfassung';

  @override
  String notesUnchangedLines(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count unveränderte Zeilen',
      one: '1 unveränderte Zeile',
    );
    return '$_temp0';
  }

  @override
  String get notesUnlock => 'Entsperren';

  @override
  String get notesUnlockToCompare =>
      'Notiz entsperren, um ihre Versionen zu vergleichen.';

  @override
  String get notesUnlockToCompareOrRestore =>
      'Notiz entsperren, um Versionen zu vergleichen oder wiederherzustellen.';

  @override
  String get notesUnlockToDuplicate =>
      'Notiz entsperren, um sie zu duplizieren.';

  @override
  String get notesUnlockToPrint => 'Notiz entsperren, um sie zu drucken.';

  @override
  String get notesUnlockToRestore =>
      'Notiz entsperren, um sie wiederherzustellen.';

  @override
  String get notesUnpin => 'Lösen';

  @override
  String get notesVersionDeleted => 'Version gelöscht';

  @override
  String get notesVersionNameHint => 'Name (optional)';

  @override
  String get notesVersionOptions => 'Versionsoptionen';

  @override
  String get notesVersionRestored => 'Version wiederhergestellt';

  @override
  String get notesVersions => 'Versionen';

  @override
  String get notesVersionsEmptyMessage =>
      'Eine Version ist eine gesicherte Kopie dieser Notiz. Eine wird automatisch angelegt, wenn ein Kapitel zur Betreuer:in geht, und du kannst jederzeit selbst eine sichern.';

  @override
  String get notesVersionsEmptyTitle => 'Noch keine Versionen';

  @override
  String notesVersionsSince(String delta) {
    return '$delta seitdem';
  }

  @override
  String notesVersionsWords(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count Wörter',
      one: '1 Wort',
    );
    return '$_temp0';
  }

  @override
  String ocrReadingText(int percent) {
    return 'Text wird gelesen… $percent %';
  }

  @override
  String get ocrRecogniseText => 'Text erkennen';

  @override
  String get ocrRecogniseTextHint => 'Scan durchsuchen und markieren';

  @override
  String get outlineEmpty => 'Diese Notiz hat noch keine Überschriften';

  @override
  String get outlineKeyOutline => 'Gliederung anzeigen';

  @override
  String get outlineShowGrid => 'Als Raster anzeigen';

  @override
  String get outlineShowList => 'Als Liste anzeigen';

  @override
  String get outlineTitle => 'Gliederung';

  @override
  String get panesClose => 'Bereich schließen';

  @override
  String get panesSetting => 'Links in neuen Fenstern öffnen';

  @override
  String get panesSettingSubtitle =>
      'Ein Link in einer Notiz oder einem Paper öffnet sich daneben, statt sie zu ersetzen';

  @override
  String get panesUntitled => 'Ohne Titel';

  @override
  String get paperAbstract => 'Abstract';

  @override
  String get paperAddToProject => 'Zu Projekt hinzufügen';

  @override
  String get paperAttachmentsEmpty =>
      'Podcasts, Bilder, Links oder Dateien zu diesem Paper.';

  @override
  String paperAttachmentsError(String error) {
    return 'Anhänge konnten nicht geladen werden: $error';
  }

  @override
  String get paperAuthorsHelper => 'Autoren mit ; trennen';

  @override
  String get paperAuthorsHint => 'Autoren';

  @override
  String get paperCitation => 'Zitation';

  @override
  String get paperCitationStyle => 'Zitierstil';

  @override
  String paperContinueReading(int page) {
    return 'Weiterlesen · S. $page';
  }

  @override
  String get paperDetails => 'Details';

  @override
  String get paperDownloadFileFailed =>
      'Die Datei konnte nicht geladen werden. Versuche es erneut.';

  @override
  String get paperDownloadPdf => 'PDF laden';

  @override
  String get paperDownloadPdfFailed =>
      'Das PDF konnte nicht geladen werden. Versuche es erneut.';

  @override
  String get paperDownloading => 'Wird geladen …';

  @override
  String get paperEditAuthors => 'Autoren bearbeiten';

  @override
  String get paperEnterIdentifier =>
      'Gib zuerst eine DOI, arXiv- oder PubMed-ID ein.';

  @override
  String get paperExportWithHighlights => 'Mit Markierungen exportieren';

  @override
  String get paperFilledIn => 'Fehlende Angaben ergänzt.';

  @override
  String get paperHighlights => 'Markierungen';

  @override
  String get paperIdentifierLabel => 'DOI, arXiv- oder PubMed-ID';

  @override
  String get paperLink => 'Link';

  @override
  String get paperLookUp => 'Suchen';

  @override
  String get paperLookupUnreachable => 'Der Suchdienst ist nicht erreichbar.';

  @override
  String get paperMoreStyles => 'Mehr …';

  @override
  String get paperNothingNew => 'Nichts Neues zu ergänzen.';

  @override
  String get paperOpenInPubmed => 'In PubMed öffnen';

  @override
  String get paperOpenLink => 'Link öffnen';

  @override
  String paperPageShort(int page) {
    return 'S. $page';
  }

  @override
  String get paperProject => 'Projekt';

  @override
  String get paperPubmedId => 'PubMed-ID';

  @override
  String get paperReadWithNote => 'Mit Notiz lesen';

  @override
  String get paperReferencedInNotes => 'In Notizen erwähnt';

  @override
  String get paperTitleHint => 'Titel';

  @override
  String get paperVenue => 'Zeitschrift oder Konferenz';

  @override
  String get paperYear => 'Jahr';

  @override
  String get platformUntitledPaper => 'Paper ohne Titel';

  @override
  String platformWidgetPage(int page) {
    return 'S. $page';
  }

  @override
  String get projectsAbbrCopyAsText => 'Als Text kopieren';

  @override
  String projectsAbbrDefined(int count) {
    return '$count erklärt';
  }

  @override
  String get projectsAbbrList => 'Liste';

  @override
  String get projectsAbbrListTitle => 'Abkürzungsverzeichnis';

  @override
  String projectsAbbrNeverSpelled(int count) {
    return 'Nie ausgeschrieben ($count)';
  }

  @override
  String projectsAbbrToCheck(int count) {
    return '$count zu prüfen';
  }

  @override
  String projectsAbbrUsedBefore(String abbreviation) {
    return '$abbreviation wird vor der Erklärung verwendet';
  }

  @override
  String get projectsAbbreviations => 'Abkürzungen';

  @override
  String get projectsAddChapter => 'Kapitel hinzufügen';

  @override
  String get projectsBibliography => 'Literaturverzeichnis';

  @override
  String projectsBibliographySubject(String project) {
    return 'Literaturverzeichnis „$project“';
  }

  @override
  String get projectsBibliographySubtitle => 'Alle Paper in einem Zitierstil';

  @override
  String get projectsChangeDate => 'Datum ändern';

  @override
  String get projectsChangeDueDate => 'Abgabedatum ändern';

  @override
  String get projectsChangeStatus => 'Status ändern';

  @override
  String projectsChapterCitations(int chapter, int count) {
    return 'Kap. $chapter · $count×';
  }

  @override
  String get projectsChapterOptions => 'Kapiteloptionen';

  @override
  String get projectsChapters => 'Kapitel';

  @override
  String projectsChaptersFinal(int finished, int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count Kapiteln',
      one: '1 Kapitel',
    );
    return '$finished von $_temp0 final';
  }

  @override
  String get projectsChaptersLockedReason =>
      'Einige Kapitel sind gesperrt. Entsperren, um sie einzubeziehen.';

  @override
  String get projectsCitations => 'Zitationen';

  @override
  String projectsCitedInChapters(int count) {
    return 'In Kapiteln zitiert ($count)';
  }

  @override
  String projectsCitedOutside(int count) {
    return 'Zitiert, nicht in diesem Projekt ($count)';
  }

  @override
  String get projectsClearDate => 'Datum entfernen';

  @override
  String get projectsClearDueDate => 'Abgabedatum entfernen';

  @override
  String get projectsCreateAndAdd => 'Anlegen und hinzufügen';

  @override
  String get projectsDatePattern => 'd. MMMM';

  @override
  String get projectsDatePatternYear => 'd. MMMM y';

  @override
  String projectsDaysAgo(int days) {
    String _temp0 = intl.Intl.pluralLogic(
      days,
      locale: localeName,
      other: '$days Tagen',
      one: '1 Tag',
    );
    return 'vor $_temp0';
  }

  @override
  String get projectsDeleteMessage =>
      'Paper und Notizen bleiben in der Bibliothek; nur die Gruppierung verschwindet.';

  @override
  String get projectsDeleteProject => 'Projekt löschen';

  @override
  String get projectsDeleteProjectSubtitle =>
      'Paper und Notizen bleiben erhalten';

  @override
  String projectsDeleteTitle(String name) {
    return '„$name“ löschen?';
  }

  @override
  String projectsDue(String date, String rest) {
    return 'Fällig am $date · $rest';
  }

  @override
  String projectsDueToday(String date) {
    return 'Fällig heute · $date';
  }

  @override
  String get projectsExportCancelledLocked =>
      'Export abgebrochen: Kapitel sind gesperrt.';

  @override
  String get projectsExportProject => 'Projekt exportieren';

  @override
  String get projectsExportProjectSubtitle => 'Die Notizen als ein Dokument';

  @override
  String get projectsFigureTodo => 'Abbildung';

  @override
  String projectsHighlightCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count Markierungen',
      one: '1 Markierung',
    );
    return '$_temp0';
  }

  @override
  String projectsInDays(int days) {
    String _temp0 = intl.Intl.pluralLogic(
      days,
      locale: localeName,
      other: '$days Tagen',
      one: '1 Tag',
    );
    return 'in $_temp0';
  }

  @override
  String get projectsMap => 'Karte';

  @override
  String get projectsNeedsCitation => 'Braucht eine Zitation';

  @override
  String get projectsNewProject => 'Neues Projekt';

  @override
  String get projectsNoNotesYet => 'Noch keine Notizen in diesem Projekt.';

  @override
  String get projectsNoPapersYet => 'Noch keine Paper in diesem Projekt.';

  @override
  String get projectsNoStatus => 'Kein Status';

  @override
  String projectsNoteCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count Notizen',
      one: '1 Notiz',
    );
    return '$_temp0';
  }

  @override
  String get projectsNothingYet => 'Noch nichts hier';

  @override
  String get projectsNothingYetMessage =>
      'Mit „Zu Projekt hinzufügen“ bei einem Paper oder einer Notiz sammelst du sie hier.';

  @override
  String get projectsOpenProject => 'Projekt öffnen';

  @override
  String get projectsOpenProjectSubtitle =>
      'Paper, Notizen und Lesefortschritt';

  @override
  String projectsPaperCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count Paper',
      one: '1 Paper',
    );
    return '$_temp0';
  }

  @override
  String get projectsPapers => 'Paper';

  @override
  String get projectsPickerIntro =>
      'Ein Projekt gruppiert Paper und Notizen für ein Review, ein Kapitel oder eine Arbeit, an der du schreibst.';

  @override
  String projectsReadNotCited(int count) {
    return 'Gelesen, aber nicht zitiert ($count)';
  }

  @override
  String projectsReadProgress(int done, int total) {
    return '$done von $total gelesen';
  }

  @override
  String get projectsRemoveFromProject => 'Aus Projekt entfernen';

  @override
  String get projectsRenameProject => 'Projekt umbenennen';

  @override
  String get projectsSetDueDate => 'Abgabedatum festlegen';

  @override
  String get projectsStatus => 'Status';

  @override
  String get projectsStatusDraft => 'Entwurf';

  @override
  String get projectsStatusFinal => 'Final';

  @override
  String get projectsStatusOutline => 'Gliederung';

  @override
  String get projectsStatusRead => 'Gelesen';

  @override
  String get projectsStatusReading => 'Am Lesen';

  @override
  String get projectsStatusRevised => 'Überarbeitet';

  @override
  String get projectsStatusToRead => 'Zu lesen';

  @override
  String get projectsStatusWithSupervisor => 'Bei Betreuer:in';

  @override
  String get projectsSubmissionDate => 'Abgabedatum';

  @override
  String get projectsSubmissionDateSubtitle => 'Das Datum der Abgabe';

  @override
  String get projectsSynthesisMatrix => 'Synthesematrix';

  @override
  String get projectsSynthesisMatrixSubtitle => 'Paper nach Themen vergleichen';

  @override
  String get projectsTodoWord => 'TODO';

  @override
  String projectsTodosTitle(int count) {
    return 'To-dos im Text ($count)';
  }

  @override
  String get projectsWordTarget => 'Wortziel';

  @override
  String get projectsWordTargetHint => 'z. B. 8000';

  @override
  String projectsWords(int words) {
    final intl.NumberFormat wordsNumberFormat =
        intl.NumberFormat.decimalPattern(localeName);
    final String wordsString = wordsNumberFormat.format(words);

    String _temp0 = intl.Intl.pluralLogic(
      words,
      locale: localeName,
      other: '$wordsString Wörter',
      one: '1 Wort',
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

    return '$wordsString / $targetString Wörter';
  }

  @override
  String get readAloudBack => 'Zurück zur Vorlesestelle';

  @override
  String get readAloudFinished => 'Beendet';

  @override
  String get readAloudNext => 'Nächster Satz';

  @override
  String get readAloudNoText => 'Kein Text';

  @override
  String get readAloudPause => 'Pause';

  @override
  String get readAloudPlay => 'Wiedergabe';

  @override
  String get readAloudPreparing => 'Lädt…';

  @override
  String get readAloudPrevious => 'Voriger Satz';

  @override
  String get readAloudSpeed => 'Tempo';

  @override
  String get readAloudStop => 'Vorlesen beenden';

  @override
  String get reviewCaughtUp => 'Alles erledigt';

  @override
  String get reviewDismiss => 'Bis morgen ausblenden';

  @override
  String get reviewEmptyMessage =>
      'Markierungen erscheinen hier einen Tag nach dem Erstellen und danach immer seltener.';

  @override
  String get reviewKeep => 'Behalten';

  @override
  String get reviewLater => 'Die behaltenen kommen später wieder.';

  @override
  String get reviewNothing => 'Nichts zu wiederholen';

  @override
  String get reviewOpenInPaper => 'Im Paper öffnen';

  @override
  String reviewPosition(int current, int total) {
    return '$current von $total';
  }

  @override
  String reviewPrompt(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count Markierungen zum Wiederholen',
      one: '1 Markierung zum Wiederholen',
    );
    return '$_temp0';
  }

  @override
  String reviewQuote(String quote) {
    return '„$quote“';
  }

  @override
  String get reviewRemind => 'Auf dem Home-Bildschirm erinnern';

  @override
  String get reviewRemindHint =>
      'Eine einzelne, leise Zeile, wenn etwas fällig ist';

  @override
  String get reviewSkip => 'Überspringen';

  @override
  String reviewSource(String title, int page) {
    return '$title · S. $page';
  }

  @override
  String get reviewTitle => 'Markierungen wiederholen';

  @override
  String get reviewTomorrow => 'Sie kommen morgen wieder.';

  @override
  String get savedSearchDelete => 'Löschen';

  @override
  String savedSearchDeleted(String name) {
    return '„$name“ gelöscht';
  }

  @override
  String get savedSearchDialogTitle => 'Suche speichern';

  @override
  String get savedSearchHeading => 'Gespeicherte Suchen';

  @override
  String get savedSearchNameLabel => 'Name';

  @override
  String get savedSearchRename => 'Umbenennen';

  @override
  String get savedSearchRenameTitle => 'Suche umbenennen';

  @override
  String get savedSearchSave => 'Suche speichern';

  @override
  String get savedSearchSection => 'Gespeicherte Suchen';

  @override
  String get savedSearchTipsBody =>
      '„genaue Wendung“ und -Wort, um ein Wort auszuschließen\ntag:name, folder:name, project:name\nin:notes, in:papers, in:highlights, in:pdfs\nis:pinned, is:template, is:daily\nMit - davor schließt du den Filter aus. Namen mit Leerzeichen in Anführungszeichen: tag:\"deep learning\"';

  @override
  String get savedSearchTipsLink => 'Suchtipps';

  @override
  String get searchAttachments => 'Anhänge';

  @override
  String get searchClear => 'Löschen';

  @override
  String get searchEmptyMessage =>
      'Eine Notiz, ein Paper oder eine markierte Passage finden.';

  @override
  String get searchEmptyTitle => 'Alles durchsuchen';

  @override
  String get searchHint => 'Notizen, Paper und Markierungen durchsuchen';

  @override
  String get searchIndexing => 'Paper werden indexiert…';

  @override
  String get searchKindHighlights => 'Markierungen';

  @override
  String get searchKindInPapers => 'In Papern';

  @override
  String get searchKindPapers => 'Paper';

  @override
  String get searchMap => 'Karte';

  @override
  String get searchNoMatches => 'Keine Treffer';

  @override
  String get searchNoMatchesHint => 'Weniger oder andere Wörter versuchen.';

  @override
  String searchPage(int page) {
    return 'S. $page';
  }

  @override
  String get settingsAppearance => 'Erscheinungsbild';

  @override
  String get settingsBackUp => 'In Datei sichern';

  @override
  String get settingsBackUpSubtitle =>
      'Notizen, Paper und Dateien in einer ZIP-Datei';

  @override
  String get settingsBackupFailed => 'Das Backup konnte nicht erstellt werden.';

  @override
  String get settingsBackupSubject => 'Corplex-Backup';

  @override
  String get settingsCantRestore => 'Wiederherstellen nicht möglich';

  @override
  String get settingsClearAndSignOut => 'Leeren und abmelden';

  @override
  String get settingsClearTitle => 'Dieses Gerät leeren?';

  @override
  String settingsErasePending(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other:
          '$count Änderungen auf diesem Gerät wurden nicht synchronisiert und gehen endgültig verloren. Alles andere ist sicher in deinem Konto.',
      one: 'Eine Änderung auf diesem Gerät wurde nicht synchronisiert und geht endgültig verloren. Alles andere ist sicher in deinem Konto.',
    );
    return '$_temp0';
  }

  @override
  String get settingsEraseSafe =>
      'Notizen, Paper und Dateien auf diesem Gerät werden entfernt. Alles ist sicher in deinem Konto.';

  @override
  String get settingsExport => 'Exportieren';

  @override
  String get settingsExportBody =>
      'Eine Markdown-Datei pro Notiz und Paper, mit Verknüpfungen, Markierungen und einer BibTeX-Datei. Den Ordner als Obsidian-Vault öffnen.';

  @override
  String get settingsExportFailed => 'Der Export konnte nicht erstellt werden.';

  @override
  String get settingsExportLocked =>
      'Gesperrte Notizen werden als Platzhalter exportiert.';

  @override
  String get settingsExportMarkdown => 'Als Markdown exportieren';

  @override
  String get settingsExportMarkdownSubtitle =>
      'Ein Ordner mit Notizen für Obsidian';

  @override
  String get settingsExportSubject => 'Corplex-Notizen (Markdown)';

  @override
  String get settingsIncludePdfs => 'PDFs einschließen';

  @override
  String get settingsIncludePdfsSubtitle => 'Macht den Export deutlich größer';

  @override
  String get settingsInterfaceSize => 'Oberflächengröße';

  @override
  String get settingsInterfaceSizeSubtitle =>
      'Für große oder Ultrawide-Displays';

  @override
  String get settingsOnDemand => 'Dateien beim Öffnen laden';

  @override
  String get settingsOnDemandSubtitle =>
      'Sonst werden Paper und Audio im Hintergrund geladen.';

  @override
  String get settingsOneMoreStep => 'Noch ein Schritt';

  @override
  String get settingsPreparingBackup => 'Backup wird vorbereitet…';

  @override
  String get settingsQuickNote => 'Kurzbefehl für Schnellnotiz (⌃⌥N)';

  @override
  String get settingsQuickNoteSubtitle => 'Notiz aus jeder App starten';

  @override
  String get settingsReadingNight => 'Nacht';

  @override
  String get settingsReadingPaper => 'Papier';

  @override
  String get settingsReadingSepia => 'Sepia';

  @override
  String get settingsReplace => 'Ersetzen';

  @override
  String get settingsReplaceTitle => 'Daten dieses Geräts ersetzen?';

  @override
  String get settingsRestartToFinish =>
      'Corplex vollständig beenden und erneut öffnen, um die Wiederherstellung abzuschließen.';

  @override
  String get settingsRestoreAction => 'Wiederherstellen';

  @override
  String settingsRestoreBody(String date, int notes, int papers) {
    String _temp0 = intl.Intl.pluralLogic(
      notes,
      locale: localeName,
      other: '$notes Notizen',
      one: '1 Notiz',
    );
    String _temp1 = intl.Intl.pluralLogic(
      papers,
      locale: localeName,
      other: '$papers Paper',
      one: '1 Paper',
    );
    return 'Vom $date: $_temp0 und $_temp1.\n\nDas ersetzt, was sich jetzt auf diesem Gerät befindet. Deine aktuelle Bibliothek bleibt für den Fall der Fälle erhalten.';
  }

  @override
  String get settingsRestoreFromBackup => 'Aus Backup wiederherstellen';

  @override
  String get settingsRestoreTitle => 'Dieses Backup wiederherstellen?';

  @override
  String get settingsSignIn => 'Anmelden';

  @override
  String get settingsSignInSubtitle =>
      'Bibliothek geräteübergreifend synchronisieren';

  @override
  String get settingsSignOut => 'Abmelden';

  @override
  String get settingsSignOutClear => 'Abmelden und dieses Gerät leeren';

  @override
  String get settingsSpellCheck => 'Rechtschreibung beim Tippen prüfen';

  @override
  String get settingsSyncFailed => 'Synchronisierung fehlgeschlagen';

  @override
  String get settingsSyncNow => 'Jetzt synchronisieren';

  @override
  String get settingsSyncOffline => 'Wird nicht synchronisiert';

  @override
  String get settingsSyncSyncing => 'Synchronisiere…';

  @override
  String get settingsSyncUpToDate => 'Auf dem neuesten Stand';

  @override
  String get settingsThemeAuto => 'Auto';

  @override
  String get settingsThemeDark => 'Dunkel';

  @override
  String get settingsThemeLight => 'Hell';

  @override
  String settingsTrashCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count Einträge',
      one: '1 Eintrag',
    );
    return '$_temp0';
  }

  @override
  String get settingsUseThisAccount =>
      'Dieses Konto auf diesem Gerät verwenden';

  @override
  String get settingsUseThisAccountSubtitle =>
      'Ersetzt die Daten auf diesem Gerät durch die Daten dieses Kontos.';

  @override
  String get settingsWifiOnly => 'Dateien nur über WLAN senden';

  @override
  String get settingsWifiOnlySubtitle =>
      'Notizen werden immer synchronisiert. Beim Öffnen wird eine Datei in jedem Netz geladen.';

  @override
  String shareAddedToLibrary(String name) {
    return '„$name“ zur Bibliothek hinzugefügt';
  }

  @override
  String shareAttachTo(String name) {
    return '„$name“ anhängen an …';
  }

  @override
  String get shareAudioAttached => 'Audio angehängt';

  @override
  String get shareNewNote => 'Eine neue Notiz';

  @override
  String get shareSavedAsNote => 'Als Notiz gesichert';

  @override
  String get shareSavedLink => 'Link als Notiz gesichert';

  @override
  String get spellIgnore => 'Schreibweise ignorieren';

  @override
  String get spellIgnoreGrammar => 'Grammatik ignorieren';

  @override
  String get spellLearn => 'Schreibweise lernen';

  @override
  String get spotlightSetting => 'In Spotlight anzeigen';

  @override
  String get spotlightSettingSubtitle =>
      'Notizen, Papers und Projekte über die Spotlight-Suche von macOS finden. Eine gesperrte Notiz zeigt nur ihren Titel.';

  @override
  String get studyAdd => 'Studiendetails hinzufügen';

  @override
  String get studyChip => 'Studie';

  @override
  String studyChipCount(int count) {
    return 'Studie · $count';
  }

  @override
  String get studyClear => 'Zurücksetzen';

  @override
  String get studyClearFilter => 'Studienfilter löschen';

  @override
  String get studyDetails => 'Studiendetails';

  @override
  String get studyFieldBrainRegions => 'Hirnregionen';

  @override
  String get studyFieldParadigm => 'Aufgabe / Paradigma';

  @override
  String get studyFieldSampleSize => 'Stichprobengröße (n)';

  @override
  String get studyFieldSpecies => 'Spezies / Modell';

  @override
  String get studyFieldTechniques => 'Methoden';

  @override
  String get studyListHint => 'Zum Hinzufügen Eingabe oder Komma drücken';

  @override
  String get studyMinSampleSize => 'Minimale Stichprobengröße (n)';

  @override
  String get switcherCmdAttachments => 'Anhänge anzeigen';

  @override
  String get switcherCmdBibliography => 'Literaturverzeichnis einfügen';

  @override
  String get switcherCmdExport => 'Als Markdown exportieren…';

  @override
  String get switcherCmdImportPdf => 'PDF importieren…';

  @override
  String get switcherCmdLockAll => 'Alle Notizen sperren';

  @override
  String get switcherCmdLockNote => 'Notiz sperren';

  @override
  String get switcherCmdNewNote => 'Neue Notiz';

  @override
  String get switcherCmdOpenProject => 'Projekt öffnen…';

  @override
  String get switcherCmdSettings => 'Einstellungen';

  @override
  String get switcherCmdShortcuts => 'Tastaturkurzbefehle…';

  @override
  String get switcherCmdToday => 'Heutige Notiz';

  @override
  String get switcherCommands => 'Befehle';

  @override
  String get switcherFolders => 'Ordner';

  @override
  String get switcherHeadings => 'Überschriften dieser Notiz';

  @override
  String get switcherHelp =>
      '# Überschriften dieser Notiz · > Befehle · ⌘↩ daneben · ⌥↩ öffnet das PDF';

  @override
  String get switcherHintJump => 'Springen';

  @override
  String get switcherHintOpen => 'Öffnen';

  @override
  String get switcherHintRun => 'Ausführen';

  @override
  String get switcherHintShow => 'Zeigen';

  @override
  String get switcherKeyGoTo => 'Gehe zu…';

  @override
  String get switcherKeyNextHeading => 'Nächste Überschrift';

  @override
  String get switcherKeyOpenLink => 'Link öffnen';

  @override
  String get switcherKeyPrevHeading => 'Vorherige Überschrift';

  @override
  String get switcherNoLink => 'Kein Link an der Schreibmarke.';

  @override
  String get switcherNoNote =>
      'Öffne eine Notiz, um zu ihren Überschriften zu springen.';

  @override
  String switcherNoResults(String query) {
    return 'Nichts passt zu „$query“';
  }

  @override
  String get switcherNotes => 'Notizen';

  @override
  String get switcherPapers => 'Papers';

  @override
  String get switcherPinned => 'Angeheftet';

  @override
  String get switcherPlaceholder => 'Zu Notiz, Paper oder Projekt springen';

  @override
  String get switcherProjects => 'Projekte';

  @override
  String get switcherRecent => 'Zuletzt';

  @override
  String get switcherSearches => 'Gespeicherte Suchen';

  @override
  String get switcherSubFolder => 'Ordner';

  @override
  String get switcherSubLocked => 'Gesperrt';

  @override
  String get switcherSubProject => 'Projekt';

  @override
  String get switcherSubSearch => 'Gespeicherte Suche';

  @override
  String get switcherSubTag => 'Tag';

  @override
  String get switcherTags => 'Tags';

  @override
  String get switcherTitle => 'Schnellwechsler';

  @override
  String get syncAccountMismatch =>
      'Dieses Gerät enthält Daten eines anderen Kontos. Melde dich wieder bei diesem Konto an, um zu synchronisieren.';

  @override
  String get syncFilesIncomplete =>
      'Einige Dateien sind noch nicht synchronisiert.';

  @override
  String get syncGenericError =>
      'Synchronisierung nicht möglich. Deine Notizen sind sicher auf diesem Gerät.';

  @override
  String get syncServerOutdated =>
      'Dein Sync-Server braucht ein Datenbank-Update. Führe die neuesten Dateien aus supabase/migrations in deinem Supabase-Projekt aus.';

  @override
  String get tableAddColumnLeft => 'Spalte links einfügen';

  @override
  String get tableAddColumnRight => 'Spalte rechts einfügen';

  @override
  String get tableAddRowAbove => 'Zeile oberhalb einfügen';

  @override
  String get tableAddRowBelow => 'Zeile unterhalb einfügen';

  @override
  String get tableDeleteColumn => 'Spalte löschen';

  @override
  String get tableDeleteRow => 'Zeile löschen';

  @override
  String get tableDeleteTable => 'Tabelle löschen';

  @override
  String get tableHeaderRow => 'Kopfzeile';

  @override
  String get tableTooltip => 'Tabelle';

  @override
  String get templatesInsert => 'Vorlage einfügen';

  @override
  String get templatesInsertHint => 'Eine deiner Vorlagen hier einfügen';

  @override
  String get templatesLiterature => 'Literaturnotiz';

  @override
  String get templatesStopUsing => 'Nicht mehr als Vorlage verwenden';

  @override
  String get templatesTitle => 'Vorlagen';

  @override
  String get templatesUnlockReason => 'Zum Verwenden dieser Vorlage entsperren';

  @override
  String get templatesUntitled => 'Vorlage ohne Titel';

  @override
  String get templatesUse => 'Als Vorlage verwenden';

  @override
  String trashDaysLeft(int days) {
    String _temp0 = intl.Intl.pluralLogic(
      days,
      locale: localeName,
      other: 'noch $days Tage',
      one: 'noch 1 Tag',
    );
    return '$_temp0';
  }

  @override
  String get trashDeletingSoon => 'wird bald gelöscht';

  @override
  String get trashEmptyAction => 'Leeren';

  @override
  String trashEmptyBody(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count Einträge werden endgültig gelöscht.',
      one: '1 Eintrag wird endgültig gelöscht.',
    );
    return '$_temp0';
  }

  @override
  String trashEmptyMessage(int days) {
    String _temp0 = intl.Intl.pluralLogic(
      days,
      locale: localeName,
      other: '$days Tage',
      one: '1 Tag',
    );
    return 'Gelöschte Notizen und Paper bleiben hier $_temp0 lang.';
  }

  @override
  String get trashEmptyTitle => 'Papierkorb leeren?';

  @override
  String get trashIsEmpty => 'Papierkorb ist leer';

  @override
  String trashKept(int days) {
    String _temp0 = intl.Intl.pluralLogic(
      days,
      locale: localeName,
      other: '$days Tage',
      one: '1 Tag',
    );
    return '$_temp0 aufbewahrt, danach endgültig gelöscht.';
  }

  @override
  String get trashKindNote => 'Notiz';

  @override
  String get trashKindPaper => 'Paper';

  @override
  String trashMovedToTrash(String label) {
    return '$label in den Papierkorb gelegt';
  }

  @override
  String trashQuoted(String title) {
    return '„$title“';
  }

  @override
  String get trashRestore => 'Wiederherstellen';

  @override
  String get trashRestored => 'Wiederhergestellt';

  @override
  String get viewerAboutThisPaper => 'Zu diesem Paper';

  @override
  String get viewerCloseSearch => 'Suche schließen';

  @override
  String get viewerContents => 'Inhalt';

  @override
  String get viewerDrawOnPage => 'Auf der Seite zeichnen';

  @override
  String get viewerExportDamaged =>
      'Dieses PDF kann nicht markiert werden: Der Aufbau ist beschädigt oder nutzt Funktionen, in die Corplex nicht schreiben kann.';

  @override
  String get viewerExportEncrypted =>
      'Dieses PDF ist verschlüsselt, daher können keine Markierungen hineingeschrieben werden.';

  @override
  String get viewerExportFailed => 'Dieses PDF konnte nicht exportiert werden.';

  @override
  String get viewerExportNoPdf =>
      'Das PDF dieses Papers ist nicht auf diesem Gerät.';

  @override
  String get viewerExportNotPdf =>
      'Diese Datei ist kein PDF, das Corplex lesen kann.';

  @override
  String get viewerExportNothing =>
      'Nichts zu exportieren: Die Markierungen passen nicht zu den Seiten dieses PDFs.';

  @override
  String get viewerFind => 'Im Dokument suchen';

  @override
  String viewerFindCount(int current, int total) {
    return '$current von $total';
  }

  @override
  String viewerFindCountMore(int current, int total) {
    return '$current von $total+';
  }

  @override
  String get viewerFindNoMatches => 'Keine Treffer';

  @override
  String get viewerFindNoMatchesYet => 'Noch keine Treffer';

  @override
  String get viewerFindSearching => 'Suche läuft…';

  @override
  String get viewerFocus => 'Fokusmodus';

  @override
  String get viewerFocusHint => 'Seite antippen, um zurückzukehren';

  @override
  String get viewerHighlightColour => 'Markierungsfarbe';

  @override
  String get viewerNextMatch => 'Nächster Treffer';

  @override
  String get viewerNightPage => 'Nachtseite';

  @override
  String get viewerNoContents => 'Dieses PDF hat kein Inhaltsverzeichnis.';

  @override
  String viewerNotesOn(String title) {
    return 'Notizen zu $title';
  }

  @override
  String viewerPageLong(int page) {
    return 'Seite $page';
  }

  @override
  String viewerPagePill(int page, int count) {
    return '$page / $count';
  }

  @override
  String viewerPageShort(int page) {
    return 'S. $page';
  }

  @override
  String get viewerPageStrip => 'Seitenleiste';

  @override
  String get viewerPaperPage => 'Papierseite';

  @override
  String get viewerPreviousMatch => 'Vorheriger Treffer';

  @override
  String get viewerQuoteAdded => 'Zur Notiz hinzugefügt';

  @override
  String get viewerQuoteNewNote => 'Neue Notiz';

  @override
  String get viewerReadAloud => 'Vorlesen';

  @override
  String get viewerReadAloudUnavailable => 'Vorlesen ist hier nicht verfügbar';

  @override
  String get viewerRecentNotes => 'Letzte Notizen';

  @override
  String get viewerSepiaPage => 'Sepiaseite';

  @override
  String get viewerShowPages => 'Seiten anzeigen';

  @override
  String get viewerSnapPrompt => 'Rahmen um Abbildung oder Tabelle ziehen';

  @override
  String get viewerSnapWholeView => 'Ganze Ansicht';

  @override
  String get viewerSnapshot => 'Schnappschuss in Notiz';

  @override
  String get viewerSnapshotHint => 'Für Abbildungen und Tabellen';

  @override
  String get viewerStopDrawing => 'Zeichnen beenden';

  @override
  String get viewerStopReadAloud => 'Vorlesen beenden';

  @override
  String get viewerUnlockToAdd => 'Notiz entsperren, um etwas hinzuzufügen.';

  @override
  String get viewerUnlockToQuote =>
      'Notiz entsperren, um dieses Zitat hinzuzufügen.';

  @override
  String get voiceDictate => 'Diktieren';

  @override
  String get voiceFinishing => 'Wird abgeschlossen …';

  @override
  String get voiceMicDenied =>
      'Corplex braucht das Mikrofon für Aufnahmen. Du kannst den Zugriff in den Einstellungen erlauben.';

  @override
  String get voiceNoSpeechCaught => 'Keine Sprache erkannt.';

  @override
  String get voiceNote => 'Sprachnotiz';

  @override
  String voiceNoteTitle(String date) {
    return 'Sprachnotiz, $date';
  }

  @override
  String get voiceOpenSettings => 'Einstellungen öffnen';

  @override
  String get voiceRecordingUnavailable =>
      'Aufnehmen ist hier nicht möglich, daher wurde nichts aufgenommen.';

  @override
  String get voiceSavedAllowSpeech =>
      'Audio gesichert. Erlaube die Spracherkennung, um auch Text zu erhalten.';

  @override
  String get voiceSavedCantTranscribe =>
      'Audio gesichert. Dieses Gerät kann es nicht offline transkribieren.';

  @override
  String get voiceSavedNoSpeech => 'Gesichert. Es wurde keine Sprache gehört.';

  @override
  String get voiceSavingTranscribing => 'Wird gesichert und transkribiert …';

  @override
  String get voiceStartRecording => 'Aufnahme starten';

  @override
  String get voiceStopRecording => 'Aufnahme beenden';

  @override
  String get zoteroApiKey => 'API-Schlüssel';

  @override
  String get zoteroBadKey =>
      'Zotero hat diese Nutzer-ID und diesen Schlüssel nicht akzeptiert. Prüfe beide und ob der Schlüssel deine Bibliothek lesen darf.';

  @override
  String get zoteroConnect => 'Verbinden';

  @override
  String get zoteroConnectTitle => 'Mit Zotero verbinden';

  @override
  String get zoteroEnterBoth => 'Gib Nutzer-ID und API-Schlüssel ein.';

  @override
  String get zoteroEverything => 'Alles';

  @override
  String get zoteroEverythingHint =>
      'Alle Einträge; Sammlungen werden zu Projekten';

  @override
  String get zoteroForgetKey => 'Schlüssel vergessen';

  @override
  String get zoteroImport => 'Importieren';

  @override
  String zoteroImportFailed(String message) {
    return '$message\nBereits Importiertes bleibt in deiner Bibliothek.';
  }

  @override
  String get zoteroImportTitle => 'Aus Zotero importieren';

  @override
  String get zoteroImporting => 'Import läuft';

  @override
  String zoteroImportingItem(String title) {
    return '„$title“ wird importiert';
  }

  @override
  String get zoteroKeyHelp =>
      'Erstelle auf zotero.org/settings/keys einen Schlüssel nur zum Lesen („Neuen privaten Schlüssel erstellen“, nur Zugriff auf die Bibliothek erlauben). Deine Nutzer-ID steht auf derselben Seite. Beides bleibt in sicherem Speicher auf diesem Gerät und wird nie synchronisiert oder gesichert.';

  @override
  String get zoteroNotFound =>
      'Zotero hat diese Bibliothek nicht gefunden. Prüfe die Nutzer-ID (die Nummer auf zotero.org/settings/keys).';

  @override
  String get zoteroOffline =>
      'Zotero ist nicht erreichbar. Prüfe die Verbindung und versuche es erneut.';

  @override
  String get zoteroOpenKeys => 'zotero.org/settings/keys öffnen';

  @override
  String zoteroProgress(int done, int total) {
    return '$done von $total';
  }

  @override
  String get zoteroRateLimited =>
      'Zotero bittet um eine Pause. Versuche es in ein paar Minuten erneut.';

  @override
  String get zoteroReadingAttachments =>
      'Anhänge und Anmerkungen werden gelesen …';

  @override
  String get zoteroReadingItems => 'Einträge werden gelesen …';

  @override
  String get zoteroReadingLibrary => 'Zotero-Bibliothek wird gelesen …';

  @override
  String get zoteroServerProblem =>
      'Bei Zotero ist ein Problem aufgetreten. Versuche es später erneut.';

  @override
  String zoteroServerProblemDetail(String detail) {
    return 'Bei Zotero ist ein Problem aufgetreten ($detail). Versuche es später erneut.';
  }

  @override
  String get zoteroSomeCollections => 'Nur einige Sammlungen';

  @override
  String get zoteroSomethingWrong => 'Etwas ist schiefgelaufen.';

  @override
  String get zoteroStopped => 'Abgebrochen';

  @override
  String get zoteroStopping => 'Wird beendet …';

  @override
  String zoteroSummaryAlreadyIn(int count) {
    return '$count bereits in der Bibliothek';
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
      other: '$papers Paper',
      one: '1 Paper',
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
      other: '$highlights Markierungen',
      one: '1 Markierung',
    );
    String _temp3 = intl.Intl.pluralLogic(
      projects,
      locale: localeName,
      other: '$projects Projekte',
      one: '1 Projekt',
    );
    return '$_temp0, $_temp1 und $_temp2 in $_temp3 importiert';
  }

  @override
  String zoteroSummaryNotes(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count Notizen',
      one: '1 Notiz',
    );
    return '$_temp0 hinzugefügt';
  }

  @override
  String zoteroSummaryPdfsFailed(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count PDFs',
      one: '1 PDF',
    );
    return '$_temp0 konnten nicht geladen werden';
  }

  @override
  String zoteroSummarySkipped(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count Einträge',
      one: '1 Eintrag',
    );
    return '$_temp0 übersprungen';
  }

  @override
  String zoteroSummaryStopped(String summary) {
    return 'Abgebrochen. $summary.';
  }

  @override
  String get zoteroTitle => 'Zotero';

  @override
  String get zoteroUserId => 'Nutzer-ID';

  @override
  String get zoteroUserIdNumber =>
      'Die Nutzer-ID ist eine Nummer, nicht dein Benutzername.';
}
