// Run with:  node --test functions/test/
//
// These tests exist because of one production failure: Gemini read a merchant's
// mutton menu correctly — the Cloud Function logged "17 item(s)" — and the app
// still showed three junk rows. The server was emitting `product_name` and
// `selling_price_paise`; the app's ExtractedMenuItem.fromJson read `dish_name`
// and `price_paise`. Nothing between the two could fail loudly, because the
// only way to run the code was to deploy it and photograph a menu.
//
// The first block below is that contract, written down.

const test = require("node:test");
const assert = require("node:assert");

const {
  resolveModels,
  buildMenuPrompt,
  buildBillPrompt,
  buildUniversalAiPrompt,
  parseModelJson,
  normalizeExtractedItem,
  DEFAULT_AI_MODELS,
} = require("../ai_extract_core");

// ---------------------------------------------------------------------------
// The app/server field contract
// ---------------------------------------------------------------------------

test("menu item carries the exact field names ExtractedMenuItem.fromJson reads", () => {
  const out = normalizeExtractedItem(
    { dish_name: "Chicken Hydrabadi (5pcs)", price_paise: 32000, category: "Chicken", is_veg: false },
    "menu"
  );

  // lib/services/gemini_ai_service.dart reads exactly these three keys.
  assert.strictEqual(out.dish_name, "Chicken Hydrabadi (5pcs)");
  assert.strictEqual(out.price_paise, 32000);
  assert.strictEqual(out.category, "Chicken");
});

test("a bill-shaped row still comes back usable as a menu item", () => {
  // This is the exact payload shape that produced "Menu Item ₹0.00" on device.
  const out = normalizeExtractedItem(
    {
      product_name: "Mutton Hydrabadi (4pcs)",
      selling_price_paise: 44000,
      category_name: "Mutton",
    },
    "menu"
  );

  assert.strictEqual(out.dish_name, "Mutton Hydrabadi (4pcs)");
  assert.strictEqual(out.price_paise, 44000);
  assert.strictEqual(out.category, "Mutton");
});

test("menu item also carries the bill field names, for the bill review sheet", () => {
  const out = normalizeExtractedItem({ dish_name: "Paneer Tikka", price_paise: 22000 }, "menu");
  assert.strictEqual(out.product_name, "Paneer Tikka");
  assert.strictEqual(out.selling_price_paise, 22000);
  assert.strictEqual(out.category_name, "General");
});

// ---------------------------------------------------------------------------
// The junk rows from the merchant's screenshot
// ---------------------------------------------------------------------------

test('drops the "Rate" column header', () => {
  assert.strictEqual(normalizeExtractedItem({ dish_name: "Rate", price_paise: 32000 }, "menu"), null);
  assert.strictEqual(normalizeExtractedItem({ dish_name: "Item", price_paise: 32000 }, "menu"), null);
  assert.strictEqual(normalizeExtractedItem({ dish_name: "Sr. No", price_paise: 100 }, "menu"), null);
  assert.strictEqual(normalizeExtractedItem({ dish_name: "MRP", price_paise: 100 }, "menu"), null);
});

test('drops a stray price cell like "360/-|"', () => {
  assert.strictEqual(normalizeExtractedItem({ dish_name: "360/-|", price_paise: 38000 }, "menu"), null);
  assert.strictEqual(normalizeExtractedItem({ dish_name: "120", price_paise: 12000 }, "menu"), null);
  assert.strictEqual(normalizeExtractedItem({ dish_name: "---", price_paise: 12000 }, "menu"), null);
  assert.strictEqual(normalizeExtractedItem({ dish_name: "  |  ", price_paise: 12000 }, "menu"), null);
});

test("strips the serial number the menu prints before each dish", () => {
  assert.strictEqual(
    normalizeExtractedItem({ dish_name: "21.Chicken Hydrabadi(5pcs)", price_paise: 32000 }, "menu").dish_name,
    "Chicken Hydrabadi(5pcs)"
  );
  assert.strictEqual(
    normalizeExtractedItem({ dish_name: "1) Mutton Kasa (4pcs)", price_paise: 32000 }, "menu").dish_name,
    "Mutton Kasa (4pcs)"
  );
  assert.strictEqual(
    normalizeExtractedItem({ dish_name: "#5 Kadai Mutton", price_paise: 38000 }, "menu").dish_name,
    "Kadai Mutton"
  );
});

