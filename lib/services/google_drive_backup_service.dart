import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:path/path.dart' as p;

/// Real Google Drive backup — uploads the `.kmb` package to the merchant's own
/// Drive over the Drive REST API, and lists / downloads it back for restore.
///
/// **What this replaces.** "Google Drive 1-Tap Cloud Backup" used to open the
/// Android share sheet and hope the merchant picked Drive from it. Nothing was
/// uploaded, nothing could be listed, and there was no restore-from-Drive at
/// all — a merchant who lost their phone had no way to get their shop back
/// unless they had manually kept the file somewhere.
///
/// **Scope: `drive.file` only.** That grants access to files this app itself
/// created, and nothing else in the merchant's Drive. It is a non-sensitive
/// scope, so it needs no Google app verification, and it means a bug here can
/// never touch a merchant's personal documents or photos.
///
/// **Deliberately no `googleapis` dependency.** Four REST calls against a
/// documented, stable API, using the same `dart:io` HTTP approach the rest of
/// this codebase already uses — versus a large generated client and its own
/// transitive auth stack. The tradeoff is that the request shapes are written
/// out by hand below; each is annotated with the endpoint it targets.
class GoogleDriveBackupService {
  GoogleDriveBackupService._();
  static final GoogleDriveBackupService instance = GoogleDriveBackupService._();

  /// Per-file access only — see the class doc for why this is not `drive`.
  static const List<String> _scopes = ['https://www.googleapis.com/auth/drive.file'];

  static const String _folderName = 'KamaiPlus Backups';
  static const String _folderMime = 'application/vnd.google-apps.folder';
  static const Duration _timeout = Duration(seconds: 60);

  /// Obtains Drive authorization headers, prompting the merchant the first
  /// time. Returns null when they decline or the platform cannot authorize —
  /// callers must treat that as "fall back to the share sheet", not an error.
  Future<Map<String, String>?> _authHeaders({bool prompt = true}) async {
    try {
      return await GoogleSignIn.instance.authorizationClient
          .authorizationHeaders(_scopes, promptIfNecessary: prompt);
    } catch (e) {
      debugPrint('Drive authorization declined or unavailable: $e');
      return null;
    }
  }

  /// True when Drive access is already granted, without showing any prompt.
  /// Lets the UI say "Connected" instead of surprising the merchant with a
  /// consent screen just for rendering a settings row.
  Future<bool> isAuthorized() async {
    final headers = await _authHeaders(prompt: false);
    return headers != null;
  }

  /// Finds (or creates) the app's own backup folder and returns its id.
  Future<String?> _ensureFolder(Map<String, String> headers) async {
    // https://developers.google.com/drive/api/v3/reference/files/list
    final query = Uri.encodeQueryComponent(
      "mimeType='$_folderMime' and name='$_folderName' and trashed=false",
    );
    final existing = await _getJson(
      'https://www.googleapis.com/drive/v3/files?q=$query&fields=files(id,name)&spaces=drive',
      headers,
    );
    final files = existing?['files'];
    if (files is List && files.isNotEmpty) {
      return (files.first as Map<String, dynamic>)['id']?.toString();
    }

    final created = await _postJson(
      'https://www.googleapis.com/drive/v3/files?fields=id',
      headers,
      {'name': _folderName, 'mimeType': _folderMime},
    );
    return created?['id']?.toString();
  }

  /// Uploads [file] to the merchant's Drive. Returns the Drive file id, or
  /// null if authorization was declined or the upload failed.
  Future<String?> uploadBackup(File file) async {
    final headers = await _authHeaders();
    if (headers == null) return null;

    try {
      final folderId = await _ensureFolder(headers);
      final bytes = await file.readAsBytes();
      final name = p.basename(file.path);

      final metadata = <String, dynamic>{
        'name': name,
        if (folderId != null) 'parents': [folderId],
      };

      // Multipart upload:
      // https://developers.google.com/drive/api/guides/manage-uploads#multipart
      const boundary = 'kamaiplus-backup-boundary-7f3a';
      final builder = BytesBuilder();
      builder.add(utf8.encode(
        '--$boundary\r\n'
        'Content-Type: application/json; charset=UTF-8\r\n\r\n'
        '${jsonEncode(metadata)}\r\n'
        '--$boundary\r\n'
        'Content-Type: application/octet-stream\r\n\r\n',
      ));
      builder.add(bytes);
      builder.add(utf8.encode('\r\n--$boundary--\r\n'));
      final body = builder.toBytes();

      final result = await _sendBytes(
        'https://www.googleapis.com/upload/drive/v3/files?uploadType=multipart&fields=id,name',
        headers: {
          ...headers,
          HttpHeaders.contentTypeHeader: 'multipart/related; boundary=$boundary',
        },
        body: body,
      );
      return result?['id']?.toString();
    } catch (e) {
      debugPrint('Drive upload failed: $e');
      return null;
    }
  }

