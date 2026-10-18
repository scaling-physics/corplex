import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../data/database.dart';
import '../../data/database_provider.dart';
import 'zotero_client.dart';
import 'zotero_credentials.dart';
import 'zotero_import.dart';

/// Library ⋮ → "Import from Zotero…": connect, choose, import.
Future<void> importFromZotero(BuildContext context, WidgetRef ref) async {
  final db = ref.read(databaseProvider);
  final store = ref.read(zoteroCredentialStoreProvider);
  await showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => ZoteroImportDialog(db: db, store: store),
  );
}

enum _Stage { loading, connect, choose, importing, done, failed }

class ZoteroImportDialog extends StatefulWidget {
  const ZoteroImportDialog({
    super.key,
    required this.db,
    required this.store,
    this.clientFactory,
    this.pageSizes,
    this.savePdf,
  });

  final AppDatabase db;
  final ZoteroCredentialStore store;

  /// Test seam.
  final ZoteroClient Function(ZoteroCredentials)? clientFactory;
  final PageSizeReader? pageSizes;
  final PdfSaver? savePdf;

  @override
  State<ZoteroImportDialog> createState() => _ZoteroImportDialogState();
}

class _ZoteroImportDialogState extends State<ZoteroImportDialog> {
  final _id = TextEditingController();
  final _key = TextEditingController();
  _Stage _stage = _Stage.loading;
  String? _error;
  ZoteroCredentials? _creds;
  ZoteroClient? _client;
  List<ZoteroCollection> _collections = const [];
  bool _everything = true;
  final Set<String> _picked = {};
  ZoteroProgress _progress = const ZoteroProgress('');
  bool _cancel = false;
  ZoteroImportSummary? _summary;

  @override
  void initState() {
    super.initState();
    _start();
  }

  @override
  void dispose() {
    _id.dispose();
    _key.dispose();
    _client?.close();
    super.dispose();
  }

  ZoteroClient _make(ZoteroCredentials c) =>
      widget.clientFactory?.call(c) ??
      ZoteroClient(userId: c.userId, apiKey: c.apiKey);

  Future<void> _start() async {
    final saved = await widget.store.read();
    if (!mounted) return;
    if (saved == null) {
      setState(() => _stage = _Stage.connect);
    } else {
      _creds = saved;
      await _loadCollections();
    }
  }

  Future<void> _connect() async {
    final c = ZoteroCredentials(_id.text.trim(), _key.text.trim());
    if (c.userId.isEmpty || c.apiKey.isEmpty) {
      setState(() => _error = 'Enter both your user ID and an API key.');
      return;
    }
    if (!RegExp(r'^\d+$').hasMatch(c.userId)) {
      setState(() => _error = 'The user ID is a number, not your username.');
      return;
    }
    setState(() {
      _error = null;
      _stage = _Stage.loading;
    });
    _creds = c;
    final client = _make(c);
    try {
      await client.check();
    } on ZoteroException catch (e) {
      client.close();
      if (!mounted) return;
      setState(() {
        _stage = _Stage.connect;
        _error = e.message;
      });
      return;
    }
    client.close();
    await widget.store.save(c);
    if (!mounted) return;
    await _loadCollections();
  }

