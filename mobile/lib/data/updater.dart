import 'dart:async';
import 'dart:io';

import 'package:cryptography/cryptography.dart';
import 'package:http/http.dart' as http;

import 'update_check.dart';

/// Where an update may come from: GitHub's release pages and the hosts they hand the file over to.
bool allowedUpdateUrl(Uri u) =>
    u.scheme == 'https' && (u.host == 'github.com' || u.host.endsWith('.githubusercontent.com'));

class UpdateException implements Exception {
  final String message;
  UpdateException(this.message);
  @override
  String toString() => message;
}

/// Downloads the APK of [info] into [dir] and checks it against the release's SHA256SUMS before returning it.
/// A file that does not match, or has no checksum to match, is deleted and never handed to the installer.
Future<File> downloadUpdate(http.Client client, UpdateInfo info, Directory dir, void Function(double) onProgress) async {
  final apkUri = Uri.parse(info.apkUrl);
  final sumsUri = info.sumsUrl == null ? null : Uri.parse(info.sumsUrl!);
  if (!allowedUpdateUrl(apkUri) || sumsUri == null || !allowedUpdateUrl(sumsUri)) {
    throw UpdateException('This release has no verified download.');
  }
  final sums = await client.get(sumsUri).timeout(const Duration(seconds: 20));
  if (sums.statusCode != 200) throw UpdateException('Could not read the checksum (HTTP ${sums.statusCode}).');
  String? want;
  for (final line in sums.body.split('\n')) {
    final parts = line.trim().split(RegExp(r'\s+'));
    if (parts.length >= 2 && parts.last.replaceFirst('*', '') == info.apkName) want = parts.first.toLowerCase();
  }
  if (want == null) throw UpdateException('The release has no checksum for ${info.apkName}.');

  await dir.create(recursive: true);
  final file = File('${dir.path}/reel-analyser.apk');
  if (await file.exists()) await file.delete();
  final res = await client.send(http.Request('GET', apkUri)).timeout(const Duration(seconds: 30));
  final finalUrl = res.request?.url ?? apkUri;
  if (res.statusCode != 200 || !allowedUpdateUrl(finalUrl)) {
    throw UpdateException('The download was refused (HTTP ${res.statusCode}).');
  }
  final sink = file.openWrite();
  final hash = Sha256().newHashSink();
  var got = 0;
  final total = res.contentLength ?? 0;
  try {
    await for (final chunk in res.stream.timeout(const Duration(seconds: 30))) {
      sink.add(chunk);
      hash.add(chunk);
      got += chunk.length;
      if (total > 0) onProgress(got / total);
    }
    await sink.close();
    hash.close();
    final got256 = (await hash.hash()).bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    if (got256 != want) throw UpdateException('The download is damaged or not the real release (checksum differs).');
  } catch (e) {
    try {
      await sink.close();
    } on Object {
      // already closed
    }
    if (await file.exists()) await file.delete();
    rethrow;
  }
  return file;
}