  /// Backups this app has uploaded, newest first. Empty when Drive has not
  /// been authorized — callers should check [isAuthorized] to tell "declined"
  /// apart from "no backups yet".
  Future<List<DriveBackupFile>> listBackups() async {
    final headers = await _authHeaders();
    if (headers == null) return [];

    try {
      final query = Uri.encodeQueryComponent("name contains '.kmb' and trashed=false");
      final json = await _getJson(
        'https://www.googleapis.com/drive/v3/files'
        '?q=$query&orderBy=modifiedTime desc&pageSize=25'
        '&fields=files(id,name,size,modifiedTime)&spaces=drive',
        headers,
      );
      final files = json?['files'];
      if (files is! List) return [];
      return files
          .whereType<Map<String, dynamic>>()
          .map(DriveBackupFile.fromJson)
          .toList();
    } catch (e) {
      debugPrint('Drive list failed: $e');
      return [];
    }
  }

  /// Downloads a Drive backup to [destination] so it can be restored through
  /// the normal `BackupRestoreService.restoreFromBackupFile` path — including
  /// its checksum verification and password prompt.
  Future<File?> downloadBackup(String fileId, File destination) async {
    final headers = await _authHeaders();
    if (headers == null) return null;

    HttpClient? client;
    try {
      client = HttpClient()..connectionTimeout = _timeout;
      final req = await client
          .getUrl(Uri.parse('https://www.googleapis.com/drive/v3/files/$fileId?alt=media'));
      headers.forEach(req.headers.set);
      final res = await req.close().timeout(_timeout);
      if (res.statusCode != 200) {
        debugPrint('Drive download failed: HTTP ${res.statusCode}');
        return null;
      }
      final sink = destination.openWrite();
      await res.pipe(sink);
      return destination;
    } catch (e) {
      debugPrint('Drive download failed: $e');
      return null;
    } finally {
      client?.close(force: true);
    }
  }

  // ===========================================================================
  // HTTP helpers
  // ===========================================================================

  Future<Map<String, dynamic>?> _getJson(String url, Map<String, String> headers) async {
    HttpClient? client;
    try {
      client = HttpClient()..connectionTimeout = _timeout;
      final req = await client.getUrl(Uri.parse(url));
      headers.forEach(req.headers.set);
      final res = await req.close().timeout(_timeout);
      final body = await res.transform(utf8.decoder).join();
      if (res.statusCode != 200) {
        debugPrint('Drive GET ${res.statusCode}: ${body.substring(0, body.length.clamp(0, 300))}');
        return null;
      }
      final decoded = jsonDecode(body);
      return decoded is Map<String, dynamic> ? decoded : null;
    } finally {
      client?.close(force: true);
    }
  }

  Future<Map<String, dynamic>?> _postJson(
    String url,
    Map<String, String> headers,
    Map<String, dynamic> payload,
  ) async {
    return _sendBytes(
      url,
      headers: {...headers, HttpHeaders.contentTypeHeader: 'application/json; charset=UTF-8'},
      body: Uint8List.fromList(utf8.encode(jsonEncode(payload))),
    );
  }

  Future<Map<String, dynamic>?> _sendBytes(
    String url, {
    required Map<String, String> headers,
    required Uint8List body,
  }) async {
    HttpClient? client;
    try {
      client = HttpClient()..connectionTimeout = _timeout;
      final req = await client.postUrl(Uri.parse(url));
      headers.forEach(req.headers.set);
      req.headers.set(HttpHeaders.contentLengthHeader, body.length.toString());
      req.add(body);
      final res = await req.close().timeout(_timeout);
      final text = await res.transform(utf8.decoder).join();
      if (res.statusCode < 200 || res.statusCode >= 300) {
        debugPrint('Drive POST ${res.statusCode}: ${text.substring(0, text.length.clamp(0, 300))}');
        return null;
      }
      final decoded = jsonDecode(text);
      return decoded is Map<String, dynamic> ? decoded : null;
    } finally {
      client?.close(force: true);
    }
  }
}

/// One `.kmb` backup sitting in the merchant's Drive.
class DriveBackupFile {
  final String id;
  final String name;
  final int sizeBytes;
  final DateTime? modifiedAt;

  const DriveBackupFile({
    required this.id,
    required this.name,
    required this.sizeBytes,
    required this.modifiedAt,
  });

  factory DriveBackupFile.fromJson(Map<String, dynamic> json) => DriveBackupFile(
        id: json['id']?.toString() ?? '',
        name: json['name']?.toString() ?? 'backup.kmb',
        // Drive returns size as a STRING, not a number.
        sizeBytes: int.tryParse(json['size']?.toString() ?? '') ?? 0,
        modifiedAt: DateTime.tryParse(json['modifiedTime']?.toString() ?? ''),
      );

  String get readableSize {
    if (sizeBytes <= 0) return '';
    if (sizeBytes < 1024 * 1024) return '${(sizeBytes / 1024).toStringAsFixed(0)} KB';
    return '${(sizeBytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
}
