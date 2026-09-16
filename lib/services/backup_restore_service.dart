import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:pointycastle/export.dart' as pc;
import 'package:file_picker/file_picker.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import '../core/database/local_database.dart';
import 'google_drive_backup_service.dart';

class BackupMetadata {
  final String formatVersion;
  final String storeName;
  final String exportDate;
  final int productsCount;
  final int salesCount;
  final int customersCount;
  final String checksum;
  final int dbSizeBytes;

  BackupMetadata({
    required this.formatVersion,
    required this.storeName,
    required this.exportDate,
    required this.productsCount,
    required this.salesCount,
    required this.customersCount,
    required this.checksum,
    required this.dbSizeBytes,
  });

  Map<String, dynamic> toMap() => {
        'format_version': formatVersion,
        'store_name': storeName,
        'export_date': exportDate,
        'products_count': productsCount,
        'sales_count': salesCount,
        'customers_count': customersCount,
        'checksum': checksum,
        'db_size_bytes': dbSizeBytes,
      };

  factory BackupMetadata.fromMap(Map<String, dynamic> map) => BackupMetadata(
        formatVersion: map['format_version'] ?? '1.0',
        storeName: map['store_name'] ?? 'Store',
        exportDate: map['export_date'] ?? '',
        productsCount: map['products_count'] ?? 0,
        salesCount: map['sales_count'] ?? 0,
        customersCount: map['customers_count'] ?? 0,
        checksum: map['checksum'] ?? '',
        dbSizeBytes: map['db_size_bytes'] ?? 0,
      );
}

class BackupRestoreResult {
  final bool success;
  final String message;
  final BackupMetadata? metadata;

  /// The restore failed only because the file is password protected and no
  /// (or the wrong) password was supplied — so the UI should ask, rather than
  /// report a dead end.
  final bool needsPassword;

  BackupRestoreResult({
    required this.success,
    required this.message,
    this.metadata,
    this.needsPassword = false,
  });
}

/// A `.kmb` file split into manifest and payload, for either format.
class _ParsedPackage {
  final BackupMetadata metadata;
  final bool isEncrypted;

  /// Raw SQLite bytes for V1; salt + nonce + AES-GCM ciphertext for V2.
  final Uint8List payload;

  _ParsedPackage({
    required this.metadata,
    required this.isEncrypted,
    required this.payload,
  });
}

class BackupRestoreService {
  BackupRestoreService._();
  static final BackupRestoreService instance = BackupRestoreService._();

  /// Plain, unencrypted package. Still written when the merchant declines a
  /// password, and still READ forever — every backup produced before password
  /// protection existed is V1, and those must keep restoring.
  static const String _magicHeaderV1 = 'KAMAI_POS_BACKUP_V1\n';

  /// Password-protected package: same plaintext manifest, AES-256-GCM database.
  static const String _magicHeaderV2 = 'KAMAI_POS_BACKUP_V2\n';

  // PBKDF2-HMAC-SHA256 → 32-byte AES key. 150k iterations is a deliberate
  // ~0.5s on the low-end Android phones this app targets (Redmi 6 class):
  // slow enough to make offline guessing expensive, fast enough that a
  // shopkeeper does not think the restore has hung.
  static const int _kdfIterations = 150000;
  static const int _saltLength = 16;
  static const int _gcmNonceLength = 12;
  static const int _gcmTagLength = 16;

  // ===========================================================================
  // CRYPTO — AES-256-GCM with a PBKDF2-derived key, via pointycastle
  // (pure Dart: no native code, so no extra platform build risk).
  //
  // GCM rather than CBC on purpose: it authenticates as well as encrypts, so a
  // wrong password or a tampered file fails loudly at decryption instead of
  // handing back plausible-looking garbage that would then be written over the
  // merchant's live database.
  // ===========================================================================

  static final Random _secureRandom = Random.secure();

  Uint8List _randomBytes(int length) {
    return Uint8List.fromList(
      List<int>.generate(length, (_) => _secureRandom.nextInt(256)),
    );
  }

