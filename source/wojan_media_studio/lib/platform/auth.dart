import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';

/// OAuth configuration injected at BUILD time (CI secrets → --dart-define).
/// Nothing secret is stored in the repository. End users configure nothing.
class OAuthConfig {
  static const desktopClientId = String.fromEnvironment('WMS_GOOGLE_DESKTOP_CLIENT_ID');
  // Google classifies desktop "client secrets" as non-confidential, but we
  // still keep it out of the repo and inject it from CI secrets.
  static const desktopClientSecret = String.fromEnvironment('WMS_GOOGLE_DESKTOP_CLIENT_SECRET');
  static const serverClientId = String.fromEnvironment('WMS_GOOGLE_SERVER_CLIENT_ID');
  static bool get configured => Platform.isAndroid ? serverClientId.isNotEmpty || true : desktopClientId.isNotEmpty;
}

const scopeDriveAppData = 'https://www.googleapis.com/auth/drive.appdata';
const scopeYouTubeUpload = 'https://www.googleapis.com/auth/youtube.upload';
const scopeYouTubeRead = 'https://www.googleapis.com/auth/youtube.readonly';
const scopeEmail = 'email';

class AuthException implements Exception {
  final String message;
  AuthException(this.message);
  @override
  String toString() => message;
}

/// Google account session: secure token storage (Android Keystore via
/// EncryptedSharedPreferences / Windows DPAPI Credential store).
class GoogleAuth {
  final _storage = const FlutterSecureStorage();
  String? email;
  String? _access;
  DateTime? _expiry;
  final Set<String> _grantedScopes = {};
  bool _androidInit = false;

  bool get signedIn => email != null;

  Future<void> restore() async {
    email = await _storage.read(key: 'google_email');
    final s = await _storage.read(key: 'google_scopes');
    if (s != null) _grantedScopes.addAll(s.split(' ').where((e) => e.isNotEmpty));
    if (Platform.isAndroid && email != null) {
      await _initAndroid();
      try {
        await GoogleSignIn.instance.attemptLightweightAuthentication();
      } catch (_) {}
    }
  }

  bool hasScope(String s) => _grantedScopes.contains(s);

  Future<void> _initAndroid() async {
    if (_androidInit) return;
    await GoogleSignIn.instance.initialize(serverClientId: OAuthConfig.serverClientId.isEmpty ? null : OAuthConfig.serverClientId);
    _androidInit = true;
  }

  /// Interactive sign-in requesting [scopes] (incremental authorisation).
  Future<void> signIn(List<String> scopes) async {
    if (Platform.isAndroid) {
      await _initAndroid();
      final acc = await GoogleSignIn.instance.authenticate(scopeHint: scopes);
      final authz = await acc.authorizationClient.authorizeScopes(scopes);
      email = acc.email;
      _access = authz.accessToken;
      _expiry = DateTime.now().add(const Duration(minutes: 50));
    } else {
      await _desktopSignIn(scopes);
    }
    _grantedScopes.addAll(scopes);
    await _storage.write(key: 'google_email', value: email);
    await _storage.write(key: 'google_scopes', value: _grantedScopes.join(' '));
  }

  /// Returns a valid access token (refreshing silently when possible).
  Future<String> accessToken({bool forceRefresh = false, List<String> scopes = const [scopeDriveAppData]}) async {
    if (!forceRefresh && _access != null && _expiry != null && DateTime.now().isBefore(_expiry!)) return _access!;
    if (Platform.isAndroid) {
      await _initAndroid();
      final a = await GoogleSignIn.instance.authorizationClient.authorizationForScopes(scopes);
      if (a == null) throw AuthException('Wymaga ponownego logowania do konta Google');
      _access = a.accessToken;
      _expiry = DateTime.now().add(const Duration(minutes: 50));
      return _access!;
    }
    final refresh = await _storage.read(key: 'google_refresh');
    if (refresh == null) throw AuthException('Wymaga ponownego logowania do konta Google');
    final r = await http.post(Uri.parse('https://oauth2.googleapis.com/token'), body: {
      'client_id': OAuthConfig.desktopClientId,
      if (OAuthConfig.desktopClientSecret.isNotEmpty) 'client_secret': OAuthConfig.desktopClientSecret,
      'grant_type': 'refresh_token',
      'refresh_token': refresh,
    });
    if (r.statusCode != 200) {
      if (r.body.contains('invalid_grant')) {
        await _storage.delete(key: 'google_refresh');
        throw AuthException('Sesja wygasła lub dostęp cofnięto – zaloguj się ponownie');
      }
      throw AuthException('Odświeżenie tokenu nie powiodło się (HTTP ${r.statusCode})');
    }
    final j = jsonDecode(r.body) as Map<String, dynamic>;
    _access = j['access_token'] as String;
    _expiry = DateTime.now().add(Duration(seconds: (j['expires_in'] as num? ?? 3600).toInt() - 120));
    return _access!;
  }

