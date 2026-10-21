import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_de.dart';
import 'app_localizations_en.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'generated/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
    : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations? of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations);
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
        delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('de'),
    Locale('en'),
  ];

  /// No description provided for @aliasesAdd.
  ///
  /// In en, this message translates to:
  /// **'Add an alias'**
  String get aliasesAdd;

  /// No description provided for @aliasesAlso.
  ///
  /// In en, this message translates to:
  /// **'Also: {names}'**
  String aliasesAlso(String names);

  /// No description provided for @aliasesMenu.
  ///
  /// In en, this message translates to:
  /// **'Aliases…'**
  String get aliasesMenu;

  /// No description provided for @aliasesMenuHint.
  ///
  /// In en, this message translates to:
  /// **'Other names, found by [[ and in mentions'**
  String get aliasesMenuHint;

  /// No description provided for @aliasesTitle.
  ///
  /// In en, this message translates to:
  /// **'Aliases'**
  String get aliasesTitle;

  /// No description provided for @attachmentsAddPodcastLink.
  ///
  /// In en, this message translates to:
  /// **'Add podcast link'**
  String get attachmentsAddPodcastLink;

  /// No description provided for @attachmentsAll.
  ///
  /// In en, this message translates to:
  /// **'All'**
  String get attachmentsAll;

  /// No description provided for @attachmentsAudio.
  ///
  /// In en, this message translates to:
  /// **'Audio'**
  String get attachmentsAudio;

  /// No description provided for @attachmentsAudioHint.
  ///
  /// In en, this message translates to:
  /// **'A NotebookLM audio overview, lecture or podcast file'**
  String get attachmentsAudioHint;

  /// No description provided for @attachmentsCopyName.
  ///
  /// In en, this message translates to:
  /// **'Copy name'**
  String get attachmentsCopyName;

  /// No description provided for @attachmentsEmptyMessage.
  ///
  /// In en, this message translates to:
  /// **'Images, recordings, links and files you attach to notes and papers appear here.'**
  String get attachmentsEmptyMessage;

  /// No description provided for @attachmentsEmptyTitle.
  ///
  /// In en, this message translates to:
  /// **'No attachments yet'**
  String get attachmentsEmptyTitle;

  /// No description provided for @attachmentsFile.
  ///
  /// In en, this message translates to:
  /// **'File'**
  String get attachmentsFile;

  /// No description provided for @attachmentsImage.
  ///
  /// In en, this message translates to:
  /// **'Image'**
  String get attachmentsImage;

  /// No description provided for @attachmentsImageFrom.
  ///
  /// In en, this message translates to:
  /// **'Image {name}, from {parent}'**
  String attachmentsImageFrom(String name, String parent);

  /// No description provided for @attachmentsKindAudio.
  ///
  /// In en, this message translates to:
  /// **'Audio'**
  String get attachmentsKindAudio;

  /// No description provided for @attachmentsKindFiles.
  ///
  /// In en, this message translates to:
  /// **'Files'**
  String get attachmentsKindFiles;

  /// No description provided for @attachmentsKindImages.
  ///
  /// In en, this message translates to:
  /// **'Images'**
  String get attachmentsKindImages;

  /// No description provided for @attachmentsKindLinks.
  ///
  /// In en, this message translates to:
  /// **'Links'**
  String get attachmentsKindLinks;

  /// No description provided for @attachmentsMarkUp.
  ///
  /// In en, this message translates to:
  /// **'Mark up'**
  String get attachmentsMarkUp;

  /// No description provided for @attachmentsNoMatch.
  ///
  /// In en, this message translates to:
  /// **'No attachment matches.'**
  String get attachmentsNoMatch;

  /// No description provided for @attachmentsNothingFound.
  ///
  /// In en, this message translates to:
  /// **'Nothing found'**
  String get attachmentsNothingFound;

  /// No description provided for @attachmentsPodcastLink.
  ///
  /// In en, this message translates to:
  /// **'Podcast link'**
  String get attachmentsPodcastLink;

  /// No description provided for @attachmentsPodcastLinkHint.
  ///
  /// In en, this message translates to:
  /// **'A NotebookLM share link or audio URL'**
  String get attachmentsPodcastLinkHint;

  /// No description provided for @attachmentsPodcastLinkNote.
  ///
  /// In en, this message translates to:
  /// **'Direct audio links (.mp3, .m4a…) play here. NotebookLM share links open in the browser — to listen and timestamp inside Corplex, download the audio overview and add it as Audio.'**
  String get attachmentsPodcastLinkNote;

  /// No description provided for @attachmentsRecordAudio.
  ///
  /// In en, this message translates to:
  /// **'Record audio'**
  String get attachmentsRecordAudio;

  /// No description provided for @attachmentsSearch.
  ///
  /// In en, this message translates to:
  /// **'Search attachments'**
  String get attachmentsSearch;

  /// No description provided for @attachmentsShowInNote.
  ///
  /// In en, this message translates to:
  /// **'Show in note'**
  String get attachmentsShowInNote;

  /// No description provided for @attachmentsShowInPaper.
  ///
  /// In en, this message translates to:
  /// **'Show in paper'**
  String get attachmentsShowInPaper;

  /// No description provided for @attachmentsTitle.
  ///
  /// In en, this message translates to:
  /// **'Attachments'**
  String get attachmentsTitle;

  /// No description provided for @attachmentsUntitledPaper.
  ///
  /// In en, this message translates to:
  /// **'Untitled paper'**
  String get attachmentsUntitledPaper;

  /// No description provided for @attachmentsVoiceNote.
  ///
  /// In en, this message translates to:
  /// **'A voice note'**
  String get attachmentsVoiceNote;

  /// No description provided for @attachmentsVoiceNoteTranscribed.
  ///
  /// In en, this message translates to:
  /// **'A voice note, transcribed on this device'**
  String get attachmentsVoiceNoteTranscribed;

  /// No description provided for @audioBack10.
  ///
  /// In en, this message translates to:
  /// **'Back 10 seconds'**
  String get audioBack10;

  /// No description provided for @audioChannelName.
  ///
  /// In en, this message translates to:
  /// **'Audio playback'**
  String get audioChannelName;

  /// No description provided for @audioClosePlayer.
  ///
  /// In en, this message translates to:
  /// **'Close player'**
  String get audioClosePlayer;

  /// No description provided for @audioForward30.
  ///
  /// In en, this message translates to:
  /// **'Forward 30 seconds'**
  String get audioForward30;

  /// No description provided for @audioMark.
  ///
  /// In en, this message translates to:
  /// **'Mark'**
  String get audioMark;

  /// No description provided for @audioNotSynced.
  ///
  /// In en, this message translates to:
  /// **'This recording hasn\'t synced to this device yet.'**
  String get audioNotSynced;

  /// No description provided for @audioPause.
  ///
  /// In en, this message translates to:
  /// **'Pause'**
  String get audioPause;

  /// No description provided for @audioPlay.
  ///
  /// In en, this message translates to:
  /// **'Play'**
  String get audioPlay;

  /// No description provided for @audioPlayFailed.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t play this recording.'**
  String get audioPlayFailed;

  /// No description provided for @authConfirmEmail.
  ///
  /// In en, this message translates to:
  /// **'Check your email to confirm your account, then sign in.'**
  String get authConfirmEmail;

  /// No description provided for @authCreateAccount.
  ///
  /// In en, this message translates to:
  /// **'Create account'**
  String get authCreateAccount;

  /// No description provided for @authCreateIntro.
  ///
  /// In en, this message translates to:
  /// **'Your notes stay on this device and sync to your other devices once you\'re signed in.'**
  String get authCreateIntro;

  /// No description provided for @authCreateTitle.
  ///
  /// In en, this message translates to:
  /// **'Create your account'**
  String get authCreateTitle;

  /// No description provided for @authEmail.
  ///
  /// In en, this message translates to:
  /// **'Email'**
  String get authEmail;

  /// No description provided for @authInvalidEmail.
  ///
  /// In en, this message translates to:
  /// **'Enter a valid email address.'**
  String get authInvalidEmail;

  /// No description provided for @authNoAccount.
  ///
  /// In en, this message translates to:
  /// **'Don\'t have an account? Sign up'**
  String get authNoAccount;

  /// No description provided for @authOffline.
  ///
  /// In en, this message translates to:
  /// **'Could not reach the server. Check your connection and try again.'**
  String get authOffline;

  /// No description provided for @authPassword.
  ///
  /// In en, this message translates to:
  /// **'Password'**
  String get authPassword;

  /// No description provided for @authPasswordHelper.
  ///
  /// In en, this message translates to:
  /// **'At least 6 characters'**
  String get authPasswordHelper;

  /// No description provided for @authShortPassword.
  ///
  /// In en, this message translates to:
  /// **'Password must be at least 6 characters.'**
  String get authShortPassword;

  /// No description provided for @authSignIn.
  ///
  /// In en, this message translates to:
  /// **'Sign in'**
  String get authSignIn;

  /// No description provided for @authSignInIntro.
  ///
  /// In en, this message translates to:
  /// **'Sign in to sync your notes and papers across your devices.'**
  String get authSignInIntro;

  /// No description provided for @authUnknown.
  ///
  /// In en, this message translates to:
  /// **'Something went wrong ({type}). Try again.'**
  String authUnknown(String type);

  /// No description provided for @authWelcomeBack.
  ///
  /// In en, this message translates to:
  /// **'Welcome back'**
  String get authWelcomeBack;

  /// No description provided for @blocksBulleted.
  ///
  /// In en, this message translates to:
  /// **'Bulleted list'**
  String get blocksBulleted;

  /// No description provided for @blocksCallout.
  ///
  /// In en, this message translates to:
  /// **'Callout'**
  String get blocksCallout;

  /// No description provided for @blocksChecklist.
  ///
  /// In en, this message translates to:
  /// **'Checklist'**
  String get blocksChecklist;

  /// No description provided for @blocksCode.
  ///
  /// In en, this message translates to:
  /// **'Code block'**
  String get blocksCode;

  /// No description provided for @blocksContentsCommand.
  ///
  /// In en, this message translates to:
  /// **'Table of contents'**
  String get blocksContentsCommand;

  /// No description provided for @blocksContentsEmpty.
  ///
  /// In en, this message translates to:
  /// **'Headings will be listed here.'**
  String get blocksContentsEmpty;

  /// No description provided for @blocksContentsHint.
  ///
  /// In en, this message translates to:
  /// **'List this note\'s headings; tap one to jump'**
  String get blocksContentsHint;

  /// No description provided for @blocksCopyLink.
  ///
  /// In en, this message translates to:
  /// **'Copy link to block'**
  String get blocksCopyLink;

  /// No description provided for @blocksDelete.
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get blocksDelete;

  /// No description provided for @blocksDuplicate.
  ///
  /// In en, this message translates to:
  /// **'Duplicate'**
  String get blocksDuplicate;

  /// No description provided for @blocksHandleLabel.
  ///
  /// In en, this message translates to:
  /// **'Move or change this block'**
  String get blocksHandleLabel;

  /// No description provided for @blocksHeading.
  ///
  /// In en, this message translates to:
  /// **'Heading'**
  String get blocksHeading;

  /// No description provided for @blocksKeyMoveDown.
  ///
  /// In en, this message translates to:
  /// **'Move block down'**
  String get blocksKeyMoveDown;

  /// No description provided for @blocksKeyMoveUp.
  ///
  /// In en, this message translates to:
  /// **'Move block up'**
  String get blocksKeyMoveUp;

  /// No description provided for @blocksLinkCopied.
  ///
  /// In en, this message translates to:
  /// **'Link copied'**
  String get blocksLinkCopied;

  /// No description provided for @blocksMoveDown.
  ///
  /// In en, this message translates to:
  /// **'Move down'**
  String get blocksMoveDown;

  /// No description provided for @blocksMoveUp.
  ///
  /// In en, this message translates to:
  /// **'Move up'**
  String get blocksMoveUp;

  /// No description provided for @blocksNumbered.
  ///
  /// In en, this message translates to:
  /// **'Numbered list'**
  String get blocksNumbered;

  /// No description provided for @blocksQuote.
  ///
  /// In en, this message translates to:
  /// **'Quote'**
  String get blocksQuote;

  /// No description provided for @blocksSubheading.
  ///
  /// In en, this message translates to:
  /// **'Subheading'**
  String get blocksSubheading;

  /// No description provided for @blocksText.
  ///
  /// In en, this message translates to:
  /// **'Text'**
  String get blocksText;

  /// No description provided for @blocksTitle.
  ///
  /// In en, this message translates to:
  /// **'Title'**
  String get blocksTitle;

  /// No description provided for @blocksToggle.
  ///
  /// In en, this message translates to:
  /// **'Toggle list'**
  String get blocksToggle;

  /// No description provided for @blocksToggleCommand.
  ///
  /// In en, this message translates to:
  /// **'Toggle list'**
  String get blocksToggleCommand;

  /// No description provided for @blocksToggleHint.
  ///
  /// In en, this message translates to:
  /// **'A line that folds the lines under it'**
  String get blocksToggleHint;

  /// No description provided for @blocksTurnInto.
  ///
  /// In en, this message translates to:
  /// **'Turn into'**
  String get blocksTurnInto;

  /// No description provided for @calloutsCommand.
  ///
  /// In en, this message translates to:
  /// **'Callout'**
  String get calloutsCommand;

  /// No description provided for @calloutsCommandHint.
  ///
  /// In en, this message translates to:
  /// **'Set a passage apart as a note, tip or warning'**
  String get calloutsCommandHint;

  /// No description provided for @calloutsLabel.
  ///
  /// In en, this message translates to:
  /// **'Callout: {type}'**
  String calloutsLabel(String type);

  /// No description provided for @calloutsPickTitle.
  ///
  /// In en, this message translates to:
  /// **'Callout type'**
  String get calloutsPickTitle;

  /// No description provided for @calloutsRemove.
  ///
  /// In en, this message translates to:
  /// **'Remove callout'**
  String get calloutsRemove;

  /// No description provided for @calloutsTypeBug.
  ///
  /// In en, this message translates to:
  /// **'Bug'**
  String get calloutsTypeBug;

  /// No description provided for @calloutsTypeCaution.
  ///
  /// In en, this message translates to:
  /// **'Caution'**
  String get calloutsTypeCaution;

  /// No description provided for @calloutsTypeDanger.
  ///
  /// In en, this message translates to:
  /// **'Danger'**
  String get calloutsTypeDanger;

  /// No description provided for @calloutsTypeExample.
  ///
  /// In en, this message translates to:
  /// **'Example'**
  String get calloutsTypeExample;

  /// No description provided for @calloutsTypeImportant.
  ///
  /// In en, this message translates to:
  /// **'Important'**
  String get calloutsTypeImportant;

  /// No description provided for @calloutsTypeInfo.
  ///
  /// In en, this message translates to:
  /// **'Info'**
  String get calloutsTypeInfo;

  /// No description provided for @calloutsTypeNote.
  ///
  /// In en, this message translates to:
  /// **'Note'**
  String get calloutsTypeNote;

  /// No description provided for @calloutsTypeQuestion.
  ///
  /// In en, this message translates to:
  /// **'Question'**
  String get calloutsTypeQuestion;

  /// No description provided for @calloutsTypeSuccess.
  ///
  /// In en, this message translates to:
  /// **'Success'**
  String get calloutsTypeSuccess;

  /// No description provided for @calloutsTypeTip.
  ///
  /// In en, this message translates to:
  /// **'Tip'**
  String get calloutsTypeTip;

  /// No description provided for @calloutsTypeTodo.
  ///
  /// In en, this message translates to:
  /// **'To do'**
  String get calloutsTypeTodo;

  /// No description provided for @calloutsTypeWarning.
  ///
  /// In en, this message translates to:
  /// **'Warning'**
  String get calloutsTypeWarning;

  /// No description provided for @commentsAddComment.
  ///
  /// In en, this message translates to:
  /// **'Add comment'**
  String get commentsAddComment;

  /// No description provided for @commentsComment.
  ///
  /// In en, this message translates to:
  /// **'Comment'**
  String get commentsComment;

  /// No description provided for @commentsDeleted.
  ///
  /// In en, this message translates to:
  /// **'Comment deleted'**
  String get commentsDeleted;

  /// No description provided for @commentsEditComment.
  ///
  /// In en, this message translates to:
  /// **'Edit comment'**
  String get commentsEditComment;

  /// No description provided for @commentsEmpty.
  ///
  /// In en, this message translates to:
  /// **'Select a passage, then choose Add comment.'**
  String get commentsEmpty;

  /// No description provided for @commentsFromHint.
  ///
  /// In en, this message translates to:
  /// **'e.g. Supervisor'**
  String get commentsFromHint;

  /// No description provided for @commentsFromOptional.
  ///
  /// In en, this message translates to:
  /// **'From (optional)'**
  String get commentsFromOptional;

  /// No description provided for @commentsNothingOpen.
  ///
  /// In en, this message translates to:
  /// **'Nothing open.'**
  String get commentsNothingOpen;

  /// No description provided for @commentsOnSelection.
  ///
  /// In en, this message translates to:
  /// **'Comment on the selection'**
  String get commentsOnSelection;

  /// No description provided for @commentsOpenCount.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 open comment} other{{count} open comments}}'**
  String commentsOpenCount(int count);

  /// No description provided for @commentsOptions.
  ///
  /// In en, this message translates to:
  /// **'Comment options'**
  String get commentsOptions;

  /// No description provided for @commentsPassageChanged.
  ///
  /// In en, this message translates to:
  /// **'Passage changed'**
  String get commentsPassageChanged;

  /// No description provided for @commentsReopen.
  ///
  /// In en, this message translates to:
  /// **'Reopen'**
  String get commentsReopen;

  /// No description provided for @commentsResolve.
  ///
  /// In en, this message translates to:
  /// **'Resolve'**
  String get commentsResolve;

  /// No description provided for @commentsSelectAPassage.
  ///
  /// In en, this message translates to:
  /// **'Select a passage to comment on'**
  String get commentsSelectAPassage;

  /// No description provided for @commentsShowResolved.
  ///
  /// In en, this message translates to:
  /// **'Show resolved ({count})'**
  String commentsShowResolved(int count);

  /// No description provided for @commentsTitle.
  ///
  /// In en, this message translates to:
  /// **'Comments'**
  String get commentsTitle;

  /// No description provided for @commentsUnlockToAdd.
  ///
  /// In en, this message translates to:
  /// **'Unlock your notes to add a comment.'**
  String get commentsUnlockToAdd;

  /// No description provided for @commonAdd.
  ///
  /// In en, this message translates to:
  /// **'Add'**
  String get commonAdd;

  /// No description provided for @commonCancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get commonCancel;

  /// No description provided for @commonClose.
  ///
  /// In en, this message translates to:
  /// **'Close'**
  String get commonClose;

  /// No description provided for @commonCopied.
  ///
  /// In en, this message translates to:
  /// **'Copied'**
  String get commonCopied;

  /// No description provided for @commonCopy.
  ///
  /// In en, this message translates to:
  /// **'Copy'**
  String get commonCopy;

  /// No description provided for @commonDelete.
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get commonDelete;

  /// No description provided for @commonDone.
  ///
  /// In en, this message translates to:
  /// **'Done'**
  String get commonDone;

  /// No description provided for @commonEdit.
  ///
  /// In en, this message translates to:
  /// **'Edit'**
  String get commonEdit;

  /// No description provided for @commonImportPdf.
  ///
  /// In en, this message translates to:
  /// **'Import PDF'**
  String get commonImportPdf;

  /// No description provided for @commonLess.
  ///
  /// In en, this message translates to:
  /// **'Less'**
  String get commonLess;

  /// No description provided for @commonLibrary.
  ///
  /// In en, this message translates to:
  /// **'Library'**
  String get commonLibrary;

  /// No description provided for @commonLocked.
  ///
  /// In en, this message translates to:
  /// **'Locked'**
  String get commonLocked;

  /// No description provided for @commonMore.
  ///
  /// In en, this message translates to:
  /// **'More'**
  String get commonMore;

  /// No description provided for @commonMoveToTrash.
  ///
  /// In en, this message translates to:
  /// **'Move to trash'**
  String get commonMoveToTrash;

  /// No description provided for @commonNewNote.
  ///
  /// In en, this message translates to:
  /// **'New note'**
  String get commonNewNote;

  /// No description provided for @commonNotes.
  ///
  /// In en, this message translates to:
  /// **'Notes'**
  String get commonNotes;

  /// No description provided for @commonOk.
  ///
  /// In en, this message translates to:
  /// **'OK'**
  String get commonOk;

  /// No description provided for @commonOpen.
  ///
  /// In en, this message translates to:
  /// **'Open'**
  String get commonOpen;

  /// No description provided for @commonProjects.
  ///
  /// In en, this message translates to:
  /// **'Projects'**
  String get commonProjects;

  /// No description provided for @commonRemove.
  ///
  /// In en, this message translates to:
  /// **'Remove'**
  String get commonRemove;

  /// No description provided for @commonRename.
  ///
  /// In en, this message translates to:
  /// **'Rename'**
  String get commonRename;

  /// No description provided for @commonSave.
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get commonSave;

  /// No description provided for @commonSearch.
  ///
  /// In en, this message translates to:
  /// **'Search'**
  String get commonSearch;

  /// No description provided for @commonSettings.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get commonSettings;

  /// No description provided for @commonShare.
  ///
  /// In en, this message translates to:
  /// **'Share'**
  String get commonShare;

  /// No description provided for @commonTrash.
  ///
  /// In en, this message translates to:
  /// **'Trash'**
  String get commonTrash;

  /// No description provided for @commonTryAgain.
  ///
  /// In en, this message translates to:
  /// **'Try again'**
  String get commonTryAgain;

  /// No description provided for @commonUndo.
  ///
  /// In en, this message translates to:
  /// **'Undo'**
  String get commonUndo;

  /// No description provided for @commonUntitled.
  ///
  /// In en, this message translates to:
  /// **'Untitled'**
  String get commonUntitled;

  /// No description provided for @cslAddStyle.
  ///
  /// In en, this message translates to:
  /// **'Add a style…'**
  String get cslAddStyle;

  /// No description provided for @cslAutomatic.
  ///
  /// In en, this message translates to:
  /// **'Automatic'**
  String get cslAutomatic;

  /// No description provided for @cslAutomaticWith.
  ///
  /// In en, this message translates to:
  /// **'Automatic ({language})'**
  String cslAutomaticWith(String language);

  /// Title of the list of languages that citation text (month names, "et al.", quotes) can be written in.
  ///
  /// In en, this message translates to:
  /// **'Citation language'**
  String get cslCitationLanguage;

  /// A quiet row in the reference style picker showing the current citation language.
  ///
  /// In en, this message translates to:
  /// **'Citation language: {language}'**
  String cslCitationLanguageRow(String language);

  /// No description provided for @cslProblemDependent.
  ///
  /// In en, this message translates to:
  /// **'This style is a small variant that points to a parent style. Import the parent style instead.'**
  String get cslProblemDependent;

  /// No description provided for @cslProblemNoBibliography.
  ///
  /// In en, this message translates to:
  /// **'That style has no bibliography section, so it can\'t format reference lists.'**
  String get cslProblemNoBibliography;

  /// No description provided for @cslProblemNoInfo.
  ///
  /// In en, this message translates to:
  /// **'That style has no title or ID block.'**
  String get cslProblemNoInfo;

  /// No description provided for @cslProblemNoLayout.
  ///
  /// In en, this message translates to:
  /// **'That style is missing its layout, so it can\'t format references.'**
  String get cslProblemNoLayout;

  /// No description provided for @cslProblemNoTitle.
  ///
  /// In en, this message translates to:
  /// **'That style has no title.'**
  String get cslProblemNoTitle;

  /// No description provided for @cslProblemNotStyle.
  ///
  /// In en, this message translates to:
  /// **'That file isn\'t a citation style (.csl) file.'**
  String get cslProblemNotStyle;

  /// No description provided for @cslProblemNotXml.
  ///
  /// In en, this message translates to:
  /// **'That file isn\'t valid XML, so it can\'t be a citation style.'**
  String get cslProblemNotXml;

  /// No description provided for @cslProblemTooLarge.
  ///
  /// In en, this message translates to:
  /// **'That file is too large to be a style.'**
  String get cslProblemTooLarge;

  /// No description provided for @cslProblemUndefinedMacro.
  ///
  /// In en, this message translates to:
  /// **'That style uses an undefined macro \"{name}\".'**
  String cslProblemUndefinedMacro(String name);

  /// No description provided for @cslProblemUnreadable.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t read that file.'**
  String get cslProblemUnreadable;

  /// No description provided for @cslProblemWrongVersion.
  ///
  /// In en, this message translates to:
  /// **'Only CSL 1.0 styles are supported.'**
  String get cslProblemWrongVersion;

  /// No description provided for @cslReferenceStyle.
  ///
  /// In en, this message translates to:
  /// **'Reference style'**
  String get cslReferenceStyle;

  /// No description provided for @cslStyleCantBeUsed.
  ///
  /// In en, this message translates to:
  /// **'That style can\'t be used'**
  String get cslStyleCantBeUsed;

  /// No description provided for @dailyFolder.
  ///
  /// In en, this message translates to:
  /// **'Folder'**
  String get dailyFolder;

  /// No description provided for @dailyKeyTodaysNote.
  ///
  /// In en, this message translates to:
  /// **'Today\'s note'**
  String get dailyKeyTodaysNote;

  /// No description provided for @dailyNext.
  ///
  /// In en, this message translates to:
  /// **'Next day\'s note'**
  String get dailyNext;

  /// No description provided for @dailyNoEarlier.
  ///
  /// In en, this message translates to:
  /// **'No earlier daily note'**
  String get dailyNoEarlier;

  /// No description provided for @dailyNoLater.
  ///
  /// In en, this message translates to:
  /// **'No later daily note'**
  String get dailyNoLater;

  /// No description provided for @dailyNone.
  ///
  /// In en, this message translates to:
  /// **'None'**
  String get dailyNone;

  /// No description provided for @dailyPrevious.
  ///
  /// In en, this message translates to:
  /// **'Previous day\'s note'**
  String get dailyPrevious;

  /// No description provided for @dailySettingsSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Template and folder for today\'s note'**
  String get dailySettingsSubtitle;

  /// No description provided for @dailySettingsTitle.
  ///
  /// In en, this message translates to:
  /// **'Daily notes'**
  String get dailySettingsTitle;

  /// No description provided for @dailyTemplate.
  ///
  /// In en, this message translates to:
  /// **'Template'**
  String get dailyTemplate;

  /// No description provided for @dailyTemplateHint.
  ///
  /// In en, this message translates to:
  /// **'Use a note as a template (note menu) to choose one here.'**
  String get dailyTemplateHint;

  /// No description provided for @dailyTodaysNote.
  ///
  /// In en, this message translates to:
  /// **'Today\'s note'**
  String get dailyTodaysNote;

  /// No description provided for @dataNewerVersion.
  ///
  /// In en, this message translates to:
  /// **'This backup was made by a newer version of Corplex. Update the app first.'**
  String get dataNewerVersion;

  /// No description provided for @dataNotABackup.
  ///
  /// In en, this message translates to:
  /// **'That file isn’t a Corplex backup.'**
  String get dataNotABackup;

  /// No description provided for @dataUnsupportedVersion.
  ///
  /// In en, this message translates to:
  /// **'This backup is from an unsupported version.'**
  String get dataUnsupportedVersion;

  /// No description provided for @editorAddBibliography.
  ///
  /// In en, this message translates to:
  /// **'Add bibliography'**
  String get editorAddBibliography;

  /// No description provided for @editorAddPaperAndCite.
  ///
  /// In en, this message translates to:
  /// **'Add this paper and cite it?'**
  String get editorAddPaperAndCite;

  /// No description provided for @editorAddToProject.
  ///
  /// In en, this message translates to:
  /// **'Add to project'**
  String get editorAddToProject;

  /// No description provided for @editorAddedReferences.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{Added 1 reference} other{Added {count} references}}'**
  String editorAddedReferences(int count);

  /// No description provided for @editorAttach.
  ///
  /// In en, this message translates to:
  /// **'Attach audio, image or file'**
  String get editorAttach;

  /// No description provided for @editorBibliographyHint.
  ///
  /// In en, this message translates to:
  /// **'A reference list of what this note cites'**
  String get editorBibliographyHint;

  /// No description provided for @editorCiteHint.
  ///
  /// In en, this message translates to:
  /// **'Or type [@ while writing'**
  String get editorCiteHint;

  /// No description provided for @editorCmdAttach.
  ///
  /// In en, this message translates to:
  /// **'Attach'**
  String get editorCmdAttach;

  /// No description provided for @editorCmdAttachHint.
  ///
  /// In en, this message translates to:
  /// **'Audio, an image or a file'**
  String get editorCmdAttachHint;

  /// No description provided for @editorCmdBibliography.
  ///
  /// In en, this message translates to:
  /// **'Add bibliography'**
  String get editorCmdBibliography;

  /// No description provided for @editorCmdBibliographyHint.
  ///
  /// In en, this message translates to:
  /// **'A reference list of what this note cites'**
  String get editorCmdBibliographyHint;

  /// No description provided for @editorCmdChecklist.
  ///
  /// In en, this message translates to:
  /// **'Checklist'**
  String get editorCmdChecklist;

  /// No description provided for @editorCmdChecklistHint.
  ///
  /// In en, this message translates to:
  /// **'Tick-box items'**
  String get editorCmdChecklistHint;

  /// No description provided for @editorCmdCite.
  ///
  /// In en, this message translates to:
  /// **'Cite a paper'**
  String get editorCmdCite;

  /// No description provided for @editorCmdCiteHint.
  ///
  /// In en, this message translates to:
  /// **'Insert a citation from your library'**
  String get editorCmdCiteHint;

  /// No description provided for @editorCmdDictate.
  ///
  /// In en, this message translates to:
  /// **'Dictate'**
  String get editorCmdDictate;

  /// No description provided for @editorCmdDictateHint.
  ///
  /// In en, this message translates to:
  /// **'Speak instead of typing'**
  String get editorCmdDictateHint;

  /// No description provided for @editorCmdDraw.
  ///
  /// In en, this message translates to:
  /// **'Draw'**
  String get editorCmdDraw;

  /// No description provided for @editorCmdDrawHint.
  ///
  /// In en, this message translates to:
  /// **'A sketch, with a pen or finger'**
  String get editorCmdDrawHint;

  /// No description provided for @editorCmdEquation.
  ///
  /// In en, this message translates to:
  /// **'Equation'**
  String get editorCmdEquation;

  /// No description provided for @editorCmdEquationHint.
  ///
  /// In en, this message translates to:
  /// **'LaTeX maths, or type \$\$'**
  String get editorCmdEquationHint;

  /// No description provided for @editorCmdFigure.
  ///
  /// In en, this message translates to:
  /// **'Figure caption'**
  String get editorCmdFigure;

  /// No description provided for @editorCmdFigureHint.
  ///
  /// In en, this message translates to:
  /// **'A numbered figure caption for this line'**
  String get editorCmdFigureHint;

  /// No description provided for @editorCmdHeading.
  ///
  /// In en, this message translates to:
  /// **'Heading'**
  String get editorCmdHeading;

  /// No description provided for @editorCmdHeadingHint.
  ///
  /// In en, this message translates to:
  /// **'Make this line a heading'**
  String get editorCmdHeadingHint;

  /// No description provided for @editorCmdInsertTable.
  ///
  /// In en, this message translates to:
  /// **'Table'**
  String get editorCmdInsertTable;

  /// No description provided for @editorCmdInsertTableHint.
  ///
  /// In en, this message translates to:
  /// **'Rows and columns, 3 by 3 to start'**
  String get editorCmdInsertTableHint;

  /// No description provided for @editorCmdLink.
  ///
  /// In en, this message translates to:
  /// **'Link to a note'**
  String get editorCmdLink;

  /// No description provided for @editorCmdLinkHint.
  ///
  /// In en, this message translates to:
  /// **'Or type [['**
  String get editorCmdLinkHint;

  /// No description provided for @editorCmdRefer.
  ///
  /// In en, this message translates to:
  /// **'Refer to a figure or table'**
  String get editorCmdRefer;

  /// No description provided for @editorCmdReferHint.
  ///
  /// In en, this message translates to:
  /// **'Insert its number, kept right as things move'**
  String get editorCmdReferHint;

  /// No description provided for @editorCmdTable.
  ///
  /// In en, this message translates to:
  /// **'Table caption'**
  String get editorCmdTable;

  /// No description provided for @editorCmdTableHint.
  ///
  /// In en, this message translates to:
  /// **'A numbered table caption for this line'**
  String get editorCmdTableHint;

  /// No description provided for @editorCmdTemplate.
  ///
  /// In en, this message translates to:
  /// **'Literature note template'**
  String get editorCmdTemplate;

  /// No description provided for @editorCmdTemplateHint.
  ///
  /// In en, this message translates to:
  /// **'Summary, method, findings, critique'**
  String get editorCmdTemplateHint;

  /// No description provided for @editorCmdVoice.
  ///
  /// In en, this message translates to:
  /// **'Voice note'**
  String get editorCmdVoice;

  /// No description provided for @editorCmdVoiceHint.
  ///
  /// In en, this message translates to:
  /// **'Record a thought as you read'**
  String get editorCmdVoiceHint;

  /// No description provided for @editorDraw.
  ///
  /// In en, this message translates to:
  /// **'Draw'**
  String get editorDraw;

  /// No description provided for @editorEditDate.
  ///
  /// In en, this message translates to:
  /// **'{date} at {time}'**
  String editorEditDate(String date, String time);

  /// No description provided for @editorExport.
  ///
  /// In en, this message translates to:
  /// **'Export'**
  String get editorExport;

  /// No description provided for @editorExportHint.
  ///
  /// In en, this message translates to:
  /// **'Markdown, Word or PDF, with references'**
  String get editorExportHint;

  /// No description provided for @editorFindInNote.
  ///
  /// In en, this message translates to:
  /// **'Find in note'**
  String get editorFindInNote;

  /// No description provided for @editorImageTapToEnlarge.
  ///
  /// In en, this message translates to:
  /// **'Image, tap to enlarge'**
  String get editorImageTapToEnlarge;

  /// No description provided for @editorLinkPaper.
  ///
  /// In en, this message translates to:
  /// **'Link a paper'**
  String get editorLinkPaper;

  /// No description provided for @editorLinkToNote.
  ///
  /// In en, this message translates to:
  /// **'Link to a note'**
  String get editorLinkToNote;

  /// No description provided for @editorLinkToNoteHint.
  ///
  /// In en, this message translates to:
  /// **'Or type [[ while writing'**
  String get editorLinkToNoteHint;

  /// No description provided for @editorLinkedFrom.
  ///
  /// In en, this message translates to:
  /// **'Linked from'**
  String get editorLinkedFrom;

  /// No description provided for @editorLockHint.
  ///
  /// In en, this message translates to:
  /// **'Needs your notes password to open'**
  String get editorLockHint;

  /// No description provided for @editorLockedTapToLock.
  ///
  /// In en, this message translates to:
  /// **'Locked — tap to lock now'**
  String get editorLockedTapToLock;

  /// No description provided for @editorLookupUnreachable.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t reach the lookup service. The link is unchanged.'**
  String get editorLookupUnreachable;

  /// No description provided for @editorMoveToFolder.
  ///
  /// In en, this message translates to:
  /// **'Move to folder'**
  String get editorMoveToFolder;

  /// No description provided for @editorNoCitations.
  ///
  /// In en, this message translates to:
  /// **'No citations to list yet. Type [@ to cite a paper.'**
  String get editorNoCitations;

  /// No description provided for @editorNoPaperFound.
  ///
  /// In en, this message translates to:
  /// **'No paper found for {id}.'**
  String editorNoPaperFound(String id);

  /// No description provided for @editorNoteLockedFiles.
  ///
  /// In en, this message translates to:
  /// **'Note locked. Attached files (images, audio, PDFs) aren\'t encrypted — only the note\'s text and sketches.'**
  String get editorNoteLockedFiles;

  /// No description provided for @editorPaperRemoved.
  ///
  /// In en, this message translates to:
  /// **'That paper was removed.'**
  String get editorPaperRemoved;

  /// No description provided for @editorPrint.
  ///
  /// In en, this message translates to:
  /// **'Print…'**
  String get editorPrint;

  /// No description provided for @editorRecordingRemoved.
  ///
  /// In en, this message translates to:
  /// **'That recording was removed.'**
  String get editorRecordingRemoved;

  /// No description provided for @editorSelectPassage.
  ///
  /// In en, this message translates to:
  /// **'Select the passage to comment on.'**
  String get editorSelectPassage;

  /// No description provided for @editorStartWriting.
  ///
  /// In en, this message translates to:
  /// **'Start writing…'**
  String get editorStartWriting;

  /// No description provided for @editorStyleBody.
  ///
  /// In en, this message translates to:
  /// **'Body text'**
  String get editorStyleBody;

  /// No description provided for @editorStyleHeading.
  ///
  /// In en, this message translates to:
  /// **'Heading'**
  String get editorStyleHeading;

  /// No description provided for @editorStyleHighlight.
  ///
  /// In en, this message translates to:
  /// **'Highlight'**
  String get editorStyleHighlight;

  /// No description provided for @editorStyleMonospaced.
  ///
  /// In en, this message translates to:
  /// **'Monospaced'**
  String get editorStyleMonospaced;

  /// No description provided for @editorStyleQuote.
  ///
  /// In en, this message translates to:
  /// **'Quote'**
  String get editorStyleQuote;

  /// No description provided for @editorStyleStrike.
  ///
  /// In en, this message translates to:
  /// **'Strikethrough'**
  String get editorStyleStrike;

  /// No description provided for @editorStyleSubheading.
  ///
  /// In en, this message translates to:
  /// **'Subheading'**
  String get editorStyleSubheading;

  /// No description provided for @editorStyleTable.
  ///
  /// In en, this message translates to:
  /// **'Table'**
  String get editorStyleTable;

  /// No description provided for @editorStyleTitle.
  ///
  /// In en, this message translates to:
  /// **'Title'**
  String get editorStyleTitle;

  /// No description provided for @editorTags.
  ///
  /// In en, this message translates to:
  /// **'Tags'**
  String get editorTags;

  /// No description provided for @editorTemplate.
  ///
  /// In en, this message translates to:
  /// **'Literature note template'**
  String get editorTemplate;

  /// No description provided for @editorTemplateHint.
  ///
  /// In en, this message translates to:
  /// **'Summary, method, findings, critique'**
  String get editorTemplateHint;

  /// No description provided for @editorTextStyle.
  ///
  /// In en, this message translates to:
  /// **'Text style'**
  String get editorTextStyle;

  /// No description provided for @editorTipBold.
  ///
  /// In en, this message translates to:
  /// **'Bold {shortcut}'**
  String editorTipBold(String shortcut);

  /// No description provided for @editorTipBulleted.
  ///
  /// In en, this message translates to:
  /// **'Bulleted list {shortcut}'**
  String editorTipBulleted(String shortcut);

  /// No description provided for @editorTipChecklist.
  ///
  /// In en, this message translates to:
  /// **'Checklist {shortcut}'**
  String editorTipChecklist(String shortcut);

  /// No description provided for @editorTipHighlight.
  ///
  /// In en, this message translates to:
  /// **'Highlight {shortcut}'**
  String editorTipHighlight(String shortcut);

  /// No description provided for @editorTipItalic.
  ///
  /// In en, this message translates to:
  /// **'Italic {shortcut}'**
  String editorTipItalic(String shortcut);

  /// No description provided for @editorTipNumbered.
  ///
  /// In en, this message translates to:
  /// **'Numbered list {shortcut}'**
  String editorTipNumbered(String shortcut);

  /// No description provided for @editorTipUnderline.
  ///
  /// In en, this message translates to:
  /// **'Underline {shortcut}'**
  String editorTipUnderline(String shortcut);

  /// No description provided for @editorTitleHint.
  ///
  /// In en, this message translates to:
  /// **'Title'**
  String get editorTitleHint;

  /// No description provided for @editorTypewriter.
  ///
  /// In en, this message translates to:
  /// **'Typewriter scrolling'**
  String get editorTypewriter;

  /// No description provided for @editorTypewriterHint.
  ///
  /// In en, this message translates to:
  /// **'Keep the line you type centred'**
  String get editorTypewriterHint;

  /// No description provided for @editorWordCount.
  ///
  /// In en, this message translates to:
  /// **'Word count'**
  String get editorWordCount;

  /// No description provided for @editorWordCountHint.
  ///
  /// In en, this message translates to:
  /// **'And reading time'**
  String get editorWordCountHint;

  /// No description provided for @exportCitationsAndReferences.
  ///
  /// In en, this message translates to:
  /// **'Citations and references'**
  String get exportCitationsAndReferences;

  /// No description provided for @exportCouldntCreateFile.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t create that file.'**
  String get exportCouldntCreateFile;

  /// No description provided for @exportFormatLatex.
  ///
  /// In en, this message translates to:
  /// **'LaTeX (Overleaf)'**
  String get exportFormatLatex;

  /// No description provided for @exportFormatMarkdown.
  ///
  /// In en, this message translates to:
  /// **'Markdown'**
  String get exportFormatMarkdown;

  /// No description provided for @exportFormatPdf.
  ///
  /// In en, this message translates to:
  /// **'PDF'**
  String get exportFormatPdf;

  /// No description provided for @exportFormatWord.
  ///
  /// In en, this message translates to:
  /// **'Word document'**
  String get exportFormatWord;

  /// No description provided for @exportUnlockNoteToContinue.
  ///
  /// In en, this message translates to:
  /// **'Unlock this note to continue.'**
  String get exportUnlockNoteToContinue;

  /// No description provided for @exportUnlockNotesToContinue.
  ///
  /// In en, this message translates to:
  /// **'Unlock your locked notes to continue.'**
  String get exportUnlockNotesToContinue;

  /// No description provided for @findCount.
  ///
  /// In en, this message translates to:
  /// **'{current} of {total}'**
  String findCount(int current, int total);

  /// No description provided for @findHideReplace.
  ///
  /// In en, this message translates to:
  /// **'Hide replace'**
  String get findHideReplace;

  /// No description provided for @findNext.
  ///
  /// In en, this message translates to:
  /// **'Next'**
  String get findNext;

  /// No description provided for @findNotFound.
  ///
  /// In en, this message translates to:
  /// **'Not found'**
  String get findNotFound;

  /// No description provided for @findPrevious.
  ///
  /// In en, this message translates to:
  /// **'Previous'**
  String get findPrevious;

  /// No description provided for @findReplace.
  ///
  /// In en, this message translates to:
  /// **'Replace'**
  String get findReplace;

  /// Button: replace every match
  ///
  /// In en, this message translates to:
  /// **'All'**
  String get findReplaceAll;

  /// No description provided for @findReplaceWith.
  ///
  /// In en, this message translates to:
  /// **'Replace with'**
  String get findReplaceWith;

  /// No description provided for @foldCollapseAll.
  ///
  /// In en, this message translates to:
  /// **'Collapse all sections'**
  String get foldCollapseAll;

  /// No description provided for @foldCollapseSection.
  ///
  /// In en, this message translates to:
  /// **'Collapse section'**
  String get foldCollapseSection;

  /// No description provided for @foldExpandAll.
  ///
  /// In en, this message translates to:
  /// **'Expand all sections'**
  String get foldExpandAll;

  /// No description provided for @foldExpandSection.
  ///
  /// In en, this message translates to:
  /// **'Expand section'**
  String get foldExpandSection;

  /// No description provided for @foldShowSection.
  ///
  /// In en, this message translates to:
  /// **'Show section'**
  String get foldShowSection;

  /// No description provided for @footnotesCommand.
  ///
  /// In en, this message translates to:
  /// **'Footnote'**
  String get footnotesCommand;

  /// No description provided for @footnotesCommandHint.
  ///
  /// In en, this message translates to:
  /// **'A note at the foot of the page'**
  String get footnotesCommandHint;

  /// No description provided for @footnotesEditTitle.
  ///
  /// In en, this message translates to:
  /// **'Footnote'**
  String get footnotesEditTitle;

  /// No description provided for @footnotesHint.
  ///
  /// In en, this message translates to:
  /// **'Write the footnote'**
  String get footnotesHint;

  /// No description provided for @footnotesLabel.
  ///
  /// In en, this message translates to:
  /// **'Footnote {number}'**
  String footnotesLabel(String number);

  /// No description provided for @footnotesStatsInFootnotes.
  ///
  /// In en, this message translates to:
  /// **'+{count} in footnotes'**
  String footnotesStatsInFootnotes(String count);

  /// No description provided for @graphCouldntDraw.
  ///
  /// In en, this message translates to:
  /// **'Couldn’t draw the map'**
  String get graphCouldntDraw;

  /// No description provided for @graphEmptyMessage.
  ///
  /// In en, this message translates to:
  /// **'Link notes to each other or to papers, or cite a paper with [@, and the connections appear here.'**
  String get graphEmptyMessage;

  /// No description provided for @graphHideUnconnected.
  ///
  /// In en, this message translates to:
  /// **'Hide unconnected items'**
  String get graphHideUnconnected;

  /// No description provided for @graphLockedNote.
  ///
  /// In en, this message translates to:
  /// **'Locked note'**
  String get graphLockedNote;

  /// No description provided for @graphMap.
  ///
  /// In en, this message translates to:
  /// **'Map'**
  String get graphMap;

  /// No description provided for @graphNothingConnected.
  ///
  /// In en, this message translates to:
  /// **'Nothing connected'**
  String get graphNothingConnected;

  /// No description provided for @graphNothingToMap.
  ///
  /// In en, this message translates to:
  /// **'Nothing to map yet'**
  String get graphNothingToMap;

  /// No description provided for @graphShowUnconnected.
  ///
  /// In en, this message translates to:
  /// **'Show unconnected items'**
  String get graphShowUnconnected;

  /// No description provided for @graphTryAgainInAMoment.
  ///
  /// In en, this message translates to:
  /// **'Try again in a moment.'**
  String get graphTryAgainInAMoment;

  /// No description provided for @graphUntitledPaper.
  ///
  /// In en, this message translates to:
  /// **'Untitled paper'**
  String get graphUntitledPaper;

  /// No description provided for @highlightsAddComment.
  ///
  /// In en, this message translates to:
  /// **'Add a comment'**
  String get highlightsAddComment;

  /// No description provided for @highlightsAddCommentMenu.
  ///
  /// In en, this message translates to:
  /// **'Add a comment…'**
  String get highlightsAddCommentMenu;

  /// No description provided for @highlightsButter.
  ///
  /// In en, this message translates to:
  /// **'Butter highlight'**
  String get highlightsButter;

  /// No description provided for @highlightsDelete.
  ///
  /// In en, this message translates to:
  /// **'Delete highlight'**
  String get highlightsDelete;

  /// No description provided for @highlightsEditCommentMenu.
  ///
  /// In en, this message translates to:
  /// **'Edit comment…'**
  String get highlightsEditCommentMenu;

  /// No description provided for @highlightsEmptyMessage.
  ///
  /// In en, this message translates to:
  /// **'Select text in a PDF and choose Highlight; it will collect here.'**
  String get highlightsEmptyMessage;

  /// No description provided for @highlightsEmptyTitle.
  ///
  /// In en, this message translates to:
  /// **'No highlights yet'**
  String get highlightsEmptyTitle;

  /// No description provided for @highlightsHighlight.
  ///
  /// In en, this message translates to:
  /// **'Highlight'**
  String get highlightsHighlight;

  /// No description provided for @highlightsMist.
  ///
  /// In en, this message translates to:
  /// **'Mist highlight'**
  String get highlightsMist;

  /// No description provided for @highlightsNoMatches.
  ///
  /// In en, this message translates to:
  /// **'No matches.'**
  String get highlightsNoMatches;

  /// No description provided for @highlightsQuoteToNote.
  ///
  /// In en, this message translates to:
  /// **'Quote to note'**
  String get highlightsQuoteToNote;

  /// No description provided for @highlightsRevisit.
  ///
  /// In en, this message translates to:
  /// **'Revisit highlights'**
  String get highlightsRevisit;

  /// No description provided for @highlightsRose.
  ///
  /// In en, this message translates to:
  /// **'Rose highlight'**
  String get highlightsRose;

  /// No description provided for @highlightsSage.
  ///
  /// In en, this message translates to:
  /// **'Sage highlight'**
  String get highlightsSage;

  /// No description provided for @highlightsSearchHint.
  ///
  /// In en, this message translates to:
  /// **'Search your highlights'**
  String get highlightsSearchHint;

  /// No description provided for @highlightsSelectHint.
  ///
  /// In en, this message translates to:
  /// **'Select text on a page, then tap Highlight.'**
  String get highlightsSelectHint;

  /// No description provided for @highlightsTooltip.
  ///
  /// In en, this message translates to:
  /// **'Highlights'**
  String get highlightsTooltip;

  /// No description provided for @historyBack.
  ///
  /// In en, this message translates to:
  /// **'Back'**
  String get historyBack;

  /// No description provided for @historyForward.
  ///
  /// In en, this message translates to:
  /// **'Forward'**
  String get historyForward;

  /// No description provided for @historyKeyForward.
  ///
  /// In en, this message translates to:
  /// **'Forward'**
  String get historyKeyForward;

  /// No description provided for @historyPeekEmpty.
  ///
  /// In en, this message translates to:
  /// **'Nothing written yet'**
  String get historyPeekEmpty;

  /// No description provided for @historyPeekLocked.
  ///
  /// In en, this message translates to:
  /// **'Locked'**
  String get historyPeekLocked;

  /// No description provided for @historyPeekMissing.
  ///
  /// In en, this message translates to:
  /// **'This note or paper is no longer here'**
  String get historyPeekMissing;

  /// No description provided for @historyPeekPage.
  ///
  /// In en, this message translates to:
  /// **'p. {page}'**
  String historyPeekPage(int page);

  /// No description provided for @historyPeekPaperNoAuthors.
  ///
  /// In en, this message translates to:
  /// **'No authors'**
  String get historyPeekPaperNoAuthors;

  /// No description provided for @homeAttachments.
  ///
  /// In en, this message translates to:
  /// **'Attachments'**
  String get homeAttachments;

  /// No description provided for @homeCountItems.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =0{No items} =1{1 item} other{{count} items}}'**
  String homeCountItems(int count);

  /// No description provided for @homeCountNotes.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =0{No notes} =1{1 note} other{{count} notes}}'**
  String homeCountNotes(int count);

  /// No description provided for @homeCountPapers.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =0{No papers} =1{1 paper} other{{count} papers}}'**
  String homeCountPapers(int count);

  /// No description provided for @homeImportFirstPaper.
  ///
  /// In en, this message translates to:
  /// **'Import your first paper'**
  String get homeImportFirstPaper;

  /// No description provided for @homeImportPdfTooltip.
  ///
  /// In en, this message translates to:
  /// **'Import PDF (⌘O)'**
  String get homeImportPdfTooltip;

  /// No description provided for @homeNewNoteTooltip.
  ///
  /// In en, this message translates to:
  /// **'New Note (⌘N)'**
  String get homeNewNoteTooltip;

  /// No description provided for @homePickNote.
  ///
  /// In en, this message translates to:
  /// **'Pick a note, or start a new one.'**
  String get homePickNote;

  /// No description provided for @homePickPaper.
  ///
  /// In en, this message translates to:
  /// **'Pick a paper to read, annotate and cite.'**
  String get homePickPaper;

  /// No description provided for @homeSearchSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Notes, papers and highlights'**
  String get homeSearchSubtitle;

  /// No description provided for @homeShowAttachments.
  ///
  /// In en, this message translates to:
  /// **'Show Attachments'**
  String get homeShowAttachments;

  /// No description provided for @homeShowSidebarTooltip.
  ///
  /// In en, this message translates to:
  /// **'Show Sidebar (⌃⌘S)'**
  String get homeShowSidebarTooltip;

  /// No description provided for @homeStepHighlightText.
  ///
  /// In en, this message translates to:
  /// **'Press and hold on the text, then Highlight or Quote to note.'**
  String get homeStepHighlightText;

  /// No description provided for @homeStepHighlightTitle.
  ///
  /// In en, this message translates to:
  /// **'Highlight as you read'**
  String get homeStepHighlightTitle;

  /// No description provided for @homeStepImportText.
  ///
  /// In en, this message translates to:
  /// **'A PDF from Files. Its title, authors and year fill in by themselves.'**
  String get homeStepImportText;

  /// No description provided for @homeStepImportTitle.
  ///
  /// In en, this message translates to:
  /// **'Import a paper'**
  String get homeStepImportTitle;

  /// No description provided for @homeStepWriteText.
  ///
  /// In en, this message translates to:
  /// **'In a note, type / for tools, or [@ to cite a paper.'**
  String get homeStepWriteText;

  /// No description provided for @homeStepWriteTitle.
  ///
  /// In en, this message translates to:
  /// **'Write and cite'**
  String get homeStepWriteTitle;

  /// No description provided for @homeWelcome.
  ///
  /// In en, this message translates to:
  /// **'Welcome to Corplex'**
  String get homeWelcome;

  /// No description provided for @homeWelcomeSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Read, annotate, take notes and cite in one place.'**
  String get homeWelcomeSubtitle;

  /// No description provided for @inkBlue.
  ///
  /// In en, this message translates to:
  /// **'Blue'**
  String get inkBlue;

  /// No description provided for @inkClay.
  ///
  /// In en, this message translates to:
  /// **'Clay'**
  String get inkClay;

  /// No description provided for @inkColor.
  ///
  /// In en, this message translates to:
  /// **'Ink color'**
  String get inkColor;

  /// No description provided for @inkColour.
  ///
  /// In en, this message translates to:
  /// **'Colour'**
  String get inkColour;

  /// No description provided for @inkConvertToText.
  ///
  /// In en, this message translates to:
  /// **'Convert to text'**
  String get inkConvertToText;

  /// No description provided for @inkDrawHere.
  ///
  /// In en, this message translates to:
  /// **'Draw here'**
  String get inkDrawHere;

  /// No description provided for @inkDrawWithFingers.
  ///
  /// In en, this message translates to:
  /// **'Draw with fingers'**
  String get inkDrawWithFingers;

  /// No description provided for @inkDrawing.
  ///
  /// In en, this message translates to:
  /// **'Drawing'**
  String get inkDrawing;

  /// No description provided for @inkDuplicate.
  ///
  /// In en, this message translates to:
  /// **'Duplicate'**
  String get inkDuplicate;

  /// No description provided for @inkEraser.
  ///
  /// In en, this message translates to:
  /// **'Eraser'**
  String get inkEraser;

  /// No description provided for @inkExpand.
  ///
  /// In en, this message translates to:
  /// **'Expand'**
  String get inkExpand;

  /// No description provided for @inkFingersDraw.
  ///
  /// In en, this message translates to:
  /// **'Fingers draw (tap to scroll with fingers instead)'**
  String get inkFingersDraw;

  /// No description provided for @inkFingersScroll.
  ///
  /// In en, this message translates to:
  /// **'Fingers scroll (tap to draw with fingers)'**
  String get inkFingersScroll;

  /// No description provided for @inkGraphite.
  ///
  /// In en, this message translates to:
  /// **'Graphite'**
  String get inkGraphite;

  /// No description provided for @inkHighlighter.
  ///
  /// In en, this message translates to:
  /// **'Highlighter'**
  String get inkHighlighter;

  /// No description provided for @inkMoreOptions.
  ///
  /// In en, this message translates to:
  /// **'More drawing options'**
  String get inkMoreOptions;

  /// No description provided for @inkMoreSpace.
  ///
  /// In en, this message translates to:
  /// **'More space'**
  String get inkMoreSpace;

  /// No description provided for @inkNoHandwriting.
  ///
  /// In en, this message translates to:
  /// **'No handwriting found'**
  String get inkNoHandwriting;

  /// No description provided for @inkPaste.
  ///
  /// In en, this message translates to:
  /// **'Paste'**
  String get inkPaste;

  /// No description provided for @inkPen.
  ///
  /// In en, this message translates to:
  /// **'Pen'**
  String get inkPen;

  /// No description provided for @inkRedo.
  ///
  /// In en, this message translates to:
  /// **'Redo'**
  String get inkRedo;

  /// No description provided for @inkSage.
  ///
  /// In en, this message translates to:
  /// **'Sage'**
  String get inkSage;

  /// No description provided for @inkScrollWithFingers.
  ///
  /// In en, this message translates to:
  /// **'Scroll with fingers'**
  String get inkScrollWithFingers;

  /// No description provided for @inkSelect.
  ///
  /// In en, this message translates to:
  /// **'Select'**
  String get inkSelect;

  /// No description provided for @inkTapToDraw.
  ///
  /// In en, this message translates to:
  /// **'Tap to draw'**
  String get inkTapToDraw;

  /// No description provided for @inkThickness.
  ///
  /// In en, this message translates to:
  /// **'Line thickness'**
  String get inkThickness;

  /// No description provided for @libraryAddById.
  ///
  /// In en, this message translates to:
  /// **'Add by DOI or arXiv ID'**
  String get libraryAddById;

  /// No description provided for @libraryAddByIdHint.
  ///
  /// In en, this message translates to:
  /// **'10.1038/nature14539, arXiv:1706.03762 or PMID: 9500320'**
  String get libraryAddByIdHint;

  /// No description provided for @libraryAddToProject.
  ///
  /// In en, this message translates to:
  /// **'Add to project…'**
  String get libraryAddToProject;

  /// No description provided for @libraryAddedPapers.
  ///
  /// In en, this message translates to:
  /// **'Added {count, plural, =1{1 paper} other{{count} papers}}'**
  String libraryAddedPapers(int count);

  /// No description provided for @libraryAll.
  ///
  /// In en, this message translates to:
  /// **'All'**
  String get libraryAll;

  /// No description provided for @libraryAllHighlights.
  ///
  /// In en, this message translates to:
  /// **'All highlights'**
  String get libraryAllHighlights;

  /// No description provided for @libraryAllHighlightsHint.
  ///
  /// In en, this message translates to:
  /// **'Across every paper'**
  String get libraryAllHighlightsHint;

  /// No description provided for @libraryAlreadyInLibrary.
  ///
  /// In en, this message translates to:
  /// **'Already in your library.'**
  String get libraryAlreadyInLibrary;

  /// No description provided for @libraryAlreadyInLibraryCount.
  ///
  /// In en, this message translates to:
  /// **'{count} already in your library'**
  String libraryAlreadyInLibraryCount(int count);

  /// No description provided for @libraryCitationCopied.
  ///
  /// In en, this message translates to:
  /// **'Citation copied'**
  String get libraryCitationCopied;

  /// No description provided for @libraryCitationsAdded.
  ///
  /// In en, this message translates to:
  /// **'Added to your library.'**
  String get libraryCitationsAdded;

  /// No description provided for @libraryCitationsCitedBy.
  ///
  /// In en, this message translates to:
  /// **'Cited by'**
  String get libraryCitationsCitedBy;

  /// No description provided for @libraryCitationsInLibrary.
  ///
  /// In en, this message translates to:
  /// **'In your library'**
  String get libraryCitationsInLibrary;

  /// No description provided for @libraryCitationsLoadMore.
  ///
  /// In en, this message translates to:
  /// **'Load more'**
  String get libraryCitationsLoadMore;

  /// No description provided for @libraryCitationsLoadMoreFailed.
  ///
  /// In en, this message translates to:
  /// **'Couldn’t load more. Try again online.'**
  String get libraryCitationsLoadMoreFailed;

  /// No description provided for @libraryCitationsLoading.
  ///
  /// In en, this message translates to:
  /// **'Loading…'**
  String get libraryCitationsLoading;

  /// No description provided for @libraryCitationsMoreNotShown.
  ///
  /// In en, this message translates to:
  /// **'{count} more not shown.'**
  String libraryCitationsMoreNotShown(int count);

  /// No description provided for @libraryCitationsNoCiting.
  ///
  /// In en, this message translates to:
  /// **'No citing papers found.'**
  String get libraryCitationsNoCiting;

  /// No description provided for @libraryCitationsNoReferences.
  ///
  /// In en, this message translates to:
  /// **'No references listed.'**
  String get libraryCitationsNoReferences;

  /// No description provided for @libraryCitationsNotFound.
  ///
  /// In en, this message translates to:
  /// **'OpenAlex has no record of this paper.'**
  String get libraryCitationsNotFound;

  /// No description provided for @libraryCitationsReferences.
  ///
  /// In en, this message translates to:
  /// **'References'**
  String get libraryCitationsReferences;

  /// No description provided for @libraryCitationsRefresh.
  ///
  /// In en, this message translates to:
  /// **'Refresh'**
  String get libraryCitationsRefresh;

  /// No description provided for @libraryCitationsRefreshFailed.
  ///
  /// In en, this message translates to:
  /// **'Couldn’t refresh. Try again online.'**
  String get libraryCitationsRefreshFailed;

  /// No description provided for @libraryCitationsRetry.
  ///
  /// In en, this message translates to:
  /// **'Retry'**
  String get libraryCitationsRetry;

  /// No description provided for @libraryCitationsTitle.
  ///
  /// In en, this message translates to:
  /// **'References · Cited by'**
  String get libraryCitationsTitle;

  /// No description provided for @libraryCitationsUnreachable.
  ///
  /// In en, this message translates to:
  /// **'Couldn’t reach OpenAlex. Try again online.'**
  String get libraryCitationsUnreachable;

  /// No description provided for @libraryCopyCitation.
  ///
  /// In en, this message translates to:
  /// **'Copy citation'**
  String get libraryCopyCitation;

  /// No description provided for @libraryEmptyMessage.
  ///
  /// In en, this message translates to:
  /// **'Tap Import PDF to add a paper, or link one from a note.'**
  String get libraryEmptyMessage;

  /// No description provided for @libraryEmptyTitle.
  ///
  /// In en, this message translates to:
  /// **'Your library is empty'**
  String get libraryEmptyTitle;

  /// No description provided for @libraryError.
  ///
  /// In en, this message translates to:
  /// **'Something went wrong: {error}'**
  String libraryError(String error);

  /// No description provided for @libraryExportBibtex.
  ///
  /// In en, this message translates to:
  /// **'Export as BibTeX'**
  String get libraryExportBibtex;

  /// No description provided for @libraryFoundDetails.
  ///
  /// In en, this message translates to:
  /// **'Found the details for “{title}”'**
  String libraryFoundDetails(String title);

  /// No description provided for @libraryImportReferences.
  ///
  /// In en, this message translates to:
  /// **'Import references'**
  String get libraryImportReferences;

  /// No description provided for @libraryImportReferencesHint.
  ///
  /// In en, this message translates to:
  /// **'BibTeX, RIS or CSL JSON (Zotero, Mendeley)'**
  String get libraryImportReferencesHint;

  /// No description provided for @libraryImportZotero.
  ///
  /// In en, this message translates to:
  /// **'Import from Zotero…'**
  String get libraryImportZotero;

  /// No description provided for @libraryIsEmpty.
  ///
  /// In en, this message translates to:
  /// **'Your library is empty.'**
  String get libraryIsEmpty;

  /// No description provided for @libraryLocatorChapter.
  ///
  /// In en, this message translates to:
  /// **'Chapter'**
  String get libraryLocatorChapter;

  /// No description provided for @libraryLocatorFigure.
  ///
  /// In en, this message translates to:
  /// **'Figure'**
  String get libraryLocatorFigure;

  /// No description provided for @libraryLocatorLine.
  ///
  /// In en, this message translates to:
  /// **'Line'**
  String get libraryLocatorLine;

  /// No description provided for @libraryLocatorNote.
  ///
  /// In en, this message translates to:
  /// **'Note'**
  String get libraryLocatorNote;

  /// No description provided for @libraryLocatorPage.
  ///
  /// In en, this message translates to:
  /// **'Page'**
  String get libraryLocatorPage;

  /// No description provided for @libraryLocatorParagraph.
  ///
  /// In en, this message translates to:
  /// **'Paragraph'**
  String get libraryLocatorParagraph;

  /// No description provided for @libraryLocatorSection.
  ///
  /// In en, this message translates to:
  /// **'Section'**
  String get libraryLocatorSection;

  /// No description provided for @libraryLocatorVolume.
  ///
  /// In en, this message translates to:
  /// **'Volume'**
  String get libraryLocatorVolume;

  /// No description provided for @libraryLookingUp.
  ///
  /// In en, this message translates to:
  /// **'Looking it up…'**
  String get libraryLookingUp;

  /// No description provided for @libraryLooksDuplicate.
  ///
  /// In en, this message translates to:
  /// **'Looks like “{title}” is already here.'**
  String libraryLooksDuplicate(String title);

  /// No description provided for @libraryLookupUnreachable.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t reach the lookup service. Try again online.'**
  String get libraryLookupUnreachable;

  /// No description provided for @libraryNoMatches.
  ///
  /// In en, this message translates to:
  /// **'No matches'**
  String get libraryNoMatches;

  /// No description provided for @libraryNoMatchesHint.
  ///
  /// In en, this message translates to:
  /// **'Try a different title or author.'**
  String get libraryNoMatchesHint;

  /// No description provided for @libraryNoPaperFound.
  ///
  /// In en, this message translates to:
  /// **'No paper found for {id}.'**
  String libraryNoPaperFound(String id);

  /// No description provided for @libraryNoReferencesFound.
  ///
  /// In en, this message translates to:
  /// **'No references found in that file.'**
  String get libraryNoReferencesFound;

  /// No description provided for @libraryNotAnIdentifier.
  ///
  /// In en, this message translates to:
  /// **'That doesn\'t look like a DOI, arXiv or PubMed ID.'**
  String get libraryNotAnIdentifier;

  /// No description provided for @libraryNoticeConcern.
  ///
  /// In en, this message translates to:
  /// **'Expression of concern issued'**
  String get libraryNoticeConcern;

  /// No description provided for @libraryNoticeCorrected.
  ///
  /// In en, this message translates to:
  /// **'Corrected'**
  String get libraryNoticeCorrected;

  /// No description provided for @libraryNoticeDatePattern.
  ///
  /// In en, this message translates to:
  /// **'d MMMM y'**
  String get libraryNoticeDatePattern;

  /// No description provided for @libraryNoticeOn.
  ///
  /// In en, this message translates to:
  /// **'{kind} on {date} — see the notice'**
  String libraryNoticeOn(String kind, String date);

  /// No description provided for @libraryNoticeRetracted.
  ///
  /// In en, this message translates to:
  /// **'Retracted'**
  String get libraryNoticeRetracted;

  /// No description provided for @libraryNoticeUndated.
  ///
  /// In en, this message translates to:
  /// **'{kind} — see the notice'**
  String libraryNoticeUndated(String kind);

  /// No description provided for @libraryNoticeWithdrawn.
  ///
  /// In en, this message translates to:
  /// **'Withdrawn'**
  String get libraryNoticeWithdrawn;

  /// No description provided for @libraryOpenPdf.
  ///
  /// In en, this message translates to:
  /// **'Open PDF'**
  String get libraryOpenPdf;

  /// No description provided for @librarySearchPapers.
  ///
  /// In en, this message translates to:
  /// **'Search papers'**
  String get librarySearchPapers;

  /// No description provided for @libraryShowAttachments.
  ///
  /// In en, this message translates to:
  /// **'Show Attachments'**
  String get libraryShowAttachments;

  /// No description provided for @libraryStatusDone.
  ///
  /// In en, this message translates to:
  /// **'Done'**
  String get libraryStatusDone;

  /// No description provided for @libraryStatusReading.
  ///
  /// In en, this message translates to:
  /// **'Reading'**
  String get libraryStatusReading;

  /// No description provided for @libraryStatusToRead.
  ///
  /// In en, this message translates to:
  /// **'To read'**
  String get libraryStatusToRead;

  /// No description provided for @linksCmdEmbed.
  ///
  /// In en, this message translates to:
  /// **'Embed a note'**
  String get linksCmdEmbed;

  /// No description provided for @linksCmdEmbedHint.
  ///
  /// In en, this message translates to:
  /// **'Show another note here, live. Or type ![['**
  String get linksCmdEmbedHint;

  /// No description provided for @linksEmbedANote.
  ///
  /// In en, this message translates to:
  /// **'Embed a note…'**
  String get linksEmbedANote;

  /// No description provided for @linksEmbedEmpty.
  ///
  /// In en, this message translates to:
  /// **'Empty note'**
  String get linksEmbedEmpty;

  /// No description provided for @linksEmbedLocked.
  ///
  /// In en, this message translates to:
  /// **'Locked'**
  String get linksEmbedLocked;

  /// No description provided for @linksEmbedMissing.
  ///
  /// In en, this message translates to:
  /// **'Note not found'**
  String get linksEmbedMissing;

  /// No description provided for @linksEmbedOpen.
  ///
  /// In en, this message translates to:
  /// **'Open {title}'**
  String linksEmbedOpen(String title);

  /// No description provided for @linksEmbedSectionMissing.
  ///
  /// In en, this message translates to:
  /// **'Section not found'**
  String get linksEmbedSectionMissing;

  /// No description provided for @linksEmbedShowAll.
  ///
  /// In en, this message translates to:
  /// **'Show all'**
  String get linksEmbedShowAll;

  /// No description provided for @linksEmbedShowLess.
  ///
  /// In en, this message translates to:
  /// **'Show less'**
  String get linksEmbedShowLess;

  /// No description provided for @linksHeadingsOf.
  ///
  /// In en, this message translates to:
  /// **'Headings'**
  String get linksHeadingsOf;

  /// No description provided for @linksLinkMention.
  ///
  /// In en, this message translates to:
  /// **'Link'**
  String get linksLinkMention;

  /// No description provided for @linksMentionLinked.
  ///
  /// In en, this message translates to:
  /// **'Linked in “{title}”'**
  String linksMentionLinked(String title);

  /// No description provided for @linksNoHeadings.
  ///
  /// In en, this message translates to:
  /// **'No headings in this note'**
  String get linksNoHeadings;

  /// No description provided for @linksNoParagraphs.
  ///
  /// In en, this message translates to:
  /// **'No paragraphs in this note'**
  String get linksNoParagraphs;

  /// No description provided for @linksParagraphUnavailable.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t mark that paragraph'**
  String get linksParagraphUnavailable;

  /// No description provided for @linksPartsLocked.
  ///
  /// In en, this message translates to:
  /// **'A locked note can only be linked as a whole.'**
  String get linksPartsLocked;

  /// No description provided for @linksToParagraph.
  ///
  /// In en, this message translates to:
  /// **'Link to a paragraph'**
  String get linksToParagraph;

  /// No description provided for @linksToParagraphHint.
  ///
  /// In en, this message translates to:
  /// **'Or type Title#^'**
  String get linksToParagraphHint;

  /// No description provided for @linksUnlinkedMentions.
  ///
  /// In en, this message translates to:
  /// **'Unlinked mentions ({count})'**
  String linksUnlinkedMentions(int count);

  /// No description provided for @listAddToProject.
  ///
  /// In en, this message translates to:
  /// **'Add to project…'**
  String get listAddToProject;

  /// No description provided for @listAll.
  ///
  /// In en, this message translates to:
  /// **'All'**
  String get listAll;

  /// No description provided for @listCreate.
  ///
  /// In en, this message translates to:
  /// **'Create'**
  String get listCreate;

  /// No description provided for @listDeleteFolderEllipsis.
  ///
  /// In en, this message translates to:
  /// **'Delete folder…'**
  String get listDeleteFolderEllipsis;

  /// No description provided for @listDeleteFolderMessage.
  ///
  /// In en, this message translates to:
  /// **'Notes inside will be unfiled, not deleted.'**
  String get listDeleteFolderMessage;

  /// No description provided for @listDeleteFolderTitle.
  ///
  /// In en, this message translates to:
  /// **'Delete “{name}”?'**
  String listDeleteFolderTitle(String name);

  /// No description provided for @listDeleteTagEllipsis.
  ///
  /// In en, this message translates to:
  /// **'Delete tag…'**
  String get listDeleteTagEllipsis;

  /// No description provided for @listDeleteTagMessage.
  ///
  /// In en, this message translates to:
  /// **'This removes the tag from every note.'**
  String get listDeleteTagMessage;

  /// No description provided for @listDeleteTagTitle.
  ///
  /// In en, this message translates to:
  /// **'Delete “#{name}”?'**
  String listDeleteTagTitle(String name);

  /// No description provided for @listDuplicate.
  ///
  /// In en, this message translates to:
  /// **'Duplicate'**
  String get listDuplicate;

  /// No description provided for @listFolderName.
  ///
  /// In en, this message translates to:
  /// **'Folder name'**
  String get listFolderName;

  /// No description provided for @listFolderOrTag.
  ///
  /// In en, this message translates to:
  /// **'Folder or tag'**
  String get listFolderOrTag;

  /// No description provided for @listLockNote.
  ///
  /// In en, this message translates to:
  /// **'Lock note'**
  String get listLockNote;

  /// No description provided for @listNewFolder.
  ///
  /// In en, this message translates to:
  /// **'New folder'**
  String get listNewFolder;

  /// No description provided for @listNewTag.
  ///
  /// In en, this message translates to:
  /// **'New tag'**
  String get listNewTag;

  /// No description provided for @listNoNotesMessage.
  ///
  /// In en, this message translates to:
  /// **'Tap New note to capture your first thought.'**
  String get listNoNotesMessage;

  /// No description provided for @listNoNotesTitle.
  ///
  /// In en, this message translates to:
  /// **'No notes yet'**
  String get listNoNotesTitle;

  /// No description provided for @listNothingHereMessage.
  ///
  /// In en, this message translates to:
  /// **'Notes you add while this filter is on land here.'**
  String get listNothingHereMessage;

  /// No description provided for @listNothingHereTitle.
  ///
  /// In en, this message translates to:
  /// **'Nothing here yet'**
  String get listNothingHereTitle;

  /// No description provided for @listPinToTop.
  ///
  /// In en, this message translates to:
  /// **'Pin to top'**
  String get listPinToTop;

  /// No description provided for @listPinned.
  ///
  /// In en, this message translates to:
  /// **'Pinned'**
  String get listPinned;

  /// No description provided for @listPrevious30Days.
  ///
  /// In en, this message translates to:
  /// **'Previous 30 Days'**
  String get listPrevious30Days;

  /// No description provided for @listPrevious7Days.
  ///
  /// In en, this message translates to:
  /// **'Previous 7 Days'**
  String get listPrevious7Days;

  /// No description provided for @listRemoveLock.
  ///
  /// In en, this message translates to:
  /// **'Remove lock'**
  String get listRemoveLock;

  /// No description provided for @listSomethingWentWrong.
  ///
  /// In en, this message translates to:
  /// **'Something went wrong: {error}'**
  String listSomethingWentWrong(String error);

  /// No description provided for @listTagName.
  ///
  /// In en, this message translates to:
  /// **'Tag name'**
  String get listTagName;

  /// No description provided for @listToday.
  ///
  /// In en, this message translates to:
  /// **'Today'**
  String get listToday;

  /// No description provided for @listUnpin.
  ///
  /// In en, this message translates to:
  /// **'Unpin'**
  String get listUnpin;

  /// No description provided for @listYesterday.
  ///
  /// In en, this message translates to:
  /// **'Yesterday'**
  String get listYesterday;

  /// No description provided for @lockBiometricFaceTouch.
  ///
  /// In en, this message translates to:
  /// **'Face ID / Touch ID'**
  String get lockBiometricFaceTouch;

  /// No description provided for @lockBiometricFingerprint.
  ///
  /// In en, this message translates to:
  /// **'fingerprint'**
  String get lockBiometricFingerprint;

  /// No description provided for @lockBiometricGeneric.
  ///
  /// In en, this message translates to:
  /// **'biometrics'**
  String get lockBiometricGeneric;

  /// No description provided for @lockBiometricReason.
  ///
  /// In en, this message translates to:
  /// **'Unlock your locked notes'**
  String get lockBiometricReason;

  /// No description provided for @lockBiometricSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Open locked notes without typing'**
  String get lockBiometricSubtitle;

  /// No description provided for @lockBiometricTouch.
  ///
  /// In en, this message translates to:
  /// **'Touch ID'**
  String get lockBiometricTouch;

  /// No description provided for @lockChangePassword.
  ///
  /// In en, this message translates to:
  /// **'Change password'**
  String get lockChangePassword;

  /// No description provided for @lockChangeTitle.
  ///
  /// In en, this message translates to:
  /// **'Change notes password'**
  String get lockChangeTitle;

  /// No description provided for @lockConfirm.
  ///
  /// In en, this message translates to:
  /// **'Confirm'**
  String get lockConfirm;

  /// No description provided for @lockContinue.
  ///
  /// In en, this message translates to:
  /// **'Continue'**
  String get lockContinue;

  /// No description provided for @lockCurrentPassword.
  ///
  /// In en, this message translates to:
  /// **'Current password'**
  String get lockCurrentPassword;

  /// No description provided for @lockCurrentWrong.
  ///
  /// In en, this message translates to:
  /// **'The current password is wrong.'**
  String get lockCurrentWrong;

  /// No description provided for @lockEarlierPassword.
  ///
  /// In en, this message translates to:
  /// **'This note uses an earlier notes password'**
  String get lockEarlierPassword;

  /// No description provided for @lockEnterPassword.
  ///
  /// In en, this message translates to:
  /// **'Enter your notes password.'**
  String get lockEnterPassword;

  /// No description provided for @lockEnterToTurnOn.
  ///
  /// In en, this message translates to:
  /// **'Enter your notes password to turn this on.'**
  String get lockEnterToTurnOn;

  /// No description provided for @lockForgottenWarning.
  ///
  /// In en, this message translates to:
  /// **'If you forget this password, locked notes can\'t be recovered — not by you, and not by us.'**
  String get lockForgottenWarning;

  /// No description provided for @lockHint.
  ///
  /// In en, this message translates to:
  /// **'Hint: {hint}'**
  String lockHint(String hint);

  /// No description provided for @lockHintHelper.
  ///
  /// In en, this message translates to:
  /// **'Shown on the lock screen. Not the password!'**
  String get lockHintHelper;

  /// No description provided for @lockHintOptional.
  ///
  /// In en, this message translates to:
  /// **'Hint (optional)'**
  String get lockHintOptional;

  /// No description provided for @lockLockedNote.
  ///
  /// In en, this message translates to:
  /// **'This note is locked'**
  String get lockLockedNote;

  /// No description provided for @lockMinLength.
  ///
  /// In en, this message translates to:
  /// **'Use at least {count} characters.'**
  String lockMinLength(int count);

  /// No description provided for @lockMismatch.
  ///
  /// In en, this message translates to:
  /// **'The passwords don\'t match.'**
  String get lockMismatch;

  /// No description provided for @lockNewMismatch.
  ///
  /// In en, this message translates to:
  /// **'The new passwords don\'t match.'**
  String get lockNewMismatch;

  /// No description provided for @lockNewPassword.
  ///
  /// In en, this message translates to:
  /// **'New password'**
  String get lockNewPassword;

  /// No description provided for @lockNotNow.
  ///
  /// In en, this message translates to:
  /// **'Not now'**
  String get lockNotNow;

  /// No description provided for @lockNotesPassword.
  ///
  /// In en, this message translates to:
  /// **'Notes password'**
  String get lockNotesPassword;

  /// No description provided for @lockNow.
  ///
  /// In en, this message translates to:
  /// **'Lock now'**
  String get lockNow;

  /// No description provided for @lockNowSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Locked notes ask for the password again'**
  String get lockNowSubtitle;

  /// No description provided for @lockOfferBody.
  ///
  /// In en, this message translates to:
  /// **'Open locked notes with {name} instead of typing the password. The password still works.'**
  String lockOfferBody(String name);

  /// No description provided for @lockOfferTitle.
  ///
  /// In en, this message translates to:
  /// **'Use {name} to unlock?'**
  String lockOfferTitle(String name);

  /// No description provided for @lockPassword.
  ///
  /// In en, this message translates to:
  /// **'Password'**
  String get lockPassword;

  /// No description provided for @lockPasswordChanged.
  ///
  /// In en, this message translates to:
  /// **'Notes password changed'**
  String get lockPasswordChanged;

  /// No description provided for @lockResetBody.
  ///
  /// In en, this message translates to:
  /// **'You\'ll choose a new password for notes you lock from now on.\n\nNotes already locked stay locked under the old password. Without it they can\'t be opened — not by you, and not by us. If you remember the old password later, entering it opens them again.'**
  String get lockResetBody;

  /// No description provided for @lockResetDialogTitle.
  ///
  /// In en, this message translates to:
  /// **'Reset the notes password?'**
  String get lockResetDialogTitle;

  /// No description provided for @lockResetItem.
  ///
  /// In en, this message translates to:
  /// **'Reset password…'**
  String get lockResetItem;

  /// No description provided for @lockResetItemSubtitle.
  ///
  /// In en, this message translates to:
  /// **'For a forgotten password'**
  String get lockResetItemSubtitle;

  /// No description provided for @lockResetPassword.
  ///
  /// In en, this message translates to:
  /// **'Reset password'**
  String get lockResetPassword;

  /// No description provided for @lockResetTitle.
  ///
  /// In en, this message translates to:
  /// **'Reset notes password'**
  String get lockResetTitle;

  /// No description provided for @lockSetPassword.
  ///
  /// In en, this message translates to:
  /// **'Set password'**
  String get lockSetPassword;

  /// No description provided for @lockSetTitle.
  ///
  /// In en, this message translates to:
  /// **'Set a notes password'**
  String get lockSetTitle;

  /// No description provided for @lockShowHint.
  ///
  /// In en, this message translates to:
  /// **'Show hint'**
  String get lockShowHint;

  /// No description provided for @lockUnlock.
  ///
  /// In en, this message translates to:
  /// **'Unlock'**
  String get lockUnlock;

  /// No description provided for @lockUnlockToContinue.
  ///
  /// In en, this message translates to:
  /// **'Unlock your locked notes to continue.'**
  String get lockUnlockToContinue;

  /// No description provided for @lockUseBiometric.
  ///
  /// In en, this message translates to:
  /// **'Use {name}'**
  String lockUseBiometric(String name);

  /// No description provided for @lockWrongPassword.
  ///
  /// In en, this message translates to:
  /// **'Wrong password'**
  String get lockWrongPassword;

  /// No description provided for @macAllNotes.
  ///
  /// In en, this message translates to:
  /// **'All Notes'**
  String get macAllNotes;

  /// No description provided for @macAllPapers.
  ///
  /// In en, this message translates to:
  /// **'All Papers'**
  String get macAllPapers;

  /// No description provided for @macCreate.
  ///
  /// In en, this message translates to:
  /// **'Create'**
  String get macCreate;

  /// No description provided for @macDeleteFolder.
  ///
  /// In en, this message translates to:
  /// **'Delete Folder…'**
  String get macDeleteFolder;

  /// No description provided for @macDeleteTag.
  ///
  /// In en, this message translates to:
  /// **'Delete Tag…'**
  String get macDeleteTag;

  /// No description provided for @macFolderNameHint.
  ///
  /// In en, this message translates to:
  /// **'Folder name'**
  String get macFolderNameHint;

  /// No description provided for @macHideSidebarTooltip.
  ///
  /// In en, this message translates to:
  /// **'Hide Sidebar (⌃⌘S)'**
  String get macHideSidebarTooltip;

  /// No description provided for @macKeyActualSize.
  ///
  /// In en, this message translates to:
  /// **'Actual size'**
  String get macKeyActualSize;

  /// No description provided for @macKeyAddComment.
  ///
  /// In en, this message translates to:
  /// **'Add comment'**
  String get macKeyAddComment;

  /// No description provided for @macKeyAttachments.
  ///
  /// In en, this message translates to:
  /// **'Attachments'**
  String get macKeyAttachments;

  /// No description provided for @macKeyBack.
  ///
  /// In en, this message translates to:
  /// **'Back'**
  String get macKeyBack;

  /// No description provided for @macKeyBlockQuote.
  ///
  /// In en, this message translates to:
  /// **'Block quote'**
  String get macKeyBlockQuote;

  /// No description provided for @macKeyBody.
  ///
  /// In en, this message translates to:
  /// **'Body'**
  String get macKeyBody;

  /// No description provided for @macKeyBold.
  ///
  /// In en, this message translates to:
  /// **'Bold'**
  String get macKeyBold;

  /// No description provided for @macKeyBulletedList.
  ///
  /// In en, this message translates to:
  /// **'Bulleted list'**
  String get macKeyBulletedList;

  /// No description provided for @macKeyChecklist.
  ///
  /// In en, this message translates to:
  /// **'Checklist'**
  String get macKeyChecklist;

  /// No description provided for @macKeyCitePaper.
  ///
  /// In en, this message translates to:
  /// **'Cite a paper'**
  String get macKeyCitePaper;

  /// No description provided for @macKeyCloseDialog.
  ///
  /// In en, this message translates to:
  /// **'Close a dialog or menu'**
  String get macKeyCloseDialog;

  /// No description provided for @macKeyCloseWindow.
  ///
  /// In en, this message translates to:
  /// **'Close window'**
  String get macKeyCloseWindow;

  /// No description provided for @macKeyDefaultInterface.
  ///
  /// In en, this message translates to:
  /// **'Default interface size'**
  String get macKeyDefaultInterface;

  /// No description provided for @macKeyDuplicateNote.
  ///
  /// In en, this message translates to:
  /// **'Duplicate note'**
  String get macKeyDuplicateNote;

  /// No description provided for @macKeyFindInDocument.
  ///
  /// In en, this message translates to:
  /// **'Find in document'**
  String get macKeyFindInDocument;

  /// No description provided for @macKeyFindNext.
  ///
  /// In en, this message translates to:
  /// **'Find next'**
  String get macKeyFindNext;

  /// No description provided for @macKeyFindPrevious.
  ///
  /// In en, this message translates to:
  /// **'Find previous'**
  String get macKeyFindPrevious;

  /// No description provided for @macKeyHeading.
  ///
  /// In en, this message translates to:
  /// **'Heading'**
  String get macKeyHeading;

  /// No description provided for @macKeyHighlight.
  ///
  /// In en, this message translates to:
  /// **'Highlight'**
  String get macKeyHighlight;

  /// No description provided for @macKeyImportPdf.
  ///
  /// In en, this message translates to:
  /// **'Import PDF'**
  String get macKeyImportPdf;

  /// No description provided for @macKeyItalic.
  ///
  /// In en, this message translates to:
  /// **'Italic'**
  String get macKeyItalic;

  /// No description provided for @macKeyLargerInterface.
  ///
  /// In en, this message translates to:
  /// **'Larger interface'**
  String get macKeyLargerInterface;

  /// No description provided for @macKeyLibrary.
  ///
  /// In en, this message translates to:
  /// **'Library'**
  String get macKeyLibrary;

  /// No description provided for @macKeyLinkNote.
  ///
  /// In en, this message translates to:
  /// **'Link to a note'**
  String get macKeyLinkNote;

  /// No description provided for @macKeyMonospaced.
  ///
  /// In en, this message translates to:
  /// **'Monospaced'**
  String get macKeyMonospaced;

  /// No description provided for @macKeyMoveThroughList.
  ///
  /// In en, this message translates to:
  /// **'Move through a list'**
  String get macKeyMoveThroughList;

  /// No description provided for @macKeyMoveToTrash.
  ///
  /// In en, this message translates to:
  /// **'Move to Trash'**
  String get macKeyMoveToTrash;

  /// No description provided for @macKeyNewNote.
  ///
  /// In en, this message translates to:
  /// **'New note'**
  String get macKeyNewNote;

  /// No description provided for @macKeyNextColumn.
  ///
  /// In en, this message translates to:
  /// **'Next or previous column'**
  String get macKeyNextColumn;

  /// No description provided for @macKeyNotes.
  ///
  /// In en, this message translates to:
  /// **'Notes'**
  String get macKeyNotes;

  /// No description provided for @macKeyNumberedList.
  ///
  /// In en, this message translates to:
  /// **'Numbered list'**
  String get macKeyNumberedList;

  /// No description provided for @macKeyOpenSelected.
  ///
  /// In en, this message translates to:
  /// **'Open the selected item'**
  String get macKeyOpenSelected;

  /// No description provided for @macKeyPrint.
  ///
  /// In en, this message translates to:
  /// **'Print'**
  String get macKeyPrint;

  /// No description provided for @macKeyQuickNote.
  ///
  /// In en, this message translates to:
  /// **'Quick note from anywhere'**
  String get macKeyQuickNote;

  /// No description provided for @macKeySearch.
  ///
  /// In en, this message translates to:
  /// **'Search'**
  String get macKeySearch;

  /// No description provided for @macKeySettings.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get macKeySettings;

  /// No description provided for @macKeyShortcuts.
  ///
  /// In en, this message translates to:
  /// **'Keyboard shortcuts'**
  String get macKeyShortcuts;

  /// No description provided for @macKeySidebar.
  ///
  /// In en, this message translates to:
  /// **'Show or hide the sidebar'**
  String get macKeySidebar;

  /// No description provided for @macKeySmallerInterface.
  ///
  /// In en, this message translates to:
  /// **'Smaller interface'**
  String get macKeySmallerInterface;

  /// No description provided for @macKeyStrikethrough.
  ///
  /// In en, this message translates to:
  /// **'Strikethrough'**
  String get macKeyStrikethrough;

  /// No description provided for @macKeySubheading.
  ///
  /// In en, this message translates to:
  /// **'Subheading'**
  String get macKeySubheading;

  /// No description provided for @macKeyTable.
  ///
  /// In en, this message translates to:
  /// **'Table'**
  String get macKeyTable;

  /// No description provided for @macKeyTitle.
  ///
  /// In en, this message translates to:
  /// **'Title'**
  String get macKeyTitle;

  /// No description provided for @macKeyUnderline.
  ///
  /// In en, this message translates to:
  /// **'Underline'**
  String get macKeyUnderline;

  /// No description provided for @macKeyZoomIn.
  ///
  /// In en, this message translates to:
  /// **'Zoom in'**
  String get macKeyZoomIn;

  /// No description provided for @macKeyZoomOut.
  ///
  /// In en, this message translates to:
  /// **'Zoom out'**
  String get macKeyZoomOut;

  /// No description provided for @macMoreMenu.
  ///
  /// In en, this message translates to:
  /// **'More…'**
  String get macMoreMenu;

  /// No description provided for @macNewFolderTitle.
  ///
  /// In en, this message translates to:
  /// **'New folder'**
  String get macNewFolderTitle;

  /// No description provided for @macNewFolderTooltip.
  ///
  /// In en, this message translates to:
  /// **'New Folder'**
  String get macNewFolderTooltip;

  /// No description provided for @macOpenProjectPage.
  ///
  /// In en, this message translates to:
  /// **'Open Project Page'**
  String get macOpenProjectPage;

  /// No description provided for @macRenameFolder.
  ///
  /// In en, this message translates to:
  /// **'Rename Folder…'**
  String get macRenameFolder;

  /// No description provided for @macRenameFolderTitle.
  ///
  /// In en, this message translates to:
  /// **'Rename folder'**
  String get macRenameFolderTitle;

  /// No description provided for @macSectionCollapsed.
  ///
  /// In en, this message translates to:
  /// **'{title}, collapsed'**
  String macSectionCollapsed(String title);

  /// No description provided for @macSectionExpanded.
  ///
  /// In en, this message translates to:
  /// **'{title}, expanded'**
  String macSectionExpanded(String title);

  /// No description provided for @macShortcutsFormatting.
  ///
  /// In en, this message translates to:
  /// **'Notes & Formatting'**
  String get macShortcutsFormatting;

  /// No description provided for @macShortcutsGeneral.
  ///
  /// In en, this message translates to:
  /// **'General'**
  String get macShortcutsGeneral;

  /// No description provided for @macShortcutsNavigation.
  ///
  /// In en, this message translates to:
  /// **'Navigation'**
  String get macShortcutsNavigation;

  /// No description provided for @macShortcutsReader.
  ///
  /// In en, this message translates to:
  /// **'Library & Reader'**
  String get macShortcutsReader;

  /// No description provided for @macShortcutsTitle.
  ///
  /// In en, this message translates to:
  /// **'Keyboard Shortcuts'**
  String get macShortcutsTitle;

  /// No description provided for @macTags.
  ///
  /// In en, this message translates to:
  /// **'Tags'**
  String get macTags;

  /// No description provided for @markupMarkUp.
  ///
  /// In en, this message translates to:
  /// **'Mark up'**
  String get markupMarkUp;

  /// No description provided for @markupOpenFailed.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t open this image.'**
  String get markupOpenFailed;

  /// No description provided for @markupSaveFailed.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t save the marks.'**
  String get markupSaveFailed;

  /// No description provided for @matrixAddDefaults.
  ///
  /// In en, this message translates to:
  /// **'Add method, sample, findings'**
  String get matrixAddDefaults;

  /// No description provided for @matrixAddStudyColumns.
  ///
  /// In en, this message translates to:
  /// **'Add study columns'**
  String get matrixAddStudyColumns;

  /// No description provided for @matrixAddTheme.
  ///
  /// In en, this message translates to:
  /// **'Add a theme'**
  String get matrixAddTheme;

  /// No description provided for @matrixAllNotHereYet.
  ///
  /// In en, this message translates to:
  /// **'All the ones not here yet'**
  String get matrixAllNotHereYet;

  /// No description provided for @matrixAlreadyAColumn.
  ///
  /// In en, this message translates to:
  /// **'Already a column'**
  String get matrixAlreadyAColumn;

  /// No description provided for @matrixCellHint.
  ///
  /// In en, this message translates to:
  /// **'What does this paper say?'**
  String get matrixCellHint;

  /// No description provided for @matrixColumnFindings.
  ///
  /// In en, this message translates to:
  /// **'Findings'**
  String get matrixColumnFindings;

  /// No description provided for @matrixColumnMethod.
  ///
  /// In en, this message translates to:
  /// **'Method'**
  String get matrixColumnMethod;

  /// No description provided for @matrixColumnSample.
  ///
  /// In en, this message translates to:
  /// **'Sample'**
  String get matrixColumnSample;

  /// No description provided for @matrixCopiedAsMarkdown.
  ///
  /// In en, this message translates to:
  /// **'Table copied as Markdown'**
  String get matrixCopiedAsMarkdown;

  /// No description provided for @matrixCopyAsMarkdown.
  ///
  /// In en, this message translates to:
  /// **'Copy as Markdown'**
  String get matrixCopyAsMarkdown;

  /// No description provided for @matrixDeleteColumn.
  ///
  /// In en, this message translates to:
  /// **'Delete column'**
  String get matrixDeleteColumn;

  /// No description provided for @matrixDeleteTheme.
  ///
  /// In en, this message translates to:
  /// **'Delete theme and its notes'**
  String get matrixDeleteTheme;

  /// No description provided for @matrixEmptyMessage.
  ///
  /// In en, this message translates to:
  /// **'Add the themes you are comparing — method, sample, findings — and fill in what each paper says.'**
  String get matrixEmptyMessage;

  /// No description provided for @matrixEmptyTitle.
  ///
  /// In en, this message translates to:
  /// **'Compare papers side by side'**
  String get matrixEmptyTitle;

  /// No description provided for @matrixExport.
  ///
  /// In en, this message translates to:
  /// **'Export'**
  String get matrixExport;

  /// No description provided for @matrixFromHighlights.
  ///
  /// In en, this message translates to:
  /// **'From your highlights'**
  String get matrixFromHighlights;

  /// No description provided for @matrixFromStudyDetails.
  ///
  /// In en, this message translates to:
  /// **'From study details'**
  String get matrixFromStudyDetails;

  /// No description provided for @matrixNewTheme.
  ///
  /// In en, this message translates to:
  /// **'New theme'**
  String get matrixNewTheme;

  /// No description provided for @matrixNoPapers.
  ///
  /// In en, this message translates to:
  /// **'No papers in this project'**
  String get matrixNoPapers;

  /// No description provided for @matrixNoPapersMessage.
  ///
  /// In en, this message translates to:
  /// **'Add papers to it from their screens, then compare them here.'**
  String get matrixNoPapersMessage;

  /// No description provided for @matrixPapersKeepDetails.
  ///
  /// In en, this message translates to:
  /// **'Papers keep their study details'**
  String get matrixPapersKeepDetails;

  /// No description provided for @matrixRenameTheme.
  ///
  /// In en, this message translates to:
  /// **'Rename theme'**
  String get matrixRenameTheme;

  /// No description provided for @matrixSeparateWithSemicolon.
  ///
  /// In en, this message translates to:
  /// **'Separate with ;'**
  String get matrixSeparateWithSemicolon;

  /// No description provided for @matrixShare.
  ///
  /// In en, this message translates to:
  /// **'Share…'**
  String get matrixShare;

  /// No description provided for @matrixShareSubject.
  ///
  /// In en, this message translates to:
  /// **'{project} matrix'**
  String matrixShareSubject(String project);

  /// No description provided for @mdImportAction.
  ///
  /// In en, this message translates to:
  /// **'Import Markdown or Obsidian vault'**
  String get mdImportAction;

  /// No description provided for @mdImportActionSubtitle.
  ///
  /// In en, this message translates to:
  /// **'A folder, .md files or a zip'**
  String get mdImportActionSubtitle;

  /// No description provided for @mdImportChooseTitle.
  ///
  /// In en, this message translates to:
  /// **'Import Markdown'**
  String get mdImportChooseTitle;

  /// No description provided for @mdImportDoneTitle.
  ///
  /// In en, this message translates to:
  /// **'Import finished'**
  String get mdImportDoneTitle;

  /// No description provided for @mdImportFiles.
  ///
  /// In en, this message translates to:
  /// **'Markdown files'**
  String get mdImportFiles;

  /// No description provided for @mdImportFolder.
  ///
  /// In en, this message translates to:
  /// **'A folder (an Obsidian vault)'**
  String get mdImportFolder;

  /// No description provided for @mdImportNothing.
  ///
  /// In en, this message translates to:
  /// **'No Markdown notes were found there.'**
  String get mdImportNothing;

  /// No description provided for @mdImportProgress.
  ///
  /// In en, this message translates to:
  /// **'Importing {done} of {total}…'**
  String mdImportProgress(int done, int total);

  /// No description provided for @mdImportReadFailed.
  ///
  /// In en, this message translates to:
  /// **'That couldn\'t be read.'**
  String get mdImportReadFailed;

  /// No description provided for @mdImportReading.
  ///
  /// In en, this message translates to:
  /// **'Reading files…'**
  String get mdImportReading;

  /// No description provided for @mdImportSummaryAttachments.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 attachment copied} other{{count} attachments copied}}'**
  String mdImportSummaryAttachments(int count);

  /// No description provided for @mdImportSummaryFailed.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 note couldn\'t be saved} other{{count} notes couldn\'t be saved}}'**
  String mdImportSummaryFailed(int count);

  /// No description provided for @mdImportSummaryNotes.
  ///
  /// In en, this message translates to:
  /// **'{notes, plural, =0{No notes imported} =1{1 note imported} other{{notes} notes imported}}'**
  String mdImportSummaryNotes(int notes);

  /// No description provided for @mdImportSummarySkipped.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 skipped (already here, locked, or a paper page)} other{{count} skipped (already here, locked, or paper pages)}}'**
  String mdImportSummarySkipped(int count);

  /// No description provided for @mdImportSummaryUnresolved.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 link matched nothing and was left as text} other{{count} links matched nothing and were left as text}}'**
  String mdImportSummaryUnresolved(int count);

  /// No description provided for @mdImportZip.
  ///
  /// In en, this message translates to:
  /// **'A zip of Markdown files'**
  String get mdImportZip;

  /// No description provided for @notesAddTag.
  ///
  /// In en, this message translates to:
  /// **'Add tag'**
  String get notesAddTag;

  /// No description provided for @notesBeforeRestoring.
  ///
  /// In en, this message translates to:
  /// **'Before restoring'**
  String get notesBeforeRestoring;

  /// No description provided for @notesChangePage.
  ///
  /// In en, this message translates to:
  /// **'Change page'**
  String get notesChangePage;

  /// No description provided for @notesCitationLabel.
  ///
  /// In en, this message translates to:
  /// **'Citation {label}'**
  String notesCitationLabel(String label);

  /// No description provided for @notesCitationMissingLabel.
  ///
  /// In en, this message translates to:
  /// **'Citation {marker}, paper not found'**
  String notesCitationMissingLabel(String marker);

  /// No description provided for @notesCitationNotInLibrary.
  ///
  /// In en, this message translates to:
  /// **'@{key} isn\'t in your library.'**
  String notesCitationNotInLibrary(String key);

  /// No description provided for @notesCiteAPaper.
  ///
  /// In en, this message translates to:
  /// **'Cite a paper'**
  String get notesCiteAPaper;

  /// No description provided for @notesClear.
  ///
  /// In en, this message translates to:
  /// **'Clear'**
  String get notesClear;

  /// No description provided for @notesCompare.
  ///
  /// In en, this message translates to:
  /// **'Compare'**
  String get notesCompare;

  /// No description provided for @notesCompareChanged.
  ///
  /// In en, this message translates to:
  /// **'{when} · now has {words} words · {added} added, {removed} removed'**
  String notesCompareChanged(String when, String words, int added, int removed);

  /// No description provided for @notesCompareSame.
  ///
  /// In en, this message translates to:
  /// **'{when} · the same as now'**
  String notesCompareSame(String when);

  /// No description provided for @notesCouldntAddFile.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t add that file.'**
  String get notesCouldntAddFile;

  /// No description provided for @notesCouldntDuplicate.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t duplicate that note.'**
  String get notesCouldntDuplicate;

  /// No description provided for @notesCouldntPrint.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t print that note.'**
  String get notesCouldntPrint;

  /// No description provided for @notesCreate.
  ///
  /// In en, this message translates to:
  /// **'Create'**
  String get notesCreate;

  /// No description provided for @notesDropToAttach.
  ///
  /// In en, this message translates to:
  /// **'Drop to attach'**
  String get notesDropToAttach;

  /// No description provided for @notesDuplicate.
  ///
  /// In en, this message translates to:
  /// **'Duplicate'**
  String get notesDuplicate;

  /// No description provided for @notesEquationEmpty.
  ///
  /// In en, this message translates to:
  /// **'Tap to write an equation'**
  String get notesEquationEmpty;

  /// No description provided for @notesEquationLabel.
  ///
  /// In en, this message translates to:
  /// **'Equation {latex}'**
  String notesEquationLabel(String latex);

  /// No description provided for @notesFigureCaptionLabel.
  ///
  /// In en, this message translates to:
  /// **'{name} caption'**
  String notesFigureCaptionLabel(String name);

  /// No description provided for @notesFigureMissing.
  ///
  /// In en, this message translates to:
  /// **'Figure ??'**
  String get notesFigureMissing;

  /// No description provided for @notesFigureName.
  ///
  /// In en, this message translates to:
  /// **'Figure {number}'**
  String notesFigureName(String number);

  /// No description provided for @notesFigureReferenceLabel.
  ///
  /// In en, this message translates to:
  /// **'Reference to {name}'**
  String notesFigureReferenceLabel(String name);

  /// No description provided for @notesFigureReferenceMissing.
  ///
  /// In en, this message translates to:
  /// **'Reference to a missing figure'**
  String get notesFigureReferenceMissing;

  /// No description provided for @notesFiguresEmpty.
  ///
  /// In en, this message translates to:
  /// **'No figures or tables yet. Type / and choose Figure caption or Table caption.'**
  String get notesFiguresEmpty;

  /// No description provided for @notesFolderName.
  ///
  /// In en, this message translates to:
  /// **'Folder name'**
  String get notesFolderName;

  /// No description provided for @notesHighlightBlue.
  ///
  /// In en, this message translates to:
  /// **'Blue'**
  String get notesHighlightBlue;

  /// No description provided for @notesHighlightGreen.
  ///
  /// In en, this message translates to:
  /// **'Green'**
  String get notesHighlightGreen;

  /// No description provided for @notesHighlightPink.
  ///
  /// In en, this message translates to:
  /// **'Pink'**
  String get notesHighlightPink;

  /// No description provided for @notesHighlightPurple.
  ///
  /// In en, this message translates to:
  /// **'Purple'**
  String get notesHighlightPurple;

  /// No description provided for @notesHighlightYellow.
  ///
  /// In en, this message translates to:
  /// **'Yellow'**
  String get notesHighlightYellow;

  /// No description provided for @notesImportAPdf.
  ///
  /// In en, this message translates to:
  /// **'Import a PDF'**
  String get notesImportAPdf;

  /// No description provided for @notesLatexHint.
  ///
  /// In en, this message translates to:
  /// **'LaTeX, e.g. x^2 + \\alpha'**
  String get notesLatexHint;

  /// No description provided for @notesLatexInvalid.
  ///
  /// In en, this message translates to:
  /// **'Not valid LaTeX yet. It is kept as you typed it.'**
  String get notesLatexInvalid;

  /// No description provided for @notesLessThanAMinute.
  ///
  /// In en, this message translates to:
  /// **'< 1 min'**
  String get notesLessThanAMinute;

  /// No description provided for @notesLinkToANote.
  ///
  /// In en, this message translates to:
  /// **'Link to a note…'**
  String get notesLinkToANote;

  /// No description provided for @notesLockNote.
  ///
  /// In en, this message translates to:
  /// **'Lock note'**
  String get notesLockNote;

  /// No description provided for @notesMinutes.
  ///
  /// In en, this message translates to:
  /// **'{count} min'**
  String notesMinutes(int count);

  /// No description provided for @notesNewFolder.
  ///
  /// In en, this message translates to:
  /// **'New folder'**
  String get notesNewFolder;

  /// No description provided for @notesNewNoteNamed.
  ///
  /// In en, this message translates to:
  /// **'New note “{title}”'**
  String notesNewNoteNamed(String title);

  /// No description provided for @notesNewTagName.
  ///
  /// In en, this message translates to:
  /// **'New tag name'**
  String get notesNewTagName;

  /// No description provided for @notesNoFolder.
  ///
  /// In en, this message translates to:
  /// **'No folder'**
  String get notesNoFolder;

  /// No description provided for @notesNoPapersFound.
  ///
  /// In en, this message translates to:
  /// **'No papers found.'**
  String get notesNoPapersFound;

  /// No description provided for @notesNoTagsYet.
  ///
  /// In en, this message translates to:
  /// **'No tags yet.'**
  String get notesNoTagsYet;

  /// No description provided for @notesNoteLocked.
  ///
  /// In en, this message translates to:
  /// **'Note locked'**
  String get notesNoteLocked;

  /// No description provided for @notesNothingMatches.
  ///
  /// In en, this message translates to:
  /// **'Nothing matches.'**
  String get notesNothingMatches;

  /// No description provided for @notesOpenPaper.
  ///
  /// In en, this message translates to:
  /// **'Open paper'**
  String get notesOpenPaper;

  /// No description provided for @notesPage.
  ///
  /// In en, this message translates to:
  /// **'Page'**
  String get notesPage;

  /// No description provided for @notesPageEllipsis.
  ///
  /// In en, this message translates to:
  /// **'Page…'**
  String get notesPageEllipsis;

  /// No description provided for @notesPageHint.
  ///
  /// In en, this message translates to:
  /// **'42 or 3–5'**
  String get notesPageHint;

  /// No description provided for @notesPageShort.
  ///
  /// In en, this message translates to:
  /// **'p. {page}'**
  String notesPageShort(int page);

  /// No description provided for @notesPinToTop.
  ///
  /// In en, this message translates to:
  /// **'Pin to top'**
  String get notesPinToTop;

  /// No description provided for @notesPreview.
  ///
  /// In en, this message translates to:
  /// **'Preview'**
  String get notesPreview;

  /// No description provided for @notesRemoveHighlight.
  ///
  /// In en, this message translates to:
  /// **'Remove highlight'**
  String get notesRemoveHighlight;

  /// No description provided for @notesRemoveLock.
  ///
  /// In en, this message translates to:
  /// **'Remove lock'**
  String get notesRemoveLock;

  /// No description provided for @notesRenameVersion.
  ///
  /// In en, this message translates to:
  /// **'Rename version'**
  String get notesRenameVersion;

  /// No description provided for @notesRestore.
  ///
  /// In en, this message translates to:
  /// **'Restore'**
  String get notesRestore;

  /// No description provided for @notesRestoreThisVersion.
  ///
  /// In en, this message translates to:
  /// **'Restore this version'**
  String get notesRestoreThisVersion;

  /// No description provided for @notesRestoreVersionMessage.
  ///
  /// In en, this message translates to:
  /// **'The note goes back to this version. What is there now is saved first as “{label}”.'**
  String notesRestoreVersionMessage(String label);

  /// No description provided for @notesRestoreVersionTitle.
  ///
  /// In en, this message translates to:
  /// **'Restore this version?'**
  String get notesRestoreVersionTitle;

  /// No description provided for @notesSaveAVersion.
  ///
  /// In en, this message translates to:
  /// **'Save a version'**
  String get notesSaveAVersion;

  /// No description provided for @notesSaveVersionNow.
  ///
  /// In en, this message translates to:
  /// **'Save a version now'**
  String get notesSaveVersionNow;

  /// No description provided for @notesSavedVersion.
  ///
  /// In en, this message translates to:
  /// **'Saved version'**
  String get notesSavedVersion;

  /// No description provided for @notesSearchFigures.
  ///
  /// In en, this message translates to:
  /// **'Search figures and tables'**
  String get notesSearchFigures;

  /// No description provided for @notesSearchPapersToLink.
  ///
  /// In en, this message translates to:
  /// **'Search papers to link'**
  String get notesSearchPapersToLink;

  /// No description provided for @notesSentToSupervisor.
  ///
  /// In en, this message translates to:
  /// **'Sent to supervisor'**
  String get notesSentToSupervisor;

  /// No description provided for @notesSet.
  ///
  /// In en, this message translates to:
  /// **'Set'**
  String get notesSet;

  /// No description provided for @notesStatsCharacters.
  ///
  /// In en, this message translates to:
  /// **'Characters'**
  String get notesStatsCharacters;

  /// No description provided for @notesStatsCitations.
  ///
  /// In en, this message translates to:
  /// **'Citations'**
  String get notesStatsCitations;

  /// No description provided for @notesStatsLinkedPapers.
  ///
  /// In en, this message translates to:
  /// **'Linked papers'**
  String get notesStatsLinkedPapers;

  /// No description provided for @notesStatsParagraphs.
  ///
  /// In en, this message translates to:
  /// **'Paragraphs'**
  String get notesStatsParagraphs;

  /// No description provided for @notesStatsReadingTime.
  ///
  /// In en, this message translates to:
  /// **'Reading time'**
  String get notesStatsReadingTime;

  /// No description provided for @notesStatsWords.
  ///
  /// In en, this message translates to:
  /// **'Words'**
  String get notesStatsWords;

  /// No description provided for @notesTableMissing.
  ///
  /// In en, this message translates to:
  /// **'Table ??'**
  String get notesTableMissing;

  /// No description provided for @notesTableName.
  ///
  /// In en, this message translates to:
  /// **'Table {number}'**
  String notesTableName(String number);

  /// No description provided for @notesTemplateCritique.
  ///
  /// In en, this message translates to:
  /// **'Critique'**
  String get notesTemplateCritique;

  /// No description provided for @notesTemplateFindings.
  ///
  /// In en, this message translates to:
  /// **'Findings'**
  String get notesTemplateFindings;

  /// No description provided for @notesTemplateMethod.
  ///
  /// In en, this message translates to:
  /// **'Method'**
  String get notesTemplateMethod;

  /// No description provided for @notesTemplateSummary.
  ///
  /// In en, this message translates to:
  /// **'Summary'**
  String get notesTemplateSummary;

  /// No description provided for @notesUnchangedLines.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 unchanged line} other{{count} unchanged lines}}'**
  String notesUnchangedLines(int count);

  /// No description provided for @notesUnlock.
  ///
  /// In en, this message translates to:
  /// **'Unlock'**
  String get notesUnlock;

  /// No description provided for @notesUnlockToCompare.
  ///
  /// In en, this message translates to:
  /// **'Unlock this note to compare its versions.'**
  String get notesUnlockToCompare;

  /// No description provided for @notesUnlockToCompareOrRestore.
  ///
  /// In en, this message translates to:
  /// **'Unlock this note to compare or restore versions.'**
  String get notesUnlockToCompareOrRestore;

  /// No description provided for @notesUnlockToDuplicate.
  ///
  /// In en, this message translates to:
  /// **'Unlock this note to duplicate it.'**
  String get notesUnlockToDuplicate;

  /// No description provided for @notesUnlockToPrint.
  ///
  /// In en, this message translates to:
  /// **'Unlock this note to print it.'**
  String get notesUnlockToPrint;

  /// No description provided for @notesUnlockToRestore.
  ///
  /// In en, this message translates to:
  /// **'Unlock the note to restore it.'**
  String get notesUnlockToRestore;

  /// No description provided for @notesUnpin.
  ///
  /// In en, this message translates to:
  /// **'Unpin'**
  String get notesUnpin;

  /// No description provided for @notesVersionDeleted.
  ///
  /// In en, this message translates to:
  /// **'Version deleted'**
  String get notesVersionDeleted;

  /// No description provided for @notesVersionNameHint.
  ///
  /// In en, this message translates to:
  /// **'Name (optional)'**
  String get notesVersionNameHint;

  /// No description provided for @notesVersionOptions.
  ///
  /// In en, this message translates to:
  /// **'Version options'**
  String get notesVersionOptions;

  /// No description provided for @notesVersionRestored.
  ///
  /// In en, this message translates to:
  /// **'Version restored'**
  String get notesVersionRestored;

  /// No description provided for @notesVersions.
  ///
  /// In en, this message translates to:
  /// **'Versions'**
  String get notesVersions;

  /// No description provided for @notesVersionsEmptyMessage.
  ///
  /// In en, this message translates to:
  /// **'A version is a saved copy of this note. One is kept automatically when a chapter goes to your supervisor, and you can save one any time.'**
  String get notesVersionsEmptyMessage;

  /// No description provided for @notesVersionsEmptyTitle.
  ///
  /// In en, this message translates to:
  /// **'No versions yet'**
  String get notesVersionsEmptyTitle;

  /// No description provided for @notesVersionsSince.
  ///
  /// In en, this message translates to:
  /// **'{delta} since'**
  String notesVersionsSince(String delta);

  /// No description provided for @notesVersionsWords.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 word} other{{count} words}}'**
  String notesVersionsWords(int count);

  /// No description provided for @ocrReadingText.
  ///
  /// In en, this message translates to:
  /// **'Reading text… {percent}%'**
  String ocrReadingText(int percent);

  /// No description provided for @ocrRecogniseText.
  ///
  /// In en, this message translates to:
  /// **'Recognise text'**
  String get ocrRecogniseText;

  /// No description provided for @ocrRecogniseTextHint.
  ///
  /// In en, this message translates to:
  /// **'Search and highlight a scan'**
  String get ocrRecogniseTextHint;

  /// No description provided for @outlineEmpty.
  ///
  /// In en, this message translates to:
  /// **'No headings in this note yet'**
  String get outlineEmpty;

  /// No description provided for @outlineKeyOutline.
  ///
  /// In en, this message translates to:
  /// **'Show outline'**
  String get outlineKeyOutline;

  /// No description provided for @outlineShowGrid.
  ///
  /// In en, this message translates to:
  /// **'Show as grid'**
  String get outlineShowGrid;

  /// No description provided for @outlineShowList.
  ///
  /// In en, this message translates to:
  /// **'Show as list'**
  String get outlineShowList;

  /// No description provided for @outlineTitle.
  ///
  /// In en, this message translates to:
  /// **'Outline'**
  String get outlineTitle;

  /// No description provided for @panesClose.
  ///
  /// In en, this message translates to:
  /// **'Close pane'**
  String get panesClose;

  /// No description provided for @panesSetting.
  ///
  /// In en, this message translates to:
  /// **'Open links in new panes'**
  String get panesSetting;

  /// No description provided for @panesSettingSubtitle.
  ///
  /// In en, this message translates to:
  /// **'A link in a note or paper opens beside it instead of replacing it'**
  String get panesSettingSubtitle;

  /// No description provided for @panesUntitled.
  ///
  /// In en, this message translates to:
  /// **'Untitled'**
  String get panesUntitled;

  /// No description provided for @paperAbstract.
  ///
  /// In en, this message translates to:
  /// **'Abstract'**
  String get paperAbstract;

  /// No description provided for @paperAddToProject.
  ///
  /// In en, this message translates to:
  /// **'Add to project'**
  String get paperAddToProject;

  /// No description provided for @paperAttachmentsEmpty.
  ///
  /// In en, this message translates to:
  /// **'Podcasts, images, links or files for this paper.'**
  String get paperAttachmentsEmpty;

  /// No description provided for @paperAttachmentsError.
  ///
  /// In en, this message translates to:
  /// **'Could not load attachments: {error}'**
  String paperAttachmentsError(String error);

  /// No description provided for @paperAuthorsHelper.
  ///
  /// In en, this message translates to:
  /// **'Separate authors with ;'**
  String get paperAuthorsHelper;

  /// No description provided for @paperAuthorsHint.
  ///
  /// In en, this message translates to:
  /// **'Authors'**
  String get paperAuthorsHint;

  /// No description provided for @paperCitation.
  ///
  /// In en, this message translates to:
  /// **'Citation'**
  String get paperCitation;

  /// No description provided for @paperCitationStyle.
  ///
  /// In en, this message translates to:
  /// **'Citation style'**
  String get paperCitationStyle;

  /// No description provided for @paperContinueReading.
  ///
  /// In en, this message translates to:
  /// **'Continue reading · p. {page}'**
  String paperContinueReading(int page);

  /// No description provided for @paperDetails.
  ///
  /// In en, this message translates to:
  /// **'Details'**
  String get paperDetails;

  /// No description provided for @paperDownloadFileFailed.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t download the file. Try again.'**
  String get paperDownloadFileFailed;

  /// No description provided for @paperDownloadPdf.
  ///
  /// In en, this message translates to:
  /// **'Download PDF'**
  String get paperDownloadPdf;

  /// No description provided for @paperDownloadPdfFailed.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t download the PDF. Try again.'**
  String get paperDownloadPdfFailed;

  /// No description provided for @paperDownloading.
  ///
  /// In en, this message translates to:
  /// **'Downloading…'**
  String get paperDownloading;

  /// No description provided for @paperEditAuthors.
  ///
  /// In en, this message translates to:
  /// **'Edit authors'**
  String get paperEditAuthors;

  /// No description provided for @paperEnterIdentifier.
  ///
  /// In en, this message translates to:
  /// **'Enter a DOI, arXiv or PubMed ID first.'**
  String get paperEnterIdentifier;

  /// No description provided for @paperExportWithHighlights.
  ///
  /// In en, this message translates to:
  /// **'Export with highlights'**
  String get paperExportWithHighlights;

  /// No description provided for @paperFilledIn.
  ///
  /// In en, this message translates to:
  /// **'Filled in the missing details.'**
  String get paperFilledIn;

  /// No description provided for @paperHighlights.
  ///
  /// In en, this message translates to:
  /// **'Highlights'**
  String get paperHighlights;

  /// No description provided for @paperIdentifierLabel.
  ///
  /// In en, this message translates to:
  /// **'DOI, arXiv or PubMed ID'**
  String get paperIdentifierLabel;

  /// No description provided for @paperLink.
  ///
  /// In en, this message translates to:
  /// **'Link'**
  String get paperLink;

  /// No description provided for @paperLookUp.
  ///
  /// In en, this message translates to:
  /// **'Look up'**
  String get paperLookUp;

  /// No description provided for @paperLookupUnreachable.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t reach the lookup service.'**
  String get paperLookupUnreachable;

  /// No description provided for @paperMoreStyles.
  ///
  /// In en, this message translates to:
  /// **'More…'**
  String get paperMoreStyles;

  /// No description provided for @paperNothingNew.
  ///
  /// In en, this message translates to:
  /// **'Nothing new to fill in.'**
  String get paperNothingNew;

  /// No description provided for @paperOpenInPubmed.
  ///
  /// In en, this message translates to:
  /// **'Open in PubMed'**
  String get paperOpenInPubmed;

  /// No description provided for @paperOpenLink.
  ///
  /// In en, this message translates to:
  /// **'Open link'**
  String get paperOpenLink;

  /// No description provided for @paperPageShort.
  ///
  /// In en, this message translates to:
  /// **'p. {page}'**
  String paperPageShort(int page);

  /// No description provided for @paperProject.
  ///
  /// In en, this message translates to:
  /// **'Project'**
  String get paperProject;

  /// No description provided for @paperPubmedId.
  ///
  /// In en, this message translates to:
  /// **'PubMed ID'**
  String get paperPubmedId;

  /// No description provided for @paperReadWithNote.
  ///
  /// In en, this message translates to:
  /// **'Read with a note'**
  String get paperReadWithNote;

  /// No description provided for @paperReferencedInNotes.
  ///
  /// In en, this message translates to:
  /// **'Referenced in notes'**
  String get paperReferencedInNotes;

  /// No description provided for @paperTitleHint.
  ///
  /// In en, this message translates to:
  /// **'Title'**
  String get paperTitleHint;

  /// No description provided for @paperVenue.
  ///
  /// In en, this message translates to:
  /// **'Journal or conference'**
  String get paperVenue;

  /// No description provided for @paperYear.
  ///
  /// In en, this message translates to:
  /// **'Year'**
  String get paperYear;

  /// No description provided for @platformUntitledPaper.
  ///
  /// In en, this message translates to:
  /// **'Untitled paper'**
  String get platformUntitledPaper;

  /// No description provided for @platformWidgetPage.
  ///
  /// In en, this message translates to:
  /// **'p. {page}'**
  String platformWidgetPage(int page);

  /// No description provided for @projectsAbbrCopyAsText.
  ///
  /// In en, this message translates to:
  /// **'Copy as text'**
  String get projectsAbbrCopyAsText;

  /// No description provided for @projectsAbbrDefined.
  ///
  /// In en, this message translates to:
  /// **'{count} defined'**
  String projectsAbbrDefined(int count);

  /// No description provided for @projectsAbbrList.
  ///
  /// In en, this message translates to:
  /// **'List'**
  String get projectsAbbrList;

  /// No description provided for @projectsAbbrListTitle.
  ///
  /// In en, this message translates to:
  /// **'List of abbreviations'**
  String get projectsAbbrListTitle;

  /// No description provided for @projectsAbbrNeverSpelled.
  ///
  /// In en, this message translates to:
  /// **'Never spelled out ({count})'**
  String projectsAbbrNeverSpelled(int count);

  /// No description provided for @projectsAbbrToCheck.
  ///
  /// In en, this message translates to:
  /// **'{count} to check'**
  String projectsAbbrToCheck(int count);

  /// No description provided for @projectsAbbrUsedBefore.
  ///
  /// In en, this message translates to:
  /// **'{abbreviation} is used before it\'s spelled out'**
  String projectsAbbrUsedBefore(String abbreviation);

  /// No description provided for @projectsAbbreviations.
  ///
  /// In en, this message translates to:
  /// **'Abbreviations'**
  String get projectsAbbreviations;

  /// No description provided for @projectsAddChapter.
  ///
  /// In en, this message translates to:
  /// **'Add chapter'**
  String get projectsAddChapter;

  /// No description provided for @projectsBibliography.
  ///
  /// In en, this message translates to:
  /// **'Bibliography'**
  String get projectsBibliography;

  /// No description provided for @projectsBibliographySubject.
  ///
  /// In en, this message translates to:
  /// **'{project} bibliography'**
  String projectsBibliographySubject(String project);

  /// No description provided for @projectsBibliographySubtitle.
  ///
  /// In en, this message translates to:
  /// **'All its papers, in a citation style'**
  String get projectsBibliographySubtitle;

  /// No description provided for @projectsChangeDate.
  ///
  /// In en, this message translates to:
  /// **'Change date'**
  String get projectsChangeDate;

  /// No description provided for @projectsChangeDueDate.
  ///
  /// In en, this message translates to:
  /// **'Change due date'**
  String get projectsChangeDueDate;

  /// No description provided for @projectsChangeStatus.
  ///
  /// In en, this message translates to:
  /// **'Change status'**
  String get projectsChangeStatus;

  /// No description provided for @projectsChapterCitations.
  ///
  /// In en, this message translates to:
  /// **'Ch. {chapter} · {count}×'**
  String projectsChapterCitations(int chapter, int count);

  /// No description provided for @projectsChapterOptions.
  ///
  /// In en, this message translates to:
  /// **'Chapter options'**
  String get projectsChapterOptions;

  /// No description provided for @projectsChapters.
  ///
  /// In en, this message translates to:
  /// **'Chapters'**
  String get projectsChapters;

  /// No description provided for @projectsChaptersFinal.
  ///
  /// In en, this message translates to:
  /// **'{finished} of {count, plural, =1{1 chapter} other{{count} chapters}} final'**
  String projectsChaptersFinal(int finished, int count);

  /// No description provided for @projectsChaptersLockedReason.
  ///
  /// In en, this message translates to:
  /// **'Some chapters are locked. Unlock them to include them.'**
  String get projectsChaptersLockedReason;

  /// No description provided for @projectsCitations.
  ///
  /// In en, this message translates to:
  /// **'Citations'**
  String get projectsCitations;

  /// No description provided for @projectsCitedInChapters.
  ///
  /// In en, this message translates to:
  /// **'Cited in chapters ({count})'**
  String projectsCitedInChapters(int count);

  /// No description provided for @projectsCitedOutside.
  ///
  /// In en, this message translates to:
  /// **'Cited, not in this project ({count})'**
  String projectsCitedOutside(int count);

  /// No description provided for @projectsClearDate.
  ///
  /// In en, this message translates to:
  /// **'Clear date'**
  String get projectsClearDate;

  /// No description provided for @projectsClearDueDate.
  ///
  /// In en, this message translates to:
  /// **'Clear due date'**
  String get projectsClearDueDate;

  /// No description provided for @projectsCreateAndAdd.
  ///
  /// In en, this message translates to:
  /// **'Create and add'**
  String get projectsCreateAndAdd;

  /// No description provided for @projectsDatePattern.
  ///
  /// In en, this message translates to:
  /// **'d MMMM'**
  String get projectsDatePattern;

  /// No description provided for @projectsDatePatternYear.
  ///
  /// In en, this message translates to:
  /// **'d MMMM y'**
  String get projectsDatePatternYear;

  /// No description provided for @projectsDaysAgo.
  ///
  /// In en, this message translates to:
  /// **'{days, plural, =1{1 day ago} other{{days} days ago}}'**
  String projectsDaysAgo(int days);

  /// No description provided for @projectsDeleteMessage.
  ///
  /// In en, this message translates to:
  /// **'The papers and notes in it stay in your library; only the grouping goes away.'**
  String get projectsDeleteMessage;

  /// No description provided for @projectsDeleteProject.
  ///
  /// In en, this message translates to:
  /// **'Delete project'**
  String get projectsDeleteProject;

  /// No description provided for @projectsDeleteProjectSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Its papers and notes are kept'**
  String get projectsDeleteProjectSubtitle;

  /// No description provided for @projectsDeleteTitle.
  ///
  /// In en, this message translates to:
  /// **'Delete “{name}”?'**
  String projectsDeleteTitle(String name);

  /// No description provided for @projectsDue.
  ///
  /// In en, this message translates to:
  /// **'Due {date} · {rest}'**
  String projectsDue(String date, String rest);

  /// No description provided for @projectsDueToday.
  ///
  /// In en, this message translates to:
  /// **'Due today · {date}'**
  String projectsDueToday(String date);

  /// No description provided for @projectsExportCancelledLocked.
  ///
  /// In en, this message translates to:
  /// **'Export cancelled: chapters are locked.'**
  String get projectsExportCancelledLocked;

  /// No description provided for @projectsExportProject.
  ///
  /// In en, this message translates to:
  /// **'Export project'**
  String get projectsExportProject;

  /// No description provided for @projectsExportProjectSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Its notes as one document'**
  String get projectsExportProjectSubtitle;

  /// No description provided for @projectsFigureTodo.
  ///
  /// In en, this message translates to:
  /// **'Figure'**
  String get projectsFigureTodo;

  /// No description provided for @projectsHighlightCount.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 highlight} other{{count} highlights}}'**
  String projectsHighlightCount(int count);

  /// No description provided for @projectsInDays.
  ///
  /// In en, this message translates to:
  /// **'{days, plural, =1{1 day} other{{days} days}}'**
  String projectsInDays(int days);

  /// No description provided for @projectsMap.
  ///
  /// In en, this message translates to:
  /// **'Map'**
  String get projectsMap;

  /// No description provided for @projectsNeedsCitation.
  ///
  /// In en, this message translates to:
  /// **'Needs a citation'**
  String get projectsNeedsCitation;

  /// No description provided for @projectsNewProject.
  ///
  /// In en, this message translates to:
  /// **'New project'**
  String get projectsNewProject;

  /// No description provided for @projectsNoNotesYet.
  ///
  /// In en, this message translates to:
  /// **'No notes in this project yet.'**
  String get projectsNoNotesYet;

  /// No description provided for @projectsNoPapersYet.
  ///
  /// In en, this message translates to:
  /// **'No papers in this project yet.'**
  String get projectsNoPapersYet;

  /// No description provided for @projectsNoStatus.
  ///
  /// In en, this message translates to:
  /// **'No status'**
  String get projectsNoStatus;

  /// No description provided for @projectsNoteCount.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 note} other{{count} notes}}'**
  String projectsNoteCount(int count);

  /// No description provided for @projectsNothingYet.
  ///
  /// In en, this message translates to:
  /// **'Nothing here yet'**
  String get projectsNothingYet;

  /// No description provided for @projectsNothingYetMessage.
  ///
  /// In en, this message translates to:
  /// **'Use “Add to project” on a paper or a note to collect it here.'**
  String get projectsNothingYetMessage;

  /// No description provided for @projectsOpenProject.
  ///
  /// In en, this message translates to:
  /// **'Open project'**
  String get projectsOpenProject;

  /// No description provided for @projectsOpenProjectSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Its papers, notes and reading progress'**
  String get projectsOpenProjectSubtitle;

  /// No description provided for @projectsPaperCount.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 paper} other{{count} papers}}'**
  String projectsPaperCount(int count);

  /// No description provided for @projectsPapers.
  ///
  /// In en, this message translates to:
  /// **'Papers'**
  String get projectsPapers;

  /// No description provided for @projectsPickerIntro.
  ///
  /// In en, this message translates to:
  /// **'A project groups the papers and notes for one review, chapter or paper you\'re writing.'**
  String get projectsPickerIntro;

  /// No description provided for @projectsReadNotCited.
  ///
  /// In en, this message translates to:
  /// **'Read but not cited ({count})'**
  String projectsReadNotCited(int count);

  /// No description provided for @projectsReadProgress.
  ///
  /// In en, this message translates to:
  /// **'{done} of {total} read'**
  String projectsReadProgress(int done, int total);

  /// No description provided for @projectsRemoveFromProject.
  ///
  /// In en, this message translates to:
  /// **'Remove from project'**
  String get projectsRemoveFromProject;

  /// No description provided for @projectsRenameProject.
  ///
  /// In en, this message translates to:
  /// **'Rename project'**
  String get projectsRenameProject;

  /// No description provided for @projectsSetDueDate.
  ///
  /// In en, this message translates to:
  /// **'Set due date'**
  String get projectsSetDueDate;

  /// No description provided for @projectsStatus.
  ///
  /// In en, this message translates to:
  /// **'Status'**
  String get projectsStatus;

  /// No description provided for @projectsStatusDraft.
  ///
  /// In en, this message translates to:
  /// **'Draft'**
  String get projectsStatusDraft;

  /// No description provided for @projectsStatusFinal.
  ///
  /// In en, this message translates to:
  /// **'Final'**
  String get projectsStatusFinal;

  /// No description provided for @projectsStatusOutline.
  ///
  /// In en, this message translates to:
  /// **'Outline'**
  String get projectsStatusOutline;

  /// No description provided for @projectsStatusRead.
  ///
  /// In en, this message translates to:
  /// **'Read'**
  String get projectsStatusRead;

  /// No description provided for @projectsStatusReading.
  ///
  /// In en, this message translates to:
  /// **'Reading'**
  String get projectsStatusReading;

  /// No description provided for @projectsStatusRevised.
  ///
  /// In en, this message translates to:
  /// **'Revised'**
  String get projectsStatusRevised;

  /// No description provided for @projectsStatusToRead.
  ///
  /// In en, this message translates to:
  /// **'To read'**
  String get projectsStatusToRead;

  /// No description provided for @projectsStatusWithSupervisor.
  ///
  /// In en, this message translates to:
  /// **'With supervisor'**
  String get projectsStatusWithSupervisor;

  /// No description provided for @projectsSubmissionDate.
  ///
  /// In en, this message translates to:
  /// **'Submission date'**
  String get projectsSubmissionDate;

  /// No description provided for @projectsSubmissionDateSubtitle.
  ///
  /// In en, this message translates to:
  /// **'The submission date'**
  String get projectsSubmissionDateSubtitle;

  /// No description provided for @projectsSynthesisMatrix.
  ///
  /// In en, this message translates to:
  /// **'Synthesis matrix'**
  String get projectsSynthesisMatrix;

  /// No description provided for @projectsSynthesisMatrixSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Compare its papers by theme'**
  String get projectsSynthesisMatrixSubtitle;

  /// No description provided for @projectsTodoWord.
  ///
  /// In en, this message translates to:
  /// **'TODO'**
  String get projectsTodoWord;

  /// No description provided for @projectsTodosTitle.
  ///
  /// In en, this message translates to:
  /// **'To do in the writing ({count})'**
  String projectsTodosTitle(int count);

  /// No description provided for @projectsWordTarget.
  ///
  /// In en, this message translates to:
  /// **'Word target'**
  String get projectsWordTarget;

  /// No description provided for @projectsWordTargetHint.
  ///
  /// In en, this message translates to:
  /// **'e.g. 8000'**
  String get projectsWordTargetHint;

  /// No description provided for @projectsWords.
  ///
  /// In en, this message translates to:
  /// **'{words, plural, =1{1 word} other{{words} words}}'**
  String projectsWords(int words);

  /// No description provided for @projectsWordsOfTarget.
  ///
  /// In en, this message translates to:
  /// **'{words} / {target} words'**
  String projectsWordsOfTarget(int words, int target);

  /// No description provided for @readAloudBack.
  ///
  /// In en, this message translates to:
  /// **'Back to reading'**
  String get readAloudBack;

  /// No description provided for @readAloudFinished.
  ///
  /// In en, this message translates to:
  /// **'Finished'**
  String get readAloudFinished;

  /// No description provided for @readAloudNext.
  ///
  /// In en, this message translates to:
  /// **'Next sentence'**
  String get readAloudNext;

  /// No description provided for @readAloudNoText.
  ///
  /// In en, this message translates to:
  /// **'No text to read'**
  String get readAloudNoText;

  /// No description provided for @readAloudPause.
  ///
  /// In en, this message translates to:
  /// **'Pause'**
  String get readAloudPause;

  /// No description provided for @readAloudPlay.
  ///
  /// In en, this message translates to:
  /// **'Play'**
  String get readAloudPlay;

  /// No description provided for @readAloudPreparing.
  ///
  /// In en, this message translates to:
  /// **'Preparing…'**
  String get readAloudPreparing;

  /// No description provided for @readAloudPrevious.
  ///
  /// In en, this message translates to:
  /// **'Previous sentence'**
  String get readAloudPrevious;

  /// No description provided for @readAloudSpeed.
  ///
  /// In en, this message translates to:
  /// **'Speed'**
  String get readAloudSpeed;

  /// No description provided for @readAloudStop.
  ///
  /// In en, this message translates to:
  /// **'Stop reading'**
  String get readAloudStop;

  /// No description provided for @reviewCaughtUp.
  ///
  /// In en, this message translates to:
  /// **'All caught up'**
  String get reviewCaughtUp;

  /// No description provided for @reviewDismiss.
  ///
  /// In en, this message translates to:
  /// **'Dismiss until tomorrow'**
  String get reviewDismiss;

  /// No description provided for @reviewEmptyMessage.
  ///
  /// In en, this message translates to:
  /// **'Highlights come back here a day after you make them, then less and less often.'**
  String get reviewEmptyMessage;

  /// No description provided for @reviewKeep.
  ///
  /// In en, this message translates to:
  /// **'Keep'**
  String get reviewKeep;

  /// No description provided for @reviewLater.
  ///
  /// In en, this message translates to:
  /// **'The ones you kept will return in a while.'**
  String get reviewLater;

  /// No description provided for @reviewNothing.
  ///
  /// In en, this message translates to:
  /// **'Nothing to revisit'**
  String get reviewNothing;

  /// No description provided for @reviewOpenInPaper.
  ///
  /// In en, this message translates to:
  /// **'Open in paper'**
  String get reviewOpenInPaper;

  /// No description provided for @reviewPosition.
  ///
  /// In en, this message translates to:
  /// **'{current} of {total}'**
  String reviewPosition(int current, int total);

  /// No description provided for @reviewPrompt.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 highlight to revisit} other{{count} highlights to revisit}}'**
  String reviewPrompt(int count);

  /// No description provided for @reviewQuote.
  ///
  /// In en, this message translates to:
  /// **'“{quote}”'**
  String reviewQuote(String quote);

  /// No description provided for @reviewRemind.
  ///
  /// In en, this message translates to:
  /// **'Remind me on the home screen'**
  String get reviewRemind;

  /// No description provided for @reviewRemindHint.
  ///
  /// In en, this message translates to:
  /// **'A single quiet line when something is due'**
  String get reviewRemindHint;

  /// No description provided for @reviewSkip.
  ///
  /// In en, this message translates to:
  /// **'Skip'**
  String get reviewSkip;

  /// No description provided for @reviewSource.
  ///
  /// In en, this message translates to:
  /// **'{title} · p. {page}'**
  String reviewSource(String title, int page);

  /// No description provided for @reviewTitle.
  ///
  /// In en, this message translates to:
  /// **'Revisit highlights'**
  String get reviewTitle;

  /// No description provided for @reviewTomorrow.
  ///
  /// In en, this message translates to:
  /// **'They will come back tomorrow.'**
  String get reviewTomorrow;

  /// No description provided for @savedSearchDelete.
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get savedSearchDelete;

  /// No description provided for @savedSearchDeleted.
  ///
  /// In en, this message translates to:
  /// **'Deleted “{name}”'**
  String savedSearchDeleted(String name);

  /// No description provided for @savedSearchDialogTitle.
  ///
  /// In en, this message translates to:
  /// **'Save search'**
  String get savedSearchDialogTitle;

  /// No description provided for @savedSearchHeading.
  ///
  /// In en, this message translates to:
  /// **'Saved searches'**
  String get savedSearchHeading;

  /// No description provided for @savedSearchNameLabel.
  ///
  /// In en, this message translates to:
  /// **'Name'**
  String get savedSearchNameLabel;

  /// No description provided for @savedSearchRename.
  ///
  /// In en, this message translates to:
  /// **'Rename'**
  String get savedSearchRename;

  /// No description provided for @savedSearchRenameTitle.
  ///
  /// In en, this message translates to:
  /// **'Rename search'**
  String get savedSearchRenameTitle;

  /// No description provided for @savedSearchSave.
  ///
  /// In en, this message translates to:
  /// **'Save this search'**
  String get savedSearchSave;

  /// No description provided for @savedSearchSection.
  ///
  /// In en, this message translates to:
  /// **'Saved Searches'**
  String get savedSearchSection;

  /// No description provided for @savedSearchTipsBody.
  ///
  /// In en, this message translates to:
  /// **'\"exact phrase\" and -word to leave a word out\ntag:name, folder:name, project:name\nin:notes, in:papers, in:highlights, in:pdfs\nis:pinned, is:template, is:daily\nPut - in front of any of these to exclude it. Use quotes for names with spaces: tag:\"deep learning\"'**
  String get savedSearchTipsBody;

  /// No description provided for @savedSearchTipsLink.
  ///
  /// In en, this message translates to:
  /// **'Search tips'**
  String get savedSearchTipsLink;

  /// No description provided for @searchAttachments.
  ///
  /// In en, this message translates to:
  /// **'Attachments'**
  String get searchAttachments;

  /// No description provided for @searchClear.
  ///
  /// In en, this message translates to:
  /// **'Clear'**
  String get searchClear;

  /// No description provided for @searchEmptyMessage.
  ///
  /// In en, this message translates to:
  /// **'Find a note, a paper, or a passage you highlighted.'**
  String get searchEmptyMessage;

  /// No description provided for @searchEmptyTitle.
  ///
  /// In en, this message translates to:
  /// **'Search everything'**
  String get searchEmptyTitle;

  /// No description provided for @searchHint.
  ///
  /// In en, this message translates to:
  /// **'Search notes, papers and highlights'**
  String get searchHint;

  /// No description provided for @searchIndexing.
  ///
  /// In en, this message translates to:
  /// **'Indexing papers…'**
  String get searchIndexing;

  /// No description provided for @searchKindHighlights.
  ///
  /// In en, this message translates to:
  /// **'Highlights'**
  String get searchKindHighlights;

  /// No description provided for @searchKindInPapers.
  ///
  /// In en, this message translates to:
  /// **'In papers'**
  String get searchKindInPapers;

  /// No description provided for @searchKindPapers.
  ///
  /// In en, this message translates to:
  /// **'Papers'**
  String get searchKindPapers;

  /// No description provided for @searchMap.
  ///
  /// In en, this message translates to:
  /// **'Map'**
  String get searchMap;

  /// No description provided for @searchNoMatches.
  ///
  /// In en, this message translates to:
  /// **'No matches'**
  String get searchNoMatches;

  /// No description provided for @searchNoMatchesHint.
  ///
  /// In en, this message translates to:
  /// **'Try fewer or different words.'**
  String get searchNoMatchesHint;

  /// No description provided for @searchPage.
  ///
  /// In en, this message translates to:
  /// **'p. {page}'**
  String searchPage(int page);

  /// No description provided for @settingsAppearance.
  ///
  /// In en, this message translates to:
  /// **'Appearance'**
  String get settingsAppearance;

  /// No description provided for @settingsBackUp.
  ///
  /// In en, this message translates to:
  /// **'Back up to a file'**
  String get settingsBackUp;

  /// No description provided for @settingsBackUpSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Notes, papers and files in one zip'**
  String get settingsBackUpSubtitle;

  /// No description provided for @settingsBackupFailed.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t create the backup.'**
  String get settingsBackupFailed;

  /// No description provided for @settingsBackupSubject.
  ///
  /// In en, this message translates to:
  /// **'Corplex backup'**
  String get settingsBackupSubject;

  /// No description provided for @settingsCantRestore.
  ///
  /// In en, this message translates to:
  /// **'Can\'t restore'**
  String get settingsCantRestore;

  /// No description provided for @settingsClearAndSignOut.
  ///
  /// In en, this message translates to:
  /// **'Clear and sign out'**
  String get settingsClearAndSignOut;

  /// No description provided for @settingsClearTitle.
  ///
  /// In en, this message translates to:
  /// **'Clear this device?'**
  String get settingsClearTitle;

  /// No description provided for @settingsErasePending.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 change on this device hasn\'t synced and will be lost for good. Everything else is safe in your account.} other{{count} changes on this device haven\'t synced and will be lost for good. Everything else is safe in your account.}}'**
  String settingsErasePending(int count);

  /// No description provided for @settingsEraseSafe.
  ///
  /// In en, this message translates to:
  /// **'Notes, papers and files on this device will be removed. Everything is safe in your account.'**
  String get settingsEraseSafe;

  /// No description provided for @settingsExport.
  ///
  /// In en, this message translates to:
  /// **'Export'**
  String get settingsExport;

  /// No description provided for @settingsExportBody.
  ///
  /// In en, this message translates to:
  /// **'One Markdown file per note and paper, with links, highlights and a BibTeX file. Open the folder as an Obsidian vault.'**
  String get settingsExportBody;

  /// No description provided for @settingsExportFailed.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t create the export.'**
  String get settingsExportFailed;

  /// No description provided for @settingsExportLocked.
  ///
  /// In en, this message translates to:
  /// **'Locked notes are exported as placeholders.'**
  String get settingsExportLocked;

  /// No description provided for @settingsExportMarkdown.
  ///
  /// In en, this message translates to:
  /// **'Export as Markdown'**
  String get settingsExportMarkdown;

  /// No description provided for @settingsExportMarkdownSubtitle.
  ///
  /// In en, this message translates to:
  /// **'A folder of notes for Obsidian'**
  String get settingsExportMarkdownSubtitle;

  /// No description provided for @settingsExportSubject.
  ///
  /// In en, this message translates to:
  /// **'Corplex notes (Markdown)'**
  String get settingsExportSubject;

  /// No description provided for @settingsIncludePdfs.
  ///
  /// In en, this message translates to:
  /// **'Include PDFs'**
  String get settingsIncludePdfs;

  /// No description provided for @settingsIncludePdfsSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Makes the export much larger'**
  String get settingsIncludePdfsSubtitle;

  /// No description provided for @settingsInterfaceSize.
  ///
  /// In en, this message translates to:
  /// **'Interface size'**
  String get settingsInterfaceSize;

  /// No description provided for @settingsInterfaceSizeSubtitle.
  ///
  /// In en, this message translates to:
  /// **'For large or ultrawide displays'**
  String get settingsInterfaceSizeSubtitle;

  /// No description provided for @settingsOnDemand.
  ///
  /// In en, this message translates to:
  /// **'Download files when opened'**
  String get settingsOnDemand;

  /// No description provided for @settingsOnDemandSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Otherwise papers and audio download in the background.'**
  String get settingsOnDemandSubtitle;

  /// No description provided for @settingsOneMoreStep.
  ///
  /// In en, this message translates to:
  /// **'One more step'**
  String get settingsOneMoreStep;

  /// No description provided for @settingsPreparingBackup.
  ///
  /// In en, this message translates to:
  /// **'Preparing backup…'**
  String get settingsPreparingBackup;

  /// No description provided for @settingsQuickNote.
  ///
  /// In en, this message translates to:
  /// **'Quick note shortcut (⌃⌥N)'**
  String get settingsQuickNote;

  /// No description provided for @settingsQuickNoteSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Start a note from any app'**
  String get settingsQuickNoteSubtitle;

  /// No description provided for @settingsReadingNight.
  ///
  /// In en, this message translates to:
  /// **'Night'**
  String get settingsReadingNight;

  /// No description provided for @settingsReadingPaper.
  ///
  /// In en, this message translates to:
  /// **'Paper'**
  String get settingsReadingPaper;

  /// No description provided for @settingsReadingSepia.
  ///
  /// In en, this message translates to:
  /// **'Sepia'**
  String get settingsReadingSepia;

  /// No description provided for @settingsReplace.
  ///
  /// In en, this message translates to:
  /// **'Replace'**
  String get settingsReplace;

  /// No description provided for @settingsReplaceTitle.
  ///
  /// In en, this message translates to:
  /// **'Replace this device\'s data?'**
  String get settingsReplaceTitle;

  /// No description provided for @settingsRestartToFinish.
  ///
  /// In en, this message translates to:
  /// **'Close Corplex completely and open it again to finish restoring.'**
  String get settingsRestartToFinish;

  /// No description provided for @settingsRestoreAction.
  ///
  /// In en, this message translates to:
  /// **'Restore'**
  String get settingsRestoreAction;

  /// No description provided for @settingsRestoreBody.
  ///
  /// In en, this message translates to:
  /// **'From {date}: {notes, plural, =1{1 note} other{{notes} notes}} and {papers, plural, =1{1 paper} other{{papers} papers}}.\n\nIt replaces what\'s on this device now. Your current library is kept aside in case you change your mind.'**
  String settingsRestoreBody(String date, int notes, int papers);

  /// No description provided for @settingsRestoreFromBackup.
  ///
  /// In en, this message translates to:
  /// **'Restore from a backup'**
  String get settingsRestoreFromBackup;

  /// No description provided for @settingsRestoreTitle.
  ///
  /// In en, this message translates to:
  /// **'Restore this backup?'**
  String get settingsRestoreTitle;

  /// No description provided for @settingsSignIn.
  ///
  /// In en, this message translates to:
  /// **'Sign in'**
  String get settingsSignIn;

  /// No description provided for @settingsSignInSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Sync your library across devices'**
  String get settingsSignInSubtitle;

  /// No description provided for @settingsSignOut.
  ///
  /// In en, this message translates to:
  /// **'Sign out'**
  String get settingsSignOut;

  /// No description provided for @settingsSignOutClear.
  ///
  /// In en, this message translates to:
  /// **'Sign out and clear this device'**
  String get settingsSignOutClear;

  /// No description provided for @settingsSpellCheck.
  ///
  /// In en, this message translates to:
  /// **'Check spelling while typing'**
  String get settingsSpellCheck;

  /// No description provided for @settingsSyncFailed.
  ///
  /// In en, this message translates to:
  /// **'Sync failed'**
  String get settingsSyncFailed;

  /// No description provided for @settingsSyncNow.
  ///
  /// In en, this message translates to:
  /// **'Sync now'**
  String get settingsSyncNow;

  /// No description provided for @settingsSyncOffline.
  ///
  /// In en, this message translates to:
  /// **'Not syncing'**
  String get settingsSyncOffline;

  /// No description provided for @settingsSyncSyncing.
  ///
  /// In en, this message translates to:
  /// **'Syncing…'**
  String get settingsSyncSyncing;

  /// No description provided for @settingsSyncUpToDate.
  ///
  /// In en, this message translates to:
  /// **'Up to date'**
  String get settingsSyncUpToDate;

  /// No description provided for @settingsThemeAuto.
  ///
  /// In en, this message translates to:
  /// **'Auto'**
  String get settingsThemeAuto;

  /// No description provided for @settingsThemeDark.
  ///
  /// In en, this message translates to:
  /// **'Dark'**
  String get settingsThemeDark;

  /// No description provided for @settingsThemeLight.
  ///
  /// In en, this message translates to:
  /// **'Light'**
  String get settingsThemeLight;

  /// No description provided for @settingsTrashCount.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 item} other{{count} items}}'**
  String settingsTrashCount(int count);

  /// No description provided for @settingsUseThisAccount.
  ///
  /// In en, this message translates to:
  /// **'Use this account on this device'**
  String get settingsUseThisAccount;

  /// No description provided for @settingsUseThisAccountSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Replaces what\'s on this device with this account\'s data.'**
  String get settingsUseThisAccountSubtitle;

  /// No description provided for @settingsWifiOnly.
  ///
  /// In en, this message translates to:
  /// **'Send files on Wi-Fi only'**
  String get settingsWifiOnly;

  /// No description provided for @settingsWifiOnlySubtitle.
  ///
  /// In en, this message translates to:
  /// **'Notes always sync. Opening a file downloads it on any network.'**
  String get settingsWifiOnlySubtitle;

  /// No description provided for @shareAddedToLibrary.
  ///
  /// In en, this message translates to:
  /// **'Added “{name}” to your library'**
  String shareAddedToLibrary(String name);

  /// No description provided for @shareAttachTo.
  ///
  /// In en, this message translates to:
  /// **'Attach “{name}” to…'**
  String shareAttachTo(String name);

  /// No description provided for @shareAudioAttached.
  ///
  /// In en, this message translates to:
  /// **'Audio attached'**
  String get shareAudioAttached;

  /// No description provided for @shareNewNote.
  ///
  /// In en, this message translates to:
  /// **'A new note'**
  String get shareNewNote;

  /// No description provided for @shareSavedAsNote.
  ///
  /// In en, this message translates to:
  /// **'Saved as a note'**
  String get shareSavedAsNote;

  /// No description provided for @shareSavedLink.
  ///
  /// In en, this message translates to:
  /// **'Saved link as a note'**
  String get shareSavedLink;

  /// No description provided for @spellIgnore.
  ///
  /// In en, this message translates to:
  /// **'Ignore Spelling'**
  String get spellIgnore;

  /// No description provided for @spellIgnoreGrammar.
  ///
  /// In en, this message translates to:
  /// **'Ignore Grammar'**
  String get spellIgnoreGrammar;

  /// No description provided for @spellLearn.
  ///
  /// In en, this message translates to:
  /// **'Learn Spelling'**
  String get spellLearn;

  /// No description provided for @spotlightSetting.
  ///
  /// In en, this message translates to:
  /// **'Show in Spotlight'**
  String get spotlightSetting;

  /// No description provided for @spotlightSettingSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Find notes, papers and projects from macOS Spotlight. A locked note shows only its title.'**
  String get spotlightSettingSubtitle;

  /// No description provided for @studyAdd.
  ///
  /// In en, this message translates to:
  /// **'Add study details'**
  String get studyAdd;

  /// No description provided for @studyChip.
  ///
  /// In en, this message translates to:
  /// **'Study'**
  String get studyChip;

  /// No description provided for @studyChipCount.
  ///
  /// In en, this message translates to:
  /// **'Study · {count}'**
  String studyChipCount(int count);

  /// No description provided for @studyClear.
  ///
  /// In en, this message translates to:
  /// **'Clear'**
  String get studyClear;

  /// No description provided for @studyClearFilter.
  ///
  /// In en, this message translates to:
  /// **'Clear study filter'**
  String get studyClearFilter;

  /// No description provided for @studyDetails.
  ///
  /// In en, this message translates to:
  /// **'Study details'**
  String get studyDetails;

  /// No description provided for @studyFieldBrainRegions.
  ///
  /// In en, this message translates to:
  /// **'Brain regions'**
  String get studyFieldBrainRegions;

  /// No description provided for @studyFieldParadigm.
  ///
  /// In en, this message translates to:
  /// **'Task / paradigm'**
  String get studyFieldParadigm;

  /// No description provided for @studyFieldSampleSize.
  ///
  /// In en, this message translates to:
  /// **'Sample size (n)'**
  String get studyFieldSampleSize;

  /// No description provided for @studyFieldSpecies.
  ///
  /// In en, this message translates to:
  /// **'Species / model'**
  String get studyFieldSpecies;

  /// No description provided for @studyFieldTechniques.
  ///
  /// In en, this message translates to:
  /// **'Techniques'**
  String get studyFieldTechniques;

  /// No description provided for @studyListHint.
  ///
  /// In en, this message translates to:
  /// **'Press enter or comma to add'**
  String get studyListHint;

  /// No description provided for @studyMinSampleSize.
  ///
  /// In en, this message translates to:
  /// **'Minimum sample size (n)'**
  String get studyMinSampleSize;

  /// No description provided for @switcherCmdAttachments.
  ///
  /// In en, this message translates to:
  /// **'Show attachments'**
  String get switcherCmdAttachments;

  /// No description provided for @switcherCmdBibliography.
  ///
  /// In en, this message translates to:
  /// **'Add bibliography'**
  String get switcherCmdBibliography;

  /// No description provided for @switcherCmdExport.
  ///
  /// In en, this message translates to:
  /// **'Export as Markdown…'**
  String get switcherCmdExport;

  /// No description provided for @switcherCmdImportPdf.
  ///
  /// In en, this message translates to:
  /// **'Import PDF…'**
  String get switcherCmdImportPdf;

  /// No description provided for @switcherCmdLockAll.
  ///
  /// In en, this message translates to:
  /// **'Lock all notes'**
  String get switcherCmdLockAll;

  /// No description provided for @switcherCmdLockNote.
  ///
  /// In en, this message translates to:
  /// **'Lock note'**
  String get switcherCmdLockNote;

  /// No description provided for @switcherCmdNewNote.
  ///
  /// In en, this message translates to:
  /// **'New note'**
  String get switcherCmdNewNote;

  /// No description provided for @switcherCmdOpenProject.
  ///
  /// In en, this message translates to:
  /// **'Open project…'**
  String get switcherCmdOpenProject;

  /// No description provided for @switcherCmdSettings.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get switcherCmdSettings;

  /// No description provided for @switcherCmdShortcuts.
  ///
  /// In en, this message translates to:
  /// **'Keyboard shortcuts…'**
  String get switcherCmdShortcuts;

  /// No description provided for @switcherCmdToday.
  ///
  /// In en, this message translates to:
  /// **'Today\'s note'**
  String get switcherCmdToday;

  /// No description provided for @switcherCommands.
  ///
  /// In en, this message translates to:
  /// **'Commands'**
  String get switcherCommands;

  /// No description provided for @switcherFolders.
  ///
  /// In en, this message translates to:
  /// **'Folders'**
  String get switcherFolders;

  /// No description provided for @switcherHeadings.
  ///
  /// In en, this message translates to:
  /// **'Headings in this note'**
  String get switcherHeadings;

  /// No description provided for @switcherHelp.
  ///
  /// In en, this message translates to:
  /// **'# headings in this note · > commands · ⌘↩ beside · ⌥↩ opens the PDF'**
  String get switcherHelp;

  /// No description provided for @switcherHintJump.
  ///
  /// In en, this message translates to:
  /// **'Jump'**
  String get switcherHintJump;

  /// No description provided for @switcherHintOpen.
  ///
  /// In en, this message translates to:
  /// **'Open'**
  String get switcherHintOpen;

  /// No description provided for @switcherHintRun.
  ///
  /// In en, this message translates to:
  /// **'Run'**
  String get switcherHintRun;

  /// No description provided for @switcherHintShow.
  ///
  /// In en, this message translates to:
  /// **'Show'**
  String get switcherHintShow;

  /// No description provided for @switcherKeyGoTo.
  ///
  /// In en, this message translates to:
  /// **'Go to…'**
  String get switcherKeyGoTo;

  /// No description provided for @switcherKeyNextHeading.
  ///
  /// In en, this message translates to:
  /// **'Next heading'**
  String get switcherKeyNextHeading;

  /// No description provided for @switcherKeyOpenLink.
  ///
  /// In en, this message translates to:
  /// **'Open link'**
  String get switcherKeyOpenLink;

  /// No description provided for @switcherKeyPrevHeading.
  ///
  /// In en, this message translates to:
  /// **'Previous heading'**
  String get switcherKeyPrevHeading;

  /// No description provided for @switcherNoLink.
  ///
  /// In en, this message translates to:
  /// **'No link at the cursor.'**
  String get switcherNoLink;

  /// No description provided for @switcherNoNote.
  ///
  /// In en, this message translates to:
  /// **'Open a note to jump to its headings.'**
  String get switcherNoNote;

  /// No description provided for @switcherNoResults.
  ///
  /// In en, this message translates to:
  /// **'Nothing matches “{query}”'**
  String switcherNoResults(String query);

  /// No description provided for @switcherNotes.
  ///
  /// In en, this message translates to:
  /// **'Notes'**
  String get switcherNotes;

  /// No description provided for @switcherPapers.
  ///
  /// In en, this message translates to:
  /// **'Papers'**
  String get switcherPapers;

  /// No description provided for @switcherPinned.
  ///
  /// In en, this message translates to:
  /// **'Pinned'**
  String get switcherPinned;

  /// No description provided for @switcherPlaceholder.
  ///
  /// In en, this message translates to:
  /// **'Go to a note, paper or project'**
  String get switcherPlaceholder;

  /// No description provided for @switcherProjects.
  ///
  /// In en, this message translates to:
  /// **'Projects'**
  String get switcherProjects;

  /// No description provided for @switcherRecent.
  ///
  /// In en, this message translates to:
  /// **'Recent'**
  String get switcherRecent;

  /// No description provided for @switcherSearches.
  ///
  /// In en, this message translates to:
  /// **'Saved searches'**
  String get switcherSearches;

  /// No description provided for @switcherSubFolder.
  ///
  /// In en, this message translates to:
  /// **'Folder'**
  String get switcherSubFolder;

  /// No description provided for @switcherSubLocked.
  ///
  /// In en, this message translates to:
  /// **'Locked'**
  String get switcherSubLocked;

  /// No description provided for @switcherSubProject.
  ///
  /// In en, this message translates to:
  /// **'Project'**
  String get switcherSubProject;

  /// No description provided for @switcherSubSearch.
  ///
  /// In en, this message translates to:
  /// **'Saved search'**
  String get switcherSubSearch;

  /// No description provided for @switcherSubTag.
  ///
  /// In en, this message translates to:
  /// **'Tag'**
  String get switcherSubTag;

  /// No description provided for @switcherTags.
  ///
  /// In en, this message translates to:
  /// **'Tags'**
  String get switcherTags;

  /// No description provided for @switcherTitle.
  ///
  /// In en, this message translates to:
  /// **'Quick switcher'**
  String get switcherTitle;

  /// No description provided for @syncAccountMismatch.
  ///
  /// In en, this message translates to:
  /// **'This device holds data from a different account. Sign back in to that account to sync.'**
  String get syncAccountMismatch;

  /// No description provided for @syncFilesIncomplete.
  ///
  /// In en, this message translates to:
  /// **'Some files haven\'t synced yet.'**
  String get syncFilesIncomplete;

  /// No description provided for @syncGenericError.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t sync. Your notes are safe on this device.'**
  String get syncGenericError;

  /// No description provided for @syncServerOutdated.
  ///
  /// In en, this message translates to:
  /// **'Your sync server needs a database update. Run the newest files in supabase/migrations on your Supabase project.'**
  String get syncServerOutdated;

  /// No description provided for @tableAddColumnLeft.
  ///
  /// In en, this message translates to:
  /// **'Add column left'**
  String get tableAddColumnLeft;

  /// No description provided for @tableAddColumnRight.
  ///
  /// In en, this message translates to:
  /// **'Add column right'**
  String get tableAddColumnRight;

  /// No description provided for @tableAddRowAbove.
  ///
  /// In en, this message translates to:
  /// **'Add row above'**
  String get tableAddRowAbove;

  /// No description provided for @tableAddRowBelow.
  ///
  /// In en, this message translates to:
  /// **'Add row below'**
  String get tableAddRowBelow;

  /// No description provided for @tableDeleteColumn.
  ///
  /// In en, this message translates to:
  /// **'Delete column'**
  String get tableDeleteColumn;

  /// No description provided for @tableDeleteRow.
  ///
  /// In en, this message translates to:
  /// **'Delete row'**
  String get tableDeleteRow;

  /// No description provided for @tableDeleteTable.
  ///
  /// In en, this message translates to:
  /// **'Delete table'**
  String get tableDeleteTable;

  /// No description provided for @tableHeaderRow.
  ///
  /// In en, this message translates to:
  /// **'Header row'**
  String get tableHeaderRow;

  /// No description provided for @tableTooltip.
  ///
  /// In en, this message translates to:
  /// **'Table'**
  String get tableTooltip;

  /// No description provided for @templatesInsert.
  ///
  /// In en, this message translates to:
  /// **'Insert template'**
  String get templatesInsert;

  /// No description provided for @templatesInsertHint.
  ///
  /// In en, this message translates to:
  /// **'Fill one of your templates in here'**
  String get templatesInsertHint;

  /// No description provided for @templatesLiterature.
  ///
  /// In en, this message translates to:
  /// **'Literature note'**
  String get templatesLiterature;

  /// No description provided for @templatesStopUsing.
  ///
  /// In en, this message translates to:
  /// **'Stop using as template'**
  String get templatesStopUsing;

  /// No description provided for @templatesTitle.
  ///
  /// In en, this message translates to:
  /// **'Templates'**
  String get templatesTitle;

  /// No description provided for @templatesUnlockReason.
  ///
  /// In en, this message translates to:
  /// **'Unlock to use this template'**
  String get templatesUnlockReason;

  /// No description provided for @templatesUntitled.
  ///
  /// In en, this message translates to:
  /// **'Untitled template'**
  String get templatesUntitled;

  /// No description provided for @templatesUse.
  ///
  /// In en, this message translates to:
  /// **'Use as template'**
  String get templatesUse;

  /// No description provided for @trashDaysLeft.
  ///
  /// In en, this message translates to:
  /// **'{days, plural, =1{1 day left} other{{days} days left}}'**
  String trashDaysLeft(int days);

  /// No description provided for @trashDeletingSoon.
  ///
  /// In en, this message translates to:
  /// **'deleting soon'**
  String get trashDeletingSoon;

  /// No description provided for @trashEmptyAction.
  ///
  /// In en, this message translates to:
  /// **'Empty'**
  String get trashEmptyAction;

  /// No description provided for @trashEmptyBody.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 item will be deleted for good.} other{{count} items will be deleted for good.}}'**
  String trashEmptyBody(int count);

  /// No description provided for @trashEmptyMessage.
  ///
  /// In en, this message translates to:
  /// **'Deleted notes and papers stay here for {days, plural, =1{1 day} other{{days} days}}.'**
  String trashEmptyMessage(int days);

  /// No description provided for @trashEmptyTitle.
  ///
  /// In en, this message translates to:
  /// **'Empty the trash?'**
  String get trashEmptyTitle;

  /// No description provided for @trashIsEmpty.
  ///
  /// In en, this message translates to:
  /// **'Trash is empty'**
  String get trashIsEmpty;

  /// No description provided for @trashKept.
  ///
  /// In en, this message translates to:
  /// **'Kept for {days, plural, =1{1 day} other{{days} days}}, then deleted for good.'**
  String trashKept(int days);

  /// No description provided for @trashKindNote.
  ///
  /// In en, this message translates to:
  /// **'Note'**
  String get trashKindNote;

  /// No description provided for @trashKindPaper.
  ///
  /// In en, this message translates to:
  /// **'Paper'**
  String get trashKindPaper;

  /// No description provided for @trashMovedToTrash.
  ///
  /// In en, this message translates to:
  /// **'{label} moved to trash'**
  String trashMovedToTrash(String label);

  /// No description provided for @trashQuoted.
  ///
  /// In en, this message translates to:
  /// **'“{title}”'**
  String trashQuoted(String title);

  /// No description provided for @trashRestore.
  ///
  /// In en, this message translates to:
  /// **'Restore'**
  String get trashRestore;

  /// No description provided for @trashRestored.
  ///
  /// In en, this message translates to:
  /// **'Restored'**
  String get trashRestored;

  /// No description provided for @viewerAboutThisPaper.
  ///
  /// In en, this message translates to:
  /// **'About this paper'**
  String get viewerAboutThisPaper;

  /// No description provided for @viewerCloseSearch.
  ///
  /// In en, this message translates to:
  /// **'Close search'**
  String get viewerCloseSearch;

  /// No description provided for @viewerContents.
  ///
  /// In en, this message translates to:
  /// **'Contents'**
  String get viewerContents;

  /// No description provided for @viewerDrawOnPage.
  ///
  /// In en, this message translates to:
  /// **'Draw on the page'**
  String get viewerDrawOnPage;

  /// No description provided for @viewerExportDamaged.
  ///
  /// In en, this message translates to:
  /// **'This PDF can’t be annotated: its structure is damaged or uses features Corplex can’t write into.'**
  String get viewerExportDamaged;

  /// No description provided for @viewerExportEncrypted.
  ///
  /// In en, this message translates to:
  /// **'This PDF is encrypted, so highlights can’t be written into it.'**
  String get viewerExportEncrypted;

  /// No description provided for @viewerExportFailed.
  ///
  /// In en, this message translates to:
  /// **'Couldn’t export this PDF.'**
  String get viewerExportFailed;

  /// No description provided for @viewerExportNoPdf.
  ///
  /// In en, this message translates to:
  /// **'This paper’s PDF isn’t on this device.'**
  String get viewerExportNoPdf;

  /// No description provided for @viewerExportNotPdf.
  ///
  /// In en, this message translates to:
  /// **'This file isn’t a PDF Corplex can read.'**
  String get viewerExportNotPdf;

  /// No description provided for @viewerExportNothing.
  ///
  /// In en, this message translates to:
  /// **'Nothing to export: the marks don’t match this PDF’s pages.'**
  String get viewerExportNothing;

  /// No description provided for @viewerFind.
  ///
  /// In en, this message translates to:
  /// **'Find in document'**
  String get viewerFind;

  /// No description provided for @viewerFindCount.
  ///
  /// In en, this message translates to:
  /// **'{current} of {total}'**
  String viewerFindCount(int current, int total);

  /// No description provided for @viewerFindCountMore.
  ///
  /// In en, this message translates to:
  /// **'{current} of {total}+'**
  String viewerFindCountMore(int current, int total);

  /// No description provided for @viewerFindNoMatches.
  ///
  /// In en, this message translates to:
  /// **'No matches'**
  String get viewerFindNoMatches;

  /// No description provided for @viewerFindNoMatchesYet.
  ///
  /// In en, this message translates to:
  /// **'No matches yet'**
  String get viewerFindNoMatchesYet;

  /// No description provided for @viewerFindSearching.
  ///
  /// In en, this message translates to:
  /// **'Searching…'**
  String get viewerFindSearching;

  /// No description provided for @viewerFocus.
  ///
  /// In en, this message translates to:
  /// **'Focus'**
  String get viewerFocus;

  /// No description provided for @viewerFocusHint.
  ///
  /// In en, this message translates to:
  /// **'Tap the page to bring back'**
  String get viewerFocusHint;

  /// No description provided for @viewerHighlightColour.
  ///
  /// In en, this message translates to:
  /// **'Highlight colour'**
  String get viewerHighlightColour;

  /// No description provided for @viewerNextMatch.
  ///
  /// In en, this message translates to:
  /// **'Next match'**
  String get viewerNextMatch;

  /// No description provided for @viewerNightPage.
  ///
  /// In en, this message translates to:
  /// **'Night page'**
  String get viewerNightPage;

  /// No description provided for @viewerNoContents.
  ///
  /// In en, this message translates to:
  /// **'This PDF has no table of contents.'**
  String get viewerNoContents;

  /// No description provided for @viewerNotesOn.
  ///
  /// In en, this message translates to:
  /// **'Notes on {title}'**
  String viewerNotesOn(String title);

  /// No description provided for @viewerPageLong.
  ///
  /// In en, this message translates to:
  /// **'Page {page}'**
  String viewerPageLong(int page);

  /// No description provided for @viewerPagePill.
  ///
  /// In en, this message translates to:
  /// **'{page} / {count}'**
  String viewerPagePill(int page, int count);

  /// No description provided for @viewerPageShort.
  ///
  /// In en, this message translates to:
  /// **'p. {page}'**
  String viewerPageShort(int page);

  /// No description provided for @viewerPageStrip.
  ///
  /// In en, this message translates to:
  /// **'Page strip'**
  String get viewerPageStrip;

  /// No description provided for @viewerPaperPage.
  ///
  /// In en, this message translates to:
  /// **'Paper page'**
  String get viewerPaperPage;

  /// No description provided for @viewerPreviousMatch.
  ///
  /// In en, this message translates to:
  /// **'Previous match'**
  String get viewerPreviousMatch;

  /// No description provided for @viewerQuoteAdded.
  ///
  /// In en, this message translates to:
  /// **'Added to your note'**
  String get viewerQuoteAdded;

  /// No description provided for @viewerQuoteNewNote.
  ///
  /// In en, this message translates to:
  /// **'New note'**
  String get viewerQuoteNewNote;

  /// No description provided for @viewerReadAloud.
  ///
  /// In en, this message translates to:
  /// **'Read aloud'**
  String get viewerReadAloud;

  /// No description provided for @viewerReadAloudUnavailable.
  ///
  /// In en, this message translates to:
  /// **'Reading aloud isn\'t available here'**
  String get viewerReadAloudUnavailable;

  /// No description provided for @viewerRecentNotes.
  ///
  /// In en, this message translates to:
  /// **'Recent notes'**
  String get viewerRecentNotes;

  /// No description provided for @viewerSepiaPage.
  ///
  /// In en, this message translates to:
  /// **'Sepia page'**
  String get viewerSepiaPage;

  /// No description provided for @viewerShowPages.
  ///
  /// In en, this message translates to:
  /// **'Show pages'**
  String get viewerShowPages;

  /// No description provided for @viewerSnapPrompt.
  ///
  /// In en, this message translates to:
  /// **'Drag around a figure or table'**
  String get viewerSnapPrompt;

  /// No description provided for @viewerSnapWholeView.
  ///
  /// In en, this message translates to:
  /// **'Whole view'**
  String get viewerSnapWholeView;

  /// No description provided for @viewerSnapshot.
  ///
  /// In en, this message translates to:
  /// **'Snapshot to a note'**
  String get viewerSnapshot;

  /// No description provided for @viewerSnapshotHint.
  ///
  /// In en, this message translates to:
  /// **'For figures and tables'**
  String get viewerSnapshotHint;

  /// No description provided for @viewerStopDrawing.
  ///
  /// In en, this message translates to:
  /// **'Stop drawing'**
  String get viewerStopDrawing;

  /// No description provided for @viewerStopReadAloud.
  ///
  /// In en, this message translates to:
  /// **'Stop reading aloud'**
  String get viewerStopReadAloud;

  /// No description provided for @viewerUnlockToAdd.
  ///
  /// In en, this message translates to:
  /// **'Unlock the note to add to it.'**
  String get viewerUnlockToAdd;

  /// No description provided for @viewerUnlockToQuote.
  ///
  /// In en, this message translates to:
  /// **'Unlock the note to add this quote to it.'**
  String get viewerUnlockToQuote;

  /// No description provided for @viewsCalendar.
  ///
  /// In en, this message translates to:
  /// **'Calendar'**
  String get viewsCalendar;

  /// No description provided for @viewsColAuthors.
  ///
  /// In en, this message translates to:
  /// **'Authors'**
  String get viewsColAuthors;

  /// No description provided for @viewsColRating.
  ///
  /// In en, this message translates to:
  /// **'Rating'**
  String get viewsColRating;

  /// No description provided for @viewsColStatus.
  ///
  /// In en, this message translates to:
  /// **'Status'**
  String get viewsColStatus;

  /// No description provided for @viewsColTitle.
  ///
  /// In en, this message translates to:
  /// **'Title'**
  String get viewsColTitle;

  /// No description provided for @viewsColVenue.
  ///
  /// In en, this message translates to:
  /// **'Venue'**
  String get viewsColVenue;

  /// No description provided for @viewsColYear.
  ///
  /// In en, this message translates to:
  /// **'Year'**
  String get viewsColYear;

  /// No description provided for @viewsCopied.
  ///
  /// In en, this message translates to:
  /// **'Copied'**
  String get viewsCopied;

  /// No description provided for @viewsCopyCsv.
  ///
  /// In en, this message translates to:
  /// **'Copy as CSV'**
  String get viewsCopyCsv;

  /// No description provided for @viewsCopyMarkdown.
  ///
  /// In en, this message translates to:
  /// **'Copy as Markdown table'**
  String get viewsCopyMarkdown;

  /// No description provided for @viewsKindDaily.
  ///
  /// In en, this message translates to:
  /// **'Daily note'**
  String get viewsKindDaily;

  /// No description provided for @viewsKindDue.
  ///
  /// In en, this message translates to:
  /// **'Due date'**
  String get viewsKindDue;

  /// No description provided for @viewsKindNote.
  ///
  /// In en, this message translates to:
  /// **'Note created'**
  String get viewsKindNote;

  /// No description provided for @viewsKindPaper.
  ///
  /// In en, this message translates to:
  /// **'Paper added'**
  String get viewsKindPaper;

  /// No description provided for @viewsLocked.
  ///
  /// In en, this message translates to:
  /// **'Locked'**
  String get viewsLocked;

  /// No description provided for @viewsMoveTo.
  ///
  /// In en, this message translates to:
  /// **'Move to…'**
  String get viewsMoveTo;

  /// No description provided for @viewsMoveToStatus.
  ///
  /// In en, this message translates to:
  /// **'Move to {status}'**
  String viewsMoveToStatus(String status);

  /// No description provided for @viewsMovedTo.
  ///
  /// In en, this message translates to:
  /// **'Moved “{title}” to {status}'**
  String viewsMovedTo(String title, String status);

  /// No description provided for @viewsNewDayNote.
  ///
  /// In en, this message translates to:
  /// **'New note for this day'**
  String get viewsNewDayNote;

  /// No description provided for @viewsNewTodaysNote.
  ///
  /// In en, this message translates to:
  /// **'New note for today'**
  String get viewsNewTodaysNote;

  /// No description provided for @viewsNextMonth.
  ///
  /// In en, this message translates to:
  /// **'Next month'**
  String get viewsNextMonth;

  /// No description provided for @viewsNoStatus.
  ///
  /// In en, this message translates to:
  /// **'No status'**
  String get viewsNoStatus;

  /// No description provided for @viewsOpenDayNote.
  ///
  /// In en, this message translates to:
  /// **'Open note for this day'**
  String get viewsOpenDayNote;

  /// No description provided for @viewsOpenTodaysNote.
  ///
  /// In en, this message translates to:
  /// **'Today’s note'**
  String get viewsOpenTodaysNote;

  /// No description provided for @viewsPreviousMonth.
  ///
  /// In en, this message translates to:
  /// **'Previous month'**
  String get viewsPreviousMonth;

  /// No description provided for @viewsTimeline.
  ///
  /// In en, this message translates to:
  /// **'Timeline'**
  String get viewsTimeline;

  /// No description provided for @viewsTimelinePace.
  ///
  /// In en, this message translates to:
  /// **'{words} / {target} words · needs ~{perDay} words/day to finish by {date}'**
  String viewsTimelinePace(
    String words,
    String target,
    String perDay,
    String date,
  );

  /// No description provided for @viewsTimelinePastDue.
  ///
  /// In en, this message translates to:
  /// **'{words} / {target} words · past the due date'**
  String viewsTimelinePastDue(String words, String target);

  /// No description provided for @viewsTimelineWords.
  ///
  /// In en, this message translates to:
  /// **'{words} / {target} words'**
  String viewsTimelineWords(String words, String target);

  /// No description provided for @viewsTimelineWordsOnly.
  ///
  /// In en, this message translates to:
  /// **'{words} words'**
  String viewsTimelineWordsOnly(String words);

  /// No description provided for @viewsViewBoard.
  ///
  /// In en, this message translates to:
  /// **'View as board'**
  String get viewsViewBoard;

  /// No description provided for @viewsViewGrid.
  ///
  /// In en, this message translates to:
  /// **'View as grid'**
  String get viewsViewGrid;

  /// No description provided for @viewsViewList.
  ///
  /// In en, this message translates to:
  /// **'View as list'**
  String get viewsViewList;

  /// No description provided for @viewsViewTable.
  ///
  /// In en, this message translates to:
  /// **'View as table'**
  String get viewsViewTable;

  /// No description provided for @voiceDictate.
  ///
  /// In en, this message translates to:
  /// **'Dictate'**
  String get voiceDictate;

  /// No description provided for @voiceFinishing.
  ///
  /// In en, this message translates to:
  /// **'Finishing…'**
  String get voiceFinishing;

  /// No description provided for @voiceMicDenied.
  ///
  /// In en, this message translates to:
  /// **'Corplex needs the microphone to record. You can allow it in Settings.'**
  String get voiceMicDenied;

  /// No description provided for @voiceNoSpeechCaught.
  ///
  /// In en, this message translates to:
  /// **'Didn’t catch any speech.'**
  String get voiceNoSpeechCaught;

  /// No description provided for @voiceNote.
  ///
  /// In en, this message translates to:
  /// **'Voice note'**
  String get voiceNote;

  /// No description provided for @voiceNoteTitle.
  ///
  /// In en, this message translates to:
  /// **'Voice note, {date}'**
  String voiceNoteTitle(String date);

  /// No description provided for @voiceOpenSettings.
  ///
  /// In en, this message translates to:
  /// **'Open Settings'**
  String get voiceOpenSettings;

  /// No description provided for @voiceRecordingUnavailable.
  ///
  /// In en, this message translates to:
  /// **'Recording isn’t available here, so nothing was recorded.'**
  String get voiceRecordingUnavailable;

  /// No description provided for @voiceSavedAllowSpeech.
  ///
  /// In en, this message translates to:
  /// **'Saved the audio. Allow Speech Recognition to get text too.'**
  String get voiceSavedAllowSpeech;

  /// No description provided for @voiceSavedCantTranscribe.
  ///
  /// In en, this message translates to:
  /// **'Saved the audio. This device can’t transcribe it offline.'**
  String get voiceSavedCantTranscribe;

  /// No description provided for @voiceSavedNoSpeech.
  ///
  /// In en, this message translates to:
  /// **'Saved. No speech was heard.'**
  String get voiceSavedNoSpeech;

  /// No description provided for @voiceSavingTranscribing.
  ///
  /// In en, this message translates to:
  /// **'Saving and transcribing…'**
  String get voiceSavingTranscribing;

  /// No description provided for @voiceStartRecording.
  ///
  /// In en, this message translates to:
  /// **'Start recording'**
  String get voiceStartRecording;

  /// No description provided for @voiceStopRecording.
  ///
  /// In en, this message translates to:
  /// **'Stop recording'**
  String get voiceStopRecording;

  /// No description provided for @zoteroApiKey.
  ///
  /// In en, this message translates to:
  /// **'API key'**
  String get zoteroApiKey;

  /// No description provided for @zoteroBadKey.
  ///
  /// In en, this message translates to:
  /// **'Zotero didn\'t accept that user ID and key. Check both, and that the key is allowed to read your library.'**
  String get zoteroBadKey;

  /// No description provided for @zoteroConnect.
  ///
  /// In en, this message translates to:
  /// **'Connect'**
  String get zoteroConnect;

  /// No description provided for @zoteroConnectTitle.
  ///
  /// In en, this message translates to:
  /// **'Connect to Zotero'**
  String get zoteroConnectTitle;

  /// No description provided for @zoteroEnterBoth.
  ///
  /// In en, this message translates to:
  /// **'Enter both your user ID and an API key.'**
  String get zoteroEnterBoth;

  /// No description provided for @zoteroEverything.
  ///
  /// In en, this message translates to:
  /// **'Everything'**
  String get zoteroEverything;

  /// No description provided for @zoteroEverythingHint.
  ///
  /// In en, this message translates to:
  /// **'Every item; collections become projects'**
  String get zoteroEverythingHint;

  /// No description provided for @zoteroForgetKey.
  ///
  /// In en, this message translates to:
  /// **'Forget key'**
  String get zoteroForgetKey;

  /// No description provided for @zoteroImport.
  ///
  /// In en, this message translates to:
  /// **'Import'**
  String get zoteroImport;

  /// No description provided for @zoteroImportFailed.
  ///
  /// In en, this message translates to:
  /// **'{message}\nWhat was imported before this stays in your library.'**
  String zoteroImportFailed(String message);

  /// No description provided for @zoteroImportTitle.
  ///
  /// In en, this message translates to:
  /// **'Import from Zotero'**
  String get zoteroImportTitle;

  /// No description provided for @zoteroImporting.
  ///
  /// In en, this message translates to:
  /// **'Importing'**
  String get zoteroImporting;

  /// No description provided for @zoteroImportingItem.
  ///
  /// In en, this message translates to:
  /// **'Importing “{title}”'**
  String zoteroImportingItem(String title);

  /// No description provided for @zoteroKeyHelp.
  ///
  /// In en, this message translates to:
  /// **'Create a read-only key at zotero.org/settings/keys (Create new private key, allow library access only). Your user ID is shown on the same page. They stay on this device, in secure storage, and are never synced or backed up.'**
  String get zoteroKeyHelp;

  /// No description provided for @zoteroNotFound.
  ///
  /// In en, this message translates to:
  /// **'Zotero couldn\'t find that library. Check the user ID (the number on zotero.org/settings/keys).'**
  String get zoteroNotFound;

  /// No description provided for @zoteroOffline.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t reach Zotero. Check your connection and try again.'**
  String get zoteroOffline;

  /// No description provided for @zoteroOpenKeys.
  ///
  /// In en, this message translates to:
  /// **'Open zotero.org/settings/keys'**
  String get zoteroOpenKeys;

  /// No description provided for @zoteroProgress.
  ///
  /// In en, this message translates to:
  /// **'{done} of {total}'**
  String zoteroProgress(int done, int total);

  /// No description provided for @zoteroRateLimited.
  ///
  /// In en, this message translates to:
  /// **'Zotero is asking for a pause. Try again in a few minutes.'**
  String get zoteroRateLimited;

  /// No description provided for @zoteroReadingAttachments.
  ///
  /// In en, this message translates to:
  /// **'Reading attachments and annotations…'**
  String get zoteroReadingAttachments;

  /// No description provided for @zoteroReadingItems.
  ///
  /// In en, this message translates to:
  /// **'Reading items…'**
  String get zoteroReadingItems;

  /// No description provided for @zoteroReadingLibrary.
  ///
  /// In en, this message translates to:
  /// **'Reading your Zotero library…'**
  String get zoteroReadingLibrary;

  /// No description provided for @zoteroServerProblem.
  ///
  /// In en, this message translates to:
  /// **'Zotero had a problem. Try again later.'**
  String get zoteroServerProblem;

  /// No description provided for @zoteroServerProblemDetail.
  ///
  /// In en, this message translates to:
  /// **'Zotero had a problem ({detail}). Try again later.'**
  String zoteroServerProblemDetail(String detail);

  /// No description provided for @zoteroSomeCollections.
  ///
  /// In en, this message translates to:
  /// **'Only some collections'**
  String get zoteroSomeCollections;

  /// No description provided for @zoteroSomethingWrong.
  ///
  /// In en, this message translates to:
  /// **'Something went wrong.'**
  String get zoteroSomethingWrong;

  /// No description provided for @zoteroStopped.
  ///
  /// In en, this message translates to:
  /// **'Stopped'**
  String get zoteroStopped;

  /// No description provided for @zoteroStopping.
  ///
  /// In en, this message translates to:
  /// **'Stopping…'**
  String get zoteroStopping;

  /// No description provided for @zoteroSummaryAlreadyIn.
  ///
  /// In en, this message translates to:
  /// **'{count} already in your library'**
  String zoteroSummaryAlreadyIn(int count);

  /// No description provided for @zoteroSummaryDone.
  ///
  /// In en, this message translates to:
  /// **'{summary}.'**
  String zoteroSummaryDone(String summary);

  /// No description provided for @zoteroSummaryMain.
  ///
  /// In en, this message translates to:
  /// **'Imported {papers, plural, =1{1 paper} other{{papers} papers}}, {pdfs, plural, =1{1 PDF} other{{pdfs} PDFs}}, {highlights, plural, =1{1 highlight} other{{highlights} highlights}} into {projects, plural, =1{1 project} other{{projects} projects}}'**
  String zoteroSummaryMain(int papers, int pdfs, int highlights, int projects);

  /// No description provided for @zoteroSummaryNotes.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 note} other{{count} notes}} added'**
  String zoteroSummaryNotes(int count);

  /// No description provided for @zoteroSummaryPdfsFailed.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 PDF} other{{count} PDFs}} couldn\'t be downloaded'**
  String zoteroSummaryPdfsFailed(int count);

  /// No description provided for @zoteroSummarySkipped.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 item} other{{count} items}} skipped'**
  String zoteroSummarySkipped(int count);

  /// No description provided for @zoteroSummaryStopped.
  ///
  /// In en, this message translates to:
  /// **'Stopped. {summary}.'**
  String zoteroSummaryStopped(String summary);

  /// No description provided for @zoteroTitle.
  ///
  /// In en, this message translates to:
  /// **'Zotero'**
  String get zoteroTitle;

  /// No description provided for @zoteroUserId.
  ///
  /// In en, this message translates to:
  /// **'User ID'**
  String get zoteroUserId;

  /// No description provided for @zoteroUserIdNumber.
  ///
  /// In en, this message translates to:
  /// **'The user ID is a number, not your username.'**
  String get zoteroUserIdNumber;
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['de', 'en'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'de':
      return AppLocalizationsDe();
    case 'en':
      return AppLocalizationsEn();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
