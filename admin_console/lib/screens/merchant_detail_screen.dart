import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/admin_models.dart';
import '../services/admin_firestore_service.dart';
import '../theme/admin_theme.dart';

/// Groups a whole-rupee digit string the Indian way (last 3 digits, then
/// pairs): "1234568" -> "12,34,568".
String _indianGroup(String digits) {
  if (digits.length <= 3) return digits;
  final lastThree = digits.substring(digits.length - 3);
  var remaining = digits.substring(0, digits.length - 3);
  final groups = <String>[];
  while (remaining.length > 2) {
    groups.insert(0, remaining.substring(remaining.length - 2));
    remaining = remaining.substring(0, remaining.length - 2);
  }
  if (remaining.isNotEmpty) groups.insert(0, remaining);
  return '${groups.join(',')},$lastThree';
}

/// Formats a paise integer as a rupee string, e.g. `123456` paise -> `₹1,235`
/// (rounded to the nearest rupee — this project has no shared currency
/// formatter, so this small helper is carried locally by every screen that
/// needs one).
String _formatPaise(int paise) {
  final rupees = (paise / 100).round();
  final sign = rupees < 0 ? '-' : '';
  return '$sign₹${_indianGroup(rupees.abs().toString())}';
}

String _titleCase(String s) {
  if (s.isEmpty) return s;
  return s
      .split(RegExp(r'[_\s]+'))
      .where((w) => w.isNotEmpty)
      .map((w) => w[0].toUpperCase() + w.substring(1).toLowerCase())
      .join(' ');
}

String _formatQty(double q) {
  if (q == q.roundToDouble()) return q.toStringAsFixed(0);
  return q.toStringAsFixed(2);
}

class _MerchantData {
  final List<AdminSale> sales;
  final List<AdminProduct> products;
  final List<AdminCustomer> customers;
  const _MerchantData({
    required this.sales,
    required this.products,
    required this.customers,
  });
}

/// One merchant's full profile: header, Pro subscription control, and
/// Sales/Products/Customers, fetched once (concurrently) on open.
class MerchantDetailScreen extends StatefulWidget {
  final AdminBusiness business;
  const MerchantDetailScreen({super.key, required this.business});

  @override
  State<MerchantDetailScreen> createState() => _MerchantDetailScreenState();
}

class _MerchantDetailScreenState extends State<MerchantDetailScreen> {
  late AdminBusiness _business;
  late Future<_MerchantData> _dataFuture;
  bool _proBusy = false;

  @override
  void initState() {
    super.initState();
    _business = widget.business;
    _dataFuture = _loadData();
  }

  Future<_MerchantData> _loadData() async {
    final results = await Future.wait([
      AdminFirestoreService.instance.getSalesForBusiness(_business.id),
      AdminFirestoreService.instance.getProductsForBusiness(_business.id),
      AdminFirestoreService.instance.getCustomersForBusiness(_business.id),
    ]);
    return _MerchantData(
      sales: results[0] as List<AdminSale>,
      products: results[1] as List<AdminProduct>,
      customers: results[2] as List<AdminCustomer>,
    );
  }

  Future<void> _refreshBusiness() async {
    final updated = await AdminFirestoreService.instance.getBusiness(
      _business.id,
    );
    if (updated != null && mounted) setState(() => _business = updated);
  }

