// Tests for optional password protection on `.kmb` backups.
//
// Background: the export was labelled "Encrypted Backup" in the UI and the
// share text invited the merchant to send it over WhatsApp — while the file
// was a magic header + JSON manifest + **raw SQLite bytes**. Anyone receiving
// it could open the entire shop database, including every customer phone
// number and khata balance, in any SQLite viewer.
//
// The format now supports AES-256-GCM under a PBKDF2 key (V2), with the
// original plain format (V1) still readable forever — every backup a merchant
// already holds is V1, and a "security improvement" that stranded those would
// be a far worse bug than the one it fixed.
//
// Raised timeout, deliberately: the key derivation is 150k PBKDF2 iterations —
// being slow is the security property under test, not an accident. Each test
// runs several derivations, and `flutter test` runs the whole suite's files
// concurrently, so on a loaded machine these comfortably exceed the 30s
// default. Do NOT "fix" a timeout here by weakening _kdfIterations.
@Timeout(Duration(minutes: 5))
library;

import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:kamaiplus_pos/core/database/local_database.dart';
import 'package:kamaiplus_pos/models/models.dart';
import 'package:kamaiplus_pos/services/backup_restore_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('kmb_test_');

    // `createBackupPackage` writes through path_provider, which has no
    // implementation in a plain Dart test host. Point it at this test's own
    // temp directory rather than stubbing out the method under test.
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (call) async => tempDir.path,
    );

    await LocalDatabase.instance
        .switchUser('backup_enc_test_${DateTime.now().microsecondsSinceEpoch}');
    // Something identifiable to prove a restore really brought data back.
    await LocalDatabase.instance.upsertCustomer(CustomerModel(
      id: 'cust_secret_1',
      businessId: 'biz_backup_test',
      name: 'Ramesh Kirana',
      phone: '9876543210',
      currentBalancePaise: 125000,
    ));
  });

  tearDown(() async {
    await LocalDatabase.instance.closeDatabase();
    try {
      await tempDir.delete(recursive: true);
    } catch (_) {}
  });

  /// Copies the package out of the app temp dir so a later export in the same
  /// test cannot overwrite it (the filename is store name + date).
  Future<File> keep(File src, String name) async {
    final dest = File('${tempDir.path}${Platform.pathSeparator}$name');
    await dest.writeAsBytes(await src.readAsBytes(), flush: true);
    return dest;
  }

  Future<String> headerOf(File f) async {
    final bytes = await f.readAsBytes();
    return String.fromCharCodes(bytes.take(20));
  }

  group('Plain (V1) packages', () {
    test('no password writes a V1 package and restores without one', () async {
      final pkg = await keep(await BackupRestoreService.instance.createBackupPackage(), 'plain.kmb');

      expect(await headerOf(pkg), startsWith('KAMAI_POS_BACKUP_V1'));
      expect(await BackupRestoreService.instance.isBackupEncrypted(pkg), isFalse);

      final res = await BackupRestoreService.instance.restoreFromBackupFile(pkg);
      expect(res.success, isTrue, reason: res.message);
      expect(res.needsPassword, isFalse);

      final customers = await LocalDatabase.instance.getAllCustomers();
      expect(customers.any((c) => c.phone == '9876543210'), isTrue);
    });

    test('a V1 package really does expose the raw database (why V2 exists)', () async {
      final pkg = await keep(await BackupRestoreService.instance.createBackupPackage(), 'plain2.kmb');
      final bytes = await pkg.readAsBytes();

      // SQLite's own file magic, sitting in the clear inside the "backup".
      final text = String.fromCharCodes(bytes);
      expect(text.contains('SQLite format 3'), isTrue,
          reason: 'V1 is plaintext by definition — this is the exposure V2 closes');
    });
  });

  group('Encrypted (V2) packages', () {
    test('a password writes a V2 package and round-trips back', () async {
      final pkg = await keep(
        await BackupRestoreService.instance.createBackupPackage(password: 'kirana-1234'),
        'locked.kmb',
      );

      expect(await headerOf(pkg), startsWith('KAMAI_POS_BACKUP_V2'));
      expect(await BackupRestoreService.instance.isBackupEncrypted(pkg), isTrue);

      final res = await BackupRestoreService.instance
          .restoreFromBackupFile(pkg, password: 'kirana-1234');
      expect(res.success, isTrue, reason: res.message);

      final customers = await LocalDatabase.instance.getAllCustomers();
      expect(customers.any((c) => c.phone == '9876543210'), isTrue);
    });

    test('the database is genuinely unreadable in the file', () async {
      final pkg = await keep(
        await BackupRestoreService.instance.createBackupPackage(password: 'kirana-1234'),
        'locked2.kmb',
      );
      final text = String.fromCharCodes(await pkg.readAsBytes());

      expect(text.contains('SQLite format 3'), isFalse,
          reason: 'the SQLite header must not survive into an encrypted package');
      expect(text.contains('9876543210'), isFalse,
          reason: "a customer's phone number must not be readable in the file");
      // The manifest is deliberately left in the clear so the restore screen
      // can preview a file before asking for its password.
      expect(text.contains('products_count'), isTrue);
    });

    test('restoring without a password asks instead of failing blindly', () async {
      final pkg = await keep(
        await BackupRestoreService.instance.createBackupPackage(password: 'kirana-1234'),
        'locked3.kmb',
      );

      final res = await BackupRestoreService.instance.restoreFromBackupFile(pkg);
      expect(res.success, isFalse);
      expect(res.needsPassword, isTrue, reason: 'the UI needs to know to prompt');
      // The preview still works without the password.
      expect(res.metadata, isNotNull);
    });

    test('a wrong password is rejected and never overwrites the live database', () async {
      final pkg = await keep(
        await BackupRestoreService.instance.createBackupPackage(password: 'kirana-1234'),
        'locked4.kmb',
      );

      final res = await BackupRestoreService.instance
          .restoreFromBackupFile(pkg, password: 'wrong-password');
      expect(res.success, isFalse);
      expect(res.needsPassword, isTrue);

      // GCM authenticates, so this fails at decryption rather than handing
      // back garbage that would then be written over the merchant's database.
      final customers = await LocalDatabase.instance.getAllCustomers();
      expect(customers.any((c) => c.phone == '9876543210'), isTrue,
          reason: 'the live database must be untouched after a failed restore');
    });

    test('a tampered encrypted package is rejected', () async {
      final pkg = await keep(
        await BackupRestoreService.instance.createBackupPackage(password: 'kirana-1234'),
        'tampered.kmb',
      );
      final bytes = Uint8List.fromList(await pkg.readAsBytes());
      // Flip a byte deep inside the ciphertext.
      bytes[bytes.length - 40] = bytes[bytes.length - 40] ^ 0xFF;
      await pkg.writeAsBytes(bytes, flush: true);

      final res = await BackupRestoreService.instance
          .restoreFromBackupFile(pkg, password: 'kirana-1234');
      expect(res.success, isFalse);
    });

    test('two exports of the same data with the same password differ', () async {
      // A fresh random salt and nonce every time. Identical ciphertext would
      // leak that nothing changed between two backups.
      final a = await keep(
        await BackupRestoreService.instance.createBackupPackage(password: 'same-password'),
        'a.kmb',
      );
      final b = await keep(
        await BackupRestoreService.instance.createBackupPackage(password: 'same-password'),
        'b.kmb',
      );

      final ba = await a.readAsBytes();
      final bb = await b.readAsBytes();
      // Compare the tail, past the manifest (whose export timestamp differs anyway).
      final tailA = ba.sublist(ba.length - 256);
      final tailB = bb.sublist(bb.length - 256);
      expect(tailA, isNot(equals(tailB)));
    });
  });

  group('Rejecting things that are not backups', () {
    test('a random file is not mistaken for a backup', () async {
      final junk = File('${tempDir.path}${Platform.pathSeparator}junk.kmb');
      await junk.writeAsBytes(List<int>.filled(4096, 7), flush: true);

      expect(await BackupRestoreService.instance.isBackupEncrypted(junk), isFalse);
      final res = await BackupRestoreService.instance.restoreFromBackupFile(junk);
      expect(res.success, isFalse);
    });
  });
}
