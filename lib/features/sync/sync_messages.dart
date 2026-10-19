import '../../l10n/l10n.dart';
import 'sync_engine.dart';
import 'sync_remote.dart';
import 'sync_service.dart';

/// The text for [SyncService.lastError] in the app's language. The service
/// keeps English messages (they're what tests and logs see); the known ones
/// are swapped for their translation here and anything else (a custom
/// service's own wording) is shown as it is.
String localizedSyncError(AppLocalizations l10n, String? error) {
  if (error == null) return l10n.settingsSyncFailed;
  if (error == const SyncAccountMismatch().toString()) {
    return l10n.syncAccountMismatch;
  }
  if (error == const SyncFilesIncomplete().toString()) {
    return l10n.syncFilesIncomplete;
  }
  if (error == const SyncServerOutdated().toString()) {
    return l10n.syncServerOutdated;
  }
  if (error == syncGenericErrorMessage) return l10n.syncGenericError;
  return error;
}