  Uint8List _deriveKey(String password, Uint8List salt) {
    final derivator = pc.PBKDF2KeyDerivator(pc.HMac(pc.SHA256Digest(), 64))
      ..init(pc.Pbkdf2Parameters(salt, _kdfIterations, 32));
    return derivator.process(Uint8List.fromList(utf8.encode(password)));
  }

  /// One call for both directions — GCM is symmetric, and keeping a single
  /// parameter set here is what stops encrypt and decrypt drifting apart.
  Uint8List _aesGcm(
    Uint8List key,
    Uint8List nonce,
    Uint8List input, {
    required bool forEncryption,
  }) {
    final cipher = pc.GCMBlockCipher(pc.AESEngine())
      ..init(
        forEncryption,
        pc.AEADParameters(
          pc.KeyParameter(key),
          _gcmTagLength * 8,
          nonce,
          Uint8List(0),
        ),
      );
    return cipher.process(input);
  }

  /// Reads the magic header to tell a V1 (plain) package from a V2 (encrypted)
  /// one. Returns null when the file is neither.
  String? _detectHeader(Uint8List bytes) {
    for (final header in [_magicHeaderV1, _magicHeaderV2]) {
      final headerBytes = utf8.encode(header);
      if (bytes.length < headerBytes.length) continue;
      var match = true;
      for (int i = 0; i < headerBytes.length; i++) {
        if (bytes[i] != headerBytes[i]) {
          match = false;
          break;
        }
      }
      if (match) return header;
    }
    return null;
  }

  /// True when this `.kmb` file needs a password to restore.
  Future<bool> isBackupEncrypted(File file) async {
    try {
      // Only the header is needed, so don't pull a 40MB database into memory.
      final head = await file.openRead(0, _magicHeaderV2.length + 8).first;
      return _detectHeader(Uint8List.fromList(head)) == _magicHeaderV2;
    } catch (_) {
      return false;
    }
  }