  Future<void> _loadCollections() async {
    setState(() {
      _stage = _Stage.loading;
      _error = null;
    });
    _client?.close();
    _client = _make(_creds!);
    try {
      final list = await ZoteroImporter(
        db: widget.db,
        client: _client!,
      ).loadCollections();
      if (!mounted) return;
      setState(() {
        _collections = list;
        _stage = _Stage.choose;
      });
    } on ZoteroException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.message;
        _stage = e.problem == ZoteroProblem.badKey
            ? _Stage.connect
            : _Stage.failed;
      });
    }
  }

  Future<void> _forget() async {
    await widget.store.forget();
    if (!mounted) return;
    _id.clear();
    _key.clear();
    setState(() {
      _creds = null;
      _error = null;
      _stage = _Stage.connect;
    });
  }

  Future<void> _import() async {
    _cancel = false;
    setState(() => _stage = _Stage.importing);
    final importer = ZoteroImporter(
      db: widget.db,
      client: _client!,
      pageSizes: widget.pageSizes,
      savePdf: widget.savePdf,
    );
    try {
      final summary = await importer.run(
        collectionKeys: _everything ? null : _picked,
        onProgress: (p) {
          if (mounted) setState(() => _progress = p);
        },
        isCancelled: () => _cancel,
      );
      if (!mounted) return;
      setState(() {
        _summary = summary;
        _stage = _Stage.done;
      });
    } on ZoteroException catch (e) {
      if (!mounted) return;
      setState(() {
        _error =
            '${e.message}\nWhat was imported before this stays in your library.';
        _stage = e.problem == ZoteroProblem.badKey
            ? _Stage.connect
            : _Stage.failed;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final (title, body, actions) = switch (_stage) {
      _Stage.loading => (
        'Zotero',
        const Center(
          heightFactor: 2,
          child: CircularProgressIndicator.adaptive(),
        ),
        <Widget>[],
      ),
      _Stage.connect => (
        'Connect to Zotero',
        _connectBody(scheme),
        [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(onPressed: _connect, child: const Text('Connect')),
        ],
      ),
      _Stage.choose => (
        'Import from Zotero',
        _chooseBody(),
        [
          TextButton(onPressed: _forget, child: const Text('Forget key')),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: _everything || _picked.isNotEmpty ? _import : null,
            child: const Text('Import'),
          ),
        ],
      ),
      _Stage.importing => (
        'Importing',
        _progressBody(),
        [
          TextButton(
            onPressed: _cancel ? null : () => setState(() => _cancel = true),
            child: Text(_cancel ? 'Stopping…' : 'Cancel'),
          ),
        ],
      ),
      _Stage.done => (
        _summary!.cancelled ? 'Stopped' : 'Done',
        Text(_summary!.message),
        [
          FilledButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
      _Stage.failed => (
        'Zotero',
        Text(_error ?? 'Something went wrong.'),
        [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
          if (_creds != null)
            FilledButton(
              onPressed: _loadCollections,
              child: const Text('Try again'),
            ),
        ],
      ),
    };
    return AlertDialog(
      title: Text(title),
      content: SizedBox(width: 420, child: body),
      actions: actions,
    );
  }

  Widget _connectBody(ColorScheme scheme) => SingleChildScrollView(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Create a read-only key at zotero.org/settings/keys (Create new '
          'private key, allow library access only). Your user ID is shown '
          'on the same page. They stay on this device, in secure storage, '
          'and are never synced or backed up.',
        ),
        TextButton.icon(
          onPressed: () => launchUrl(
            Uri.https('www.zotero.org', '/settings/keys'),
            mode: LaunchMode.externalApplication,
          ),
          icon: const Icon(Icons.open_in_new, size: 18),
          label: const Text('Open zotero.org/settings/keys'),
        ),
        TextField(
          controller: _id,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(labelText: 'User ID'),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _key,
          obscureText: true,
          autocorrect: false,
          enableSuggestions: false,
          decoration: const InputDecoration(labelText: 'API key'),
        ),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Text(_error!, style: TextStyle(color: scheme.error)),
          ),
      ],
    ),
  );

  Widget _chooseBody() => SizedBox(
    height: 360,
    child: ListView(
      children: [
        ListTile(
          leading: Icon(
            _everything
                ? Icons.radio_button_checked
                : Icons.radio_button_unchecked,
          ),
          onTap: () => setState(() => _everything = true),
          title: const Text('Everything'),
          subtitle: const Text('Every item; collections become projects'),
        ),
        if (_collections.isNotEmpty)
          ListTile(
            leading: Icon(
              !_everything
                  ? Icons.radio_button_checked
                  : Icons.radio_button_unchecked,
            ),
            onTap: () => setState(() => _everything = false),
            title: const Text('Only some collections'),
          ),
        if (!_everything)
          for (final c in _collections)
            Padding(
              padding: EdgeInsets.only(left: 16.0 * c.depth),
              child: CheckboxListTile(
                dense: true,
                value: _picked.contains(c.key),
                onChanged: (v) => setState(
                  () => v == true ? _picked.add(c.key) : _picked.remove(c.key),
                ),
                title: Text(c.name),
                secondary: Text('${c.itemCount}'),
              ),
            ),
      ],
    ),
  );

  Widget _progressBody() {
    final p = _progress;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(p.phase, maxLines: 2, overflow: TextOverflow.ellipsis),
        const SizedBox(height: 12),
        LinearProgressIndicator(value: p.total > 0 ? p.done / p.total : null),
        if (p.total > 0)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text('${p.done} of ${p.total}'),
          ),
      ],
    );
  }
}
