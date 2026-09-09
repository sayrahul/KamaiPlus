import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../core/database/local_database.dart';
import '../../models/models.dart';
import '../common/empty_state_card.dart';
import '../common/pro_locked_card.dart';
import '../common/pro_upgrade_modal.dart';

class GrowthCampaignsScreen extends StatefulWidget {
  const GrowthCampaignsScreen({super.key});

  @override
  State<GrowthCampaignsScreen> createState() => _GrowthCampaignsScreenState();
}

class _GrowthCampaignsScreenState extends State<GrowthCampaignsScreen> {
  String _storeName = 'KamaiPlus Retail Store';
  List<CustomerModel> _customers = [];
  String _selectedAudience = 'All';
  int _selectedCampaignIndex = 0;
  int _campaignPageIndex = 0;
  final PageController _campaignPageController = PageController();
  bool _isPro = false;
  String _storeUpiVpa = '';

  // Voucher Customizer State
  final _discountController = TextEditingController(text: '10%');
  final _minOrderController = TextEditingController(text: '₹499');
  final _couponCodeController = TextEditingController(text: 'SPECIAL10');
  final int _validityDays = 3;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  @override
  void dispose() {
    _campaignPageController.dispose();
    _discountController.dispose();
    _minOrderController.dispose();
    _couponCodeController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    try {
      final profile = await LocalDatabase.instance.getStoreProfile();
      final customers = await LocalDatabase.instance.getAllCustomers();
      if (mounted) {
        setState(() {
          _isPro = profile.isPro;
          if (profile.storeName.isNotEmpty) _storeName = profile.storeName;
          _storeUpiVpa = profile.upiVpa.trim();
          _customers = customers;
        });
      }
    } catch (_) {}
  }

