class AppLanguage {
  final String code;
  final String name;
  final String nativeName;
  final String flag;

  const AppLanguage({
    required this.code,
    required this.name,
    required this.nativeName,
    required this.flag,
  });
}

class AppStrings {
  static const List<AppLanguage> supportedLanguages = [
    AppLanguage(code: 'en', name: 'English', nativeName: 'English', flag: '🇬🇧'),
    AppLanguage(code: 'hi', name: 'Hindi', nativeName: 'हिंदी', flag: '🇮🇳'),
    AppLanguage(code: 'mr', name: 'Marathi', nativeName: 'मराठी', flag: '🇮🇳'),
    AppLanguage(code: 'gu', name: 'Gujarati', nativeName: 'ગુજરાતી', flag: '🇮🇳'),
  ];

  static const Map<String, Map<String, String>> _translations = {
    // English
    'en': {
      // Navigation
      'nav_home': 'Home',
      'nav_products': 'Products',
      'nav_billing': 'Billing',
      'nav_khata': 'Khata',
      'nav_menu': 'Menu',

      // POS / Billing
      'pos_billing_title': 'Fast Billing Counter',
      'search_items_placeholder': 'Search items, barcode or SKU...',
      'cart_empty_title': 'Cart is Empty',
      'cart_empty_subtitle': 'Tap products from the catalog or scan barcodes',
      'total': 'Total',
      'subtotal': 'Subtotal',
      'tax': 'Tax',
      'discount': 'Discount',
      'round_off': 'Round Off',
      'pay_now': 'Charge',
      'checkout': 'Checkout',
      'clear_cart': 'Clear',
      'hold_cart': 'Hold',
      'recall_cart': 'Recall',
      'item': 'Item',
      'items': 'Items',
      'qty': 'Qty',
      'price': 'Price',
      'stock': 'Stock',
      'cash': 'Cash',
      'online_upi': 'UPI / Online',
      'udhar_credit': 'Udhar (Credit)',
      'split_payment': 'Split Payment',
      'tendered': 'Tendered',
      'change': 'Change Return',
      'customer_optional': 'Customer (Optional)',

      // Products / Inventory
      'products_title': 'Products & Inventory',
      'add_product': 'Add Product',
      'inward_ai': 'Inward with AI',
      'rapid_scan': 'Rapid Scan',
      'cost_price': 'Purchase Price',
      'selling_price': 'Selling Price',
      'mrp': 'MRP',
      'variants': 'Variants',
      'select_variant': 'Select Variant',
      'low_stock_warning': 'Low Stock Alert',
      'unlimited_stock': 'Unlimited Stock',
      'category': 'Category',
      'unit': 'Unit',

      // Returns / Refund
      'sales_return': 'Sales Return',
      'partial_return': 'Partial Return',
      'return_items': 'Return Items',
      'full_void': 'Full Void',
      'refund_amount': 'Refund Amount',
      'refund_mode': 'Refund Mode',
      'return_reason': 'Reason for Return',
      'restock_items': 'Restock in Inventory',
      'credit_note': 'Credit Note',

      // Khata / Customers
      'khata_title': 'Customer Khata (Ledger)',
      'customer_name': 'Customer Name',
      'customer_phone': 'Phone Number',
      'current_balance': 'Current Balance',
      'give_credit': 'Give Credit (Udhar)',
      'receive_payment': 'Receive Payment (Jama)',
      'send_reminder': 'Send Reminder',

      // Menu & Settings
      'settings': 'Settings',
      'store_profile': 'Store Profile & Tax Setup',
      'business_vertical': 'Business Vertical',
      'whatsapp_support': 'WhatsApp Support',
      'app_version': 'App Version',
      'language': 'Language / भाषा',
      'select_language': 'Select Language',
      'save': 'Save',
      'cancel': 'Cancel',
      'confirm': 'Confirm',
      'delete': 'Delete',
      'edit': 'Edit',
      'close': 'Close',
    },

    // Hindi (हिंदी)
    'hi': {
      // Navigation
      'nav_home': 'होम',
      'nav_products': 'सामान',
      'nav_billing': 'बिलिंग',
      'nav_khata': 'खाता',
      'nav_menu': 'मेनू',

      // POS / Billing
      'pos_billing_title': 'तेज़ बिलिंग काउंटर',
      'search_items_placeholder': 'सामान खोजें या बारकोड स्कैन करें...',
      'cart_empty_title': 'कार्ट खाली है',
      'cart_empty_subtitle': 'सूची से सामान चुनें या बारकोड स्कैन करें',
      'total': 'कुल योग',
      'subtotal': 'उप-योग',
      'tax': 'जीएसटी / टैक्स',
      'discount': 'छूट / डिस्काउंट',
      'round_off': 'राउंड ऑफ',
      'pay_now': 'बिल बनाएं',
      'checkout': 'चेकआउट',
      'clear_cart': 'खाली करें',
      'hold_cart': 'होल्ड',
      'recall_cart': 'वापस लाएं',
      'item': 'सामान',
      'items': 'सामान',
      'qty': 'मात्रा',
      'price': 'कीमत',
      'stock': 'स्टॉक',
      'cash': 'नकद (Cash)',
      'online_upi': 'ऑनलाइन / UPI',
      'udhar_credit': 'उधार (Khata)',
      'split_payment': 'स्प्लिट भुगतान',
      'tendered': 'ग्राहक ने दिया',
      'change': 'वापस देना है',
      'customer_optional': 'ग्राहक (वैकल्पिक)',

      // Products / Inventory
      'products_title': 'उत्पाद और स्टॉक',
      'add_product': '+ नया सामान जोड़ें',
      'inward_ai': 'AI से बिल चढ़ाएं',
      'rapid_scan': 'रैपिड स्कैन',
      'cost_price': 'खरीद भाव (Cost)',
      'selling_price': 'बिक्री मूल्य (Sale)',
      'mrp': 'एमआरपी',
      'variants': 'साइज / कलर',
      'select_variant': 'साइज / कलर चुनें',
      'low_stock_warning': 'कम स्टॉक अलर्ट',
      'unlimited_stock': 'असीमित स्टॉक',
      'category': 'कैटेगरी',
      'unit': 'इकाई (Unit)',

      // Returns / Refund
      'sales_return': 'बिक्री वापसी',
      'partial_return': 'टुकड़ों में वापसी',
      'return_items': 'सामान वापस लें',
      'full_void': 'पूरा बिल रद्द',
      'refund_amount': 'वापसी राशि',
      'refund_mode': 'वापसी माध्यम',
      'return_reason': 'वापसी का कारण',
      'restock_items': 'स्टॉक में वापस जोड़ें',
      'credit_note': 'क्रेडिट नोट',

      // Khata / Customers
      'khata_title': 'ग्राहक खाता (उधार बही)',
      'customer_name': 'ग्राहक का नाम',
      'customer_phone': 'मोबाइल नंबर',
      'current_balance': 'बकाया राशि',
      'give_credit': 'उधार दिया',
      'receive_payment': 'जमा लिया',
      'send_reminder': 'व्हाट्सएप तकादा भेजें',

      // Menu & Settings
      'settings': 'सेटिंग्स',
      'store_profile': 'दुकान प्रोफाइल व जीएसटी',
      'business_vertical': 'दुकान का प्रकार (Vertical)',
      'whatsapp_support': 'व्हाट्सएप सपोर्ट',
      'app_version': 'ऐप वर्शन',
      'language': 'भाषा (Language)',
      'select_language': 'अपनी भाषा चुनें',
      'save': 'सुरक्षित करें',
      'cancel': 'रद्द करें',
      'confirm': 'पुष्टि करें',
      'delete': 'हटाएं',
      'edit': 'बदलें',
      'close': 'बंद करें',
    },

    // Marathi (मराठी)
    'mr': {
      // Navigation
      'nav_home': 'मुख्य',
      'nav_products': 'वस्तू',
      'nav_billing': 'बिलिंग',
      'nav_khata': 'खाते',
      'nav_menu': 'मेनू',

      // POS / Billing
      'pos_billing_title': 'जलद बिलिंग काउंटर',
      'search_items_placeholder': 'वस्तू शोधा किंवा बारकोड स्कॅन करा...',
      'cart_empty_title': 'कार्ट रिकामी आहे',
      'cart_empty_subtitle': 'यादीतून वस्तू निवडा किंवा बारकोड स्कॅन करा',
      'total': 'एकूण',
      'subtotal': 'उप-एकूण',
      'tax': 'जीएसटी / कर',
      'discount': 'सूट / डिस्काउंट',
      'round_off': 'राउंड ऑफ',
      'pay_now': 'बिल बनवा',
      'checkout': 'चेकआउट',
      'clear_cart': 'रिकामा करा',
      'hold_cart': 'होल्ड',
      'recall_cart': 'परत आणा',
      'item': 'वस्तू',
      'items': 'वस्तू',
      'qty': 'नग / प्रमाण',
      'price': 'दर',
      'stock': 'शिल्लक',
      'cash': 'रोख (Cash)',
      'online_upi': 'ऑनलाइन / UPI',
      'udhar_credit': 'उधारी (Khata)',
      'split_payment': 'विभागून पेमेंट',
      'tendered': 'ग्राहकाने दिले',
      'change': 'परत देणे',
      'customer_optional': 'ग्राहक (ऐच्छिक)',

      // Products / Inventory
      'products_title': 'उत्पादने व साठा',
      'add_product': '+ नवीन वस्तू जोडा',
      'inward_ai': 'AI द्वारे आवक नोंदवा',
      'rapid_scan': 'रॅपिड स्कॅन',
      'cost_price': 'खरेदी दर',
      'selling_price': 'विक्री दर',
      'mrp': 'एमआरपी',
      'variants': 'व्हेरिएंट्स (आकार/रंग)',
      'select_variant': 'व्हेरिएंट निवडा',
      'low_stock_warning': 'कमी साठा इशारा',
      'unlimited_stock': 'अमर्याद साठा',
      'category': 'वर्गवारी (Category)',
      'unit': 'एकक (Unit)',

      // Returns / Refund
      'sales_return': 'विक्री परत',
      'partial_return': 'काही वस्तू परत (टुकड्यांत)',
      'return_items': 'वस्तू परत घ्या',
      'full_void': 'पूर्ण बिल रद्द',
      'refund_amount': 'परतावा रक्कम',
      'refund_mode': 'परतावा पद्धत',
      'return_reason': 'परतीचे कारण',
      'restock_items': 'साठ्यात पुन्हा जमा करा',
      'credit_note': 'क्रेडिट नोट',

      // Khata / Customers
      'khata_title': 'ग्राहक खातेवही (उधारी)',
      'customer_name': 'ग्राहकाचे नाव',
      'customer_phone': 'मोबाईल नंबर',
      'current_balance': 'शिल्लक बाकी',
      'give_credit': 'उधार दिले',
      'receive_payment': 'जमा केले',
      'send_reminder': 'व्हॉट्सअॅप आठवण पाठवा',

      // Menu & Settings
      'settings': 'सेटिंग्ज',
      'store_profile': 'दुकान प्रोफाईल व कर',
      'business_vertical': 'व्यवसाय प्रकार',
      'whatsapp_support': 'व्हॉट्सअॅप मदत',
      'app_version': 'अ‍ॅप आवृत्ती',
      'language': 'भाषा (Language)',
      'select_language': 'आपली भाषा निवडा',
      'save': 'जतन करा',
      'cancel': 'रद्द करा',
      'confirm': 'खात्री करा',
      'delete': 'हटवा',
      'edit': 'बदला',
      'close': 'बंद करा',
    },

    // Gujarati (ગુજરાતી)
    'gu': {
      // Navigation
      'nav_home': 'હોમ',
      'nav_products': 'વસ્તુઓ',
      'nav_billing': 'બિલિંગ',
      'nav_khata': 'ખાતાવહી',
      'nav_menu': 'મેનુ',

      // POS / Billing
      'pos_billing_title': 'ઝડપી બિલિંગ કાઉન્ટર',
      'search_items_placeholder': 'વસ્તુ શોધો અથવા બારકોડ સ્કેન કરો...',
      'cart_empty_title': 'કાર્ટ ખાલી છે',
      'cart_empty_subtitle': 'યાદીમાંથી વસ્તુ પસંદ કરો અથવા સ્કેન કરો',
      'total': 'કુલ રકમ',
      'subtotal': 'પેટા રકમ',
      'tax': 'જીએસટી / ટેક્સ',
      'discount': 'ડિસ્કાઉન્ટ / છૂટ',
      'round_off': 'રાઉન્ડ ઓફ',
      'pay_now': 'બિલ બનાવો',
      'checkout': 'ચેકઆઉટ',
      'clear_cart': 'ખાલી કરો',
      'hold_cart': 'હોલ્ડ',
      'recall_cart': 'પાછું લાવો',
      'item': 'વસ્તુ',
      'items': 'વસ્તુઓ',
      'qty': 'જથ્થો (Qty)',
      'price': 'ભાવ',
      'stock': 'સ્ટોક',
      'cash': 'રોકડ (Cash)',
      'online_upi': 'ઓનલાઇન / UPI',
      'udhar_credit': 'ઉધાર (ખાતું)',
      'split_payment': 'ભાગલા પેમેન્ટ',
      'tendered': 'ગ્રાહકે આપ્યા',
      'change': 'પાછા આપવાના',
      'customer_optional': 'ગ્રાહક (વૈકલ્પિક)',

      // Products / Inventory
      'products_title': 'વસ્તુઓ અને સ્ટોક',
      'add_product': '+ નવી વસ્તુ ઉમેરો',
      'inward_ai': 'AI થી બિલ ચડાવો',
      'rapid_scan': 'રેપિડ સ્કેન',
      'cost_price': 'ખરીદી કિંમત',
      'selling_price': 'વેચાણ કિંમત',
      'mrp': 'એમઆરપી',
      'variants': 'સાઇઝ / કલર',
      'select_variant': 'વેરિઅન્ટ પસંદ કરો',
      'low_stock_warning': 'ઓછા સ્ટોકની ચેતવણી',
      'unlimited_stock': 'અમર્યાદિત સ્ટોક',
      'category': 'કેટેગરી',
      'unit': 'એકમ (Unit)',

      // Returns / Refund
      'sales_return': 'વેચાણ પરત',
      'partial_return': 'ટુકડાઓમાં વાપસી',
      'return_items': 'વસ્તુઓ પાછી લો',
      'full_void': 'આખું બિલ રદ',
      'refund_amount': 'પરત રકમ',
      'refund_mode': 'પરત પદ્ધતિ',
      'return_reason': 'વાપસીનું કારણ',
      'restock_items': 'સ્ટોકમાં પાછું ઉમેરો',
      'credit_note': 'ક્રેડિટ નોટ',

      // Khata / Customers
      'khata_title': 'ગ્રાહક ખાતાવહી (ઉધાર)',
      'customer_name': 'ગ્રાહકનું નામ',
      'customer_phone': 'મોબાઇલ નંબર',
      'current_balance': 'બાકી રકમ',
      'give_credit': 'ઉધાર આપ્યું',
      'receive_payment': 'જમા લીધું',
      'send_reminder': 'વોટ્સએપ યાદી મોકલો',

      // Menu & Settings
      'settings': 'સેટિંગ્સ',
      'store_profile': 'દુકાન પ્રોફાઇલ અને જીએસટી',
      'business_vertical': 'વેપાર પ્રકાર',
      'whatsapp_support': 'વોટ્સએપ સપોર્ટ',
      'app_version': 'એપ વર્ઝન',
      'language': 'ભાષા (Language)',
      'select_language': 'તમારી ભાષા પસંદ કરો',
      'save': 'સાચવો',
      'cancel': 'રદ કરો',
      'confirm': 'ખાતરી કરો',
      'delete': 'કાઢી નાખો',
      'edit': 'ફેરફાર કરો',
      'close': 'બંધ કરો',
    },
  };

  static String get(String key, {String lang = 'en'}) {
    final langMap = _translations[lang] ?? _translations['en']!;
    return langMap[key] ?? _translations['en']?[key] ?? key;
  }
}
