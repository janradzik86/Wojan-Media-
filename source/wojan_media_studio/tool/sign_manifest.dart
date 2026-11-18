// Usage: dart run tool/sign_manifest.dart <privateSeedBase64> <manifest.json>
// Prints the signed manifest {payload, signature} consumed by the app updater.
// Generate a key pair once with: dart run tool/sign_manifest.dart --keygen
import 'dart:convert';
import 'dart:io';

import 'package:cryptography/cryptography.dart';

Future<void> main(List<String> args) async {
  final ed = Ed25519();
  if (args.isNotEmpty && args.first == '--keygen') {
    final kp = await ed.newKeyPair();
    final seed = await kp.extractPrivateKeyBytes();
    final pub = (await kp.extractPublicKey()).bytes;
    stdout.writeln('PRIVATE (keep secret): ${base64Encode(seed)}');
    stdout.writeln('PUBLIC  (WMS_UPDATE_PUBKEY): ${base64Encode(pub)}');
    return;
  }
  final kp = await ed.newKeyPairFromSeed(base64Decode(args[0]));
  final payload = utf8.encode(await File(args[1]).readAsString());
  final sig = await ed.sign(payload, keyPair: kp);
  stdout.writeln(const JsonEncoder.withIndent('  ').convert({'payload': base64Encode(payload), 'signature': base64Encode(sig.bytes)}));
}
