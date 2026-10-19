import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../data/database.dart';
import '../../data/database_provider.dart';
import '../../l10n/l10n.dart';
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
  ZoteroProgress _progress = const ZoteroProgress(ZoteroPhase.library);
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
      setState(() => _error = context.l10n.zoteroEnterBoth);
      return;
    }
    if (!RegExp(r'^\d+$').hasMatch(c.userId)) {
      setState(() => _error = context.l10n.zoteroUserIdNumber);
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
        _error = e.messageFor(context.l10n);
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
        _error = e.messageFor(context.l10n);
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
        _error = context.l10n.zoteroImportFailed(e.messageFor(context.l10n));
        _stage = e.problem == ZoteroProblem.badKey
            ? _Stage.connect
            : _Stage.failed;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final l10n = context.l10n;
    final (title, body, actions) = switch (_stage) {
      _Stage.loading => (
        l10n.zoteroTitle,
        const Center(
          heightFactor: 2,
          child: CircularProgressIndicator.adaptive(),
        ),
        <Widget>[],
      ),
      _Stage.connect => (
        l10n.zoteroConnectTitle,
        _connectBody(scheme),
        [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(l10n.commonCancel),
          ),
          FilledButton(onPressed: _connect, child: Text(l10n.zoteroConnect)),
        ],
      ),
      _Stage.choose => (
        l10n.zoteroImportTitle,
        _chooseBody(),
        [
          TextButton(onPressed: _forget, child: Text(l10n.zoteroForgetKey)),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(l10n.commonCancel),
          ),
          FilledButton(
            onPressed: _everything || _picked.isNotEmpty ? _import : null,
            child: Text(l10n.zoteroImport),
          ),
        ],
      ),
      _Stage.importing => (
        l10n.zoteroImporting,
        _progressBody(),
        [
          TextButton(
            onPressed: _cancel ? null : () => setState(() => _cancel = true),
            child: Text(_cancel ? l10n.zoteroStopping : l10n.commonCancel),
          ),
        ],
      ),
      _Stage.done => (
        _summary!.cancelled ? l10n.zoteroStopped : l10n.commonDone,
        Text(_summary!.messageFor(l10n)),
        [
          FilledButton(
            onPressed: () => Navigator.pop(context),
            child: Text(l10n.commonClose),
          ),
        ],
      ),
      _Stage.failed => (
        l10n.zoteroTitle,
        Text(_error ?? l10n.zoteroSomethingWrong),
        [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(l10n.commonClose),
          ),
          if (_creds != null)
            FilledButton(
              onPressed: _loadCollections,
              child: Text(l10n.commonTryAgain),
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
        Text(context.l10n.zoteroKeyHelp),
        TextButton.icon(
          onPressed: () => launchUrl(
            Uri.https('www.zotero.org', '/settings/keys'),
            mode: LaunchMode.externalApplication,
          ),
          icon: const Icon(Icons.open_in_new, size: 18),
          label: Text(context.l10n.zoteroOpenKeys),
        ),
        TextField(
          controller: _id,
          keyboardType: TextInputType.number,
          decoration: InputDecoration(labelText: context.l10n.zoteroUserId),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _key,
          obscureText: true,
          autocorrect: false,
          enableSuggestions: false,
          decoration: InputDecoration(labelText: context.l10n.zoteroApiKey),
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
          title: Text(context.l10n.zoteroEverything),
          subtitle: Text(context.l10n.zoteroEverythingHint),
        ),
        if (_collections.isNotEmpty)
          ListTile(
            leading: Icon(
              !_everything
                  ? Icons.radio_button_checked
                  : Icons.radio_button_unchecked,
            ),
            onTap: () => setState(() => _everything = false),
            title: Text(context.l10n.zoteroSomeCollections),
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
        Text(
          switch (p.phase) {
            ZoteroPhase.library => context.l10n.zoteroReadingLibrary,
            ZoteroPhase.items => context.l10n.zoteroReadingItems,
            ZoteroPhase.attachments => context.l10n.zoteroReadingAttachments,
            ZoteroPhase.importing => context.l10n.zoteroImportingItem(p.title),
            ZoteroPhase.done => context.l10n.commonDone,
          },
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        const SizedBox(height: 12),
        LinearProgressIndicator(value: p.total > 0 ? p.done / p.total : null),
        if (p.total > 0)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(context.l10n.zoteroProgress(p.done, p.total)),
          ),
      ],
    );
  }
}