test("a dish with no readable price is dropped rather than shown as free", () => {
  assert.strictEqual(normalizeExtractedItem({ dish_name: "Mutton Kasa", price_paise: 0 }, "menu"), null);
  assert.strictEqual(normalizeExtractedItem({ dish_name: "Mutton Kasa" }, "menu"), null);
});

test("a bill line with no rate survives — the app applies its own markup", () => {
  const out = normalizeExtractedItem({ product_name: "Tata Salt 1kg", quantity: 10 }, "bill");
  assert.ok(out);
  assert.strictEqual(out.quantity, 10);
  assert.strictEqual(out.purchase_price_paise, 0);
});

// ---------------------------------------------------------------------------
// Languages
// ---------------------------------------------------------------------------

test("keeps non-Latin dish names instead of dropping them as junk", () => {
  for (const name of ["मटन कसा", "பன்னீர் டிக்கா", "ਪਨੀਰ ਟਿੱਕਾ", "চিকেন কারি", "పన్నీర్"]) {
    const out = normalizeExtractedItem({ dish_name: name, price_paise: 20000 }, "menu");
    assert.ok(out, `${name} should survive normalization`);
    assert.strictEqual(out.dish_name, name);
  }
});

test("a Devanagari name with a serial prefix still loses only the number", () => {
  const out = normalizeExtractedItem({ dish_name: "3. मटन रेजाला", price_paise: 36000 }, "menu");
  assert.strictEqual(out.dish_name, "मटन रेजाला");
});

// ---------------------------------------------------------------------------
// Veg / non-veg
// ---------------------------------------------------------------------------

test("meat dishes are marked non-veg even when the model says otherwise", () => {
  assert.strictEqual(
    normalizeExtractedItem({ dish_name: "Mutton Kasa (4pcs)", price_paise: 32000, is_veg: true }, "menu").is_veg,
    false
  );
  assert.strictEqual(
    normalizeExtractedItem({ dish_name: "Fish Fry", price_paise: 32000 }, "menu").is_veg,
    false
  );
});

test("veg dishes default to veg", () => {
  assert.strictEqual(
    normalizeExtractedItem({ dish_name: "Dal Tadka", price_paise: 18000 }, "menu").is_veg,
    true
  );
});

test("category alone is enough to mark a dish non-veg", () => {
  const out = normalizeExtractedItem({ dish_name: "Handi Special", price_paise: 42000, category: "Mutton" }, "menu");
  assert.strictEqual(out.is_veg, false);
});

// ---------------------------------------------------------------------------
// Price handling
// ---------------------------------------------------------------------------

test("a bill's purchase rate is NOT copied into the selling price", () => {
  // ExtractedBillItem.fromJson only applies the app's default markup when
  // selling_price_paise is 0. Copying the cost in here would stock every
  // AI-inwarded item at zero margin.
  const out = normalizeExtractedItem({ product_name: "Atta 5kg", purchase_price_paise: 26000 }, "bill");
  assert.strictEqual(out.purchase_price_paise, 26000);
  assert.strictEqual(out.selling_price_paise, 0, "must stay 0 so the app marks it up");
});

test("a bill's printed MRP and selling price are kept when the bill shows them", () => {
  const out = normalizeExtractedItem(
    { product_name: "Atta 5kg", purchase_price_paise: 26000, mrp_paise: 33000, selling_price_paise: 31000 },
    "bill"
  );
  assert.strictEqual(out.purchase_price_paise, 26000);
  assert.strictEqual(out.mrp_paise, 33000);
  assert.strictEqual(out.selling_price_paise, 31000);
});

test("a price-only slip reads its single number as the cost, not the retail price", () => {
  const out = normalizeExtractedItem({ product_name: "Onion 1kg", selling_price_paise: 4000 }, "bill");
  assert.strictEqual(out.purchase_price_paise, 4000);
  assert.strictEqual(out.selling_price_paise, 0);
});

test("a menu price fills all three fields — a menu has no wholesale cost", () => {
  const out = normalizeExtractedItem({ dish_name: "Mutton Kasa (4pcs)", price_paise: 32000 }, "menu");
  assert.strictEqual(out.price_paise, 32000);
  assert.strictEqual(out.selling_price_paise, 32000);
  assert.strictEqual(out.purchase_price_paise, 32000);
  assert.strictEqual(out.mrp_paise, 32000);
});

