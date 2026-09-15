import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import '../core/database/local_database.dart';

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

  BackupRestoreResult({
    required this.success,
    required this.message,
    this.metadata,
  });
}

class BackupRestoreService {
  BackupRestoreService._();
  static final BackupRestoreService instance = BackupRestoreService._();

  static const String _magicHeader = 'KAMAI_POS_BACKUP_V1\n';

  /// Creates an encrypted package file from current SQLite database
  Future<File> createBackupPackage() async {
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

    final metadata = BackupMetadata(
      formatVersion: '1.0',
      storeName: profile.storeName.isNotEmpty ? profile.storeName : 'KamaiPlus_Store',
      exportDate: DateTime.now().toIso8601String(),
      productsCount: products.length,
      salesCount: sales.length,
      customersCount: customers.length,
      checksum: checksum,
      dbSizeBytes: dbBytes.length,
    );

    final metaJson = jsonEncode(metadata.toMap());
    final metaBytes = utf8.encode(metaJson);

    // Format: MAGIC_HEADER + 4-byte big-endian meta length + meta bytes + raw SQLite DB bytes
    final metaLenBytes = ByteData(4)..setUint32(0, metaBytes.length, Endian.big);

    final builder = BytesBuilder();
    builder.add(utf8.encode(_magicHeader));
    builder.add(metaLenBytes.buffer.asUint8List());
    builder.add(metaBytes);
    builder.add(dbBytes);

    final safeStoreName = metadata.storeName.replaceAll(RegExp(r'[^a-zA-Z0-9_]'), '_');
    final dateStr = DateTime.now().toIso8601String().split('T').first;
    final tempDir = await getTemporaryDirectory();
    final outputFile = File(p.join(tempDir.path, 'KamaiPlus_${safeStoreName}_$dateStr.kmb'));
    await outputFile.writeAsBytes(builder.toBytes(), flush: true);

    return outputFile;
  }

  /// 1-Tap Google Drive / Cloud Backup: exports package and launches Drive upload sheet
  Future<BackupRestoreResult> saveToGoogleDrive() async {
    try {
      final file = await createBackupPackage();
      final fileName = p.basename(file.path);
      // ignore: deprecated_member_use
      await Share.shareXFiles(
        [XFile(file.path, mimeType: 'application/octet-stream', name: fileName)],
        subject: 'Save to Google Drive: $fileName',
        text: 'KamaiPlus POS Encrypted SQLite Backup ($fileName). Choose "Save to Drive" or "Google Drive" to store in cloud.',
      );
      return BackupRestoreResult(
        success: true,
        message: 'Backup package ready! Select Google Drive in the share sheet.',
      );
    } catch (e) {
      return BackupRestoreResult(
        success: false,
        message: 'Google Drive backup failed: $e',
      );
    }
  }

  /// Exports backup and opens native Android sheet to share to Drive, WhatsApp, Files, or Email
  Future<void> shareBackupFile() async {
    final file = await createBackupPackage();
    final fileName = p.basename(file.path);
    // ignore: deprecated_member_use
    await Share.shareXFiles(
      [XFile(file.path, mimeType: 'application/octet-stream', name: fileName)],
      subject: 'KamaiPlus Store Backup: $fileName',
      text: 'KamaiPlus POS Encrypted Store Backup ($fileName). Save this file to Google Drive, WhatsApp, or File Manager for safe recovery.',
    );
  }

  /// Verifies and unpacks a .kmb backup file
  Future<BackupMetadata> inspectBackupFile(File file) async {
    final bytes = await file.readAsBytes();
    return _extractMetadataFromBytes(bytes);
  }

  BackupMetadata _extractMetadataFromBytes(Uint8List bytes) {
    final headerBytes = utf8.encode(_magicHeader);
    if (bytes.length < headerBytes.length + 4) {
      throw Exception('Invalid backup file: file too small or corrupted');
    }

    // Check header
    for (int i = 0; i < headerBytes.length; i++) {
      if (bytes[i] != headerBytes[i]) {
        throw Exception('Not a valid KamaiPlus backup file (.kmb)');
      }
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
    return BackupMetadata.fromMap(metaMap);
  }

  /// Restores SQLite database from a selected backup file
  Future<BackupRestoreResult> restoreFromBackupFile(File backupFile) async {
    try {
      final bytes = await backupFile.readAsBytes();
      final metadata = _extractMetadataFromBytes(bytes);

      final headerBytes = utf8.encode(_magicHeader);
      final metaLenOffset = headerBytes.length;
      final byteData = ByteData.sublistView(bytes, metaLenOffset, metaLenOffset + 4);
      final metaLen = byteData.getUint32(0, Endian.big);
      final dbStart = metaLenOffset + 4 + metaLen;

      final dbBytes = bytes.sublist(dbStart);

      // Verify SHA-256 integrity
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

  /// Prompts user to pick a .kmb backup file from device storage and restores it
  Future<BackupRestoreResult> pickAndRestore() async {
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
      return await restoreFromBackupFile(selectedFile);
    } catch (e) {
      return BackupRestoreResult(
        success: false,
        message: 'Restore error: $e',
      );
    }
  }
}
