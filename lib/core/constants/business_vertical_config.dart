import 'package:flutter/foundation.dart';

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