test("a negative or non-numeric price is treated as absent", () => {
  assert.strictEqual(normalizeExtractedItem({ dish_name: "Soup", price_paise: -500 }, "menu"), null);
  assert.strictEqual(normalizeExtractedItem({ dish_name: "Soup", price_paise: "abc" }, "menu"), null);
});

test("a string price from a sloppy model is still read", () => {
  const out = normalizeExtractedItem({ dish_name: "Soup", price_paise: "18000" }, "menu");
  assert.strictEqual(out.price_paise, 18000);
});

// ---------------------------------------------------------------------------
// Model response parsing
// ---------------------------------------------------------------------------

test("parses a bare JSON object", () => {
  assert.deepStrictEqual(parseModelJson('{"items":[]}'), { items: [] });
});

test("parses JSON wrapped in a markdown fence", () => {
  assert.deepStrictEqual(parseModelJson('```json\n{"items":[1]}\n```'), { items: [1] });
});

test("parses JSON with a sentence of commentary around it", () => {
  const out = parseModelJson('Here is the menu:\n{"items":[{"dish_name":"X"}]}\nHope that helps!');
  assert.strictEqual(out.items[0].dish_name, "X");
});

test("throws on a response with no JSON at all", () => {
  assert.throws(() => parseModelJson("I cannot read this image."));
});

// ---------------------------------------------------------------------------
// Model order
// ---------------------------------------------------------------------------

test("the admin console's chosen model is tried first", () => {
  const models = resolveModels({ active_model: "gemini-2.5-flash" });
  assert.strictEqual(models[0], "gemini-2.5-flash");
});

test("built-in models always remain as a fallback behind the admin choice", () => {
  const models = resolveModels({ active_model: "totally-made-up-model" });
  assert.strictEqual(models[0], "totally-made-up-model");
  for (const m of DEFAULT_AI_MODELS) assert.ok(models.includes(m), `${m} missing`);
});

test("no model is tried twice", () => {
  const models = resolveModels({ active_model: DEFAULT_AI_MODELS[0] });
  assert.strictEqual(new Set(models).size, models.length);
});

test("an empty or missing config still yields the built-in list", () => {
  assert.deepStrictEqual(resolveModels(null), DEFAULT_AI_MODELS);
  assert.deepStrictEqual(resolveModels({}), DEFAULT_AI_MODELS);
});

test("gemini-2.5-flash-latest is gone — it 404s", () => {
  assert.ok(!DEFAULT_AI_MODELS.includes("gemini-2.5-flash-latest"));
});

// ---------------------------------------------------------------------------
// Prompts
// ---------------------------------------------------------------------------

test("a menu upload gets the menu prompt, not the bill one", () => {
  const menu = buildUniversalAiPrompt("menu", "restaurant");
  assert.ok(menu.includes("menu-card reader"));
  assert.ok(!menu.includes("supplier_name"));

  const bill = buildUniversalAiPrompt("bill", "grocery");
  assert.ok(bill.includes("supplier_name"));
});

test("the menu prompt asks for the field names the app reads", () => {
  const p = buildMenuPrompt("cafe");
  assert.ok(p.includes('"dish_name"'));
  assert.ok(p.includes('"price_paise"'));
});

test("both prompts name the languages merchants actually photograph", () => {
  for (const p of [buildMenuPrompt("cafe"), buildBillPrompt("kirana")]) {
    for (const lang of ["Devanagari", "Tamil", "Gujarati", "Bengali", "Urdu"]) {
      assert.ok(p.includes(lang), `prompt should mention ${lang}`);
    }
  }
});

test("the menu prompt warns against the exact mistakes we saw in production", () => {
  const p = buildMenuPrompt("restaurant");
  assert.ok(p.includes('"Rate"'), "must warn about the Rate column header");
  assert.ok(p.includes("320/-"), "must explain the /- price form");
  assert.ok(p.includes("15-60 dishes"), "must push for a complete read");
});

test("the merchant's vertical reaches the prompt", () => {
  assert.ok(buildMenuPrompt("dhaba").includes("dhaba"));
  assert.ok(buildBillPrompt("pharmacy").includes("pharmacy"));
});
