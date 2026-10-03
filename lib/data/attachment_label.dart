import 'database.dart';
import 'local_files.dart';

extension AttachmentLabel on Attachment {
  /// What to call this attachment on screen (and on the lock screen): its
  /// title, else its link, else a name made from its file. Titles saved
  /// straight from a file name ("Audio_Overview_Attention") read with
  /// spaces.
  String get label {
    final title = this.title?.trim();
    if (title != null && title.isNotEmpty) {
      return title.contains(' ') ? title : title.replaceAll('_', ' ');
    }
    if (url case final url? when url.isNotEmpty) return url;
    if (path case final path? when path.isNotEmpty) {
      // Stored copies are named "<microseconds>_<original name>".
      final name = path.split('/').last.replaceFirst(RegExp(r'^\d+_'), '');
      return titleFromFileName(name);
    }
    return 'Attachment';
  }
}