  /// Creates a single-file `.kmb` backup package from the current SQLite
  /// database.
  ///
  /// Pass a [password] to write an **encrypted V2** package: the manifest
  /// stays readable but the database itself is AES-256-GCM sealed under a
  /// PBKDF2 key. Without one, a plain **V1** package is written — the format
  /// that shipped before password protection existed, and the reason
  /// [restoreFromBackupFile] must keep reading both forever.
  ///
  /// Encryption is offered, not forced, on purpose. The file is only useful to
  /// the merchant who made it, and for this audience a forgotten password is a
  /// far more likely disaster than a stolen backup — there is no recovery path
  /// once the key is lost. The UI states that plainly and lets the shopkeeper
  /// choose.
  ///
  /// **What a V1 package exposes.** Magic header + JSON manifest + raw SQLite
  /// bytes: anyone holding the file can open the whole shop database —
  /// products, every sale, customer phone numbers, every khata balance — in
  /// any SQLite viewer. It was previously described as "encrypted" in the UI
  /// and in the share text, which is precisely the wrong thing to tell someone
  /// about to forward it over WhatsApp.
  ///
  /// **What a V2 package still exposes.** The manifest (store name, item and
  /// sale counts, export date) is deliberately left in the clear so the
  /// restore screen can preview a file before asking for its password. The
  /// sensitive contents — every customer number, balance and transaction —
  /// are inside the encrypted blob.
  Future<File> createBackupPackage({String? password}) async {
    final dbPath = await LocalDatabase.instance.getActiveDatabasePath();
    final dbFile = File(dbPath);
    if (!await dbFile.exists()) {
      throw Exception('Active database file not found on device');
    }

    final dbBytes = await dbFile.readAsBytes();
    final checksum = sha256.convert(dbBytes).toString();

    // Fetch store metadata for backup manifest
    final profile = await LocalDatabase.instance.getStoreProfile();
    final products = await LocalDatabase.instance.getAllProducts();
    final sales = await LocalDatabase.instance.getAllSales();
    final customers = await LocalDatabase.instance.getAllCustomers();

    final bool encrypt = password != null && password.trim().isNotEmpty;

    final metadata = BackupMetadata(
      formatVersion: encrypt ? '2.0' : '1.0',
      storeName: profile.storeName.isNotEmpty ? profile.storeName : 'KamaiPlus_Store',
      exportDate: DateTime.now().toIso8601String(),
      productsCount: products.length,
      salesCount: sales.length,
      customersCount: customers.length,
      // Checksum is always of the PLAINTEXT database, so restore can verify
      // integrity after decrypting and the check means the same thing in both
      // formats.
      checksum: checksum,
      dbSizeBytes: dbBytes.length,
    );

    final metaJson = jsonEncode(metadata.toMap());
    final metaBytes = utf8.encode(metaJson);

    // V1: MAGIC + uint32(metaLen) + meta + raw SQLite bytes
    // V2: MAGIC + uint32(metaLen) + meta + salt(16) + nonce(12) + AES-GCM(db)
    final metaLenBytes = ByteData(4)..setUint32(0, metaBytes.length, Endian.big);

    final builder = BytesBuilder();
    builder.add(utf8.encode(encrypt ? _magicHeaderV2 : _magicHeaderV1));
    builder.add(metaLenBytes.buffer.asUint8List());
    builder.add(metaBytes);

    if (encrypt) {
      final salt = _randomBytes(_saltLength);
      final nonce = _randomBytes(_gcmNonceLength);
      final key = _deriveKey(password.trim(), salt);
      builder.add(salt);
      builder.add(nonce);
      builder.add(_aesGcm(key, nonce, dbBytes, forEncryption: true));
    } else {
      builder.add(dbBytes);
    }

    final safeStoreName = metadata.storeName.replaceAll(RegExp(r'[^a-zA-Z0-9_]'), '_');
    final dateStr = DateTime.now().toIso8601String().split('T').first;
    final tempDir = await getTemporaryDirectory();
    final outputFile = File(p.join(tempDir.path, 'KamaiPlus_${safeStoreName}_$dateStr.kmb'));
    await outputFile.writeAsBytes(builder.toBytes(), flush: true);

    return outputFile;
  }

  /// 1-Tap Google Drive cloud backup — a real upload to the merchant's Drive.
  ///
  /// This used to just open the Android share sheet and hope the merchant
  /// picked Drive out of it: nothing was ever uploaded, nothing could be
  /// listed, and there was no restore-from-Drive at all, despite the feature
  /// being sold as "Google Drive 1-Tap Cloud Backup". It now uploads over the
  /// Drive REST API under the `drive.file` scope (this app's own files only).
  ///
  /// The share sheet remains the fallback for a merchant who declines the
  /// Drive permission — losing the upload should not mean losing the ability
  /// to get a backup off the phone at all.
  Future<BackupRestoreResult> saveToGoogleDrive({String? password}) async {
    try {
      final file = await createBackupPackage(password: password);
      final fileName = p.basename(file.path);

      final driveId = await GoogleDriveBackupService.instance.uploadBackup(file);
      if (driveId != null) {
        return BackupRestoreResult(
          success: true,
          message: '✓ Uploaded to Google Drive → "KamaiPlus Backups" ($fileName)',
        );
      }

      // ignore: deprecated_member_use
      await Share.shareXFiles(
        [XFile(file.path, mimeType: 'application/octet-stream', name: fileName)],
        subject: 'Save to Google Drive: $fileName',
        text: 'KamaiPlus POS store backup ($fileName). Contains your full shop database — keep it private. Choose "Save to Drive" or "Google Drive" to store in cloud.',
      );
      return BackupRestoreResult(
        success: true,
        message: 'Drive permission not granted — pick Google Drive in the share sheet instead.',
      );
    } catch (e) {
      return BackupRestoreResult(
        success: false,
        message: 'Google Drive backup failed: $e',
      );
    }
  }

