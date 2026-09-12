import 'package:flutter/material.dart';

class VerticalFeatureToggles {
  final bool showBarcode;
  final bool showWeightUnits;
  final bool showBatchExpiry;
  final bool showTableOrderType;
  final bool showSizeVariants;
  final bool showImeiWarranty;
  final bool showDoctorPrescription;
  final bool hasBillScan;
  final bool showQuotationEstimate;

  const VerticalFeatureToggles({
    required this.showBarcode,
    required this.showWeightUnits,
    required this.showBatchExpiry,
    required this.showTableOrderType,
    required this.showSizeVariants,
    required this.showImeiWarranty,
    required this.showDoctorPrescription,
    required this.hasBillScan,
    required this.showQuotationEstimate,
  });
}

class VerticalPlaceholders {
  final String searchProduct;
  final String newProductName;
  final String customerSearch;
  final String supplierNameExample;
  final String invoiceFooterNote;

  const VerticalPlaceholders({
    required this.searchProduct,
    required this.newProductName,
    required this.customerSearch,
    required this.supplierNameExample,
    required this.invoiceFooterNote,
  });
}

class BusinessVerticalProfile {
  final String id;
  final String name;
  final String shortName;
  final String emoji;
  final VerticalFeatureToggles toggles;
  final VerticalPlaceholders placeholders;
  final String defaultUnit;
  final List<String> recommendedUnits;
  final List<String> quickCategories;
  final String productsMenuTitle;
  final String productsMenuSubtitle;
  final String purchasesMenuTitle;
  final String purchasesMenuSubtitle;

  const BusinessVerticalProfile({
    required this.id,
    required this.name,
    required this.shortName,
    required this.emoji,
    required this.toggles,
    required this.placeholders,
    required this.defaultUnit,
    required this.recommendedUnits,
    required this.quickCategories,
    required this.productsMenuTitle,
    required this.productsMenuSubtitle,
    required this.purchasesMenuTitle,
    required this.purchasesMenuSubtitle,
  });

  /// Dynamic bottom nav label for Tab 1
  String get bottomNavLabel {
    switch (id) {
      case 'restaurant':
        return 'Menu';
      case 'pharmacy':
        return 'Medicines';
      case 'clothing':
        return 'Apparel';
      case 'hardware':
        return 'Items';
      default:
        return 'Product';
    }
  }

  /// Dynamic bottom nav active icon for Tab 1
  IconData get navActiveIcon {
    switch (id) {
      case 'restaurant':
        return Icons.restaurant_menu_rounded;
      case 'pharmacy':
        return Icons.medication_rounded;
      case 'clothing':
        return Icons.checkroom_rounded;
      case 'hardware':
        return Icons.construction_rounded;
      default:
        return Icons.inventory_2_rounded;
    }
  }

  /// Dynamic bottom nav inactive icon for Tab 1
  IconData get navInactiveIcon {
    switch (id) {
      case 'restaurant':
        return Icons.restaurant_menu_outlined;
      case 'pharmacy':
        return Icons.medication_outlined;
      case 'clothing':
        return Icons.checkroom_outlined;
      case 'hardware':
        return Icons.construction_outlined;
      default:
        return Icons.inventory_2_outlined;
    }
  }

  /// Master header title on Products screen
  String get productsScreenTitle {
    switch (id) {
      case 'restaurant':
        return 'Menu Items & Dishes';
      case 'pharmacy':
        return 'Medicines & Drugs';
      case 'clothing':
        return 'Apparel & Footwear';
      case 'hardware':
        return 'Hardware & Tools';
      default:
        return 'Products Master & Items';
    }
  }

  /// "+ Add Product" button label
  String get addProductButtonLabel {
    switch (id) {
      case 'restaurant':
        return 'Add Dish';
      case 'pharmacy':
        return 'Add Medicine';
      case 'clothing':
        return 'Add Apparel';
      case 'hardware':
        return 'Add Item';
      default:
        return 'Add Product';
    }
  }

  /// Label for the AI bulk-add button on the Products screen. Restaurant gets
  /// its own wording ("Scan Menu") because it opens MenuScanSheet, not the
  /// wholesale-purchase AiInwardModal every other vertical opens — see
  /// products_screen.dart's _openAiInwardSheet.
  String get aiBulkAddButtonLabel {
    switch (id) {
      case 'restaurant':
        return 'Scan Menu';
      default:
        return 'Inward with AI';
    }
  }