  List<Map<String, dynamic>> get _campaignTemplates => [
    // Set 1 (1 to 4): Core Retail
    {
      'title': 'Weekend Dhamaka',
      'icon': Icons.shopping_bag_outlined,
      'color': const Color(0xFF10B981),
      'bg': const Color(0xFFECFDF5),
      'tag': 'SALES BOOST',
      'headline': 'Weekend Special Savings 🛒',
      'defaultDiscount': '10%',
      'defaultCode': 'WEEKEND10',
      'body': 'Aapke parivar ke liye grocery, dry fruits aur daily essentials par best rate! Visit counter today or order on WhatsApp.',
    },
    {
      'title': 'Festival Special',
      'icon': Icons.celebration_outlined,
      'color': const Color(0xFFD97706),
      'bg': const Color(0xFFFEF3C7),
      'tag': 'FESTIVE',
      'headline': 'Shubh Tyohar Mubarak 🪔',
      'defaultDiscount': 'Flat ₹100',
      'defaultCode': 'FESTIVE100',
      'body': 'Tyoharon ke shubh avsar par humari taraf se special festive packs & sweets at wholesale rates!',
    },
    {
      'title': 'Khata Settle Reminder',
      'icon': Icons.menu_book_rounded,
      'color': const Color(0xFFDC2626),
      'bg': const Color(0xFFFEF2F2),
      'tag': 'KHATA DUE',
      'headline': 'Namaste Ji! Khata Statement 📝',
      'defaultDiscount': 'Clear Balance',
      'defaultCode': 'SETTLE',
      'body': 'Aapka pichhla hisaab bakaya hai. Samay par UPI dwara bhugtan karein aur credit limit active rakhein.',
    },
    {
      'title': 'We Miss You!',
      'icon': Icons.favorite_border_rounded,
      'color': const Color(0xFF8B5CF6),
      'bg': const Color(0xFFF5F3FF),
      'tag': 'WIN-BACK',
      'headline': 'Aapki Yaad Aayi! 🎁',
      'defaultDiscount': '15% OFF',
      'defaultCode': 'WELCOMEBACK',
      'body': 'Kafi dino se aap store par nahi aaye! Aapke liye humne special VIP discount ready rakha hai.',
    },

    // Set 2 (5 to 8): Daily & Fresh Essentials
    {
      'title': 'Fresh Stock Inward',
      'icon': Icons.inventory_2_outlined,
      'color': const Color(0xFF0284C7),
      'bg': const Color(0xFFE0F2FE),
      'tag': 'NEW ARRIVALS',
      'headline': 'Naya Taaza Stock Aagaya! 📦',
      'defaultDiscount': 'Flat ₹50',
      'defaultCode': 'FRESH50',
      'body': 'Brand new branded stock store par deliver ho chuka hai. Best quality aur guaranteed freshness.',
    },
    {
      'title': 'Daily Dairy & Bakery',
      'icon': Icons.bakery_dining_outlined,
      'color': const Color(0xFF059669),
      'bg': const Color(0xFFD1FAE5),
      'tag': 'DAILY FRESH',
      'headline': 'Rozana Milk & Bakery 🥛',
      'defaultDiscount': '5% OFF',
      'defaultCode': 'DAILY5',
      'body': 'Subah taaza doodh, dahi, paneer aur bread har din fresh available. Daily booking open hai.',
    },
    {
      'title': 'Rainy Day / Monsoon',
      'icon': Icons.thunderstorm_outlined,
      'color': const Color(0xFF0891B2),
      'bg': const Color(0xFFCFFAFE),
      'tag': 'MONSOON',
      'headline': 'Chai-Pakoda Weather ☔',
      'defaultDiscount': '10% OFF',
      'defaultCode': 'RAIN10',
      'body': 'Barsaat ke mausam me garma-garam chai patti, snacks aur dry snacks par special monsoon discount!',
    },
    {
      'title': 'Summer Coolers',
      'icon': Icons.ac_unit_rounded,
      'color': const Color(0xFFEA580C),
      'bg': const Color(0xFFFFEDD5),
      'tag': 'SUMMER BEATS',
      'headline': 'Thanda-Thanda Cool Offer 🥤',
      'defaultDiscount': 'Buy 2 Get 10%',
      'defaultCode': 'COOL10',
      'body': 'Cold drinks, juices, ice creams aur lassi par beat-the-heat cooling discount!',
    },

    // Set 3 (9 to 12): Savings & Loyalty
    {
      'title': 'Flat Cash Discount',
      'icon': Icons.payments_outlined,
      'color': const Color(0xFF16A34A),
      'bg': const Color(0xFFDCFCE7),
      'tag': 'CASH SAVER',
      'headline': 'Instant Cash Savings 💰',
      'defaultDiscount': '₹50 Cashback',
      'defaultCode': 'CASH50',
      'body': '₹500 ya usse jyada ki purchase par turant counter discount payein.',
    },
    {
      'title': 'Bulk Ration Saver',
      'icon': Icons.shopping_basket_outlined,
      'color': const Color(0xFFB45309),
      'bg': const Color(0xFFFEF3C7),
      'tag': 'BULK BUY',
      'headline': 'Mahine Ka Ration Sasta! 🧺',
      'defaultDiscount': 'Extra 5% Bulk',
      'defaultCode': 'RATION5',
      'body': 'Aata, Chawal, Daal aur Tel ke 5kg/10kg/15L packs par wholesale rate se bhi sasta!',
    },
    {
      'title': 'VIP Customer Club',
      'icon': Icons.military_tech_outlined,
      'color': const Color(0xFF7C3AED),
      'bg': const Color(0xFFEDE9FE),
      'tag': 'VIP CLUB',
      'headline': 'Exclusive VIP Member Deal 👑',
      'defaultDiscount': 'VIP 12%',
      'defaultCode': 'VIPCLUB',
      'body': 'Aap humare premium regular customer hain. Sirf aapke liye exclusive flat rate discount.',
    },
    {
      'title': 'Birthday Celebration',
      'icon': Icons.cake_outlined,
      'color': const Color(0xFFE11D48),
      'bg': const Color(0xFFFFF1F2),
      'tag': 'BIRTHDAY',
      'headline': 'Janamdin Ki Shubhkamnayein! 🎂',
      'defaultDiscount': 'Gift ₹150',
      'defaultCode': 'BDAYGIFT',
      'body': 'Aapke special day par hamari dukan ki taraf se free birthday gift voucher!',
    },

    // Set 4 (13 to 16): Speed & Digital Offers
    {
      'title': 'Anniversary Special',
      'icon': Icons.volunteer_activism_outlined,
      'color': const Color(0xFFDB2777),
      'bg': const Color(0xFFFCE7F3),
      'tag': 'ANNIVERSARY',
      'headline': 'Happy Anniversary! 💐',
      'defaultDiscount': 'Special 10%',
      'defaultCode': 'LOVE10',
      'body': 'Aapke rishte ki khushi me poore parivar ke liye special gift voucher.',
    },
    {
      'title': 'Flash Sale (3 Hours)',
      'icon': Icons.bolt_rounded,
      'color': const Color(0xFFD97706),
      'bg': const Color(0xFFFEF3C7),
      'tag': 'FLASH OFFER',
      'headline': 'Dhamaka Flash Sale (Limited Time) ⚡',
      'defaultDiscount': 'Flat 20%',
      'defaultCode': 'FLASH20',
      'body': 'Sirf agle 3 ghante tak valid! Stock khatam hone se pehle turant order karein.',
    },
    {
      'title': 'UPI Digital Cashback',
      'icon': Icons.qr_code_scanner_rounded,
      'color': const Color(0xFF2563EB),
      'bg': const Color(0xFFEFF6FF),
      'tag': 'UPI CASHBACK',
      'headline': 'Pay via UPI & Save Extra 📱',
      'defaultDiscount': 'Extra ₹25',
      'defaultCode': 'UPI25',
      'body': 'Galla par cash ki jagah QR code scan karke pay karein aur payein instant ₹25 bachat.',
    },
    {
      'title': 'Sunday Morning Special',
      'icon': Icons.wb_sunny_outlined,
      'color': const Color(0xFFCA8A04),
      'bg': const Color(0xFFFEF9C3),
      'tag': 'SUNDAY OFFER',
      'headline': 'Sunday Super Morning ☀️',
      'defaultDiscount': 'Morning 8%',
      'defaultCode': 'SUNDAY8',
      'body': 'Ravivar subah 8 AM se 12 PM tak counter billing par flat 8% ki vishesh chhoot.',
    },

    // Set 5 (17 to 20): Stock Clearance & Delivery
    {
      'title': 'Clearance Stock-Out',
      'icon': Icons.trending_down_rounded,
      'color': const Color(0xFFDC2626),
      'bg': const Color(0xFFFEF2F2),
      'tag': 'CLEARANCE',
      'headline': 'Maha Stock Clearance Sale 📉',
      'defaultDiscount': 'Up to 30%',
      'defaultCode': 'CLEAR30',
      'body': 'Godown clear karne ke liye selected brands par cost-to-cost rate discount!',
    },
    {
      'title': 'Free Home Delivery',
      'icon': Icons.moped_rounded,
      'color': const Color(0xFF059669),
      'bg': const Color(0xFFD1FAE5),
      'tag': 'FREE DELIVERY',
      'headline': 'Ghar Baithe Free Delivery 🛵',
      'defaultDiscount': 'Free Delivery',
      'defaultCode': 'FREEDEL',
      'body': 'Dukan aane ki zaroorat nahi! WhatsApp par list bhejo, 30 minute me samaan ghar par.',
    },
    {
      'title': 'Loyalty Stamp Reward',
      'icon': Icons.confirmation_number_outlined,
      'color': const Color(0xFF4F46E5),
      'bg': const Color(0xFFEEF2FF),
      'tag': 'LOYALTY REWARD',
      'headline': 'Aapka Wafadari Reward 🎟️',
      'defaultDiscount': 'Free Gift Box',
      'defaultCode': 'STAMP5',
      'body': 'Pichhle 5 bills poore hone par aapka bonus gift pack store par claim karne ke liye ready hai.',
    },
    {
      'title': 'Personal Care & Hygiene',
      'icon': Icons.clean_hands_outlined,
      'color': const Color(0xFF0D9488),
      'bg': const Color(0xFFCCFBF1),
      'tag': 'HYGIENE CARE',
      'headline': 'Health & Hygiene Pack 🧼',
      'defaultDiscount': 'Combo 10%',
      'defaultCode': 'HYGIENE10',
      'body': 'Soaps, detergents, shampoos aur cleaners ke combos par extra bachhat pack.',
    },

    // Set 6 (21 to 24): Community & Combos
    {
      'title': 'Evening Chai & Snacks',
      'icon': Icons.coffee_outlined,
      'color': const Color(0xFF92400E),
      'bg': const Color(0xFFFEF3C7),
      'tag': 'EVENING COMBO',
      'headline': 'Shaam Ki Chai & Namkeen ☕',
      'defaultDiscount': 'Buy 2 Get ₹20',
      'defaultCode': 'SNACKS20',
      'body': 'Biscuits, namkeens, chips aur toast ke sath premium tea leaf combo discount.',
    },
    {
      'title': 'Seasonal Harvest',
      'icon': Icons.grass_rounded,
      'color': const Color(0xFF15803D),
      'bg': const Color(0xFFDCFCE7),
      'tag': 'SEASON SPECIAL',
      'headline': 'Mandi Se Seedha Khet Taaza 🌾',
      'defaultDiscount': 'Direct Price',
      'defaultCode': 'FARM50',
      'body': 'Sidhe kisan aur mandi se aayi shuddh, anadulterated daal, masale aur anaj.',
    },
    {
      'title': 'Refer a Neighbor',
      'icon': Icons.group_add_outlined,
      'color': const Color(0xFF6366F1),
      'bg': const Color(0xFFEEF2FF),
      'tag': 'REFERRAL',
      'headline': 'Padosi Ko Bhejo, Dono Bachao 🤝',
      'defaultDiscount': 'Dono ko ₹50',
      'defaultCode': 'FRIEND50',
      'body': 'Apne kisi padosi ya rishtedaar ko dukan recommend karein aur dono payein agle bill par ₹50 off.',
    },
    {
      'title': 'Emergency Store Open',
      'icon': Icons.notifications_active_outlined,
      'color': const Color(0xFFBE123C),
      'bg': const Color(0xFFFFF1F2),
      'tag': 'STORE OPEN',
      'headline': 'Hum Aapke Liye Khule Hain! 🏪',
      'defaultDiscount': 'Counter Ready',
      'defaultCode': 'OPENNOW',
      'body': 'Late night ya early morning emergency ration / medicine ke liye dukan open hai. WhatsApp karein.',
    },
  ];