  /// Restores directly from a backup sitting in the merchant's Google Drive.
  ///
  /// Downloads to a temp file and then goes through the exact same
  /// [restoreFromBackupFile] path as a local file, so the checksum check and
  /// the password prompt behave identically — there is no second, weaker
  /// restore path to keep in sync.
  Future<BackupRestoreResult> restoreFromDrive(
    String driveFileId, {
    String? password,
  }) async {
    try {
      final tempDir = await getTemporaryDirectory();
      final dest = File(p.join(tempDir.path, 'drive_restore_$driveFileId.kmb'));
      final downloaded =
          await GoogleDriveBackupService.instance.downloadBackup(driveFileId, dest);
      if (downloaded == null) {
        return BackupRestoreResult(
          success: false,
          message: 'Could not download that backup from Google Drive.',
        );
      }
      return await restoreFromBackupFile(downloaded, password: password);
    } catch (e) {
      return BackupRestoreResult(
        success: false,
        message: 'Drive restore failed: $e',
      );
    }
  }

  /// Exports backup and opens native Android sheet to share to Drive, WhatsApp, Files, or Email
  Future<void> shareBackupFile({String? password}) async {
    final file = await createBackupPackage(password: password);
    final fileName = p.basename(file.path);
    // ignore: deprecated_member_use
    await Share.shareXFiles(
      [XFile(file.path, mimeType: 'application/octet-stream', name: fileName)],
      subject: 'KamaiPlus Store Backup: $fileName',
      text: 'KamaiPlus POS store backup ($fileName). Contains your full shop database including customer numbers and khata balances — share it only with yourself. Save to Google Drive or File Manager for safe recovery.',
    );
  }

  /// Verifies and unpacks a .kmb backup file
  Future<BackupMetadata> inspectBackupFile(File file) async {
    final bytes = await file.readAsBytes();
    return _extractMetadataFromBytes(bytes);
  }

  BackupMetadata _extractMetadataFromBytes(Uint8List bytes) {
    return _parsePackage(bytes).metadata;
  }

  /// Splits a `.kmb` file into its manifest and its payload, for either
  /// format. Kept as one parser so V1 and V2 can never disagree about where
  /// the manifest ends and the database begins.
  _ParsedPackage _parsePackage(Uint8List bytes) {
    final header = _detectHeader(bytes);
    if (header == null) {
      throw Exception('Not a valid KamaiPlus backup file (.kmb)');
    }

    final headerBytes = utf8.encode(header);
    if (bytes.length < headerBytes.length + 4) {
      throw Exception('Invalid backup file: file too small or corrupted');
    }

    final metaLenOffset = headerBytes.length;
    final byteData = ByteData.sublistView(bytes, metaLenOffset, metaLenOffset + 4);
    final metaLen = byteData.getUint32(0, Endian.big);

    final metaStart = metaLenOffset + 4;
    final metaEnd = metaStart + metaLen;
    if (bytes.length < metaEnd) {
      throw Exception('Corrupted backup manifest');
    }

    final metaJson = utf8.decode(bytes.sublist(metaStart, metaEnd));
    final metaMap = jsonDecode(metaJson) as Map<String, dynamic>;

    return _ParsedPackage(
      metadata: BackupMetadata.fromMap(metaMap),
      isEncrypted: header == _magicHeaderV2,
      payload: bytes.sublist(metaEnd),
    );
  }

