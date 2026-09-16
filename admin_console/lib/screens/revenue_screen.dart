import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/admin_models.dart';
import '../services/admin_firestore_service.dart';
import '../theme/admin_theme.dart';

/// KamaiPlus's OWN subscription income — every Razorpay payment that was
/// actually captured.
///
/// This screen exists because the console had no view of real income at all.
/// "Lifetime revenue" on the dashboard is the sum of the MERCHANTS' shop
/// takings (`businesses.total_revenue_paise`) — a measure of how big the
/// platform is, not of what KamaiPlus earned. An owner reading it as income
/// would be out by orders of magnitude.
///
/// Source is `razorpay_payments`, written only by the `verifyRazorpayPayment`
/// Cloud Function through the Admin SDK, and only after Razorpay's own API
/// confirmed the payment was `captured`. firestore.rules forbids every client
/// write, so nothing a device claims can inflate these figures.
class RevenueScreen extends StatefulWidget {
  const RevenueScreen({super.key});

  @override
  State<RevenueScreen> createState() => _RevenueScreenState();
}

class _RevenueScreenState extends State<RevenueScreen> {
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: StreamBuilder<List<AdminPayment>>(
        stream: AdminFirestoreService.instance.watchPayments(),
        builder: (context, paySnap) {
          if (paySnap.hasError) {
            return _Message(
              icon: Icons.lock_outline_rounded,
              color: AdminColors.red,
              title: 'Could not load payments',
              subtitle:
                  'If this says "permission denied", deploy the updated firestore.rules — '
                  'razorpay_payments needs its admin read rule.\n\n${paySnap.error}',
            );
          }
          if (!paySnap.hasData) {
            return const _Message(
              icon: Icons.hourglass_top_rounded,
              color: AdminColors.inkFaint,
              title: 'Loading payments…',
              subtitle: 'Reading the verified payment ledger.',
              loading: true,
            );
          }

          final payments = paySnap.data!;

          return StreamBuilder<List<AdminBusiness>>(
            stream: AdminFirestoreService.instance.watchBusinesses(),
            builder: (context, bizSnap) {
              final businesses = bizSnap.data ?? const <AdminBusiness>[];
              return _RevenueBody(payments: payments, businesses: businesses);
            },
          );
        },
      ),
    );
  }
}

class _RevenueBody extends StatelessWidget {
  final List<AdminPayment> payments;
  final List<AdminBusiness> businesses;
  const _RevenueBody({required this.payments, required this.businesses});

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final monthStart = DateTime(now.year, now.month);
    final prevMonthStart = DateTime(now.year, now.month - 1);

    int sum(Iterable<AdminPayment> ps) => ps.fold(0, (s, p) => s + p.amountPaise);

    final thisMonth = payments.where((p) => (p.verifiedAt ?? DateTime(2000)).isAfter(monthStart));
    final prevMonth = payments.where((p) {
      final d = p.verifiedAt ?? DateTime(2000);
      return d.isAfter(prevMonthStart) && d.isBefore(monthStart);
    });

    final lifetimePaise = sum(payments);
    final thisMonthPaise = sum(thisMonth);
    final prevMonthPaise = sum(prevMonth);

    // A payment is only "live income" while the subscription it bought is
    // still in date. Counting lapsed ones as active would overstate MRR.
    final activePayments = payments.where((p) => p.isStillActive).toList();
    final payingBusinessIds = activePayments.map((p) => p.businessId).toSet();

    final trialCount = businesses.where((b) => b.isTrialActive).length;
    final expiredPayers = payments
        .map((p) => p.businessId)
        .toSet()
        .difference(payingBusinessIds)
        .length;

    // Mismatch radar: a device believing it is Pro with no verified payment
    // and no live trial behind it. Usually a purchase whose verification never
    // completed — a paying customer possibly without what they paid for.
    final mismatches = businesses.where((b) => b.hasProMismatch).toList();

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Subscription Revenue', style: AdminTheme.heading(22)),
          const SizedBox(height: 4),
          const Text(
            'Real money received by KamaiPlus. Every row below was confirmed as captured '
            'by Razorpay before it was written — nothing here comes from a merchant\'s device.',
            style: TextStyle(color: AdminColors.inkMuted, fontSize: 13),
          ),
          const SizedBox(height: 22),