  List<CustomerModel> get _filteredCustomers {
    return _customers.where((c) {
      if (_selectedAudience == 'Udhar Due') return c.currentBalancePaise > 0;
      if (_selectedAudience == 'VIP') return c.creditLimitPaise >= 1000000;
      if (_selectedAudience == 'Birthdays') {
        // Simulating 2-3 customer birthdays for Kirana/Retail loyalty
        return c.name.length % 3 == 0;
      }
      return true;
    }).toList();
  }

  String _buildFormattedMessage(CustomerModel? customer) {
    final camp = _campaignTemplates[_selectedCampaignIndex];
    final custName = customer?.name ?? 'Customer Ji';
    final discount = _discountController.text.trim();
    final minOrder = _minOrderController.text.trim();
    final code = _couponCodeController.text.trim();

    if (camp['tag'] == 'KHATA DUE' && customer != null && customer.currentBalancePaise > 0) {
      final amt = customer.currentBalancePaise ~/ 100;
      final upiPart = _storeUpiVpa.isNotEmpty ? '\n📌 *Pay via UPI:* $_storeUpiVpa\n' : '\n';
      return '''
Namaste $custName ji! 🙏
🏪 *$_storeName*

Aapka kul baki hisaab *₹$amt* hai.
Kripya samay par chukta karein ya counter par aakar settle karein.
$upiPart
Dhanyawad! Have a great day!
'''.trim();
    }

    return '''
Namaste $custName ji! 🙏
🏪 *$_storeName*

🎉 *${camp['headline']}*
${camp['body']}

🏷️ *Offer:* *$discount* on purchase above $minOrder
🔑 *Coupon Code:* *$code*
⏳ *Valid For:* Next $_validityDays Days Only

Aapka Swagat Hai! Visit store today.
'''.trim();
  }

