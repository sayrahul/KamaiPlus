import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:url_launcher/url_launcher.dart';

class GrowthCampaignsScreen extends StatefulWidget {
  const GrowthCampaignsScreen({super.key});

  @override
  State<GrowthCampaignsScreen> createState() => _GrowthCampaignsScreenState();
}

class _GrowthCampaignsScreenState extends State<GrowthCampaignsScreen> {
  final List<Map<String, String>> _templates = [
    {
      'title': 'Weekend Dhamaka Offer 🛒',
      'discount': '10% OFF',
      'body': 'Namaste! Weekend special sale at Sharma Kirana Store! Get 10% instant discount on Atta, Dal and Cooking Oil. Visit today or order on WhatsApp!',
      'tag': 'SALES BOOST',
    },
    {
      'title': 'Diwali / Festival Mubarak 🪔',
      'discount': 'Free Gift Hamper',
      'body': 'Wishing you and your family a very happy and prosperous festival! Special dry fruit boxes and festive sweets now in stock at special rates.',
      'tag': 'FESTIVAL',
    },
    {
      'title': 'Polite Udhar Payment Reminder 📝',
      'discount': 'Account Settlement',
      'body': 'Namaste Ji! This is a gentle reminder regarding pending balance in your store Khata. Kindly clear via UPI or visit the counter. Dhanyawad!',
      'tag': 'KHATA DUE',
    },
    {
      'title': 'New Fresh Arrivals in Stock 📦',
      'discount': 'Fresh Harvest',
      'body': 'Fresh stock of Basmati Rice, Dry Fruits, Cold Drinks & Dairy arrived today. Special wholesale rates for regular customers!',
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
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF065F46), Color(0xFF047857)],
              ),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Row(
              children: [
                const Icon(Icons.mark_chat_unread_rounded, color: Colors.white, size: 36),
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
          const SizedBox(height: 20),
          Text(
            'SELECT CAMPAIGN TEMPLATE',
            style: GoogleFonts.outfit(fontSize: 12, fontWeight: FontWeight.w800, color: const Color(0xFF64748B), letterSpacing: 0.5),
          ),
          const SizedBox(height: 8),
          ..._templates.map((t) => _buildTemplateCard(t)),
        ],
      ),
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
              final text = Uri.encodeComponent(t['body']!);
              final uri = Uri.parse('whatsapp://send?text=$text');
              if (await canLaunchUrl(uri)) {
                await launchUrl(uri);
              } else {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Copied campaign message to clipboard!')),
                  );
                }
              }
            },
            icon: const Icon(Icons.share_rounded, size: 16),
            label: Text('Send via WhatsApp', style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w700)),
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
