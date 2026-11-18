import 'dart:convert';
import 'dart:io';

import 'package:cryptography/cryptography.dart';
import 'package:http/http.dart' as http;

import '../util/hash.dart';
import '../util/json_util.dart';

/// Ed25519 public key that signs update manifests (private key is kept by
/// the owner / CI secret UPDATE_SIGNING_KEY – never in the repository).
const updatePublicKeyB64 = String.fromEnvironment('WMS_UPDATE_PUBKEY', defaultValue: 'REPLACED_AT_BUILD');

class UpdateAsset {
  final String url, sha256;
  final int size;
  UpdateAsset(this.url, this.sha256, this.size);
}

class UpdateInfo {
  final String version;
  final int build;
  final String notes;
  final int minDataVersion; // project format compatibility for rollback
  final UpdateAsset? windows, android;
  UpdateInfo(this.version, this.build, this.notes, this.minDataVersion, this.windows, this.android);
}

class UpdateException implements Exception {
  final String message;
  UpdateException(this.message);
  @override
  String toString() => message;
}

int compareVersions(String a, String b) {
  final pa = a.split(RegExp(r'[.+]')).map((e) => int.tryParse(e) ?? 0).toList();
  final pb = b.split(RegExp(r'[.+]')).map((e) => int.tryParse(e) ?? 0).toList();
  for (var i = 0; i < 4; i++) {
    final x = i < pa.length ? pa[i] : 0, y = i < pb.length ? pb[i] : 0;
    if (x != y) return x.compareTo(y);
  }
  return 0;
}

/// Secure updater: signed manifest (Ed25519) + SHA-256 verified download.
class Updater {
  final http.Client client;
  final String manifestUrl;
  final List<int> publicKey;
  Updater({required this.manifestUrl, required this.publicKey, http.Client? client}) : client = client ?? http.Client();

  /// Verifies `{payload: base64(json), signature: base64(ed25519)}`.
  static Future<Map<String, dynamic>> verifyManifest(String body, List<int> publicKey) async {
    final j = jsonDecode(body) as Map<String, dynamic>;
    final payload = base64Decode(js(j['payload']));
    final sig = base64Decode(js(j['signature']));
    final ok = await Ed25519().verify(payload, signature: Signature(sig, publicKey: SimplePublicKey(publicKey, type: KeyPairType.ed25519)));
    if (!ok) throw UpdateException('Podpis manifestu aktualizacji jest nieprawidłowy – aktualizacja odrzucona');
    return jsonDecode(utf8.decode(payload)) as Map<String, dynamic>;
  }

  static Future<String> signManifest(Map<String, dynamic> manifest, SimpleKeyPair key) async {
    final payload = utf8.encode(jsonEncode(manifest));
    final sig = await Ed25519().sign(payload, keyPair: key);
    return const JsonEncoder.withIndent('  ').convert({'payload': base64Encode(payload), 'signature': base64Encode(sig.bytes)});
  }

  Future<UpdateInfo?> check(String currentVersion) async {
    final r = await client.get(Uri.parse(manifestUrl));
    if (r.statusCode != 200) throw UpdateException('Serwer aktualizacji zwrócił HTTP ${r.statusCode}');
    final m = await verifyManifest(r.body, publicKey);
    final v = js(m['version']);
    if (compareVersions(v, currentVersion) <= 0) return null;
    UpdateAsset? asset(Object? o) {
      final a = jm(o);
      return a.isEmpty ? null : UpdateAsset(js(a['url']), js(a['sha256']).toLowerCase(), ji(a['size']));
    }

    return UpdateInfo(v, ji(m['build']), js(m['notes']), ji(m['minDataVersion'], 1), asset(m['windows']), asset(m['android']));
  }

  /// Downloads and verifies SHA-256; deletes the file on mismatch.
  Future<File> download(UpdateAsset a, String dest, {void Function(int got, int total)? onProgress}) async {
    if (!a.url.startsWith('https://')) throw UpdateException('Aktualizacje są pobierane wyłącznie przez HTTPS');
    final req = http.Request('GET', Uri.parse(a.url));
    final resp = await client.send(req);
    if (resp.statusCode != 200) throw UpdateException('Pobieranie aktualizacji: HTTP ${resp.statusCode}');
    final f = File(dest);
    await f.parent.create(recursive: true);
    final sink = f.openWrite();
    var got = 0;
    await for (final c in resp.stream) {
      sink.add(c);
      got += c.length;
      onProgress?.call(got, a.size > 0 ? a.size : (resp.contentLength ?? 0));
    }
    await sink.close();
    final sha = await sha256File(f);
    if (sha != a.sha256) {
      await f.delete();
      throw UpdateException('Suma SHA-256 pobranego pliku nie zgadza się – plik usunięto');
    }
    return f;
  }
}