  /// Field label for item name in add/edit modal
  String get itemFieldLabel {
    switch (id) {
      case 'restaurant':
        return 'Dish / Food Item Name *';
      case 'pharmacy':
        return 'Medicine Name & Strength *';
      case 'clothing':
        return 'Apparel / Style Name *';
      case 'hardware':
        return 'Item / Part Name *';
      default:
        return 'Product / Item Full Name *';
    }
  }

  /// Subtitle description for products screen header
  String getCatalogDescription(int count) {
    switch (id) {
      case 'restaurant':
        return '$count registered food & beverage items with quick dining category filters';
      case 'pharmacy':
        return '$count registered medicines with strip packaging, batch expiry & barcodes';
      case 'clothing':
        return '$count registered apparel items with sizes, colors & price tags';
      case 'hardware':
        return '$count registered hardware & electrical items with warranty tracking';
      default:
        return '$count registered products with barcodes, batch expiry & instant stock tracking';
    }
  }

  /// Headline for a genuinely-empty catalog (zero products, no search/filter
  /// active) — deliberately distinct from "no results for your search",
  /// which every screen using this should show instead when a search query
  /// or filter is what actually produced the empty list. Conflating the two
  /// (a generic "No matching products found" shown even on a brand-new
  /// store with nothing added yet) was the exact gap flagged in the
  /// KamaiPlus Playbook's professional-polish pass.
  String get emptyCatalogTitle {
    switch (id) {
      case 'restaurant':
        return 'No dishes on your menu yet';
      case 'pharmacy':
        return 'No medicines added yet';
      case 'clothing':
        return 'No apparel added yet';
      case 'hardware':
        return 'No items added yet';
      default:
        return 'No products added yet';
    }
  }

  /// Companion body text for [emptyCatalogTitle] — names the actual first
  /// action available on that screen (matches [aiBulkAddButtonLabel] /
  /// [addProductButtonLabel] wording) rather than a generic "add something".
  String get emptyCatalogDescription {
    switch (id) {
      case 'restaurant':
        return 'Scan a photo of your menu card, or add your first dish manually.';
      case 'pharmacy':
        return 'Scan a barcode or add your first medicine to get started.';
      case 'clothing':
        return 'Add your first apparel item — sizes and colors can be set per item.';
      case 'hardware':
        return 'Scan a barcode or add your first item to get started.';
      default:
        return 'Scan a barcode or add your first product to get started.';
    }
  }
}

class BusinessVerticals {
  static const grocery = BusinessVerticalProfile(
    id: 'grocery',
    name: 'Kirana & Grocery Store',
    shortName: 'Kirana',
    emoji: '🌾',
    toggles: VerticalFeatureToggles(
      showBarcode: true,
      showWeightUnits: true,
      showBatchExpiry: false,
      showTableOrderType: false,
      showSizeVariants: false,
      showImeiWarranty: false,
      showDoctorPrescription: false,
      hasBillScan: true,
      showQuotationEstimate: false,
    ),
    placeholders: VerticalPlaceholders(
      searchProduct: 'Scan barcode or type Atta, Rice, Oil, Maggi...',
      newProductName: 'e.g., Aashirvaad Shudh Chakki Atta 5kg',
      customerSearch: 'Search regular customer name or 10-digit mobile...',
      supplierNameExample: 'e.g. Metro Cash & Carry, Parle Agency...',
      invoiceFooterNote: 'Thank you for shopping with us! Please visit again.',
    ),
    defaultUnit: 'kg',
    recommendedUnits: ['kg', 'gram', 'litre', 'packet', 'piece', 'box', 'dozen'],
    quickCategories: [
      'Atta, Rice & Dal',
      'Spices & Cooking Oil',
      'Dairy, Bread & Eggs',
      'Biscuits & Snacks',
      'Soaps & Detergents',
      'Pooja & Agarbatti',
    ],
    productsMenuTitle: 'Products & FMCG',
    productsMenuSubtitle: 'Daily Essentials & Barcodes',
    purchasesMenuTitle: 'Wholesale Inward',
    purchasesMenuSubtitle: 'Mandi & Supplier Bills',
  );