  /// Restores SQLite database from a selected backup file
  Future<BackupRestoreResult> restoreFromBackupFile(
    File backupFile, {
    String? password,
  }) async {
    try {
      final bytes = await backupFile.readAsBytes();
      final pkg = _parsePackage(bytes);
      final metadata = pkg.metadata;

      Uint8List dbBytes;
      if (pkg.isEncrypted) {
        if (password == null || password.trim().isEmpty) {
          return BackupRestoreResult(
            success: false,
            message: 'This backup is password protected. Enter its password to restore.',
            metadata: metadata,
            needsPassword: true,
          );
        }
        final minLength = _saltLength + _gcmNonceLength + _gcmTagLength;
        if (pkg.payload.length < minLength) {
          return BackupRestoreResult(
            success: false,
            message: 'Backup file is truncated or corrupted.',
          );
        }
        final salt = pkg.payload.sublist(0, _saltLength);
        final nonce = pkg.payload.sublist(_saltLength, _saltLength + _gcmNonceLength);
        final cipherText = pkg.payload.sublist(_saltLength + _gcmNonceLength);
        try {
          final key = _deriveKey(password.trim(), salt);
          dbBytes = _aesGcm(key, nonce, cipherText, forEncryption: false);
        } catch (_) {
          // GCM authenticates, so a wrong password fails here rather than
          // producing garbage that would then overwrite the live database.
          return BackupRestoreResult(
            success: false,
            message: 'Wrong password — this backup could not be unlocked.',
            metadata: metadata,
            needsPassword: true,
          );
        }
      } else {
        dbBytes = pkg.payload;
      }

      // Verify SHA-256 integrity — always against the PLAINTEXT database, so
      // the check means the same thing for an encrypted and a plain package.
      final calculatedChecksum = sha256.convert(dbBytes).toString();
      if (calculatedChecksum != metadata.checksum) {
        return BackupRestoreResult(
          success: false,
          message: 'Integrity check failed! Backup file may be corrupted or modified.',
        );
      }

      // Close current DB and write new bytes
      final dbPath = await LocalDatabase.instance.getActiveDatabasePath();
      await LocalDatabase.instance.closeDatabase();

      final targetDbFile = File(dbPath);
      await targetDbFile.writeAsBytes(dbBytes, flush: true);

      // Reload DB and update app data bus
      await LocalDatabase.instance.reloadDatabase();

      return BackupRestoreResult(
        success: true,
        message: '✓ Store restored successfully! Loaded ${metadata.productsCount} products, ${metadata.salesCount} sales, ${metadata.customersCount} customers.',
        metadata: metadata,
      );
    } catch (e) {
      return BackupRestoreResult(
        success: false,
        message: 'Failed to restore backup: $e',
      );
    }
  }

  /// Prompts the user to pick a `.kmb` backup file and restores it.
  ///
  /// [onPasswordNeeded] is called only when the chosen file turns out to be
  /// password protected; return the password, or null to abandon the restore.
  /// Passed as a callback rather than a parameter because the file is chosen
  /// AFTER this is called — there is no way for the caller to know whether a
  /// password will be needed until the merchant has picked something.
  Future<BackupRestoreResult> pickAndRestore({
    Future<String?> Function(BackupMetadata metadata)? onPasswordNeeded,
  }) async {
    try {
      final files = await FilePicker.pickFiles(
        type: FileType.any,
      );

      if (files.isEmpty) {
        return BackupRestoreResult(
          success: false,
          message: 'No backup file selected.',
        );
      }

      final path = files.first.path;
      if (path == null) {
        return BackupRestoreResult(
          success: false,
          message: 'Could not access file path.',
        );
      }

      final selectedFile = File(path);
      var result = await restoreFromBackupFile(selectedFile);

      // Encrypted file: ask once, then retry. Deliberately a single retry
      // rather than a loop — a shopkeeper who mistypes can simply tap Restore
      // again, and looping here would hold the file picker's result hostage
      // to an unbounded prompt.
      if (result.needsPassword && onPasswordNeeded != null) {
        final password = await onPasswordNeeded(
          result.metadata ??
              BackupMetadata(
                formatVersion: '2.0',
                storeName: 'Store',
                exportDate: '',
                productsCount: 0,
                salesCount: 0,
                customersCount: 0,
                checksum: '',
                dbSizeBytes: 0,
              ),
        );
        if (password == null || password.trim().isEmpty) {
          return BackupRestoreResult(
            success: false,
            message: 'Restore cancelled — no password entered.',
          );
        }
        result = await restoreFromBackupFile(selectedFile, password: password);
      }
      return result;
    } catch (e) {
      return BackupRestoreResult(
        success: false,
        message: 'Restore error: $e',
      );
    }
  }
}