  void _showSnack(String message, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? AdminColors.red : AdminColors.ink,
      ),
    );
  }

  Future<bool> _confirm({
    required String title,
    required String message,
    required String confirmLabel,
    bool destructive = false,
  }) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title, style: AdminTheme.heading(16)),
        content: Text(
          message,
          style: const TextStyle(
            color: AdminColors.inkMuted,
            fontSize: 13,
            height: 1.4,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: destructive
                ? ElevatedButton.styleFrom(
                    backgroundColor: AdminColors.red,
                    foregroundColor: Colors.white,
                  )
                : ElevatedButton.styleFrom(
                    backgroundColor: AdminColors.accent,
                    foregroundColor: Colors.white,
                  ),
            child: Text(confirmLabel),
          ),
        ],
      ),
    );
    return result ?? false;
  }

  Future<void> _handleGrantPro() async {
    final plan = await showDialog<String>(
      context: context,
      builder: (ctx) => _PlanPickerDialog(businessName: _business.name),
    );
    if (plan == null || !mounted) return;

    final days = plan == 'annual' ? 365 : 30;
    final expiry = DateTime.now().add(Duration(days: days));
    final confirmed = await _confirm(
      title: 'Grant Pro to ${_business.name}?',
      message:
          'This immediately activates ${plan == 'annual' ? 'an annual' : 'a monthly'} Pro subscription for "${_business.name}", '
          'valid until ${DateFormat('d MMM yyyy').format(expiry)}. Their app will unlock Pro features and reflect this within seconds.',
      confirmLabel: 'Grant Pro',
    );
    if (!confirmed || !mounted) return;

    setState(() => _proBusy = true);
    try {
      await AdminFirestoreService.instance.setProStatus(
        _business.id,
        isPro: true,
        plan: plan,
        expiry: expiry,
      );
      await _refreshBusiness();
      if (mounted) _showSnack('Pro granted to ${_business.name}.');
    } catch (e) {
      if (mounted) _showSnack('Failed to grant Pro: $e', isError: true);
    } finally {
      if (mounted) setState(() => _proBusy = false);
    }
  }

  Future<void> _handleToggleDisabled() async {
    final willDisable = !_business.isDisabled;
    final confirmed = await _confirm(
      title: willDisable ? 'Disable ${_business.name}?' : 'Re-enable ${_business.name}?',
      message: willDisable
          ? 'This immediately signs "${_business.name}" out of their Android app and blocks them from logging back in, within seconds. '
              'Their products, sales, and customer data are NOT touched — you can re-enable access at any time.'
          : 'This restores "${_business.name}"\'s access to their Android app immediately. They can sign back in right away.',
      confirmLabel: willDisable ? 'Disable account' : 'Re-enable account',
      destructive: willDisable,
    );
    if (!confirmed || !mounted) return;

    setState(() => _proBusy = true);
    try {
      await AdminFirestoreService.instance.setAccountDisabled(_business.id, willDisable);
      await _refreshBusiness();
      if (mounted) {
        _showSnack(willDisable ? '${_business.name} has been disabled.' : '${_business.name} re-enabled.');
      }
    } catch (e) {
      if (mounted) _showSnack('Failed to update account status: $e', isError: true);
    } finally {
      if (mounted) setState(() => _proBusy = false);
    }
  }

  Future<void> _handlePermanentDelete() async {
    final typedName = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => _PermanentDeleteDialog(business: _business),
    );
    if (typedName == null || !mounted) return;

    setState(() => _proBusy = true);
    try {
      await AdminFirestoreService.instance.permanentlyDeleteBusiness(
        _business.id,
        ownerUid: _business.ownerUid,
      );
      if (!mounted) return;
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${_business.name} permanently deleted.')),
      );
    } catch (e) {
      if (mounted) {
        setState(() => _proBusy = false);
        _showSnack('Failed to delete: $e', isError: true);
      }
    }
  }

  Future<void> _handleRevokePro() async {
    final expiryNote = _business.proExpiry != null
        ? ' (was valid until ${DateFormat('d MMM yyyy').format(_business.proExpiry!)})'
        : '';
    final confirmed = await _confirm(
      title: 'Revoke Pro from ${_business.name}?',
      message:
          'This immediately removes the Pro subscription for "${_business.name}"$expiryNote. '
          'They will lose access to Pro features in the app right away.',
      confirmLabel: 'Revoke Pro',
      destructive: true,
    );
    if (!confirmed || !mounted) return;

    setState(() => _proBusy = true);
    try {
      await AdminFirestoreService.instance.setProStatus(
        _business.id,
        isPro: false,
      );
      await _refreshBusiness();
      if (mounted) _showSnack('Pro revoked from ${_business.name}.');
    } catch (e) {
      if (mounted) _showSnack('Failed to revoke Pro: $e', isError: true);
    } finally {
      if (mounted) setState(() => _proBusy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_business.name, style: AdminTheme.heading(18)),
        actions: [
          if (_business.isDisabled)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
                decoration: BoxDecoration(
                  color: AdminColors.redSoft,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: AdminColors.red.withValues(alpha: 0.35)),
                ),
                child: const Text(
                  'DISABLED',
                  style: TextStyle(color: AdminColors.red, fontSize: 11, fontWeight: FontWeight.w800),
                ),
              ),
            ),
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: _proBusy
                ? const SizedBox.shrink()
                : TextButton.icon(
                    onPressed: _handleToggleDisabled,
                    icon: Icon(
                      _business.isDisabled ? Icons.lock_open_rounded : Icons.block_rounded,
                      size: 17,
                      color: _business.isDisabled ? AdminColors.accent : AdminColors.red,
                    ),
                    label: Text(
                      _business.isDisabled ? 'Re-enable' : 'Disable',
                      style: TextStyle(color: _business.isDisabled ? AdminColors.accent : AdminColors.red),
                    ),
                  ),
          ),
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: IconButton(
              tooltip: 'Permanently delete this merchant',
              onPressed: _proBusy ? null : _handlePermanentDelete,
              icon: const Icon(Icons.delete_forever_rounded, color: AdminColors.red),
            ),
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _HeaderCard(business: _business),
            const SizedBox(height: 16),
            _ProCard(
              business: _business,
              busy: _proBusy,
              onGrant: _handleGrantPro,
              onRevoke: _handleRevokePro,
            ),
            const SizedBox(height: 16),
            Expanded(
              child: FutureBuilder<_MerchantData>(
                future: _dataFuture,
                builder: (context, snapshot) {
                  if (snapshot.hasError) {
                    return _MessageState(
                      icon: Icons.error_outline_rounded,
                      color: AdminColors.red,
                      title: 'Could not load merchant data',
                      subtitle: '${snapshot.error}',
                    );
                  }
                  if (!snapshot.hasData) {
                    return const _MessageState(
                      icon: Icons.hourglass_top_rounded,
                      color: AdminColors.inkFaint,
                      title: 'Loading merchant data…',
                      subtitle: 'Fetching sales, products, and customers.',
                      loading: true,
                    );
                  }
                  final data = snapshot.data!;
                  return _MerchantTabs(data: data);
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _HeaderCard extends StatelessWidget {
  final AdminBusiness business;
  const _HeaderCard({required this.business});

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                color: AdminColors.accentSoft,
                borderRadius: BorderRadius.circular(12),
              ),
              alignment: Alignment.center,
              child: Text(
                business.name.isNotEmpty ? business.name[0].toUpperCase() : '?',
                style: AdminTheme.heading(22)
                    .copyWith(color: AdminColors.accent),
              ),
            ),
            const SizedBox(width: 18),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          business.name,
                          style: AdminTheme.heading(18),
                        ),
                      ),
                      const SizedBox(width: 10),
                      _ProBadge(business: business),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 28,
                    runSpacing: 10,
                    children: [
                      _InfoTile(
                        label: 'Owner',
                        value: business.ownerName.isEmpty
                            ? '—'
                            : business.ownerName,
                      ),
                      _InfoTile(
                        label: 'Phone',
                        value: business.phone.isEmpty ? '—' : business.phone,
                      ),
                      _InfoTile(
                        label: 'Email',
                        value: business.email.isEmpty ? '—' : business.email,
                      ),
                      _InfoTile(
                        label: 'Business type',
                        value: _titleCase(business.businessType),
                      ),
                      _InfoTile(
                        label: 'GSTIN',
                        value: business.gstin.isEmpty ? '—' : business.gstin,
                      ),
                      _InfoTile(
                        label: 'Address',
                        value: business.address.isEmpty
                            ? '—'
                            : business.address,
                        maxWidth: 260,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _InfoTile extends StatelessWidget {
  final String label;
  final String value;
  final double? maxWidth;
  const _InfoTile({required this.label, required this.value, this.maxWidth});

  @override
  Widget build(BuildContext context) {
    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label.toUpperCase(),
          style: const TextStyle(
            color: AdminColors.inkFaint,
            fontSize: 10.5,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.4,
          ),
        ),
        const SizedBox(height: 3),
        Text(
          value,
          style: const TextStyle(
            color: AdminColors.ink,
            fontSize: 13,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
    if (maxWidth == null) return content;
    return ConstrainedBox(
      constraints: BoxConstraints(maxWidth: maxWidth!),
      child: content,
    );
  }
}

class _ProBadge extends StatelessWidget {
  final AdminBusiness business;
  const _ProBadge({required this.business});

  @override
  Widget build(BuildContext context) {
    final Color fg;
    final Color bg;
    final String label;
    if (business.isProEffective) {
      fg = AdminColors.accent;
      bg = AdminColors.accentSoft;
      label = 'PRO';
    } else if (business.isPro) {
      fg = AdminColors.amber;
      bg = AdminColors.amberSoft;
      label = 'EXPIRED';
    } else {
      fg = AdminColors.inkMuted;
      bg = AdminColors.surfaceSunken;
      label = 'FREE';
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: fg.withValues(alpha: 0.35)),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: fg,
          fontSize: 11.5,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

class _ProCard extends StatelessWidget {
  final AdminBusiness business;
  final bool busy;
  final VoidCallback onGrant;
  final VoidCallback onRevoke;
  const _ProCard({
    required this.business,
    required this.busy,
    required this.onGrant,
    required this.onRevoke,
  });

  @override
  Widget build(BuildContext context) {
    final isEffective = business.isProEffective;
    return Card(
      margin: EdgeInsets.zero,
      color: isEffective ? AdminColors.accentSoft : AdminColors.surface,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        child: Row(
          children: [
            Icon(
              Icons.workspace_premium_rounded,
              color: isEffective ? AdminColors.accent : AdminColors.inkFaint,
              size: 22,
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Pro subscription', style: AdminTheme.heading(14)),
                  const SizedBox(height: 3),
                  Text(
                    isEffective
                        ? 'Pro (${_titleCase(business.proPlan.isEmpty ? 'plan' : business.proPlan)})'
                              '${business.proExpiry != null ? ' until ${DateFormat('d MMM yyyy').format(business.proExpiry!)}' : ''}'
                        : business.isPro
                        ? 'Pro expired${business.proExpiry != null ? ' on ${DateFormat('d MMM yyyy').format(business.proExpiry!)}' : ''}'
                        : 'This merchant is on the Free plan.',
                    style: const TextStyle(
                      color: AdminColors.inkMuted,
                      fontSize: 12.5,
                    ),
                  ),
                  if (business.couponCodeUsed != null && business.couponCodeUsed!.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: AdminColors.violetSoft,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        'Used coupon: ${business.couponCodeUsed}',
                        style: const TextStyle(color: AdminColors.violet, fontSize: 11, fontWeight: FontWeight.w700),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 12),
            if (busy)
              const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2.5),
              )
            else if (isEffective)
              OutlinedButton.icon(
                onPressed: onRevoke,
                style: OutlinedButton.styleFrom(
                  foregroundColor: AdminColors.red,
                  side: const BorderSide(color: AdminColors.red),
                ),
                icon: const Icon(Icons.remove_circle_outline_rounded, size: 16),
                label: const Text('Revoke Pro'),
              )
            else
              ElevatedButton.icon(
                onPressed: onGrant,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AdminColors.accent,
                  foregroundColor: Colors.white,
                ),
                icon: const Icon(Icons.add_circle_outline_rounded, size: 16),
                label: const Text('Grant Pro'),
              ),
          ],
        ),
      ),
    );
  }
}

/// Irreversible-action confirmation: the admin must type the merchant's
/// exact store name before the delete button enables at all — the same
/// "type to confirm" pattern used for destructive actions everywhere,
/// specifically because a plain Yes/No dialog is too easy to click through
/// on a real merchant's actual business data with no way back.
class _PermanentDeleteDialog extends StatefulWidget {
  final AdminBusiness business;
  const _PermanentDeleteDialog({required this.business});

  @override
  State<_PermanentDeleteDialog> createState() => _PermanentDeleteDialogState();
}

class _PermanentDeleteDialogState extends State<_PermanentDeleteDialog> {
  final _typedCtrl = TextEditingController();
  bool _matches = false;

  @override
  void dispose() {
    _typedCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final name = widget.business.name;
    return AlertDialog(
      title: Row(
        children: [
          const Icon(Icons.warning_rounded, color: AdminColors.red, size: 22),
          const SizedBox(width: 10),
          Expanded(child: Text('Permanently delete "$name"?', style: AdminTheme.heading(16))),
        ],
      ),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'This erases every product, category, customer, and sale this merchant has ever synced to the cloud — permanently, with no undo. Their Android app is signed out immediately, and the same email can sign up again and build a brand-new store from zero.',
              style: TextStyle(color: AdminColors.inkMuted, fontSize: 13, height: 1.4),
            ),
            const SizedBox(height: 10),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AdminColors.amberSoft,
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Text(
                'This only reaches the cloud. If this device still has the store\'s data cached locally, it stays there until that app is reinstalled or its data is cleared — this action cannot reach into a merchant\'s phone.',
                style: TextStyle(color: AdminColors.amber, fontSize: 12, height: 1.4),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'Type "$name" to confirm:',
              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13, color: AdminColors.ink),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _typedCtrl,
              autofocus: true,
              onChanged: (v) => setState(() => _matches = v.trim() == name),
              decoration: InputDecoration(
                hintText: name,
                isDense: true,
                border: const OutlineInputBorder(),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: _matches ? () => Navigator.pop(context, _typedCtrl.text.trim()) : null,
          style: ElevatedButton.styleFrom(backgroundColor: AdminColors.red, foregroundColor: Colors.white),
          child: const Text('Permanently delete'),
        ),
      ],
    );
  }
}