  static const pharmacy = BusinessVerticalProfile(
    id: 'pharmacy',
    name: 'Medical Store & Pharmacy',
    shortName: 'Medical',
    emoji: '💊',
    toggles: VerticalFeatureToggles(
      showBarcode: true,
      showWeightUnits: false,
      showBatchExpiry: true,
      showTableOrderType: false,
      showSizeVariants: false,
      showImeiWarranty: false,
      showDoctorPrescription: true,
      hasBillScan: true,
      showQuotationEstimate: false,
    ),
    placeholders: VerticalPlaceholders(
      searchProduct: 'Type medicine name (Paracetamol, Cetirizine, Syrup)...',
      newProductName: 'e.g., Dolo 650mg Paracetamol (Strip of 15)',
      customerSearch: 'Patient name, WhatsApp number, or Doctor name...',
      supplierNameExample: 'e.g. Zenith Pharma Distributors...',
      invoiceFooterNote:
          'Medicines once sold cannot be returned without original batch verification. Get well soon!',
    ),
    defaultUnit: 'strip',
    recommendedUnits: ['strip', 'piece', 'box', 'ml', 'litre', 'packet'],
    quickCategories: [
      'Tablets & Capsules',
      'Syrups & Suspensions',
      'Injections & Vials',
      'Ointments & Creams',
      'First Aid & Bandages',
      'Generic Medicines',
    ],
    productsMenuTitle: 'Medicines & Stock',
    productsMenuSubtitle: 'Batch, Expiry & Barcodes',
    purchasesMenuTitle: 'Stockist Inward',
    purchasesMenuSubtitle: 'Distributor & Stockist Bills',
  );

  static const clothing = BusinessVerticalProfile(
    id: 'clothing',
    name: 'Clothing, Footwear & Apparel',
    shortName: 'Apparel',
    emoji: '👕',
    toggles: VerticalFeatureToggles(
      showBarcode: true,
      showWeightUnits: false,
      showBatchExpiry: false,
      showTableOrderType: false,
      showSizeVariants: true,
      showImeiWarranty: false,
      showDoctorPrescription: false,
      hasBillScan: true,
      showQuotationEstimate: false,
    ),
    placeholders: VerticalPlaceholders(
      searchProduct: 'Search Shirt, Jeans, Kurti, Shoes or scan tag...',
      newProductName: 'e.g., Men Pure Cotton Slim Fit Shirt (Size 40)',
      customerSearch: 'Customer name or WhatsApp number...',
      supplierNameExample: 'e.g. Surat Textile Wholesaler...',
      invoiceFooterNote:
          'Exchange permitted within 7 days with original bill and price tags intact. No cash refund.',
    ),
    defaultUnit: 'piece',
    recommendedUnits: ['piece', 'pair', 'set', 'meter', 'box'],
    quickCategories: [
      'Men Shirts & T-Shirts',
      'Women Kurtis & Sarees',
      'Jeans & Trousers',
      'Kids Wear',
      'Shoes & Footwear',
      'Innerwear & Accessories',
    ],
    productsMenuTitle: 'Products & Sizes',
    productsMenuSubtitle: 'Size, Color & Stock',
    purchasesMenuTitle: 'Wholesale Inward',
    purchasesMenuSubtitle: 'Wholesaler & Manufacturer Bills',
  );

  static const hardware = BusinessVerticalProfile(
    id: 'hardware',
    name: 'Hardware, Electrical & Sanitary',
    shortName: 'Hardware',
    emoji: '🔩',
    toggles: VerticalFeatureToggles(
      showBarcode: true,
      showWeightUnits: true,
      showBatchExpiry: false,
      showTableOrderType: false,
      showSizeVariants: false,
      showImeiWarranty: true,
      showDoctorPrescription: false,
      hasBillScan: true,
      showQuotationEstimate: true,
    ),
    placeholders: VerticalPlaceholders(
      searchProduct: 'Search Paint, PVC Pipe, Screw, Wire, MCB, Tap...',
      newProductName: 'e.g., Asian Paints Apex Exterior Emulsion 4L',
      customerSearch: 'Contractor, electrician, plumber or customer mobile...',
      supplierNameExample: 'e.g. Havells Distributor, Local Hardware Supplier...',
      invoiceFooterNote:
          'Goods once cut or tinted cannot be taken back. Replacement warranty on LED & Fans with bill copy.',
    ),
    defaultUnit: 'piece',
    recommendedUnits: ['piece', 'meter', 'foot', 'sqft', 'kg', 'litre', 'box', 'bundle'],
    quickCategories: [
      'Pipes & PVC Fittings',
      'Paints & Wall Primer',
      'Wires, Switches & MCB',
      'Hand & Power Tools',
      'Screws, Nails & Fasteners',
      'Sanitary & Water Taps',
      'Cement & Adhesives',
      'LED Bulbs & Battens',
    ],
    productsMenuTitle: 'Products & Stock',
    productsMenuSubtitle: 'Tools, Paints & Electricals',
    purchasesMenuTitle: 'Supplier Inward',
    purchasesMenuSubtitle: 'Distributor & Supplier Bills',
  );