          LayoutBuilder(
            builder: (context, c) {
              final cross = c.maxWidth >= 1080 ? 4 : (c.maxWidth >= 720 ? 2 : 1);
              return GridView.count(
                crossAxisCount: cross,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                crossAxisSpacing: 16,
                mainAxisSpacing: 16,
                childAspectRatio: cross == 4 ? 1.9 : (cross == 2 ? 2.3 : 2.8),
                children: [
                  _Stat(
                    icon: Icons.payments_rounded,
                    color: AdminColors.accent,
                    bg: AdminColors.accentSoft,
                    value: _money(thisMonthPaise),
                    label: 'This month',
                    sub: prevMonthPaise == 0
                        ? 'No payments last month'
                        : 'Last month ${_money(prevMonthPaise)}',
                  ),
                  _Stat(
                    icon: Icons.workspace_premium_rounded,
                    color: AdminColors.violet,
                    bg: AdminColors.violetSoft,
                    value: '${payingBusinessIds.length}',
                    label: 'Paying merchants',
                    sub: '$trialCount on trial • $expiredPayers lapsed',
                  ),
                  _Stat(
                    icon: Icons.account_balance_wallet_rounded,
                    color: AdminColors.accent,
                    bg: AdminColors.accentSoft,
                    value: _money(lifetimePaise),
                    label: 'Lifetime income',
                    sub: '${payments.length} verified payment(s)',
                  ),
                  _Stat(
                    icon: mismatches.isEmpty
                        ? Icons.verified_rounded
                        : Icons.report_problem_rounded,
                    color: mismatches.isEmpty ? AdminColors.accent : AdminColors.amber,
                    bg: mismatches.isEmpty ? AdminColors.accentSoft : AdminColors.amberSoft,
                    value: '${mismatches.length}',
                    label: 'Needs checking',
                    sub: mismatches.isEmpty
                        ? 'Every device agrees with the server'
                        : 'Device says Pro, server has no payment',
                  ),
                ],
              );
            },
          ),

          const SizedBox(height: 24),

          if (mismatches.isNotEmpty) ...[
            _Panel(
              title: 'Devices claiming Pro with no verified payment',
              child: Column(
                children: mismatches.take(8).map((b) {
                  return ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.warning_amber_rounded, color: AdminColors.amber),
                    title: Text(b.name,
                        style: const TextStyle(color: AdminColors.ink, fontSize: 13)),
                    subtitle: Text(
                      '${b.phone.isEmpty ? b.id : b.phone} • device reports Pro, no captured payment and no live trial',
                      style: const TextStyle(color: AdminColors.inkMuted, fontSize: 11.5),
                    ),
                  );
                }).toList(),
              ),
            ),
            const SizedBox(height: 16),
          ],

          _Panel(
            title: 'Verified payments (${payments.length})',
            child: payments.isEmpty
                ? const Padding(
                    padding: EdgeInsets.symmetric(vertical: 28),
                    child: Text(
                      'No verified payments yet.\n\n'
                      'A payment appears here the moment verifyRazorpayPayment confirms it with '
                      'Razorpay. If a merchant has paid and nothing shows, that function is '
                      'probably not deployed — check its logs.',
                      style: TextStyle(color: AdminColors.inkMuted, fontSize: 12.5, height: 1.5),
                    ),
                  )
                : Column(
                    children: payments.take(60).map((p) {
                      final biz = businesses.where((b) => b.id == p.businessId).firstOrNull;
                      return _PaymentRow(payment: p, businessName: biz?.name);
                    }).toList(),
                  ),
          ),
        ],
      ),
    );
  }
}

class _PaymentRow extends StatelessWidget {
  final AdminPayment payment;
  final String? businessName;
  const _PaymentRow({required this.payment, this.businessName});

