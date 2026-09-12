import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../models/admin_models.dart';
import '../services/admin_firestore_service.dart';
import '../theme/admin_theme.dart';

enum _DiscountType { percent, flat }

/// Admin CRUD for the `coupons/{CODE}` collection — the same collection the
/// mobile app's Pro-upgrade screen reads at checkout to validate a code (see
/// `pro_upgrade_modal.dart`). Every write here is live for merchants within
/// seconds, so the form and the delete flow both call that out.
class CouponsScreen extends StatefulWidget {
  const CouponsScreen({super.key});

  @override
  State<CouponsScreen> createState() => _CouponsScreenState();
}

class _CouponsScreenState extends State<CouponsScreen> {
  final _dateFmt = DateFormat('dd MMM yyyy');

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AdminColors.surfaceSunken,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(28, 24, 28, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              LayoutBuilder(
                builder: (context, constraints) {
                  final title = Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Coupons', style: AdminTheme.heading(24)),
                      const SizedBox(height: 4),
                      Text(
                        'Codes merchants apply at checkout to buy Pro — changes go live immediately.',
                        style: TextStyle(
                          color: AdminColors.inkMuted,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  );
                  final newButton = ElevatedButton.icon(
                    onPressed: () => _openCouponDialog(context, existing: null),
                    icon: const Icon(Icons.add_rounded, size: 18),
                    label: const Text('New Coupon'),
                  );
                  if (constraints.maxWidth < 520) {
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        title,
                        const SizedBox(height: 14),
                        SizedBox(width: double.infinity, child: newButton),
                      ],
                    );
                  }
                  return Row(
                    children: [
                      Expanded(child: title),
                      newButton,
                    ],
                  );
                },
              ),
              const SizedBox(height: 20),
              Expanded(
                child: StreamBuilder<List<AdminCoupon>>(
                  stream: AdminFirestoreService.instance.watchCoupons(),
                  builder: (context, snapshot) {
                    if (snapshot.hasError) {
                      return _MessageState(
                        icon: Icons.error_outline_rounded,
                        color: AdminColors.red,
                        title: 'Could not load coupons',
                        subtitle: '${snapshot.error}',
                      );
                    }
                    if (!snapshot.hasData) {
                      return const Center(child: CircularProgressIndicator());
                    }
                    final coupons = snapshot.data!;
                    if (coupons.isEmpty) {
                      return const _MessageState(
                        icon: Icons.local_offer_outlined,
                        color: AdminColors.inkFaint,
                        title: 'No coupons yet',
                        subtitle: 'Create one to let merchants apply it when upgrading to Pro.',
                      );
                    }
                    return _CouponsTable(
                      coupons: coupons,
                      dateFmt: _dateFmt,
                      onTap: (c) => _openCouponDialog(context, existing: c),
                      onDelete: (c) => _confirmDelete(context, c),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _openCouponDialog(
    BuildContext context, {
    required AdminCoupon? existing,
  }) async {
    await showDialog<void>(
      context: context,
      builder: (_) => _CouponFormDialog(existing: existing),
    );
  }

  Future<void> _confirmDelete(BuildContext context, AdminCoupon coupon) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete this coupon?'),
        content: RichText(
          text: TextSpan(
            style: const TextStyle(
              color: AdminColors.ink,
              fontSize: 14,
              height: 1.5,
            ),
            children: [
              const TextSpan(text: 'Deleting '),
              TextSpan(text: coupon.code, style: AdminTheme.mono(14)),
              const TextSpan(
                text:
                    ' removes it immediately. Any merchant actively entering this code at checkout '
                    'will start seeing "Invalid coupon code" right away.',
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AdminColors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete coupon'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await AdminFirestoreService.instance.deleteCoupon(coupon.code);
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Deleted ${coupon.code}')));
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to delete: $e'),
            backgroundColor: AdminColors.red,
          ),
        );
      }
    }
  }
}

class _CouponsTable extends StatelessWidget {
  final List<AdminCoupon> coupons;
  final DateFormat dateFmt;
  final void Function(AdminCoupon) onTap;
  final void Function(AdminCoupon) onDelete;

  const _CouponsTable({
    required this.coupons,
    required this.dateFmt,
    required this.onTap,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 700) {
          return ListView.separated(
            itemCount: coupons.length,
            separatorBuilder: (_, _) => const SizedBox(height: 10),
            itemBuilder: (context, i) {
              final c = coupons[i];
              return _CouponCard(
                coupon: c,
                dateFmt: dateFmt,
                discountLabel: _discountLabel(c),
                onTap: () => onTap(c),
                onDelete: () => onDelete(c),
              );
            },
          );
        }
        return _buildTable(context);
      },
    );
  }

  Widget _buildTable(BuildContext context) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: SingleChildScrollView(
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: ConstrainedBox(
            constraints: BoxConstraints(
              minWidth: MediaQuery.of(context).size.width - 56,
            ),
            child: DataTable(
              headingRowColor: WidgetStateProperty.all(
                AdminColors.surfaceSunken,
              ),
              columns: const [
                DataColumn(label: Text('Code')),
                DataColumn(label: Text('Status')),
                DataColumn(label: Text('Discount')),
                DataColumn(label: Text('Expiry')),
                DataColumn(label: Text('Used by')),
                DataColumn(label: Text('')),
              ],
              rows: [
                for (final c in coupons)
                  DataRow(
                    onSelectChanged: (_) => onTap(c),
                    cells: [
                      DataCell(Text(c.code, style: AdminTheme.mono(13))),
                      DataCell(
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            _Badge(
                              label: c.active ? 'Active' : 'Inactive',
                              color: c.active
                                  ? AdminColors.accent
                                  : AdminColors.inkMuted,
                              bg: c.active
                                  ? AdminColors.accentSoft
                                  : AdminColors.surfaceSunken,
                            ),
                            if (c.isExpired) ...[
                              const SizedBox(width: 6),
                              const _Badge(
                                label: 'Expired',
                                color: AdminColors.red,
                                bg: AdminColors.redSoft,
                              ),
                            ],
                          ],
                        ),
                      ),
                      DataCell(
                        Text(
                          _discountLabel(c),
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                      ),
                      DataCell(
                        Text(
                          c.validTill == null
                              ? 'No expiry'
                              : dateFmt.format(c.validTill!),
                          style: TextStyle(
                            color: c.isExpired
                                ? AdminColors.red
                                : AdminColors.inkMuted,
                          ),
                        ),
                      ),
                      DataCell(_UsageCount(code: c.code)),
                      DataCell(
                        IconButton(
                          tooltip: 'Delete coupon',
                          icon: const Icon(
                            Icons.delete_outline_rounded,
                            size: 19,
                            color: AdminColors.red,
                          ),
                          onPressed: () => onDelete(c),
                        ),
                      ),
                    ],
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _discountLabel(AdminCoupon c) {
    if (c.discountPercent != null) {
      final p = c.discountPercent!;
      final pStr = p == p.roundToDouble() ? p.toStringAsFixed(0) : p.toString();
      return '$pStr% off';
    }
    if (c.flatOffPaise != null) {
      return '₹${(c.flatOffPaise! / 100).toStringAsFixed(2)} off';
    }
    return '—';
  }
}

/// Narrow-width stand-in for a coupon `DataRow`, same fields as a tappable
/// card instead of a 6-column table that would otherwise need horizontal
/// scrolling on a phone.
class _CouponCard extends StatelessWidget {
  final AdminCoupon coupon;
  final DateFormat dateFmt;
  final String discountLabel;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  const _CouponCard({
    required this.coupon,
    required this.dateFmt,
    required this.discountLabel,
    required this.onTap,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final c = coupon;
    return Card(
      clipBehavior: Clip.antiAlias,
      margin: EdgeInsets.zero,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(child: Text(c.code, style: AdminTheme.mono(15))),
                  _Badge(
                    label: c.active ? 'Active' : 'Inactive',
                    color: c.active ? AdminColors.accent : AdminColors.inkMuted,
                    bg: c.active
                        ? AdminColors.accentSoft
                        : AdminColors.surfaceSunken,
                  ),
                  if (c.isExpired) ...[
                    const SizedBox(width: 6),
                    const _Badge(
                      label: 'Expired',
                      color: AdminColors.red,
                      bg: AdminColors.redSoft,
                    ),
                  ],
                  IconButton(
                    tooltip: 'Delete coupon',
                    icon: const Icon(
                      Icons.delete_outline_rounded,
                      size: 19,
                      color: AdminColors.red,
                    ),
                    onPressed: onDelete,
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                discountLabel,
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 15,
                ),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Text(
                    c.validTill == null
                        ? 'No expiry'
                        : dateFmt.format(c.validTill!),
                    style: TextStyle(
                      fontSize: 12.5,
                      color: c.isExpired
                          ? AdminColors.red
                          : AdminColors.inkMuted,
                    ),
                  ),
                  const Spacer(),
                  _UsageCount(code: c.code),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// How many merchants' Pro purchase used this code — surfaces
/// `AdminBusiness.couponCodeUsed`, written by the mobile app's
/// razorpay_service.dart at checkout, so an admin can see whether a coupon
/// is actually being used before deciding to deactivate or extend it.
class _UsageCount extends StatelessWidget {
  final String code;
  const _UsageCount({required this.code});

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<dynamic>>(
      future: AdminFirestoreService.instance.getBusinessesUsingCoupon(code),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const SizedBox(
            width: 14,
            height: 14,
            child: CircularProgressIndicator(strokeWidth: 1.5),
          );
        }
        final count = snapshot.data!.length;
        return Text(
          count == 0
              ? 'Not used yet'
              : '$count merchant${count == 1 ? '' : 's'}',
          style: TextStyle(
            fontSize: 12.5,
            fontWeight: count == 0 ? FontWeight.w400 : FontWeight.w700,
            color: count == 0 ? AdminColors.inkFaint : AdminColors.ink,
          ),
        );
      },
    );
  }
}

class _Badge extends StatelessWidget {
  final String label;
  final Color color;
  final Color bg;
  const _Badge({required this.label, required this.color, required this.bg});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 11,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _MessageState extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String title;
  final String subtitle;
  const _MessageState({
    required this.icon,
    required this.color,
    required this.title,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 44, color: color),
          const SizedBox(height: 12),
          Text(title, style: AdminTheme.heading(16)),
          const SizedBox(height: 6),
          Text(
            subtitle,
            style: const TextStyle(color: AdminColors.inkMuted, fontSize: 13),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

/// Create/edit form. `existing == null` means "new coupon"; otherwise the
/// dialog pre-fills from it and Save overwrites the same doc (coupons are
/// keyed by their own code, so `upsertCoupon` is naturally also "edit").
class _CouponFormDialog extends StatefulWidget {
  final AdminCoupon? existing;
  const _CouponFormDialog({required this.existing});

  @override
  State<_CouponFormDialog> createState() => _CouponFormDialogState();
}

class _CouponFormDialogState extends State<_CouponFormDialog> {
  late final TextEditingController _codeCtrl;
  late final TextEditingController _valueCtrl;
  late bool _active;
  late _DiscountType _type;
  DateTime? _expiry;
  bool _saving = false;
  String? _codeError;
  String? _valueError;

  bool get _isEditing => widget.existing != null;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _codeCtrl = TextEditingController(text: e?.code ?? '');
    _active = e?.active ?? true;
    _type = (e?.flatOffPaise != null)
        ? _DiscountType.flat
        : _DiscountType.percent;
    final initialValue = e == null
        ? ''
        : (_type == _DiscountType.percent
              ? (e.discountPercent == null
                    ? ''
                    : (e.discountPercent! == e.discountPercent!.roundToDouble()
                          ? e.discountPercent!.toStringAsFixed(0)
                          : e.discountPercent!.toString()))
              : (e.flatOffPaise == null
                    ? ''
                    : (e.flatOffPaise! / 100).toStringAsFixed(2)));
    _valueCtrl = TextEditingController(text: initialValue);
    _expiry = e?.validTill;
  }

  @override
  void dispose() {
    _codeCtrl.dispose();
    _valueCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 440),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  _isEditing ? 'Edit coupon' : 'New coupon',
                  style: AdminTheme.heading(19),
                ),
                const SizedBox(height: 18),
                TextField(
                  controller: _codeCtrl,
                  enabled: !_isEditing,
                  textCapitalization: TextCapitalization.characters,
                  inputFormatters: [
                    UpperCaseTextFormatter(),
                    FilteringTextInputFormatter.deny(RegExp(r'\s')),
                  ],
                  decoration: InputDecoration(
                    labelText: 'Code',
                    hintText: 'e.g. FESTIVE50',
                    errorText: _codeError,
                    helperText: _isEditing
                        ? 'Code can\'t be changed once created — delete and recreate instead.'
                        : 'This becomes the document ID — avoid "/" and spaces.',
                    helperMaxLines: 2,
                  ),
                  style: AdminTheme.mono(14),
                  onChanged: (_) => setState(
                    () => _codeError = _validateCode(_codeCtrl.text),
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Active',
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          color: AdminColors.ink,
                        ),
                      ),
                    ),
                    Switch(
                      value: _active,
                      onChanged: (v) => setState(() => _active = v),
                    ),
                  ],
                ),
                const Divider(height: 28),
                Text(
                  'Discount type',
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    color: AdminColors.ink,
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 4),
                RadioGroup<_DiscountType>(
                  groupValue: _type,
                  onChanged: (v) => setState(() {
                    _type = v!;
                    _valueError = null;
                  }),
                  child: Column(
                    children: const [
                      RadioListTile<_DiscountType>(
                        contentPadding: EdgeInsets.zero,
                        dense: true,
                        title: Text('Percent off'),
                        value: _DiscountType.percent,
                      ),
                      RadioListTile<_DiscountType>(
                        contentPadding: EdgeInsets.zero,
                        dense: true,
                        title: Text('Flat amount off (₹)'),
                        value: _DiscountType.flat,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _valueCtrl,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
                  ],
                  decoration: InputDecoration(
                    labelText: _type == _DiscountType.percent
                        ? 'Percent off (1-100)'
                        : 'Amount off (₹)',
                    prefixText: _type == _DiscountType.percent ? null : '₹ ',
                    suffixText: _type == _DiscountType.percent ? '%' : null,
                    errorText: _valueError,
                  ),
                  onChanged: (_) => setState(() => _valueError = null),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        _expiry == null
                            ? 'No expiry'
                            : 'Expires ${DateFormat('dd MMM yyyy').format(_expiry!)}',
                        style: const TextStyle(
                          color: AdminColors.inkMuted,
                          fontSize: 13,
                        ),
                      ),
                    ),
                    TextButton.icon(
                      onPressed: _pickExpiry,
                      icon: const Icon(Icons.calendar_month_rounded, size: 17),
                      label: Text(_expiry == null ? 'Set expiry' : 'Change'),
                    ),
                    if (_expiry != null)
                      IconButton(
                        tooltip: 'Clear expiry',
                        icon: const Icon(Icons.close_rounded, size: 18),
                        onPressed: () => setState(() => _expiry = null),
                      ),
                  ],
                ),
                const SizedBox(height: 20),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: _saving ? null : () => Navigator.pop(context),
                      child: const Text('Cancel'),
                    ),
                    const SizedBox(width: 8),
                    ElevatedButton(
                      onPressed: _saving ? null : _save,
                      child: _saving
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : Text(_isEditing ? 'Save changes' : 'Create coupon'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _pickExpiry() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _expiry ?? now.add(const Duration(days: 30)),
      firstDate: DateTime(now.year - 1),
      lastDate: DateTime(now.year + 5),
    );
    if (picked != null) setState(() => _expiry = picked);
  }

  String? _validateCode(String raw) {
    final code = raw.trim();
    if (code.isEmpty) return 'Code is required';
    if (code.contains('/')) {
      return 'Code can\'t contain "/" — it becomes the document ID';
    }
    return null;
  }

  String? _validateValue(String raw) {
    final v = double.tryParse(raw.trim());
    if (v == null || v <= 0) return 'Enter a value greater than 0';
    if (_type == _DiscountType.percent && v > 100) {
      return 'Percent off can\'t exceed 100';
    }
    return null;
  }

  Future<void> _save() async {
    final codeErr = _validateCode(_codeCtrl.text);
    final valueErr = _validateValue(_valueCtrl.text);
    setState(() {
      _codeError = codeErr;
      _valueError = valueErr;
    });
    if (codeErr != null || valueErr != null) return;

    final code = _codeCtrl.text.trim().toUpperCase();
    final value = double.parse(_valueCtrl.text.trim());
    final clampedPercent = _type == _DiscountType.percent
        ? value.clamp(1, 100).toDouble()
        : null;
    final flatOffPaise = _type == _DiscountType.flat
        ? (value * 100).round()
        : null;

    final coupon = AdminCoupon(
      code: code,
      active: _active,
      discountPercent: clampedPercent,
      flatOffPaise: flatOffPaise,
      validTill: _expiry,
    );

    setState(() => _saving = true);
    try {
      await AdminFirestoreService.instance.upsertCoupon(coupon);
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(_isEditing ? 'Saved $code' : 'Created $code')),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to save: $e'),
            backgroundColor: AdminColors.red,
          ),
        );
      }
    }
  }
}

/// Forces every keystroke in the code field to uppercase, in place, without
/// fighting the cursor position — Firestore doc IDs are case-sensitive and
/// coupon codes are conventionally shown uppercase everywhere in the UI.
class UpperCaseTextFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    return TextEditingValue(
      text: newValue.text.toUpperCase(),
      selection: newValue.selection,
    );
  }
}