  static const restaurant = BusinessVerticalProfile(
    id: 'restaurant',
    name: 'Restaurant, Cafe & Fast Food',
    shortName: 'Cafe / Dine',
    emoji: '🍽️',
    toggles: VerticalFeatureToggles(
      showBarcode: false,
      showWeightUnits: false,
      showBatchExpiry: false,
      showTableOrderType: true,
      showSizeVariants: false,
      showImeiWarranty: false,
      showDoctorPrescription: false,
      hasBillScan: false,
      showQuotationEstimate: false,
    ),
    placeholders: VerticalPlaceholders(
      searchProduct: 'Touch category or type Chai, Paneer, Dosa, Pizza...',
      newProductName: 'e.g., Paneer Butter Masala (Full) / Cold Coffee',
      customerSearch: 'Guest name or phone (optional for dine-in)...',
      supplierNameExample: 'e.g. Local Vegetable Vendor, Dairy Supplier...',
      invoiceFooterNote:
          'Thank you for dining with us! Hope you enjoyed the food. Please visit again.',
    ),
    defaultUnit: 'plate',
    recommendedUnits: ['plate', 'portion', 'piece', 'packet', 'box'],
    quickCategories: [
      'Hot & Cold Beverages',
      'Starters & Snacks',
      'Main Course (Curries)',
      'Roti, Naan & Rice',
      'Fast Food & Pizzas',
      'Desserts & Sweets',
    ],
    productsMenuTitle: 'Menu Items',
    productsMenuSubtitle: 'Dishes & Prices',
    purchasesMenuTitle: 'Kitchen Inward',
    purchasesMenuSubtitle: 'Vendor & Raw Material Bills',
  );

  static const Map<String, BusinessVerticalProfile> all = {
    'grocery': grocery,
    'pharmacy': pharmacy,
    'clothing': clothing,
    'hardware': hardware,
    'restaurant': restaurant,
  };

  /// Legacy free-text category strings already stored on existing installs
  /// (from the current signup screen's 4 options) must resolve correctly.
  static const Map<String, String> _legacyMap = {
    'grocery / kirana': 'grocery',
    'apparel / clothing': 'clothing',
    'electronics & mobile': 'hardware',
    'cafe / restaurant': 'restaurant',
    'medical / pharmacy': 'pharmacy',
  };

  /// Master unit dictionary mapping canonical unit IDs to cashier-friendly display labels
  static const Map<String, String> unitDisplayLabels = {
    'kg': 'Kilogram (kg)',
    'gram': 'Gram (g)',
    'g': 'Gram (g)',
    'litre': 'Litre (L)',
    'ltr': 'Litre (L)',
    'ml': 'Millilitre (ml)',
    'packet': 'Packet (pkt)',
    'pkt': 'Packet (pkt)',
    'piece': 'Piece (pcs)',
    'pcs': 'Piece (pcs)',
    'box': 'Box (box)',
    'dozen': 'Dozen (dz)',
    'strip': 'Medicine Strip (strip)',
    'pair': 'Pair (pair)',
    'set': 'Set (set)',
    'meter': 'Meter (m)',
    'foot': 'Foot (ft)',
    'sqft': 'Square Feet (sq.ft)',
    'bundle': 'Bundle (bdl)',
    'plate': 'Plate / Dish (plate)',
    'portion': 'Portion (portion)',
    'btl': 'Bottle (btl)',
  };

  /// Global reactive notifier for instant UI update when merchant changes vertical in Settings
  static final ValueNotifier<String> activeBusinessTypeNotifier = ValueNotifier<String>('grocery');

  static void updateActiveBusinessType(String newType) {
    activeBusinessTypeNotifier.value = resolve(newType).id;
  }

  static BusinessVerticalProfile resolve(String? businessType) {
    if (businessType == null || businessType.isEmpty) return grocery;
    final lower = businessType.toLowerCase().trim();
    if (all.containsKey(lower)) return all[lower]!;
    final mapped = _legacyMap[lower];
    if (mapped != null && all.containsKey(mapped)) return all[mapped]!;
    return grocery;
  }
}
