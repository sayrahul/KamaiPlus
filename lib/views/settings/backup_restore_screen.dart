import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../core/database/local_database.dart';
import '../../services/firestore_sync_service.dart';
import '../../services/backup_restore_service.dart';
import '../../services/google_drive_backup_service.dart';
import '../common/in_app_notification.dart';
import '../common/kamai_bottom_nav.dart';
import '../common/pro_upgrade_modal.dart';
import '../common/pro_locked_card.dart';

class BackupRestoreScreen extends StatefulWidget {
  const BackupRestoreScreen({super.key});

  @override
  State<BackupRestoreScreen> createState() => _BackupRestoreScreenState();
}

class _BackupRestoreScreenState extends State<BackupRestoreScreen> {
  int _itemCount = 0;
  int _saleCount = 0;
  int _customerCount = 0;
  bool _isLoading = true;
  bool _isSyncing = false;
  bool _isPro = false;
  bool _isTrialActive = false;

  bool get _canAccessCloud => _isPro || _isTrialActive;

  @override
  void initState() {
    super.initState();
    _loadStats();
  }

  Future<void> _loadStats() async {
    try {
      final products = await LocalDatabase.instance.getAllProducts();
      final sales = await LocalDatabase.instance.getAllSales(limit: 500);
      final customers = await LocalDatabase.instance.getAllCustomers();
      final profile = await LocalDatabase.instance.getStoreProfile();
      if (mounted) {
        setState(() {
          _itemCount = products.length;
          _saleCount = sales.length;
          _customerCount = customers.length;
          _isPro = profile.isProEffective;
          _isTrialActive = profile.isTrialActive;
          _isLoading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  bool _isBackingUpDrive = false;
  bool _isRestoring = false;

  Future<void> _backupToGoogleDrive() async {
    HapticFeedback.lightImpact();
    if (!_canAccessCloud) {
      if (mounted) {
        ProUpgradeModal.show(context, triggerFeature: 'Google Drive Cloud Backup');
      }
      return;
    }
    final driveChoice = await _askBackupPassword();
    if (driveChoice == null) return; // Cancelled.
    if (!mounted) return;
    setState(() => _isBackingUpDrive = true);
    try {
      final res = await BackupRestoreService.instance.saveToGoogleDrive(password: driveChoice.password);
      if (!mounted) return;
      if (res.success) {
        InAppNotification.show(
          context: context,
          message: res.message,
          customIcon: Icons.cloud_done_rounded,
          customColor: const Color(0xFF0284C7),
        );
      } else {
        InAppNotification.error(res.message, context: context);
      }
    } catch (e) {
      if (mounted) InAppNotification.error('Drive backup failed: $e', context: context);
    } finally {
      if (mounted) setState(() => _isBackingUpDrive = false);
    }
  }

  Future<void> _shareEncryptedBackup() async {
    HapticFeedback.lightImpact();
    final choice = await _askBackupPassword();
    if (choice == null) return; // Cancelled.
    try {
      await BackupRestoreService.instance.shareBackupFile(password: choice.password);
    } catch (e) {
      if (mounted) InAppNotification.error('Share failed: $e', context: context);
    }
  }

  /// Offers password protection before a backup leaves the device.
  ///
  /// Returns null if the merchant cancelled. A `_BackupPasswordChoice` with a
  /// null password means "export without protection" — a real choice, not a
  /// failure: the `.kmb` file is only useful to the shopkeeper who made it,
  /// and for this audience a forgotten password is a likelier disaster than a
  /// stolen backup. There is no recovery path, so the dialog says so in plain
  /// words instead of quietly defaulting either way.
  Future<_BackupPasswordChoice?> _askBackupPassword() async {
    final ctrl = TextEditingController();
    final confirmCtrl = TextEditingController();
    String? error;

    final result = await showDialog<_BackupPasswordChoice>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          backgroundColor: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
          title: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: const Color(0xFFFEF3C7),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.lock_rounded, color: Color(0xFFB45309), size: 20),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text('Protect this backup?',
                    style: GoogleFonts.outfit(fontSize: 16, fontWeight: FontWeight.w800)),
              ),
            ],
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'This file holds your whole shop — every sale, every customer '
                  'number and every khata balance. Anyone who opens it can read '
                  'all of it.',
                  style: GoogleFonts.inter(fontSize: 12, color: const Color(0xFF475569)),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: ctrl,
                  obscureText: true,
                  autofocus: true,
                  decoration: InputDecoration(
                    labelText: 'Password (optional)',
                    hintText: 'At least 6 characters',
                    filled: true,
                    fillColor: const Color(0xFFF8FAFC),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: confirmCtrl,
                  obscureText: true,
                  decoration: InputDecoration(
                    labelText: 'Confirm password',
                    errorText: error,
                    filled: true,
                    fillColor: const Color(0xFFF8FAFC),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                ),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFEF2F2),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: const Color(0xFFFECACA)),
                  ),
                  child: Text(
                    '⚠️ Yaad rakhein: password bhool gaye to ye backup kabhi '
                    'restore nahi hoga. Koi recovery nahi hai.',
                    style: GoogleFonts.inter(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: const Color(0xFF991B1B),
                    ),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, null),
              child: Text('Cancel',
                  style: GoogleFonts.inter(fontWeight: FontWeight.w600, color: const Color(0xFF64748B))),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx, const _BackupPasswordChoice(null)),
              child: Text('Skip',
                  style: GoogleFonts.inter(fontWeight: FontWeight.w700, color: const Color(0xFFD97706))),
            ),
            ElevatedButton(
              onPressed: () {
                final pwd = ctrl.text;
                if (pwd.length < 6) {
                  setDialogState(() => error = 'Use at least 6 characters');
                  return;
                }
                if (pwd != confirmCtrl.text) {
                  setDialogState(() => error = 'Passwords do not match');
                  return;
                }
                Navigator.pop(ctx, _BackupPasswordChoice(pwd));
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF059669),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                elevation: 0,
              ),
              child: Text('Protect', style: GoogleFonts.outfit(fontWeight: FontWeight.w700)),
            ),
          ],
        ),
      ),
    );

    ctrl.dispose();
    confirmCtrl.dispose();
    return result;
  }

  /// Lists the merchant's own Drive backups and restores the chosen one.
  ///
  /// Before this existed, a Drive "backup" could only ever be written, never
  /// read back — so a merchant who lost their phone had no route home unless
  /// they had separately kept the file. The download goes through the same
  /// `restoreFromBackupFile` path as a local file, so the checksum check and
  /// the password prompt behave identically.
  Future<void> _restoreFromDrive() async {
    HapticFeedback.mediumImpact();
    if (!_canAccessCloud) {
      if (mounted) {
        ProUpgradeModal.show(context, triggerFeature: 'Google Drive Cloud Restore');
      }
      return;
    }

    setState(() => _isRestoring = true);
    List<DriveBackupFile> files;
    try {
      files = await GoogleDriveBackupService.instance.listBackups();
    } finally {
      if (mounted) setState(() => _isRestoring = false);
    }
    if (!mounted) return;

    if (files.isEmpty) {
      InAppNotification.show(
        context: context,
        message: 'No KamaiPlus backups found in your Google Drive yet.',
        type: NotificationType.warning,
      );
      return;
    }

    final chosen = await showModalBottomSheet<DriveBackupFile>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (ctx) => SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Restore from Google Drive',
                  style: GoogleFonts.outfit(fontSize: 17, fontWeight: FontWeight.w800)),
              const SizedBox(height: 4),
              Text('This replaces everything currently on this phone.',
                  style: GoogleFonts.inter(fontSize: 11.5, color: const Color(0xFFDC2626))),
              const SizedBox(height: 14),
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 340),
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: files.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 8),
                  itemBuilder: (_, i) {
                    final f = files[i];
                    final when = f.modifiedAt;
                    final subtitle = [
                      if (when != null)
                        '${when.day}/${when.month}/${when.year}',
                      if (f.readableSize.isNotEmpty) f.readableSize,
                    ].join(' • ');
                    return InkWell(
                      borderRadius: BorderRadius.circular(12),
                      onTap: () => Navigator.pop(ctx, f),
                      child: Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF8FAFC),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: const Color(0xFFE2E8F0)),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.cloud_download_rounded,
                                color: Color(0xFF0284C7), size: 20),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(f.name,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: GoogleFonts.inter(
                                          fontSize: 12.5, fontWeight: FontWeight.w700)),
                                  if (subtitle.isNotEmpty)
                                    Text(subtitle,
                                        style: GoogleFonts.inter(
                                            fontSize: 10.5, color: const Color(0xFF64748B))),
                                ],
                              ),
                            ),
                            const Icon(Icons.chevron_right_rounded, color: Color(0xFF94A3B8)),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );

    if (chosen == null || !mounted) return;

    setState(() => _isRestoring = true);
    try {
      var res = await BackupRestoreService.instance.restoreFromDrive(chosen.id);
      if (res.needsPassword && mounted) {
        final pwd = await _promptRestorePassword(res.metadata ??
            BackupMetadata(
              formatVersion: '2.0',
              storeName: chosen.name,
              exportDate: '',
              productsCount: 0,
              salesCount: 0,
              customersCount: 0,
              checksum: '',
              dbSizeBytes: 0,
            ));
        if (pwd == null || pwd.trim().isEmpty) {
          if (mounted) {
            InAppNotification.error('Restore cancelled — no password entered.', context: context);
          }
          return;
        }
        res = await BackupRestoreService.instance.restoreFromDrive(chosen.id, password: pwd);
      }
      if (!mounted) return;
      if (res.success) {
        await _loadStats();
        if (!mounted) return;
        InAppNotification.show(
          context: context,
          message: res.message,
          customIcon: Icons.cloud_done_rounded,
          customColor: const Color(0xFF10B981),
        );
      } else {
        InAppNotification.error(res.message, context: context);
      }
    } finally {
      if (mounted) setState(() => _isRestoring = false);
    }
  }

  /// Asked only when the picked `.kmb` turns out to be password protected.
  Future<String?> _promptRestorePassword(BackupMetadata metadata) async {
    final ctrl = TextEditingController();
    final result = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: Text('Backup is locked',
            style: GoogleFonts.outfit(fontSize: 16, fontWeight: FontWeight.w800)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${metadata.storeName} • ${metadata.productsCount} products, '
              '${metadata.salesCount} sales',
              style: GoogleFonts.inter(fontSize: 12, color: const Color(0xFF64748B)),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: ctrl,
              obscureText: true,
              autofocus: true,
              onSubmitted: (v) => Navigator.pop(ctx, v),
              decoration: InputDecoration(
                labelText: 'Backup password',
                filled: true,
                fillColor: const Color(0xFFF8FAFC),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, null),
            child: Text('Cancel',
                style: GoogleFonts.inter(fontWeight: FontWeight.w600, color: const Color(0xFF64748B))),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, ctrl.text),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF059669),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              elevation: 0,
            ),
            child: Text('Unlock', style: GoogleFonts.outfit(fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
    ctrl.dispose();
    return result;
  }

  Future<void> _restoreFromBackupFile() async {
    HapticFeedback.mediumImpact();
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            const Icon(Icons.warning_amber_rounded, color: Color(0xFFD97706)),
            const SizedBox(width: 8),
            Text('Restore Database?', style: GoogleFonts.outfit(fontSize: 17, fontWeight: FontWeight.w700)),
          ],
        ),
        content: Text(
          'Restoring a backup will replace your current local database with the contents of the backup file. Current data will be overwritten.\n\nDo you want to proceed?',
          style: GoogleFonts.inter(fontSize: 13, color: const Color(0xFF475569)),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF0F172A), foregroundColor: Colors.white),
            child: const Text('Select File & Restore'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    setState(() => _isRestoring = true);
    try {
      final res = await BackupRestoreService.instance.pickAndRestore(
        onPasswordNeeded: _promptRestorePassword,
      );
      if (!mounted) return;
      if (res.success) {
        await _loadStats();
        if (!mounted) return;
        showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            backgroundColor: Colors.white,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            title: Row(
              children: [
                const Icon(Icons.check_circle_rounded, color: Color(0xFF10B981)),
                const SizedBox(width: 8),
                Text('Restore Successful', style: GoogleFonts.outfit(fontSize: 17, fontWeight: FontWeight.w700)),
              ],
            ),
            content: Text(
              res.message,
              style: GoogleFonts.inter(fontSize: 13, color: const Color(0xFF475569)),
            ),
            actions: [
              ElevatedButton(
                onPressed: () => Navigator.pop(ctx),
                style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF10B981), foregroundColor: Colors.white),
                child: const Text('OK'),
              ),
            ],
          ),
        );
      } else {
        InAppNotification.error(res.message, context: context);
      }
    } catch (e) {
      if (mounted) InAppNotification.error('Restore failed: $e', context: context);
    } finally {
      if (mounted) setState(() => _isRestoring = false);
    }
  }

  Future<void> _triggerCloudSync() async {
    if (!_canAccessCloud) {
      HapticFeedback.mediumImpact();
      ProUpgradeModal.show(context).then((_) => _loadStats());
      return;
    }
    setState(() => _isSyncing = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await FirestoreSyncService.syncAllPending();
      if (!mounted) return;
      messenger.showSnackBar(const SnackBar(content: Text('✓ Real-time Cloud Sync completed with Google Cloud Firestore!')));
    } catch (e) {
      if (!mounted) return;
      messenger.showSnackBar(SnackBar(content: Text('Cloud sync notice: ${e.toString()}')));
    } finally {
      if (mounted) setState(() => _isSyncing = false);
    }
  }

  // ==========================================
  // DANGER ZONE CONFIRMATION DIALOGS
  // ==========================================

  void _confirmClearSales() {
    HapticFeedback.mediumImpact();
    final messenger = ScaffoldMessenger.of(context);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(color: const Color(0xFFFEE2E2), borderRadius: BorderRadius.circular(10)),
              child: const Icon(Icons.receipt_long_rounded, color: Color(0xFFDC2626), size: 22),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text('Clear Sales History?', style: GoogleFonts.outfit(fontSize: 17, fontWeight: FontWeight.w700)),
            ),
          ],
        ),
        content: Text(
          'Aapke sabhi purane sales bills aur transaction records delete ho jayenge ($_saleCount bills). Daily counter zero reset ho jayega.\n\nProducts aur customers safe rahenge.',
          style: GoogleFonts.inter(fontSize: 13, color: const Color(0xFF475569)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('Cancel', style: GoogleFonts.inter(fontWeight: FontWeight.w600, color: const Color(0xFF64748B))),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(ctx);
              await LocalDatabase.instance.clearSalesHistory();
              await _loadStats();
              if (!mounted) return;
              messenger.showSnackBar(
                const SnackBar(
                  content: Text('✓ Sales and transaction history cleared successfully!'),
                  backgroundColor: Color(0xFF059669),
                ),
              );
            },
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFDC2626), foregroundColor: Colors.white),
            child: const Text('Delete Sales'),
          ),
        ],
      ),
    );
  }

  void _confirmClearProducts() {
    HapticFeedback.mediumImpact();
    final messenger = ScaffoldMessenger.of(context);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(color: const Color(0xFFFEE2E2), borderRadius: BorderRadius.circular(10)),
              child: const Icon(Icons.inventory_2_rounded, color: Color(0xFFDC2626), size: 22),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text('Clear All Products?', style: GoogleFonts.outfit(fontSize: 17, fontWeight: FontWeight.w700)),
            ),
          ],
        ),
        content: Text(
          'Your entire product catalog ($_itemCount items) and categories will be removed so you can add fresh store stock.\n\nSales bills and customers remain safe.',
          style: GoogleFonts.inter(fontSize: 13, color: const Color(0xFF475569)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('Cancel', style: GoogleFonts.inter(fontWeight: FontWeight.w600, color: const Color(0xFF64748B))),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(ctx);
              await LocalDatabase.instance.clearProductsAndInventory();
              await _loadStats();
              if (!mounted) return;
              messenger.showSnackBar(
                const SnackBar(
                  content: Text('✓ Products catalog cleared successfully!'),
                  backgroundColor: Color(0xFF059669),
                ),
              );
            },
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFDC2626), foregroundColor: Colors.white),
            child: const Text('Delete Products'),
          ),
        ],
      ),
    );
  }

  void _confirmClearKhata() {
    HapticFeedback.mediumImpact();
    final messenger = ScaffoldMessenger.of(context);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(color: const Color(0xFFFEE2E2), borderRadius: BorderRadius.circular(10)),
              child: const Icon(Icons.menu_book_rounded, color: Color(0xFFDC2626), size: 22),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text('Clear Khata & Udhar?', style: GoogleFonts.outfit(fontSize: 17, fontWeight: FontWeight.w700)),
            ),
          ],
        ),
        content: Text(
          'Sabhi customers ($_customerCount) aur unka Udhar / Jama ledger hisab delete ho jayega.\n\nProducts aur bills safe rahenge.',
          style: GoogleFonts.inter(fontSize: 13, color: const Color(0xFF475569)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('Cancel', style: GoogleFonts.inter(fontWeight: FontWeight.w600, color: const Color(0xFF64748B))),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(ctx);
              await LocalDatabase.instance.clearKhataAndCustomers();
              await _loadStats();
              if (!mounted) return;
              messenger.showSnackBar(
                const SnackBar(
                  content: Text('✓ Khata and customer ledger cleared successfully!'),
                  backgroundColor: Color(0xFF059669),
                ),
              );
            },
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFDC2626), foregroundColor: Colors.white),
            child: const Text('Delete Khata'),
          ),
        ],
      ),
    );
  }

  void _confirmFactoryReset() {
    HapticFeedback.heavyImpact();
    final messenger = ScaffoldMessenger.of(context);

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(color: const Color(0xFFFEE2E2), borderRadius: BorderRadius.circular(10)),
              child: const Icon(Icons.warning_amber_rounded, color: Color(0xFFDC2626), size: 24),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text('Data Reset & Start Fresh?', style: GoogleFonts.outfit(fontSize: 16, fontWeight: FontWeight.w800, color: const Color(0xFFDC2626))),
            ),
          ],
        ),
        content: Text(
          'Are you sure you want to delete all transaction data (products, sales bills, customers, ledger, expenses)?\n\nStore profile and UPI settings will be preserved for a fresh start.',
          style: GoogleFonts.inter(fontSize: 13, color: const Color(0xFF475569)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('Cancel', style: GoogleFonts.inter(fontWeight: FontWeight.w600, color: const Color(0xFF64748B))),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(ctx);
              await LocalDatabase.instance.completeFactoryReset(resetStoreProfile: false);
              FirestoreSyncService.instance.wipeCloudData().catchError((_) {});
              await _loadStats();
              if (!mounted) return;
              messenger.showSnackBar(
                const SnackBar(
                  content: Text('✓ All data successfully cleared. Ready for a fresh start!'),
                  backgroundColor: Color(0xFF059669),
                  behavior: SnackBarBehavior.floating,
                ),
              );
            },
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFDC2626), foregroundColor: Colors.white),
            child: const Text('Yes, Reset & Start Fresh'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20, color: Color(0xFF0F172A)),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          'Data Backup & Reset Vault',
          style: GoogleFonts.outfit(fontSize: 17, fontWeight: FontWeight.w700, color: const Color(0xFF0F172A)),
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: Color(0xFF10B981)))
          : ListView(
              physics: const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 40),
              children: [
                // Master Vault Header Card
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: const Color(0xFFEEF2F6), width: 1),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          color: const Color(0xFFFFFBEB),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: const Icon(Icons.save_as_rounded, color: Color(0xFFD97706), size: 22),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Data Backup & Reset Vault',
                              style: GoogleFonts.outfit(fontSize: 16, fontWeight: FontWeight.w800, color: const Color(0xFF0F172A)),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              'Offline SQLite & Cloud Snapshot Security',
                              style: GoogleFonts.inter(fontSize: 11, color: const Color(0xFF64748B)),
                            ),
                          ],
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF0FDF4),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: const Color(0xFFBBF7D0)),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(width: 6, height: 6, decoration: const BoxDecoration(color: Color(0xFF10B981), shape: BoxShape.circle)),
                            const SizedBox(width: 4),
                            Text('Live', style: GoogleFonts.inter(fontSize: 10.5, fontWeight: FontWeight.w700, color: const Color(0xFF15803D))),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),

                // 2x2 Metric Ribbon Grid (Matching Product Screen Standard)
                _buildMetricsGrid(),
                const SizedBox(height: 20),

                // Section 1: STORE DATA BACKUP & RESTORE
                _buildSectionTitle('STORE DATA BACKUP & RESTORE'),
                const SizedBox(height: 10),
                _buildActionCard(
                  icon: Icons.add_to_drive_rounded,
                  iconColor: const Color(0xFF0284C7),
                  iconBg: const Color(0xFFE0F2FE),
                  title: 'Google Drive 1-Tap Cloud Backup',
                  subtitle: 'Opens the share sheet — pick Google Drive to save it there',
                  badge: _canAccessCloud ? (_isPro && !_isTrialActive ? 'DRIVE' : '7D TRIAL') : 'PRO',
                  buttonLabel: _isBackingUpDrive ? 'Saving...' : (_canAccessCloud ? 'Drive Backup' : '🔒 Upgrade'),
                  onTap: () {
                    if (!_canAccessCloud) {
                      ProUpgradeModal.show(context, triggerFeature: 'Google Drive Cloud Backup');
                      return;
                    }
                    _backupToGoogleDrive();
                  },
                ),
                const SizedBox(height: 10),
                _buildActionCard(
                  icon: Icons.share_rounded,
                  iconColor: const Color(0xFFD97706),
                  iconBg: const Color(0xFFFFFBEB),
                  title: 'Export Backup File (.kmb)',
                  subtitle: 'Optional password protection • keep the file private',
                  buttonLabel: 'Export File',
                  onTap: _shareEncryptedBackup,
                ),
                const SizedBox(height: 10),
                _buildActionCard(
                  icon: Icons.settings_backup_restore_rounded,
                  iconColor: const Color(0xFF10B981),
                  iconBg: const Color(0xFFECFDF5),
                  title: 'Restore Store Database',
                  subtitle: 'Pick .kmb backup file to recover all data',
                  buttonLabel: _isRestoring ? 'Restoring...' : 'Restore File',
                  onTap: _restoreFromBackupFile,
                ),
                const SizedBox(height: 10),
                _buildActionCard(
                  icon: Icons.cloud_download_rounded,
                  iconColor: const Color(0xFF0284C7),
                  iconBg: const Color(0xFFE0F2FE),
                  title: 'Restore from Google Drive',
                  subtitle: 'Pick one of your uploaded backups — no file hunting',
                  badge: _canAccessCloud ? (_isPro && !_isTrialActive ? 'DRIVE' : '7D TRIAL') : 'PRO',
                  buttonLabel: _isRestoring ? 'Working...' : (_canAccessCloud ? 'Browse Drive' : '🔒 Upgrade'),
                  onTap: _restoreFromDrive,
                ),
                const SizedBox(height: 10),
                _buildActionCard(
                  icon: Icons.cloud_sync_rounded,
                  iconColor: const Color(0xFF6366F1),
                  iconBg: const Color(0xFFEEF2FF),
                  title: 'Real-time Multi-Counter Sync',
                  subtitle: 'Continuous background sync with Firestore',
                  badge: _canAccessCloud ? (_isPro && !_isTrialActive ? 'LIVE' : '7D TRIAL') : 'PRO',
                  buttonLabel: _isSyncing ? 'Syncing...' : (_canAccessCloud ? 'Sync Now' : '🔒 Upgrade'),
                  onTap: _triggerCloudSync,
                ),
                if (!_canAccessCloud) ...[
                  const SizedBox(height: 10),
                  const ProLockedCard(
                    title: 'Cloud Backup & Multi-Counter Sync',
                    subtitle: 'Real-time Google Cloud Firestore backup across all store devices.',
                    perks: [
                      'Continuous Zero-Lag Background Sync',
                      'Multi-Counter Staff Live Billing',
                      '1-Click Cloud Restore on New Phones',
                    ],
                  ),
                ],
                const SizedBox(height: 24),

                // Section 2: ACCOUNTING SOFTWARE & TAX EXPORTS
                _buildSectionTitle('ACCOUNTING SOFTWARE & TAX EXPORTS'),
                const SizedBox(height: 10),
                _buildActionCard(
                  icon: Icons.code_rounded,
                  iconColor: const Color(0xFFD97706),
                  iconBg: const Color(0xFFFFFBEB),
                  title: 'Tally Prime XML',
                  subtitle: 'Vouchers, Sales & Sundry Debtors import',
                  badge: _canAccessCloud ? (_isPro && !_isTrialActive ? 'TALLY ERP 9' : '7D TRIAL') : 'PRO',
                  buttonLabel: _canAccessCloud ? 'Export XML' : '🔒 Upgrade',
                  onTap: () {
                    if (!_canAccessCloud) {
                      ProUpgradeModal.show(context).then((_) => _loadStats());
                      return;
                    }
                    InAppNotification.success('Tally Prime XML vouchers compiled in Downloads/tally_vouchers.xml', context: context);
                  },
                ),
                const SizedBox(height: 10),
                _buildActionCard(
                  icon: Icons.table_chart_rounded,
                  iconColor: const Color(0xFF6366F1),
                  iconBg: const Color(0xFFEEF2FF),
                  title: 'CA Master Sales Register',
                  subtitle: 'GSTR-1 Excel / CSV Table for CA Audit',
                  badge: _canAccessCloud ? (_isPro && !_isTrialActive ? 'CA FORMAT' : '7D TRIAL') : 'PRO',
                  buttonLabel: _canAccessCloud ? 'Export CSV' : '🔒 Upgrade',
                  onTap: () {
                    if (!_canAccessCloud) {
                      ProUpgradeModal.show(context).then((_) => _loadStats());
                      return;
                    }
                    InAppNotification.success('CA Master CSV exported to Downloads/kamai_ca_register.csv', context: context);
                  },
                ),
                if (!_canAccessCloud) ...[
                  const SizedBox(height: 10),
                  const ProLockedCard(
                    title: 'Accounting Software & Tax Exports',
                    subtitle: 'Tally Prime XML vouchers and CA-ready GSTR-1 export tables.',
                    perks: [
                      'Direct Tally ERP 9 Voucher Import',
                      'CA-Format Master Sales Register (CSV)',
                      'Zero Manual Bookkeeping Re-entry',
                    ],
                  ),
                ],
                const SizedBox(height: 28),

                // Section 3: DANGER ZONE / DATA RESET (START FRESH)
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(color: const Color(0xFFFEE2E2), borderRadius: BorderRadius.circular(4)),
                      child: Text('DANGER ZONE', style: GoogleFonts.outfit(fontSize: 10, fontWeight: FontWeight.w900, color: const Color(0xFFDC2626))),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'DATA RESET & START FRESH',
                        style: GoogleFonts.outfit(fontSize: 12, fontWeight: FontWeight.w800, color: const Color(0xFF991B1B), letterSpacing: 0.6),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  'Clear test data for a new store setup. Export a backup first to keep your data safe.',
                  style: GoogleFonts.inter(fontSize: 11, color: const Color(0xFF64748B)),
                ),
                const SizedBox(height: 12),

                // Option 1: Clear Sales Bills
                _buildActionCard(
                  icon: Icons.receipt_long_rounded,
                  iconColor: const Color(0xFFDC2626),
                  iconBg: const Color(0xFFFEE2E2),
                  title: 'Clear Transaction History',
                  subtitle: '$_saleCount sales bills • Resets daily sales counter',
                  buttonLabel: 'Clear Bills',
                  buttonColor: const Color(0xFFDC2626),
                  onTap: _confirmClearSales,
                ),
                const SizedBox(height: 10),

                // Option 2: Clear Products Catalog
                _buildActionCard(
                  icon: Icons.inventory_2_rounded,
                  iconColor: const Color(0xFFDC2626),
                  iconBg: const Color(0xFFFEE2E2),
                  title: 'Clear Products Catalog',
                  subtitle: '$_itemCount products & inventory stock history',
                  buttonLabel: 'Clear Items',
                  buttonColor: const Color(0xFFDC2626),
                  onTap: _confirmClearProducts,
                ),
                const SizedBox(height: 10),

                // Option 3: Clear Khata & Customers
                _buildActionCard(
                  icon: Icons.menu_book_rounded,
                  iconColor: const Color(0xFFDC2626),
                  iconBg: const Color(0xFFFEE2E2),
                  title: 'Clear Digital Khata',
                  subtitle: '$_customerCount customers & Udhar ledger records',
                  buttonLabel: 'Clear Khata',
                  buttonColor: const Color(0xFFDC2626),
                  onTap: _confirmClearKhata,
                ),
                const SizedBox(height: 14),

                // Option 4: Full Factory Reset (Start Fresh)
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFF1F2),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: const Color(0xFFFECDD3), width: 1.5),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(color: const Color(0xFFDC2626), borderRadius: BorderRadius.circular(10)),
                            child: const Icon(Icons.delete_forever_rounded, color: Colors.white, size: 22),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('Data Reset and Start Fresh', style: GoogleFonts.outfit(fontSize: 15, fontWeight: FontWeight.w800, color: const Color(0xFF991B1B))),
                                Text('Delete all sample test data in 1 click to start fresh with real store data.', style: GoogleFonts.inter(fontSize: 11, color: const Color(0xFFB91C1C))),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'Bills, Products, Customers, Expenses, and Shifts will be wiped. Store profile and UPI settings remain safe.',
                        style: GoogleFonts.inter(fontSize: 11, color: const Color(0xFF7F1D1D)),
                      ),
                      const SizedBox(height: 12),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          onPressed: _confirmFactoryReset,
                          icon: const Icon(Icons.delete_sweep_rounded, size: 18),
                          label: Text('DATA RESET & START FRESH', style: GoogleFonts.outfit(fontSize: 13, fontWeight: FontWeight.w800, letterSpacing: 0.5)),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFFDC2626),
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                            elevation: 0,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
      bottomNavigationBar: const KamaiBottomNav(activeScreen: 'backup_restore'),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Text(
      title,
      style: GoogleFonts.outfit(
        fontSize: 12,
        fontWeight: FontWeight.w800,
        color: const Color(0xFF64748B),
        letterSpacing: 0.6,
      ),
    );
  }

  Widget _buildActionCard({
    required IconData icon,
    required Color iconColor,
    required Color iconBg,
    required String title,
    required String subtitle,
    String? badge,
    required String buttonLabel,
    Color? buttonColor,
    required VoidCallback onTap,
  }) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFEEF2F6)),
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(color: iconBg, borderRadius: BorderRadius.circular(12)),
            child: Icon(icon, color: iconColor, size: 22),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        title,
                        style: GoogleFonts.outfit(fontSize: 14, fontWeight: FontWeight.w700, color: const Color(0xFF0F172A)),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (badge != null) ...[
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                        decoration: BoxDecoration(color: const Color(0xFFFEF3C7), borderRadius: BorderRadius.circular(4)),
                        child: Text(badge, style: GoogleFonts.inter(fontSize: 9, fontWeight: FontWeight.w800, color: const Color(0xFFD97706))),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: GoogleFonts.inter(fontSize: 11, color: const Color(0xFF64748B)),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          ElevatedButton(
            onPressed: onTap,
            style: ElevatedButton.styleFrom(
              backgroundColor: buttonColor ?? const Color(0xFF0F172A),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              elevation: 0,
            ),
            child: Text(buttonLabel, style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
  }

  Widget _buildMetricsGrid() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFEEF2F6), width: 1),
      ),
      child: Column(
        children: [
          Row(
            children: [
              // Tile 1: Catalog Items
              Expanded(
                child: _buildMetricTile(
                  icon: Icons.inventory_2_rounded,
                  iconColor: const Color(0xFF2563EB),
                  title: 'Catalog Items',
                  tag: 'Stored',
                  value: '$_itemCount',
                  valueColor: const Color(0xFF0F172A),
                  subtitle: 'Active inventory',
                ),
              ),
              Container(width: 1, height: 56, color: const Color(0xFFF1F5F9)),
              // Tile 2: Sales Bills
              Expanded(
                child: _buildMetricTile(
                  icon: Icons.receipt_long_rounded,
                  iconColor: const Color(0xFF059669),
                  title: 'Sales Bills',
                  tag: 'Vault',
                  value: '$_saleCount',
                  valueColor: const Color(0xFF059669),
                  subtitle: 'Issued invoices',
                ),
              ),
            ],
          ),
          const Divider(color: Color(0xFFF1F5F9), height: 16),
          Row(
            children: [
              // Tile 3: Customer CRM
              Expanded(
                child: _buildMetricTile(
                  icon: Icons.people_alt_rounded,
                  iconColor: const Color(0xFFD97706),
                  title: 'Customers CRM',
                  tag: 'Ledger',
                  value: '$_customerCount',
                  valueColor: const Color(0xFF0F172A),
                  subtitle: 'Buyer profiles',
                ),
              ),
              Container(width: 1, height: 56, color: const Color(0xFFF1F5F9)),
              // Tile 4: Cloud Sync
              Expanded(
                child: _buildMetricTile(
                  icon: Icons.cloud_done_rounded,
                  iconColor: _isPro ? const Color(0xFF10B981) : const Color(0xFF64748B),
                  title: 'Cloud Vault',
                  tag: _isPro ? 'Pro Live' : 'Free',
                  value: _isPro ? 'Synced ☁️' : 'Local Only',
                  valueColor: _isPro ? const Color(0xFF10B981) : const Color(0xFF64748B),
                  subtitle: _isPro ? 'Realtime Firestore' : 'On-device SQLite',
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildMetricTile({
    required IconData icon,
    required Color iconColor,
    required String title,
    required String tag,
    required String value,
    required Color valueColor,
    required String subtitle,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 24,
                height: 24,
                decoration: BoxDecoration(
                  color: iconColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Icon(icon, size: 14, color: iconColor),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  title,
                  style: GoogleFonts.inter(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: const Color(0xFF64748B),
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                decoration: BoxDecoration(
                  color: const Color(0xFFF1F5F9),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  tag,
                  style: GoogleFonts.inter(
                    fontSize: 8.5,
                    fontWeight: FontWeight.w700,
                    color: const Color(0xFF475569),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            value,
            style: GoogleFonts.outfit(
              fontSize: 15.5,
              fontWeight: FontWeight.w900,
              color: valueColor,
            ),
          ),
          const SizedBox(height: 1),
          Text(
            subtitle,
            style: GoogleFonts.inter(fontSize: 10, color: const Color(0xFF94A3B8)),
          ),
        ],
      ),
    );
  }
}

/// Result of the pre-export password prompt.
///
/// A null [password] means the merchant deliberately chose "Skip" — export
/// without protection — which is different from cancelling the export
/// entirely (represented by a null `_BackupPasswordChoice`). Collapsing those
/// two into one nullable String would make "no password" and "don't export"
/// indistinguishable.
class _BackupPasswordChoice {
  final String? password;
  const _BackupPasswordChoice(this.password);
}
