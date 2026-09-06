import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:uuid/uuid.dart';
import '../../models/models.dart';
import '../../core/database/local_database.dart';
import '../../services/firestore_sync_service.dart';

class KhataScreen extends StatefulWidget {
  const KhataScreen({super.key});

  @override
  State<KhataScreen> createState() => _KhataScreenState();
}

class _KhataScreenState extends State<KhataScreen> {
  final currencyFormat = NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 0);

  List<CustomerModel> _customers = [];
  bool _isLoading = true;
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _loadCustomers();
  }

  Future<void> _loadCustomers() async {
    final custs = await LocalDatabase.instance.getAllCustomers();
    if (mounted) {
      setState(() {
        _customers = custs;
        _isLoading = false;
      });
    }
  }

  int get totalPendingUdharPaise {
    int sum = 0;
    for (var c in _customers) {
      if (c.currentBalancePaise > 0) sum += c.currentBalancePaise;
    }
    return sum;
  }

  int get customersWithDuesCount {
    return _customers.where((c) => c.currentBalancePaise > 0).length;
  }

  void _sendWhatsAppReminder(CustomerModel customer) async {
    HapticFeedback.lightImpact();
    final rupees = customer.currentBalancePaise ~/ 100;
    final msg = Uri.encodeComponent(
      'Namaste ${customer.name} ji! KamaiPlus store par aapka ₹$rupees udhar baki hai. Kripya samay par UPI ya cash me chukta karein. UPI: proventure@icici. Dhanyawad!',
    );
    final url = Uri.parse('https://wa.me/91${customer.phone}?text=$msg');
    try {
      if (await canLaunchUrl(url)) {
        await launchUrl(url, mode: LaunchMode.externalApplication);
      }
    } catch (_) {}
  }

  void _openAddCustomerDialog() {
    final nameCtrl = TextEditingController();
    final phoneCtrl = TextEditingController();

    showDialog(
      context: context,
      builder: (dialogCtx) {
        return AlertDialog(
          backgroundColor: const Color(0xFF131B2A),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: Text(
            "Add Khata Customer",
            style: GoogleFonts.outfit(fontWeight: FontWeight.w700, color: Colors.white),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameCtrl,
                style: GoogleFonts.inter(color: Colors.white),
                decoration: InputDecoration(
                  labelText: "Customer Name",
                  labelStyle: GoogleFonts.inter(color: const Color(0xFF94A3B8)),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: Color(0xFF1E293B)),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: Color(0xFF10B981)),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: phoneCtrl,
                keyboardType: TextInputType.phone,
                style: GoogleFonts.inter(color: Colors.white),
                decoration: InputDecoration(
                  labelText: "Phone (10 digits)",
                  labelStyle: GoogleFonts.inter(color: const Color(0xFF94A3B8)),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: Color(0xFF1E293B)),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: Color(0xFF10B981)),
                  ),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogCtx),
              child: Text("Cancel", style: GoogleFonts.inter(color: const Color(0xFF64748B))),
            ),
            ElevatedButton(
              onPressed: () async {
                final name = nameCtrl.text.trim();
                final phone = phoneCtrl.text.trim();
                if (name.isNotEmpty && phone.isNotEmpty) {
                  final newCust = CustomerModel(
                    id: const Uuid().v4(),
                    businessId: FirestoreSyncService.instance.activeBusinessId,
                    name: name,
                    phone: phone,
                    currentBalancePaise: 0,
                    creditLimitPaise: 500000,
                    syncStatus: 'pending',
                  );
                  await LocalDatabase.instance.upsertCustomer(newCust);
                  if (!dialogCtx.mounted) return;
                  Navigator.pop(dialogCtx);
                  _loadCustomers();
                }
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF10B981),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              child: Text("Save", style: GoogleFonts.outfit(fontWeight: FontWeight.w700, color: Colors.white)),
            ),
          ],
        );
      },
    );
  }

  void _openCustomerLedgerSheet(CustomerModel customer) async {
    HapticFeedback.lightImpact();
    final ledgerEntries = await LocalDatabase.instance.getLedgerForCustomer(customer.id);

    if (!mounted) return;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF131B2A),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (context) {
        final balRupees = customer.currentBalancePaise / 100.0;
        return Padding(
          padding: EdgeInsets.only(
            top: 20,
            left: 20,
            right: 20,
            bottom: MediaQuery.of(context).viewInsets.bottom + 20,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(color: const Color(0xFF334155), borderRadius: BorderRadius.circular(2)),
                ),
              ),
              const SizedBox(height: 16),

              // Customer Header
              Row(
                children: [
                  CircleAvatar(
                    radius: 22,
                    backgroundColor: const Color(0xFFF59E0B).withValues(alpha: 0.2),
                    child: Text(customer.name[0], style: const TextStyle(color: Color(0xFFF59E0B), fontSize: 18, fontWeight: FontWeight.bold)),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(customer.name, style: GoogleFonts.outfit(fontSize: 18, fontWeight: FontWeight.w700, color: Colors.white)),
                        Text(customer.phone, style: GoogleFonts.inter(fontSize: 12, color: const Color(0xFF94A3B8))),
                      ],
                    ),
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text("Net Balance", style: GoogleFonts.inter(fontSize: 11, color: const Color(0xFF94A3B8))),
                      Text(
                        currencyFormat.format(balRupees),
                        style: GoogleFonts.outfit(
                          fontSize: 20,
                          fontWeight: FontWeight.w800,
                          color: balRupees > 0 ? const Color(0xFFF59E0B) : const Color(0xFF10B981),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 20),

              // Action Buttons: Settle Jama / Reminder
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: () => _openSettleBalanceDialog(customer),
                      icon: const Icon(Icons.download_done, color: Colors.white, size: 18),
                      label: Text("Jama Settle", style: GoogleFonts.outfit(fontWeight: FontWeight.w700, color: Colors.white)),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF10B981),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => _sendWhatsAppReminder(customer),
                      icon: const Icon(Icons.chat, color: Color(0xFF10B981), size: 18),
                      label: Text("WhatsApp", style: GoogleFonts.outfit(fontWeight: FontWeight.w700, color: const Color(0xFF10B981))),
                      style: OutlinedButton.styleFrom(
                        side: const BorderSide(color: Color(0xFF10B981)),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),

              // Ledger Transactions List
              Text("TRANSACTION HISTORY", style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w700, color: const Color(0xFF64748B))),
              const SizedBox(height: 10),
              if (ledgerEntries.isEmpty)
                Container(
                  padding: const EdgeInsets.all(20),
                  child: Center(
                    child: Text("No transaction history recorded yet", style: GoogleFonts.inter(color: const Color(0xFF64748B), fontSize: 13)),
                  ),
                )
              else
                ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 260),
                  child: ListView.builder(
                    shrinkWrap: true,
                    itemCount: ledgerEntries.length,
                    itemBuilder: (context, idx) {
                      final item = ledgerEntries[idx];
                      final isDebit = item.type == 'credit'; // given udhar
                      final amtRupees = item.amountPaise / 100.0;
                      return Container(
                        margin: const EdgeInsets.only(bottom: 8),
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: const Color(0xFF0B0F19),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: const Color(0xFF1E293B)),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(item.description, style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.white)),
                                Text(DateFormat('dd MMM yyyy, hh:mm a').format(item.createdAt), style: GoogleFonts.inter(fontSize: 11, color: const Color(0xFF64748B))),
                              ],
                            ),
                            Text(
                              "${isDebit ? '+' : '-'} ${currencyFormat.format(amtRupees)}",
                              style: GoogleFonts.outfit(
                                fontSize: 15,
                                fontWeight: FontWeight.w800,
                                color: isDebit ? const Color(0xFFF59E0B) : const Color(0xFF10B981),
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  void _openSettleBalanceDialog(CustomerModel customer) {
    final amountCtrl = TextEditingController(text: (customer.currentBalancePaise / 100.0).toStringAsFixed(0));
    showDialog(
      context: context,
      builder: (dialogCtx) {
        return AlertDialog(
          backgroundColor: const Color(0xFF131B2A),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: Text("Receive Payment (Jama)", style: GoogleFonts.outfit(fontWeight: FontWeight.w700, color: Colors.white)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text("Customer: ${customer.name}", style: GoogleFonts.inter(color: const Color(0xFF94A3B8))),
              const SizedBox(height: 14),
              TextField(
                controller: amountCtrl,
                keyboardType: TextInputType.number,
                style: GoogleFonts.outfit(fontSize: 22, fontWeight: FontWeight.w800, color: const Color(0xFF10B981)),
                decoration: InputDecoration(
                  prefixText: "₹ ",
                  prefixStyle: GoogleFonts.outfit(fontSize: 22, fontWeight: FontWeight.w800, color: const Color(0xFF10B981)),
                  labelText: "Amount Received",
                  labelStyle: GoogleFonts.inter(color: const Color(0xFF94A3B8)),
                  enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFF1E293B))),
                  focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFF10B981))),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text("Cancel", style: GoogleFonts.inter(color: const Color(0xFF64748B))),
            ),
            ElevatedButton(
              onPressed: () async {
                final rupees = double.tryParse(amountCtrl.text.trim()) ?? 0;
                final paise = (rupees * 100).toInt();
                if (paise > 0) {
                  final newBalance = customer.currentBalancePaise - paise;
                  final updatedCust = CustomerModel(
                    id: customer.id,
                    businessId: customer.businessId,
                    name: customer.name,
                    phone: customer.phone,
                    currentBalancePaise: newBalance < 0 ? 0 : newBalance,
                    creditLimitPaise: customer.creditLimitPaise,
                    syncStatus: 'pending',
                  );
                  await LocalDatabase.instance.upsertCustomer(updatedCust);

                  // Add ledger payment entry
                  final ledgerEntry = LedgerTransactionModel(
                    id: const Uuid().v4(),
                    businessId: customer.businessId,
                    customerId: customer.id,
                    type: 'debit', // payment received
                    amountPaise: paise,
                    balanceAfterPaise: newBalance < 0 ? 0 : newBalance,
                    description: 'Cash Payment Received',
                    createdAt: DateTime.now(),
                    syncStatus: 'pending',
                  );
                  final db = await LocalDatabase.instance.database;
                  await db.insert('ledger_transactions', ledgerEntry.toMap());

                  if (!dialogCtx.mounted) return;
                  Navigator.pop(dialogCtx);
                  _loadCustomers();
                }
              },
              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF10B981), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
              child: Text("Confirm Jama", style: GoogleFonts.outfit(fontWeight: FontWeight.w700, color: Colors.white)),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        backgroundColor: Color(0xFF0B0F19),
        body: Center(child: CircularProgressIndicator(color: Color(0xFF10B981))),
      );
    }

    final filteredCustomers = _customers.where((c) {
      return c.name.toLowerCase().contains(_searchQuery.toLowerCase()) || c.phone.contains(_searchQuery);
    }).toList();

    return Scaffold(
      backgroundColor: const Color(0xFF0B0F19),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Top Bar with Add Customer Button
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text("Digital Khata", style: GoogleFonts.outfit(fontSize: 24, fontWeight: FontWeight.w800, color: Colors.white)),
                  ElevatedButton.icon(
                    onPressed: _openAddCustomerDialog,
                    icon: const Icon(Icons.person_add, size: 16, color: Colors.white),
                    label: Text("New Customer", style: GoogleFonts.outfit(fontWeight: FontWeight.w700, color: Colors.white, fontSize: 12)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF10B981),
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // Total Market Udhar Card
              _buildMarketUdharCard(),
              const SizedBox(height: 18),

              // Search Bar
              Container(
                height: 44,
                decoration: BoxDecoration(
                  color: const Color(0xFF131B2A),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: const Color(0xFF1E293B)),
                ),
                child: TextField(
                  onChanged: (val) => setState(() => _searchQuery = val),
                  style: GoogleFonts.inter(color: Colors.white, fontSize: 14),
                  decoration: InputDecoration(
                    hintText: "Search customer name or phone...",
                    hintStyle: GoogleFonts.inter(color: const Color(0xFF64748B), fontSize: 13),
                    prefixIcon: const Icon(Icons.search, color: Color(0xFF64748B), size: 20),
                    border: InputBorder.none,
                    contentPadding: const EdgeInsets.symmetric(vertical: 10),
                  ),
                ),
              ),
              const SizedBox(height: 16),

              // Customers List
              Text("ALL CUSTOMERS (${filteredCustomers.length})", style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w700, color: const Color(0xFF64748B))),
              const SizedBox(height: 10),
              ListView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: filteredCustomers.length,
                itemBuilder: (context, idx) {
                  final cust = filteredCustomers[idx];
                  final balRupees = cust.currentBalancePaise / 100.0;
                  final hasUdhar = balRupees > 0;

                  return Container(
                    margin: const EdgeInsets.only(bottom: 10),
                    decoration: BoxDecoration(
                      color: const Color(0xFF131B2A),
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(color: hasUdhar ? const Color(0xFFF59E0B).withValues(alpha: 0.3) : const Color(0xFF1E293B)),
                    ),
                    child: ListTile(
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                      onTap: () => _openCustomerLedgerSheet(cust),
                      leading: CircleAvatar(
                        radius: 22,
                        backgroundColor: hasUdhar ? const Color(0xFFF59E0B).withValues(alpha: 0.15) : const Color(0xFF10B981).withValues(alpha: 0.15),
                        child: Text(
                          cust.name[0],
                          style: TextStyle(
                            color: hasUdhar ? const Color(0xFFF59E0B) : const Color(0xFF10B981),
                            fontWeight: FontWeight.w800,
                            fontSize: 16,
                          ),
                        ),
                      ),
                      title: Text(cust.name, style: GoogleFonts.inter(fontSize: 15, fontWeight: FontWeight.w700, color: Colors.white)),
                      subtitle: Text(cust.phone, style: GoogleFonts.inter(fontSize: 12, color: const Color(0xFF64748B))),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Text(
                                currencyFormat.format(balRupees),
                                style: GoogleFonts.outfit(
                                  fontSize: 17,
                                  fontWeight: FontWeight.w800,
                                  color: hasUdhar ? const Color(0xFFF59E0B) : const Color(0xFF10B981),
                                ),
                              ),
                              Text(
                                hasUdhar ? "Pending" : "Clear",
                                style: GoogleFonts.inter(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w600,
                                  color: hasUdhar ? const Color(0xFFF59E0B) : const Color(0xFF10B981),
                                ),
                              ),
                            ],
                          ),
                          if (hasUdhar) ...[
                            const SizedBox(width: 8),
                            IconButton(
                              icon: Container(
                                padding: const EdgeInsets.all(6),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF10B981).withValues(alpha: 0.15),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: const Icon(Icons.chat, color: Color(0xFF10B981), size: 16),
                              ),
                              onPressed: () => _sendWhatsAppReminder(cust),
                              tooltip: "Send WhatsApp Reminder",
                            ),
                          ],
                        ],
                      ),
                    ),
                  );
                },
              ),
              const SizedBox(height: 80),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMarketUdharCard() {
    final udharRupees = totalPendingUdharPaise / 100.0;
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            const Color(0xFF162032),
            const Color(0xFF1E293B).withValues(alpha: 0.8),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: const Color(0xFFF59E0B).withValues(alpha: 0.35),
          width: 1.2,
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFFF59E0B).withValues(alpha: 0.08),
            blurRadius: 24,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  const Icon(Icons.menu_book, color: Color(0xFFF59E0B), size: 18),
                  const SizedBox(width: 6),
                  Text(
                    "TOTAL MARKET UDHAR",
                    style: GoogleFonts.inter(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: const Color(0xFFF59E0B),
                      letterSpacing: 1.1,
                    ),
                  ),
                ],
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFFF59E0B).withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  "$customersWithDuesCount Due",
                  style: GoogleFonts.inter(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: const Color(0xFFF59E0B),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            currencyFormat.format(udharRupees),
            style: GoogleFonts.outfit(
              fontSize: 36,
              fontWeight: FontWeight.w800,
              color: Colors.white,
              letterSpacing: -1,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            "Market me itna udhar vasooli baki hai",
            style: GoogleFonts.inter(fontSize: 12, color: const Color(0xFF94A3B8)),
          ),
        ],
      ),
    );
  }
}
