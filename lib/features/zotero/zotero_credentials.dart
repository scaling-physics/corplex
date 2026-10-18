import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../lock/biometric_store.dart';

class ZoteroCredentials {
  const ZoteroCredentials(this.userId, this.apiKey);
  final String userId;
  final String apiKey;
}

/// The Zotero user id and API key live in the device's secure storage:
/// never in the database, so never synced or backed up.
class ZoteroCredentialStore {
  ZoteroCredentialStore(this._slot);

  final SecretSlot _slot;

  static const _idKey = 'zotero.userId';
  static const _apiKey = 'zotero.apiKey';

  Future<ZoteroCredentials?> read() async {
    final id = await _slot.read(_idKey);
    final key = await _slot.read(_apiKey);
    if (id == null || key == null || id.isEmpty || key.isEmpty) return null;
    return ZoteroCredentials(id, key);
  }

  Future<void> save(ZoteroCredentials c) async {
    await _slot.write(_idKey, c.userId);
    await _slot.write(_apiKey, c.apiKey);
  }

  Future<void> forget() async {
    await _slot.delete(_idKey);
    await _slot.delete(_apiKey);
  }
}

final zoteroCredentialStoreProvider = Provider<ZoteroCredentialStore>(
  (ref) => ZoteroCredentialStore(SecureStorageSlot()),
);
