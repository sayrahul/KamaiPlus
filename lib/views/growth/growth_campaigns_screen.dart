import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../core/database/local_database.dart';
import '../../models/models.dart';
import '../common/kamai_bottom_nav.dart';

class GrowthCampaignsScreen extends StatefulWidget {
  const GrowthCampaignsScreen({super.key});

  @override
  State<GrowthCampaignsScreen> createState() => _GrowthCampaignsScreenState();
}

class _GrowthCampaignsScreenState extends State<GrowthCampaignsScreen> {
  String _storeName = 'KamaiPlus Retail Store';
  List<CustomerModel> _customers = [];
  String _selectedAudience = 'All Customers';

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    try {
      final profile = await LocalDatabase.instance.getStoreProfile();
      final customers = await LocalDatabase.instance.getAllCustomers();
      if (mounted) {
        setState(() {
          if (profile.storeName.isNotEmpty) _storeName = profile.storeName;
          _customers = customers;
        });
      }
    } catch (_) {}
  }

  int get _audienceCount {
    if (_selectedAudience == 'Udhar Due Customers') {
      return _customers.where((c) => c.currentBalancePaise > 0).length;
    }
    if (_selectedAudience == 'VIP Customers') {
      return _customers.where((c) => c.creditLimitPaise >= 1000000).length;
    }
    return _customers.length;
  }

  List<Map<String, String>> get _templates => [
    {
      'title': 'Weekend Dhamaka Offer 🛒',
      'discount': '10% OFF',
      'body': 'Namaste! Weekend special sale at $_storeName! Get instant discount on Grocery, Snacks & Essentials. Visit today or order on WhatsApp!',
      'tag': 'SALES BOOST',
    },
    {
      'title': 'Diwali / Festival Mubarak 🪔',
      'discount': 'Free Gift Hamper',
      'body': 'Wishing you and your family a very happy and prosperous festival from $_storeName! Special festive gift packs now in stock at wholesale rates.',
      'tag': 'FESTIVAL',
    },
    {
      'title': 'Polite Udhar Payment Reminder 📝',
      'discount': 'Account Settlement',
      'body': 'Namaste Ji! Gentle reminder from $_storeName regarding your pending store Khata. Kindly clear your balance via UPI or visit our counter. Dhanyawad!',
      'tag': 'KHATA DUE',
    },
    {
      'title': 'New Fresh Arrivals in Stock 📦',
      'discount': 'Fresh Stock',
      'body': 'Fresh stock of FMCG products, dairy items & grains arrived today at $_storeName. Best wholesale rates for regular family shoppers!',
      'tag': 'NEW STOCK',
    },
  ];

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
          'WhatsApp Growth Campaigns',
          style: GoogleFonts.outfit(fontSize: 17, fontWeight: FontWeight.w700, color: const Color(0xFF0F172A)),
        ),
      ),
      body: ListView(
        physics: const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 40),
        children: [
          // Banner
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF065F46), Color(0xFF047857)],
              ),
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(color: const Color(0xFF047857).withValues(alpha: 0.2), blurRadius: 10, offset: const Offset(0, 4)),
              ],
            ),
            child: Row(
              children: [
                Image.asset('assets/images/whatsapp_logo.png', width: 36, height: 36),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('1-Click WhatsApp Marketing', style: GoogleFonts.outfit(fontSize: 16, fontWeight: FontWeight.w800, color: Colors.white)),
                      Text('Send offers, greetings & reminders directly to customer phones', style: GoogleFonts.inter(fontSize: 11, color: const Color(0xFFA7F3D0))),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Target Audience Picker
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0xFFEEF2F6)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('TARGET AUDIENCE', style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w700, color: const Color(0xFF64748B))),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(color: const Color(0xFFEFF6FF), borderRadius: BorderRadius.circular(8)),
                      child: Text('$_audienceCount Recipients', style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w700, color: const Color(0xFF0284C7))),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: ['All Customers', 'Udhar Due Customers', 'VIP Customers'].map((aud) {
                      final sel = _selectedAudience == aud;
                      return Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: ChoiceChip(
                          label: Text(aud),
                          selected: sel,
                          onSelected: (_) => setState(() => _selectedAudience = aud),
                          selectedColor: const Color(0xFF0F172A),
                          labelStyle: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w600, color: sel ? Colors.white : const Color(0xFF475569)),
                          backgroundColor: const Color(0xFFF1F5F9),
                          side: BorderSide.none,
                        ),
                      );
                    }).toList(),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          Text(
            'SELECT CAMPAIGN TEMPLATE',
            style: GoogleFonts.outfit(fontSize: 12, fontWeight: FontWeight.w800, color: const Color(0xFF64748B), letterSpacing: 0.5),
          ),
          const SizedBox(height: 8),
          ..._templates.map((t) => _buildTemplateCard(t)),
        ],
      ),
      bottomNavigationBar: const KamaiBottomNav(),
    );
  }

  Widget _buildTemplateCard(Map<String, String> t) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFEEF2F6)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(t['title']!, style: GoogleFonts.outfit(fontSize: 15, fontWeight: FontWeight.w700, color: const Color(0xFF0F172A))),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(color: const Color(0xFFECFDF5), borderRadius: BorderRadius.circular(6)),
                child: Text(t['tag']!, style: GoogleFonts.inter(fontSize: 9, fontWeight: FontWeight.w800, color: const Color(0xFF059669))),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFFF8FAFC),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFFE2E8F0)),
            ),
            child: Text(t['body']!, style: GoogleFonts.inter(fontSize: 12, color: const Color(0xFF334155), height: 1.4)),
          ),
          const SizedBox(height: 12),
          ElevatedButton.icon(
            onPressed: () async {
              HapticFeedback.selectionClick();
              final text = Uri.encodeComponent(t['body']!);
              final uri = Uri.parse('whatsapp://send?text=$text');
              if (await canLaunchUrl(uri)) {
                await launchUrl(uri);
              } else {
                if (mounted) {
                  Clipboard.setData(ClipboardData(text: t['body']!));
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('✓ Campaign message copied to clipboard!')),
                  );
                }
              }
            },
            icon: Image.asset('assets/images/whatsapp_logo.png', width: 16, height: 16),
            label: Text('Send to $_selectedAudience', style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w700)),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF10B981),
              foregroundColor: Colors.white,
              minimumSize: const Size.fromHeight(42),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              elevation: 0,
            ),
          ),
        ],
      ),
    );
  }
}