  String _b64(List<int> b) => base64UrlEncode(b).replaceAll('=', '');

  /// Desktop OAuth 2.0 for installed apps: loopback redirect + PKCE (S256),
  /// in the system browser (no embedded webview).
  Future<void> _desktopSignIn(List<String> scopes) async {
    if (OAuthConfig.desktopClientId.isEmpty) {
      throw AuthException('Ta kompilacja nie zawiera identyfikatora klienta OAuth Google (WMS_GOOGLE_DESKTOP_CLIENT_ID). Zobacz docs/SYNC_ARCHITECTURE.md – konfiguracja jednorazowa właściciela.');
    }
    final rnd = Random.secure();
    final verifier = _b64(List.generate(48, (_) => rnd.nextInt(256)));
    final challenge = _b64(sha256.convert(ascii.encode(verifier)).bytes);
    final state = _b64(List.generate(16, (_) => rnd.nextInt(256)));
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final redirect = 'http://127.0.0.1:${server.port}';
    final url = Uri.https('accounts.google.com', '/o/oauth2/v2/auth', {
      'client_id': OAuthConfig.desktopClientId,
      'redirect_uri': redirect,
      'response_type': 'code',
      'scope': {...scopes, scopeEmail, ..._grantedScopes}.join(' '),
      'code_challenge': challenge,
      'code_challenge_method': 'S256',
      'state': state,
      'access_type': 'offline',
      'prompt': 'consent',
      'include_granted_scopes': 'true',
    });
    if (!await launchUrl(url, mode: LaunchMode.externalApplication)) {
      await server.close(force: true);
      throw AuthException('Nie można otworzyć przeglądarki');
    }
    String? code;
    try {
      final req = await server.first.timeout(const Duration(minutes: 5));
      final q = req.uri.queryParameters;
      final ok = q['state'] == state && q['code'] != null;
      req.response
        ..statusCode = 200
        ..headers.contentType = ContentType.html
        ..write('<html><body style="font-family:sans-serif;background:#16181d;color:#eee;text-align:center;padding-top:80px">'
            '<h2>WoJan Media Studio</h2><p>${ok ? 'Logowanie zakończone. Możesz zamknąć to okno.' : 'Logowanie nie powiodło się.'}</p></body></html>');
      await req.response.close();
      if (!ok) throw AuthException(q['error'] ?? 'Nieprawidłowa odpowiedź logowania');
      code = q['code'];
    } on TimeoutException {
      throw AuthException('Upłynął czas logowania');
    } finally {
      await server.close(force: true);
    }
    final r = await http.post(Uri.parse('https://oauth2.googleapis.com/token'), body: {
      'client_id': OAuthConfig.desktopClientId,
      if (OAuthConfig.desktopClientSecret.isNotEmpty) 'client_secret': OAuthConfig.desktopClientSecret,
      'code': code,
      'code_verifier': verifier,
      'grant_type': 'authorization_code',
      'redirect_uri': redirect,
    });
    if (r.statusCode != 200) throw AuthException('Wymiana kodu nie powiodła się: ${r.body}');
    final j = jsonDecode(r.body) as Map<String, dynamic>;
    _access = j['access_token'] as String;
    _expiry = DateTime.now().add(Duration(seconds: (j['expires_in'] as num? ?? 3600).toInt() - 120));
    if (j['refresh_token'] != null) await _storage.write(key: 'google_refresh', value: j['refresh_token'] as String);
    // email from userinfo (scope email)
    final ui = await http.get(Uri.parse('https://openidconnect.googleapis.com/v1/userinfo'), headers: {'Authorization': 'Bearer $_access'});
    if (ui.statusCode == 200) email = (jsonDecode(ui.body) as Map)['email'] as String?;
    email ??= 'konto Google';
  }

  Future<void> signOut({bool revoke = true}) async {
    try {
      if (Platform.isAndroid) {
        await _initAndroid();
        revoke ? await GoogleSignIn.instance.disconnect() : await GoogleSignIn.instance.signOut();
      } else if (revoke) {
        final t = await _storage.read(key: 'google_refresh');
        if (t != null) await http.post(Uri.parse('https://oauth2.googleapis.com/revoke'), body: {'token': t});
      }
    } catch (_) {}
    await _storage.delete(key: 'google_refresh');
    await _storage.delete(key: 'google_email');
    await _storage.delete(key: 'google_scopes');
    email = null;
    _access = null;
    _grantedScopes.clear();
  }
}