class _PlanPickerDialog extends StatefulWidget {
  final String businessName;
  const _PlanPickerDialog({required this.businessName});

  @override
  State<_PlanPickerDialog> createState() => _PlanPickerDialogState();
}

class _PlanPickerDialogState extends State<_PlanPickerDialog> {
  String _plan = 'monthly';

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(
        'Grant Pro — ${widget.businessName}',
        style: AdminTheme.heading(16),
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Choose a plan:',
            style: TextStyle(color: AdminColors.inkMuted, fontSize: 12.5),
          ),
          RadioGroup<String>(
            groupValue: _plan,
            onChanged: (v) => setState(() => _plan = v!),
            child: const Column(
              children: [
                RadioListTile<String>(
                  value: 'monthly',
                  title: Text('Monthly (30 days)'),
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                ),
                RadioListTile<String>(
                  value: 'annual',
                  title: Text('Annual (365 days)'),
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                ),
              ],
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: () => Navigator.pop(context, _plan),
          child: const Text('Continue'),
        ),
      ],
    );
  }
}

class _MerchantTabs extends StatelessWidget {
  final _MerchantData data;
  const _MerchantTabs({required this.data});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      child: Card(
        margin: EdgeInsets.zero,
        clipBehavior: Clip.antiAlias,
        child: Column(
          children: [
            TabBar(
              labelColor: AdminColors.accent,
              unselectedLabelColor: AdminColors.inkMuted,
              indicatorColor: AdminColors.accent,
              tabs: [
                Tab(text: 'Sales (${data.sales.length})'),
                Tab(text: 'Products (${data.products.length})'),
                Tab(text: 'Customers (${data.customers.length})'),
              ],
            ),
            const Divider(height: 1, color: AdminColors.border),
            Expanded(
              child: TabBarView(
                children: [
                  _SalesTab(sales: data.sales),
                  _ProductsTab(products: data.products),
                  _CustomersTab(customers: data.customers),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SalesTab extends StatelessWidget {
  final List<AdminSale> sales;
  const _SalesTab({required this.sales});

  Color _statusColor(String status) {
    switch (status.toLowerCase()) {
      case 'completed':
      case 'paid':
        return AdminColors.accent;
      case 'refunded':
      case 'cancelled':
      case 'void':
        return AdminColors.red;
      case 'pending':
        return AdminColors.amber;
      default:
        return AdminColors.inkMuted;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (sales.isEmpty) {
      return const _MessageState(
        icon: Icons.receipt_long_outlined,
        color: AdminColors.inkFaint,
        title: 'No sales yet',
        subtitle:
            'Invoices will appear here once this merchant starts billing.',
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.all(12),
      itemCount: sales.length,
      separatorBuilder: (_, _) =>
          const Divider(height: 1, color: AdminColors.border),
      itemBuilder: (context, i) {
        final s = sales[i];
        final color = _statusColor(s.status);
        return ListTile(
          leading: CircleAvatar(
            backgroundColor: AdminColors.surfaceSunken,
            child: Icon(
              Icons.receipt_rounded,
              color: AdminColors.inkMuted,
              size: 18,
            ),
          ),
          title: Text(
            '#${s.invoiceNumber} · ${s.customerName}',
            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5),
          ),
          subtitle: Text(
            '${s.createdAt != null ? DateFormat('d MMM yyyy, h:mm a').format(s.createdAt!) : 'Unknown date'} · ${_titleCase(s.paymentMethod)}',
            style: const TextStyle(color: AdminColors.inkMuted, fontSize: 12),
          ),
          trailing: Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                _formatPaise(s.totalAmountPaise),
                style: AdminTheme.mono(14),
              ),
              const SizedBox(height: 3),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(5),
                ),
                child: Text(
                  _titleCase(s.status),
                  style: TextStyle(
                    color: color,
                    fontSize: 10.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _ProductsTab extends StatelessWidget {
  final List<AdminProduct> products;
  const _ProductsTab({required this.products});

  @override
  Widget build(BuildContext context) {
    if (products.isEmpty) {
      return const _MessageState(
        icon: Icons.inventory_2_outlined,
        color: AdminColors.inkFaint,
        title: 'No products yet',
        subtitle: 'This merchant has not synced a catalog yet.',
      );
    }
    final sorted = List<AdminProduct>.of(products)
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return ListView.separated(
      padding: const EdgeInsets.all(12),
      itemCount: sorted.length,
      separatorBuilder: (_, _) =>
          const Divider(height: 1, color: AdminColors.border),
      itemBuilder: (context, i) {
        final p = sorted[i];
        return ListTile(
          leading: CircleAvatar(
            backgroundColor: p.isLowStock
                ? AdminColors.redSoft
                : AdminColors.surfaceSunken,
            child: Icon(
              Icons.inventory_2_rounded,
              color: p.isLowStock ? AdminColors.red : AdminColors.inkMuted,
              size: 18,
            ),
          ),
          title: Text(
            p.name,
            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5),
          ),
          subtitle: p.barcode == null || p.barcode!.isEmpty
              ? null
              : Text(
                  p.barcode!,
                  style: AdminTheme.mono(11)
                      .copyWith(color: AdminColors.inkFaint),
                ),
          trailing: Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                _formatPaise(p.sellingPricePaise),
                style: AdminTheme.mono(14),
              ),
              const SizedBox(height: 3),
              Text(
                '${_formatQty(p.stockQuantity)} ${p.unit} ${p.isLowStock ? '· low stock' : ''}',
                style: TextStyle(
                  color: p.isLowStock ? AdminColors.red : AdminColors.inkMuted,
                  fontSize: 11.5,
                  fontWeight: p.isLowStock ? FontWeight.w700 : FontWeight.w400,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _CustomersTab extends StatelessWidget {
  final List<AdminCustomer> customers;
  const _CustomersTab({required this.customers});

  @override
  Widget build(BuildContext context) {
    if (customers.isEmpty) {
      return const _MessageState(
        icon: Icons.people_outline_rounded,
        color: AdminColors.inkFaint,
        title: 'No customers yet',
        subtitle: 'This merchant has not synced their khata book yet.',
      );
    }
    final sorted = List<AdminCustomer>.of(customers)
      ..sort((a, b) => b.currentBalancePaise.compareTo(a.currentBalancePaise));
    return ListView.separated(
      padding: const EdgeInsets.all(12),
      itemCount: sorted.length,
      separatorBuilder: (_, _) =>
          const Divider(height: 1, color: AdminColors.border),
      itemBuilder: (context, i) {
        final c = sorted[i];
        final owesMoney = c.currentBalancePaise > 0;
        return ListTile(
          leading: CircleAvatar(
            backgroundColor: owesMoney
                ? AdminColors.amberSoft
                : AdminColors.surfaceSunken,
            child: Icon(
              Icons.person_rounded,
              color: owesMoney ? AdminColors.amber : AdminColors.inkMuted,
              size: 18,
            ),
          ),
          title: Text(
            c.name,
            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5),
          ),
          subtitle: Text(
            c.phone.isEmpty ? '—' : c.phone,
            style: const TextStyle(color: AdminColors.inkMuted, fontSize: 12),
          ),
          trailing: Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                _formatPaise(c.currentBalancePaise),
                style: AdminTheme.mono(14).copyWith(
                  color: owesMoney ? AdminColors.amber : AdminColors.ink,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                owesMoney ? 'balance due' : 'settled',
                style: const TextStyle(
                  color: AdminColors.inkFaint,
                  fontSize: 10.5,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _MessageState extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String title;
  final String subtitle;
  final bool loading;
  const _MessageState({
    required this.icon,
    required this.color,
    required this.title,
    required this.subtitle,
    this.loading = false,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (loading)
            const SizedBox(
              width: 28,
              height: 28,
              child: CircularProgressIndicator(strokeWidth: 2.5),
            )
          else
            Icon(icon, size: 40, color: color),
          const SizedBox(height: 14),
          Text(title, style: AdminTheme.heading(15)),
          const SizedBox(height: 4),
          Text(
            subtitle,
            textAlign: TextAlign.center,
            style: const TextStyle(color: AdminColors.inkMuted, fontSize: 12.5),
          ),
        ],
      ),
    );
  }
}