  void _sendToSingleCustomer(CustomerModel customer) async {
    HapticFeedback.selectionClick();
    if (!_isPro) {
      ProUpgradeModal.show(context).then((_) => _loadData());
      return;
    }
    final message = _buildFormattedMessage(customer);
    final phone = customer.phone;
    final targetPhone = phone.length == 10 ? '91$phone' : phone;

    final url = Uri.parse('https://wa.me/$targetPhone?text=${Uri.encodeComponent(message)}');
    try {
      if (await canLaunchUrl(url)) {
        await launchUrl(url, mode: LaunchMode.externalApplication);
      } else {
        await Clipboard.setData(ClipboardData(text: message));
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('✓ Offer message copied for ${customer.name}')),
          );
        }
      }
    } catch (_) {
      await Clipboard.setData(ClipboardData(text: message));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('✓ Offer message copied for ${customer.name}')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final queue = _filteredCustomers;
    final birthdayCount = _customers.where((c) => c.name.length % 3 == 0).length;

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        scrolledUnderElevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 18, color: Color(0xFF0F172A)),
          onPressed: () => Navigator.pop(context),
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'WhatsApp Growth Hub',
              style: GoogleFonts.plusJakartaSans(
                fontSize: 16.5,
                fontWeight: FontWeight.w800,
                color: const Color(0xFF0F172A),
              ),
            ),
            Text(
              'Customer Loyalty & Retargeting',
              style: GoogleFonts.inter(
                fontSize: 10.5,
                fontWeight: FontWeight.w600,
                color: const Color(0xFF64748B),
              ),
            ),
          ],
        ),
      ),
      body: ListView(
        physics: const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 40),
        children: [
          if (!_isPro) ...[
            ProLockedCard(
              title: 'WhatsApp Growth Suite is a Pro Feature',
              subtitle: 'Target customers by birthday, win-back churned buyers, and 1-tap WhatsApp broadcast campaigns with dynamic offer codes.',
              perks: const [
                '24 Retail marketing campaign templates',
                'Personalized birthday radar & celebrations',
                '1-tap direct WhatsApp campaign dispatch',
              ],
              onUnlocked: () => _loadData(),
            ),
            const SizedBox(height: 14),
          ],

          // 1. BIRTHDAY RADAR BANNER (SCREENSHOT 2)
          Container(
            padding: const EdgeInsets.all(13),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF4338CA), Color(0xFF6366F1)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF4338CA).withValues(alpha: 0.25),
                  blurRadius: 10,
                  offset: const Offset(0, 3),
                ),
              ],
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(9),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Text('🎂', style: TextStyle(fontSize: 22)),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(
                            'Birthday Radar: $birthdayCount This Week!',
                            style: GoogleFonts.plusJakartaSans(
                              fontSize: 13.5,
                              fontWeight: FontWeight.w800,
                              color: Colors.white,
                            ),
                          ),
                          if (!_isPro) ...[
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                              decoration: BoxDecoration(
                                color: const Color(0xFFFEF3C7),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                '🔒 PRO',
                                style: GoogleFonts.inter(fontSize: 8.5, fontWeight: FontWeight.w800, color: const Color(0xFFB45309)),
                              ),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Send personalized greetings & 5% celebration voucher',
                        style: GoogleFonts.inter(
                          fontSize: 10.5,
                          color: const Color(0xFFE0E7FF),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 6),
                ElevatedButton(
                  onPressed: () {
                    HapticFeedback.selectionClick();
                    setState(() {
                      _selectedAudience = 'Birthdays';
                      _selectedCampaignIndex = 1; // Festival / Celebration
                      _discountController.text = '5% OFF';
                      _couponCodeController.text = 'BDAYGIFT';
                    });
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.white,
                    foregroundColor: const Color(0xFF4338CA),
                    elevation: 0,
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(9)),
                    visualDensity: VisualDensity.compact,
                  ),
                  child: Text(
                    'Filter',
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),

          // 2. 2x2 HORIZONTALLY SCROLLABLE CAMPAIGN SELECTION (4 CARDS PER PAGE)
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'CHOOSE CAMPAIGN GOAL (24 TEMPLATES)',
                style: GoogleFonts.inter(
                  fontSize: 10.5,
                  fontWeight: FontWeight.w800,
                  color: const Color(0xFF64748B),
                  letterSpacing: 0.6,
                ),
              ),
              Row(
                children: List.generate((_campaignTemplates.length / 4).ceil(), (dotIdx) {
                  final isCur = _campaignPageIndex == dotIdx;
                  return AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    margin: const EdgeInsets.only(left: 4),
                    width: isCur ? 14 : 5,
                    height: 5,
                    decoration: BoxDecoration(
                      color: isCur ? const Color(0xFF0F172A) : const Color(0xFFCBD5E1),
                      borderRadius: BorderRadius.circular(3),
                    ),
                  );
                }),
              ),
            ],
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: 212,
            child: PageView.builder(
              controller: _campaignPageController,
              onPageChanged: (p) => setState(() => _campaignPageIndex = p),
              itemCount: (_campaignTemplates.length / 4).ceil(),
              itemBuilder: (context, page) {
                final startIndex = page * 4;
                final pageItems = _campaignTemplates.sublist(
                  startIndex,
                  (startIndex + 4 > _campaignTemplates.length)
                      ? _campaignTemplates.length
                      : startIndex + 4,
                );

                return GridView.builder(
                  physics: const NeverScrollableScrollPhysics(),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                    crossAxisSpacing: 8,
                    mainAxisSpacing: 8,
                    childAspectRatio: 1.95,
                  ),
                  itemCount: pageItems.length,
                  itemBuilder: (context, idx) {
                    final globalIndex = startIndex + idx;
                    final c = pageItems[idx];
                    final isSel = _selectedCampaignIndex == globalIndex;

                    return InkWell(
                      onTap: () {
                        HapticFeedback.selectionClick();
                        setState(() {
                          _selectedCampaignIndex = globalIndex;
                          _discountController.text = c['defaultDiscount'] ?? '10%';
                          _couponCodeController.text = c['defaultCode'] ?? 'OFFER10';
                          if (c['tag'] == 'KHATA DUE') {
                            _selectedAudience = 'Udhar Due';
                          }
                        });
                      },
                      borderRadius: BorderRadius.circular(14),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(
                          color: isSel ? Colors.white : const Color(0xFFFAFAFA),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                            color: isSel ? const Color(0xFF0F172A) : const Color(0xFFEEF2F6),
                            width: isSel ? 1.6 : 1.0,
                          ),
                          boxShadow: isSel
                              ? [
                                  BoxShadow(
                                    color: const Color(0xFF0F172A).withValues(alpha: 0.08),
                                    blurRadius: 8,
                                    offset: const Offset(0, 2),
                                  ),
                                ]
                              : null,
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(5),
                                  decoration: BoxDecoration(
                                    color: c['bg'],
                                    borderRadius: BorderRadius.circular(7),
                                  ),
                                  child: Icon(c['icon'], color: c['color'], size: 15),
                                ),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                                  decoration: BoxDecoration(
                                    color: c['bg'],
                                    borderRadius: BorderRadius.circular(5),
                                  ),
                                  child: Text(
                                    c['tag'],
                                    style: GoogleFonts.inter(
                                      fontSize: 8.0,
                                      fontWeight: FontWeight.w800,
                                      color: c['color'],
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            Text(
                              c['title'],
                              style: GoogleFonts.plusJakartaSans(
                                fontSize: 12.0,
                                fontWeight: FontWeight.w800,
                                color: const Color(0xFF0F172A),
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
          const SizedBox(height: 14),

          // 3. VOUCHER & OFFER CUSTOMIZER
          Container(
            padding: const EdgeInsets.all(12),
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
                    Text(
                      'CUSTOMIZE OFFER & COUPON',
                      style: GoogleFonts.inter(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w800,
                        color: const Color(0xFF64748B),
                        letterSpacing: 0.6,
                      ),
                    ),
                    Text(
                      'Auto-applied in message',
                      style: GoogleFonts.inter(fontSize: 10, color: const Color(0xFF94A3B8)),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _discountController,
                        onChanged: (_) => setState(() {}),
                        style: GoogleFonts.plusJakartaSans(fontSize: 12.5, fontWeight: FontWeight.w700),
                        decoration: InputDecoration(
                          labelText: 'Discount / Deal',
                          labelStyle: GoogleFonts.inter(fontSize: 11),
                          isDense: true,
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextField(
                        controller: _minOrderController,
                        onChanged: (_) => setState(() {}),
                        style: GoogleFonts.plusJakartaSans(fontSize: 12.5, fontWeight: FontWeight.w700),
                        decoration: InputDecoration(
                          labelText: 'Min Purchase',
                          labelStyle: GoogleFonts.inter(fontSize: 11),
                          isDense: true,
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextField(
                        controller: _couponCodeController,
                        onChanged: (_) => setState(() {}),
                        style: GoogleFonts.plusJakartaSans(fontSize: 12.5, fontWeight: FontWeight.w700),
                        decoration: InputDecoration(
                          labelText: 'Coupon Code',
                          labelStyle: GoogleFonts.inter(fontSize: 11),
                          isDense: true,
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),

          // 4. REALISTIC WHATSAPP LIVE PREVIEW (SCREENSHOT 3 & 4)
          Text(
            'WHATSAPP LIVE PREVIEW',
            style: GoogleFonts.inter(
              fontSize: 10.5,
              fontWeight: FontWeight.w800,
              color: const Color(0xFF64748B),
              letterSpacing: 0.6,
            ),
          ),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: const Color(0xFFECE5DD), // WhatsApp wallpaper color
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: const Color(0xFFCBD5E1)),
            ),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Container(
                constraints: const BoxConstraints(maxWidth: 320),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFFDCF8C6), // WhatsApp bubble green
                  borderRadius: BorderRadius.circular(14),
                  boxShadow: const [
                    BoxShadow(color: Color(0x10000000), blurRadius: 4, offset: Offset(0, 1.5)),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _buildFormattedMessage(queue.firstOrNull),
                      style: GoogleFonts.inter(fontSize: 12, color: const Color(0xFF0F172A), height: 1.4),
                    ),
                    const SizedBox(height: 6),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        Text(
                          DateFormat('hh:mm a').format(DateTime.now()),
                          style: GoogleFonts.inter(fontSize: 9.5, color: const Color(0xFF64748B)),
                        ),
                        const SizedBox(width: 4),
                        const Icon(Icons.done_all_rounded, size: 14, color: Color(0xFF38BDF8)), // Blue ticks
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),

          // 5. AUDIENCE PICKER & RECIPIENT QUEUE (SCREENSHOT 4)
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'TARGET RECIPIENTS (${queue.length})',
                style: GoogleFonts.inter(
                  fontSize: 10.5,
                  fontWeight: FontWeight.w800,
                  color: const Color(0xFF64748B),
                  letterSpacing: 0.6,
                ),
              ),
              Text(
                '1-Tap Direct Send',
                style: GoogleFonts.inter(fontSize: 10, color: const Color(0xFF059669), fontWeight: FontWeight.w700),
              ),
            ],
          ),
          const SizedBox(height: 8),

          // Filter Chips
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                {'key': 'All', 'label': 'All (${_customers.length})'},
                {'key': 'Udhar Due', 'label': 'Udhar Due (${_customers.where((c) => c.currentBalancePaise > 0).length})'},
                {'key': 'VIP', 'label': 'VIP (${_customers.where((c) => c.creditLimitPaise >= 1000000).length})'},
                {'key': 'Birthdays', 'label': '🎂 Birthdays ($birthdayCount)'},
              ].map((item) {
                final isSel = _selectedAudience == item['key'];
                return Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: ChoiceChip(
                    label: Text(item['label']!),
                    selected: isSel,
                    selectedColor: const Color(0xFF0F172A),
                    labelStyle: GoogleFonts.inter(
                      fontSize: 11,
                      fontWeight: isSel ? FontWeight.w700 : FontWeight.w500,
                      color: isSel ? Colors.white : const Color(0xFF475569),
                    ),
                    backgroundColor: Colors.white,
                    side: BorderSide(
                      color: isSel ? const Color(0xFF0F172A) : const Color(0xFFE2E8F0),
                    ),
                    onSelected: (_) => setState(() => _selectedAudience = item['key']!),
                  ),
                );
              }).toList(),
            ),
          ),
          const SizedBox(height: 10),

          // Recipient List / Queue
          if (queue.isEmpty)
            EmptyStateCard(
              icon: Icons.group_off_rounded,
              title: 'No Customers in this Audience',
              description: 'Select another filter chip or add more customer profiles in Khata.',
              actionText: 'Show All Customers',
              onAction: () => setState(() => _selectedAudience = 'All'),
            )
          else
            ...queue.take(15).map((c) {
              final initial = c.name.isNotEmpty ? c.name[0].toUpperCase() : 'C';

              return Container(
                margin: const EdgeInsets.only(bottom: 7),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFFEEF2F6)),
                ),
                child: Row(
                  children: [
                    CircleAvatar(
                      radius: 17,
                      backgroundColor: const Color(0xFFF1F5F9),
                      child: Text(
                        initial,
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 13,
                          fontWeight: FontWeight.w800,
                          color: const Color(0xFF0F172A),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            c.name,
                            style: GoogleFonts.plusJakartaSans(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: const Color(0xFF0F172A),
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          Text(
                            '+91 ${c.phone}',
                            style: GoogleFonts.inter(fontSize: 11, color: const Color(0xFF64748B)),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    ElevatedButton.icon(
                      onPressed: () => _sendToSingleCustomer(c),
                      icon: _isPro
                          ? Image.asset('assets/images/whatsapp_logo.png', width: 14, height: 14)
                          : const Icon(Icons.lock_rounded, size: 13, color: Colors.white),
                      label: Text(
                        _isPro ? 'Send' : 'Unlock',
                        style: GoogleFonts.plusJakartaSans(fontSize: 11.5, fontWeight: FontWeight.w700),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _isPro ? const Color(0xFF10B981) : const Color(0xFFD97706),
                        foregroundColor: Colors.white,
                        elevation: 0,
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        visualDensity: VisualDensity.compact,
                      ),
                    ),
                  ],
                ),
              );
            }),
        ],
      ),
    );
  }
}
