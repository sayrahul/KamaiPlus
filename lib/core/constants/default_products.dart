/// Default starter products seeded during onboarding per business vertical.
/// All prices are in INTEGER PAISE (₹1 = 100 paise). Financial Invariant must not be violated.
library;

class DefaultProductSeed {
  final String name;
  final String categoryName;
  final int sellingPricePaise;
  final int mrpPaise;
  final int purchasePricePaise;
  final double stockQuantity;
  final String unit;
  final double taxRate;

  const DefaultProductSeed({
    required this.name,
    required this.categoryName,
    required this.sellingPricePaise,
    required this.mrpPaise,
    required this.purchasePricePaise,
    required this.stockQuantity,
    required this.unit,
    this.taxRate = 0.0,
  });
}

/// Master map keyed by business vertical ID -> list of default products to seed.
const Map<String, List<DefaultProductSeed>> kDefaultProductsByVertical = {
  'grocery': [
    DefaultProductSeed(name: 'Aashirvaad Atta 5 kg', categoryName: 'Atta, Rice & Dal', sellingPricePaise: 27000, mrpPaise: 29500, purchasePricePaise: 24000, stockQuantity: 20, unit: 'packet'),
    DefaultProductSeed(name: 'India Gate Basmati Rice 1 kg', categoryName: 'Atta, Rice & Dal', sellingPricePaise: 9500, mrpPaise: 10500, purchasePricePaise: 8000, stockQuantity: 30, unit: 'kg'),
    DefaultProductSeed(name: 'Toor Dal 1 kg', categoryName: 'Atta, Rice & Dal', sellingPricePaise: 16000, mrpPaise: 17000, purchasePricePaise: 14000, stockQuantity: 20, unit: 'kg'),
    DefaultProductSeed(name: 'Sugar 1 kg', categoryName: 'Atta, Rice & Dal', sellingPricePaise: 4500, mrpPaise: 4800, purchasePricePaise: 4000, stockQuantity: 50, unit: 'kg'),
    DefaultProductSeed(name: 'Fortune Sunflower Oil 1 L', categoryName: 'Spices & Cooking Oil', sellingPricePaise: 13500, mrpPaise: 14500, purchasePricePaise: 12000, stockQuantity: 25, unit: 'litre'),
    DefaultProductSeed(name: 'MDH Garam Masala 100 g', categoryName: 'Spices & Cooking Oil', sellingPricePaise: 5500, mrpPaise: 6000, purchasePricePaise: 4500, stockQuantity: 15, unit: 'packet'),
    DefaultProductSeed(name: 'Amul Full Cream Milk 500 ml', categoryName: 'Dairy, Bread & Eggs', sellingPricePaise: 3400, mrpPaise: 3400, purchasePricePaise: 3000, stockQuantity: 40, unit: 'packet'),
    DefaultProductSeed(name: 'Britannia Good Day Biscuits 200 g', categoryName: 'Biscuits & Snacks', sellingPricePaise: 3500, mrpPaise: 4000, purchasePricePaise: 2800, stockQuantity: 30, unit: 'packet'),
    DefaultProductSeed(name: 'Maggi 2-Minute Noodles 70 g', categoryName: 'Biscuits & Snacks', sellingPricePaise: 1500, mrpPaise: 1500, purchasePricePaise: 1200, stockQuantity: 50, unit: 'packet'),
    DefaultProductSeed(name: 'Surf Excel Quick Wash 500 g', categoryName: 'Soaps & Detergents', sellingPricePaise: 8800, mrpPaise: 9500, purchasePricePaise: 7500, stockQuantity: 15, unit: 'packet'),
    DefaultProductSeed(name: 'Lux Soap Bar 100 g', categoryName: 'Soaps & Detergents', sellingPricePaise: 5000, mrpPaise: 5500, purchasePricePaise: 4000, stockQuantity: 24, unit: 'piece'),
    DefaultProductSeed(name: 'Cycle No. 1 Agarbatti', categoryName: 'Pooja & Agarbatti', sellingPricePaise: 3500, mrpPaise: 4000, purchasePricePaise: 2800, stockQuantity: 20, unit: 'packet'),
  ],
  'pharmacy': [
    DefaultProductSeed(name: 'Dolo 650 Paracetamol (Strip of 15)', categoryName: 'Tablets & Capsules', sellingPricePaise: 3500, mrpPaise: 3700, purchasePricePaise: 2800, stockQuantity: 50, unit: 'strip'),
    DefaultProductSeed(name: 'Cetirizine 10mg (Strip of 10)', categoryName: 'Tablets & Capsules', sellingPricePaise: 2200, mrpPaise: 2500, purchasePricePaise: 1800, stockQuantity: 30, unit: 'strip'),
    DefaultProductSeed(name: 'Pantoprazole 40mg (Strip of 15)', categoryName: 'Tablets & Capsules', sellingPricePaise: 8500, mrpPaise: 9500, purchasePricePaise: 7000, stockQuantity: 25, unit: 'strip'),
    DefaultProductSeed(name: 'Azithromycin 500mg (Strip of 5)', categoryName: 'Tablets & Capsules', sellingPricePaise: 5500, mrpPaise: 6000, purchasePricePaise: 4500, stockQuantity: 20, unit: 'strip'),
    DefaultProductSeed(name: 'Cough Syrup Benadryl 100 ml', categoryName: 'Syrups & Suspensions', sellingPricePaise: 9500, mrpPaise: 9900, purchasePricePaise: 8000, stockQuantity: 20, unit: 'box'),
    DefaultProductSeed(name: 'Ascoril LS Syrup 100 ml', categoryName: 'Syrups & Suspensions', sellingPricePaise: 9000, mrpPaise: 9500, purchasePricePaise: 7500, stockQuantity: 15, unit: 'box'),
    DefaultProductSeed(name: 'Betadine Ointment 20 g', categoryName: 'Ointments & Creams', sellingPricePaise: 5500, mrpPaise: 6000, purchasePricePaise: 4500, stockQuantity: 15, unit: 'piece'),
    DefaultProductSeed(name: 'Band-Aid Bandage Box (100 strips)', categoryName: 'First Aid & Bandages', sellingPricePaise: 7500, mrpPaise: 8500, purchasePricePaise: 6000, stockQuantity: 10, unit: 'box'),
    DefaultProductSeed(name: 'Disprin (Aspirin) Strip of 12', categoryName: 'Generic Medicines', sellingPricePaise: 1800, mrpPaise: 2000, purchasePricePaise: 1400, stockQuantity: 40, unit: 'strip'),
    DefaultProductSeed(name: 'Eno Fruit Salt Sachet (30 pcs)', categoryName: 'Generic Medicines', sellingPricePaise: 9000, mrpPaise: 9500, purchasePricePaise: 7500, stockQuantity: 12, unit: 'box'),
  ],
  'clothing': [
    DefaultProductSeed(name: 'Men Cotton T-Shirt (Size M)', categoryName: 'Men Shirts & T-Shirts', sellingPricePaise: 39900, mrpPaise: 59900, purchasePricePaise: 25000, stockQuantity: 10, unit: 'piece'),
    DefaultProductSeed(name: 'Men Formal Shirt Full Sleeve (Size 40)', categoryName: 'Men Shirts & T-Shirts', sellingPricePaise: 69900, mrpPaise: 99900, purchasePricePaise: 45000, stockQuantity: 8, unit: 'piece'),
    DefaultProductSeed(name: 'Women Kurti Cotton (Size M)', categoryName: 'Women Kurtis & Sarees', sellingPricePaise: 59900, mrpPaise: 89900, purchasePricePaise: 35000, stockQuantity: 10, unit: 'piece'),
    DefaultProductSeed(name: 'Silk Saree (Designer)', categoryName: 'Women Kurtis & Sarees', sellingPricePaise: 299900, mrpPaise: 399900, purchasePricePaise: 200000, stockQuantity: 5, unit: 'piece'),
    DefaultProductSeed(name: 'Men Denim Jeans Slim Fit (Size 32)', categoryName: 'Jeans & Trousers', sellingPricePaise: 99900, mrpPaise: 149900, purchasePricePaise: 65000, stockQuantity: 8, unit: 'piece'),
    DefaultProductSeed(name: 'Kids T-Shirt Cotton (Age 4-5 yrs)', categoryName: 'Kids Wear', sellingPricePaise: 24900, mrpPaise: 39900, purchasePricePaise: 15000, stockQuantity: 12, unit: 'piece'),
    DefaultProductSeed(name: 'Men Sports Shoes (Size 8)', categoryName: 'Shoes & Footwear', sellingPricePaise: 149900, mrpPaise: 199900, purchasePricePaise: 100000, stockQuantity: 6, unit: 'pair'),
    DefaultProductSeed(name: 'Women Sandals Block Heel (Size 6)', categoryName: 'Shoes & Footwear', sellingPricePaise: 79900, mrpPaise: 129900, purchasePricePaise: 50000, stockQuantity: 6, unit: 'pair'),
    DefaultProductSeed(name: 'Men Innerwear Vest (Size M) - Pack of 3', categoryName: 'Innerwear & Accessories', sellingPricePaise: 29900, mrpPaise: 39900, purchasePricePaise: 20000, stockQuantity: 10, unit: 'set'),
    DefaultProductSeed(name: 'Women Stole / Dupatta (Cotton)', categoryName: 'Innerwear & Accessories', sellingPricePaise: 19900, mrpPaise: 29900, purchasePricePaise: 12000, stockQuantity: 15, unit: 'piece'),
  ],
  'hardware': [
    DefaultProductSeed(name: 'PVC Pipe 1 inch (1 meter)', categoryName: 'Pipes & PVC Fittings', sellingPricePaise: 5500, mrpPaise: 6000, purchasePricePaise: 4200, stockQuantity: 50, unit: 'meter'),
    DefaultProductSeed(name: 'Asian Paints Apex Emulsion 4 L', categoryName: 'Paints & Wall Primer', sellingPricePaise: 149900, mrpPaise: 165000, purchasePricePaise: 128000, stockQuantity: 10, unit: 'piece'),
    DefaultProductSeed(name: 'Havells 2.5 sq mm Wire (per meter)', categoryName: 'Wires, Switches & MCB', sellingPricePaise: 3500, mrpPaise: 3800, purchasePricePaise: 2900, stockQuantity: 100, unit: 'meter'),
    DefaultProductSeed(name: 'Legrand MCB 32A Single Pole', categoryName: 'Wires, Switches & MCB', sellingPricePaise: 38000, mrpPaise: 45000, purchasePricePaise: 30000, stockQuantity: 10, unit: 'piece'),
    DefaultProductSeed(name: 'Stanley Screwdriver Set (6 pcs)', categoryName: 'Hand & Power Tools', sellingPricePaise: 24900, mrpPaise: 35000, purchasePricePaise: 18000, stockQuantity: 5, unit: 'set'),
    DefaultProductSeed(name: 'M6 Nut Bolt Set (Pack of 50)', categoryName: 'Screws, Nails & Fasteners', sellingPricePaise: 8000, mrpPaise: 10000, purchasePricePaise: 6000, stockQuantity: 10, unit: 'box'),
    DefaultProductSeed(name: 'Parryware Wall-Hung Washbasin', categoryName: 'Sanitary & Water Taps', sellingPricePaise: 299900, mrpPaise: 350000, purchasePricePaise: 250000, stockQuantity: 4, unit: 'piece'),
    DefaultProductSeed(name: 'Ambuja Cement 50 kg Bag', categoryName: 'Cement & Adhesives', sellingPricePaise: 38000, mrpPaise: 40000, purchasePricePaise: 34000, stockQuantity: 20, unit: 'piece'),
    DefaultProductSeed(name: 'Philips LED Bulb 9W B22', categoryName: 'LED Bulbs & Battens', sellingPricePaise: 12000, mrpPaise: 14900, purchasePricePaise: 9000, stockQuantity: 30, unit: 'piece'),
    DefaultProductSeed(name: 'Panasonic LED Batten 20W 2ft', categoryName: 'LED Bulbs & Battens', sellingPricePaise: 24900, mrpPaise: 29900, purchasePricePaise: 19000, stockQuantity: 15, unit: 'piece'),
  ],
  'restaurant': [
    DefaultProductSeed(name: 'Masala Chai', categoryName: 'Hot & Cold Beverages', sellingPricePaise: 2000, mrpPaise: 2000, purchasePricePaise: 500, stockQuantity: 999, unit: 'plate'),
    DefaultProductSeed(name: 'Cold Coffee', categoryName: 'Hot & Cold Beverages', sellingPricePaise: 8000, mrpPaise: 8000, purchasePricePaise: 3000, stockQuantity: 999, unit: 'plate'),
    DefaultProductSeed(name: 'Samosa (2 pcs)', categoryName: 'Starters & Snacks', sellingPricePaise: 2500, mrpPaise: 2500, purchasePricePaise: 1000, stockQuantity: 999, unit: 'plate'),
    DefaultProductSeed(name: 'Veg Spring Rolls (4 pcs)', categoryName: 'Starters & Snacks', sellingPricePaise: 12000, mrpPaise: 12000, purchasePricePaise: 5000, stockQuantity: 999, unit: 'plate'),
    DefaultProductSeed(name: 'Paneer Butter Masala (Full)', categoryName: 'Main Course (Curries)', sellingPricePaise: 22000, mrpPaise: 22000, purchasePricePaise: 9000, stockQuantity: 999, unit: 'plate'),
    DefaultProductSeed(name: 'Dal Makhani', categoryName: 'Main Course (Curries)', sellingPricePaise: 18000, mrpPaise: 18000, purchasePricePaise: 7000, stockQuantity: 999, unit: 'plate'),
    DefaultProductSeed(name: 'Butter Naan (1 pc)', categoryName: 'Roti, Naan & Rice', sellingPricePaise: 4000, mrpPaise: 4000, purchasePricePaise: 1500, stockQuantity: 999, unit: 'piece'),
    DefaultProductSeed(name: 'Jeera Rice', categoryName: 'Roti, Naan & Rice', sellingPricePaise: 14000, mrpPaise: 14000, purchasePricePaise: 5000, stockQuantity: 999, unit: 'plate'),
    DefaultProductSeed(name: 'Veg Burger', categoryName: 'Fast Food & Pizzas', sellingPricePaise: 9900, mrpPaise: 9900, purchasePricePaise: 4000, stockQuantity: 999, unit: 'piece'),
    DefaultProductSeed(name: 'Gulab Jamun (2 pcs)', categoryName: 'Desserts & Sweets', sellingPricePaise: 6000, mrpPaise: 6000, purchasePricePaise: 2500, stockQuantity: 999, unit: 'plate'),
    DefaultProductSeed(name: 'Kulfi Malai', categoryName: 'Desserts & Sweets', sellingPricePaise: 8000, mrpPaise: 8000, purchasePricePaise: 3500, stockQuantity: 999, unit: 'piece'),
  ],
};