  @override
  Widget build(BuildContext context) {
    final active = payment.isStillActive;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 9),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: active ? AdminColors.accentSoft : AdminColors.surfaceSunken,
              borderRadius: BorderRadius.circular(9),
            ),
            child: Icon(
              active ? Icons.check_circle_rounded : Icons.history_rounded,
              size: 16,
              color: active ? AdminColors.accent : AdminColors.inkFaint,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  businessName ?? payment.businessId,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      color: AdminColors.ink, fontSize: 13, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 2),
                Text(
                  [
                    payment.plan.toUpperCase(),
                    if (payment.verifiedAt != null)
                      DateFormat('d MMM yyyy').format(payment.verifiedAt!),
                    if (payment.couponCode != null) 'coupon ${payment.couponCode}',
                    payment.paymentId,
                  ].join(' • '),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: AdminColors.inkFaint, fontSize: 11),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                _money(payment.amountPaise),
                style: const TextStyle(
                    color: AdminColors.ink, fontSize: 13.5, fontWeight: FontWeight.w800),
              ),
              Text(
                active ? 'Active' : 'Lapsed',
                style: TextStyle(
                  fontSize: 10.5,
                  fontWeight: FontWeight.w700,
                  color: active ? AdminColors.accent : AdminColors.inkFaint,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Whole-rupee, Indian digit grouping. Kept local, like every other screen in
/// this console — there is no shared currency formatter here.
String _money(int paise) {
  final rupees = (paise / 100).round();
  final s = rupees.abs().toString();
  String grouped;
  if (s.length <= 3) {
    grouped = s;
  } else {
    final last3 = s.substring(s.length - 3);
    var rest = s.substring(0, s.length - 3);
    final parts = <String>[];
    while (rest.length > 2) {
      parts.insert(0, rest.substring(rest.length - 2));
      rest = rest.substring(0, rest.length - 2);
    }
    if (rest.isNotEmpty) parts.insert(0, rest);
    grouped = '${parts.join(',')},$last3';
  }
  return '${rupees < 0 ? '-' : ''}₹$grouped';
}

class _Stat extends StatelessWidget {
  final IconData icon;
  final Color color;
  final Color bg;
  final String value;
  final String label;
  final String sub;
  const _Stat({
    required this.icon,
    required this.color,
    required this.bg,
    required this.value,
    required this.label,
    required this.sub,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AdminColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AdminColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(7),
            decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(9)),
            child: Icon(icon, color: color, size: 16),
          ),
          const SizedBox(height: 10),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(value,
                style: const TextStyle(
                    color: AdminColors.ink, fontSize: 22, fontWeight: FontWeight.w800)),
          ),
          const SizedBox(height: 2),
          Text(label,
              style: const TextStyle(
                  color: AdminColors.ink, fontSize: 12.5, fontWeight: FontWeight.w600)),
          Text(sub,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: AdminColors.inkFaint, fontSize: 11)),
        ],
      ),
    );
  }
}

class _Panel extends StatelessWidget {
  final String title;
  final Widget child;
  const _Panel({required this.title, required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AdminColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AdminColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title,
              style: const TextStyle(
                  color: AdminColors.ink, fontSize: 14, fontWeight: FontWeight.w700)),
          const SizedBox(height: 10),
          child,
        ],
      ),
    );
  }
}

class _Message extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String title;
  final String subtitle;
  final bool loading;
  const _Message({
    required this.icon,
    required this.color,
    required this.title,
    required this.subtitle,
    this.loading = false,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 460),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (loading)
              const CircularProgressIndicator(color: AdminColors.accent)
            else
              Icon(icon, color: color, size: 40),
            const SizedBox(height: 14),
            Text(title,
                textAlign: TextAlign.center,
                style: const TextStyle(
                    color: AdminColors.ink, fontSize: 16, fontWeight: FontWeight.w700)),
            const SizedBox(height: 6),
            Text(subtitle,
                textAlign: TextAlign.center,
                style: const TextStyle(color: AdminColors.inkMuted, fontSize: 12.5, height: 1.5)),
          ],
        ),
      ),
    );
  }
}
