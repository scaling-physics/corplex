import 'package:path/path.dart' as p;

import '../../data/database.dart';
import '../../data/tables/attachments_table.dart';

/// Timestamps in notes are ordinary Quill links with this scheme, e.g.
/// `corplex://audio/<attachmentId>?t=754`. Being plain links, they survive
/// sync, copy/paste and export untouched; the note editor recognizes them
/// and turns a tap into "play this recording from 12:34".
const audioLinkScheme = 'corplex';

String audioTimestampLink(String attachmentId, Duration at) =>
    '$audioLinkScheme://audio/$attachmentId?t=${at.inSeconds}';

/// The recording and position a timestamp link points at, or null if
/// [link] isn't one.
({String attachmentId, Duration at})? parseAudioTimestampLink(String link) {
  final uri = Uri.tryParse(link);
  if (uri == null ||
      uri.scheme != audioLinkScheme ||
      uri.host != 'audio' ||
      uri.pathSegments.length != 1) {
    return null;
  }
  final seconds = int.tryParse(uri.queryParameters['t'] ?? '0');
  if (seconds == null || seconds < 0) return null;
  return (
    attachmentId: uri.pathSegments.single,
    at: Duration(seconds: seconds),
  );
}

/// `4:05`, or `1:02:03` past an hour.
String formatTimestamp(Duration d) {
  final h = d.inHours;
  final m = d.inMinutes.remainder(60);
  final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
  return h > 0 ? '$h:${m.toString().padLeft(2, '0')}:$s' : '$m:$s';
}

const _audioExtensions = {
  '.mp3',
  '.m4a',
  '.aac',
  '.wav',
  '.ogg',
  '.oga',
  '.opus',
  '.flac',
};

bool _looksLikeAudio(String pathOrUrl) {
  final path = Uri.tryParse(pathOrUrl)?.path ?? pathOrUrl;
  return _audioExtensions.contains(p.extension(path).toLowerCase());
}

/// What an attachment can be played from: its file on this device, or a
/// direct audio URL. Null for a page link (e.g. a NotebookLM share page,
/// which isn't an audio file) or a file still syncing to this device.
({String? path, String? url})? audioSourceOf(Attachment a) {
  if (a.path case final path?) {
    if (a.type == AttachmentType.podcast || _looksLikeAudio(path)) {
      return (path: path, url: null);
    }
  }
  if (a.url case final url? when _looksLikeAudio(url)) {
    return (path: null, url: url);
  }
  return null;
}

/// True for audio that exists somewhere (possibly still downloading), so
/// the UI can show a player chip rather than a generic file chip.
bool isAudioAttachment(Attachment a) =>
    audioSourceOf(a) != null ||
    (a.type == AttachmentType.podcast && a.storageKey != null);
