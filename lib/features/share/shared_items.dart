import 'package:path/path.dart' as p;
import 'package:receive_sharing_intent/receive_sharing_intent.dart';

import '../library/metadata_lookup.dart';

/// What another app shared with Corplex, sorted into the things it can do
/// something useful with.
sealed class SharedItem {
  const SharedItem();
}

class SharedPdf extends SharedItem {
  const SharedPdf(this.path);

  final String path;
  String get name => p.basenameWithoutExtension(path);
}

class SharedAudio extends SharedItem {
  const SharedAudio(this.path);

  final String path;
  String get name => p.basenameWithoutExtension(path);
}

/// A DOI or arXiv id, alone or inside a link.
class SharedIdentifier extends SharedItem {
  const SharedIdentifier(this.identifier);

  final PaperIdentifier identifier;
}

/// Any other web link.
class SharedLink extends SharedItem {
  const SharedLink(this.url);

  final Uri url;
}

class SharedText extends SharedItem {
  const SharedText(this.text);

  final String text;
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

/// Sorts shared media. Text and URLs arrive with their content in `path`.
/// Anything unrecognized (images, videos, other files) is dropped: the app
/// declares no interest in them.
List<SharedItem> classifyShared(Iterable<SharedMediaFile> media) {
  final items = <SharedItem>[];
  for (final m in media) {
    switch (m.type) {
      case SharedMediaType.text || SharedMediaType.url:
        items.addAll(_classifyText(m.path));
      case SharedMediaType.file:
        final ext = p.extension(m.path).toLowerCase();
        if (ext == '.pdf' || m.mimeType == 'application/pdf') {
          items.add(SharedPdf(m.path));
        } else if (_audioExtensions.contains(ext) ||
            (m.mimeType?.startsWith('audio/') ?? false)) {
          items.add(SharedAudio(m.path));
        }
      case SharedMediaType.image || SharedMediaType.video:
        break;
    }
  }
  return items;
}

/// A shared page usually arrives as "Title\nhttps://…"; find what matters.
Iterable<SharedItem> _classifyText(String raw) sync* {
  final text = raw.trim();
  if (text.isEmpty) return;

  final id = parseIdentifier(text);
  if (id != null) {
    yield SharedIdentifier(id);
    return;
  }
  final url = RegExp(r'https?://\S+').firstMatch(text)?.group(0);
  if (url != null) {
    final uri = Uri.tryParse(url);
    if (uri != null) {
      yield SharedLink(uri);
      return;
    }
  }
  yield SharedText(text);
}
