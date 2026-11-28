import 'dart:isolate';

import 'package:flutter/foundation.dart';
import 'package:workmanager/workmanager.dart';

import '../app_services.dart';
import 'export.dart';
import 'key_backup.dart';

/// Settings → Backup → Back up every day: a complete export (notes, chats, the blocker rules and, when a passphrase is set,
/// the API keys encrypted with it) written to Downloads/ReelBot/Backups once a day, at midnight, one file per day.
class AutoBackup {
  static const folder = 'Backups';
  static const _on = 'auto_backup', _last = 'auto_backup_last';
  static const task = 'backup-midnight';

  static String _two(int v) => v.toString().padLeft(2, '0');
  static String day(DateTime d) => '${d.year}-${_two(d.month)}-${_two(d.day)}';

  /// `backup-2026-11-29.json`: a second backup on the same day replaces that day's file.
  static String fileName(DateTime d) => 'backup-${day(d)}.json';

  static DateTime nextMidnight(DateTime now) => DateTime(now.year, now.month, now.day + 1);

  /// Today's backup is still to be made.
  static bool due(String? lastDay, DateTime now) => lastDay != day(now);

  static Future<bool> isOn(AppServices s) => s.keys.flag(_on);

  /// Turns it on (making today's backup now) or off. [passphrase] encrypts the API keys; null leaves them out.
  static Future<void> setOn(AppServices s, bool on, {String? passphrase}) async {
    await s.keys.setFlagTo(_on, on);
    await s.keys.setAutoBackupPassphrase(on ? passphrase : null);
    if (!on) {
      await Workmanager().cancelByTag(task);
      return;
    }
    await backup(s);
    await schedule();
  }

  /// Writes today's file and remembers the day.
  static Future<String> backup(AppServices s, {DateTime? at}) async {
    final now = at ?? DateTime.now();
    final pass = await s.keys.autoBackupPassphrase;
    Map<String, Object?>? keys;
    if (pass != null && pass.isNotEmpty) {
      final all = await s.keys.all();
      keys = await Isolate.run(() => KeyBackup.encrypt(all, pass));
    }
    final name = fileName(now);
    await s.bridge.saveDownload(
      name,
      exportJson(await s.library.reels(), await s.library.chats(), keys, await s.library.noteChats(), await s.features.exportExtras(s)),
      folder: folder,
    );
    await s.keys.writeLock(_last, day(now));
    return name;
  }

  /// From the background (the midnight task, and the 15-minute task as the fallback when the phone held the midnight one back).
  static Future<void> inBackground(AppServices s) async {
    if (!await isOn(s)) return;
    try {
      if (due(await s.keys.readLock(_last), DateTime.now())) await backup(s);
    } on Object catch (e) {
      debugPrint('Daily backup failed: $e');
    }
    await schedule();
  }

  /// One task for the next 00:00, named by its day so the one running now can book tomorrow's without cancelling itself.
  static Future<void> schedule() async {
    try {
      final now = DateTime.now();
      final at = nextMidnight(now);
      await Workmanager().registerOneOffTask(
        'backup-${day(at)}',
        task,
        tag: task,
        initialDelay: at.difference(now),
        existingWorkPolicy: ExistingWorkPolicy.keep,
      );
    } on Object catch (e) {
      debugPrint('Daily backup not scheduled: $e');
    }
  }
}
