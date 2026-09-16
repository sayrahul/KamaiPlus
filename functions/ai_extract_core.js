// ============================================================================
// AI EXTRACTION — PURE CORE
// ----------------------------------------------------------------------------
// The prompt text, the model order, and the response normalizer, with no
// Firebase, no network and no secrets, so `functions/test/ai_extract_core.test.js`
// can exercise them directly.
//
// It lives apart from index.js because of what went wrong the last time it did
// not: the server emitted `product_name`/`selling_price_paise` while the app
// read `dish_name`/`price_paise`, and nothing anywhere could notice, because
// the only way to run this code was to deploy it and photograph a menu. The
// contract between the two halves is now a test.
// ============================================================================

/**
 * Tried in order; the first that answers wins.
 *
 * Only models this project has actually seen answer are listed. The previous
 * list ended with "gemini-2.5-flash-latest", which returns 404 (see the
 * 2026-09-16 08:33 log line) — so every failed scan paid for one extra
 * round trip to a model that cannot exist. A retired model is still just a
 * redeploy, and the Admin Console can override the order live (below)
 * without one.
 */
const DEFAULT_AI_MODELS = [
  "gemini-3.6-flash",
  "gemini-3.5-flash-lite",
  "gemini-2.5-flash",
];

/**
 * Resolves the model order for this request.
 *
 * The Admin Console has always written `active_model` into
 * platform_settings/ai_config, and this function has always ignored it — the
 * dropdown changed a Firestore field and nothing else. Whatever the admin
 * picks is now tried first, with the built-in list behind it so a typo in the
 * console degrades to "slower", never to "AI is down".
 */
function resolveModels(cfg) {
  const picked = String(cfg?.active_model || "").trim();
  const extra = Array.isArray(cfg?.model_fallbacks)
    ? cfg.model_fallbacks.map((m) => String(m || "").trim()).filter(Boolean)
    : [];
  return [...new Set([picked, ...extra, ...DEFAULT_AI_MODELS].filter(Boolean))];
}


/**
 * Language guidance shared by both prompts.
 *
 * A merchant photographs whatever is on their wall. That board is as likely to
 * be in Devanagari, Gurmukhi, Gujarati, Tamil or a Hinglish mix as in English,
 * and the on-device OCR fallback can only read Latin script — so if this
 * prompt does not handle the language, nothing downstream will.
 */
const LANGUAGE_RULES = `LANGUAGE (the document can be in ANY Indian language):
- Expect English, Hindi/Devanagari (मटन कसा), Marathi, Gujarati, Bengali, Punjabi/Gurmukhi,
  Tamil, Telugu, Kannada, Malayalam, Odia, Urdu, or a Hinglish mix — often two scripts on one card.
- Read the text in whatever script it is printed in. Never refuse because of the language.
- Return every name in the SAME SCRIPT AS PRINTED, so the merchant recognises their own item
  on the review screen. Do not translate "पनीर टिक्का" into "Paneer Tikka", and do not translate
  English names into Hindi.
- Indian numerals (१२३) and Arabic numerals are both possible. Always return prices as
  Arabic-numeral integers.`;

/**
 * Paise is the app's only money unit end to end, so the conversion has to be
 * unambiguous here or it silently becomes a 100x pricing error in the catalog.
 */
const PRICE_RULES = `PRICE RULES (STRICT — money is stored as INTEGER PAISE, 1 rupee = 100 paise):
- Indian price forms you will see: "320/-", "₹320", "Rs. 320", "Rs.320/-", "320 Rs", "INR 320",
  "320.00", "320|-" (a scan artefact for "320/-"), "3 2 0" (OCR letter-spacing).
- Convert the RUPEE value to paise by multiplying by 100:
    "320/-"   -> 32000
    "₹45.50"  -> 4550
    "1,200/-" -> 120000
- Never return null, a decimal, or a string for a *_paise field. Integers only.
- If a price is genuinely unreadable, omit that item rather than guessing a number.`;

/**
 * Builds the prompt for a RESTAURANT MENU CARD.
 *
 * Kept separate from the purchase-bill prompt rather than branched inside one
 * blob. They disagree on nearly everything that matters: a menu has no
 * supplier, no bill number, no received quantity and no wholesale cost, and the
 * single price printed on it is what the customer PAYS. Feeding a menu through
 * the bill prompt made that price a purchase cost and then marked it up.
 *
 * Rules 2, 3 and 6 exist because of a real reported failure: a merchant's
 * mutton menu came back as three items named "Rate", "Mutton Hydrabadi(4pcs)"
 * and "360/-|" — a column header, one real dish, and a stray price.
 */
function buildMenuPrompt(vertical) {
  return `You are an expert menu-card reader for Indian restaurants, dhabas, cafes, bakeries and food stalls.
The merchant's business type is "${vertical}". They have photographed their own menu card, price board,
rate list or takeaway leaflet, and want every dish loaded into their billing app.

YOUR JOB: extract EVERY dish on the image, with its price.

${LANGUAGE_RULES}

${PRICE_RULES}

READING A MENU CARD — the layout traps you must not fall into:

1. TWO-COLUMN LAYOUT. Almost every Indian menu prints dish names down the left and prices down the
   right, sometimes with dot leaders between them. Match each dish to the price ON ITS OWN ROW by
   following that row across visually. Do NOT pair a dish with the price of the row above or below.

2. COLUMN HEADERS ARE NOT DISHES. Words like "Item", "Items", "Rate", "Rate/-", "Price", "MRP",
   "Sr. No", "S.No", "Dish", "Name", "Qty", "Amount", "Half", "Full", "Veg", "Non-Veg", "New" are
   table headers or column labels. NEVER emit one as a dish. If you are about to output an item
   named "Rate" or "Item", you have misread the table — re-read that row.

3. SECTION HEADINGS ARE CATEGORIES, NOT DISHES. Banners like "CHICKEN", "MUTTON", "STARTERS",
   "TANDOOR", "BIRYANI", "CHINESE", "BREADS", "BEVERAGES", "SOUPS", "DESSERTS", "VEG", "NON-VEG"
   name the section that follows. Use them as the category for every dish underneath, and do not
   emit the heading itself as a dish.

4. SERIAL NUMBERS. Rows are usually numbered ("21.Chicken Hydrabadi(5pcs)", "1. Mutton Kasa(4pcs)").
   Strip the leading number and separator: "21.Chicken Hydrabadi(5pcs)" -> "Chicken Hydrabadi (5pcs)".

5. PORTION INFORMATION IS PART OF THE NAME. Keep "(4pcs)", "(5pcs)", "(Half)", "(Full)", "(250ml)",
   "(Plate)" in the dish name — it is how the kitchen and the customer tell two rows apart.
   If one dish shows TWO prices (Half / Full, Quarter / Plate), emit it as TWO separate items:
   "Kadai Paneer (Half)" and "Kadai Paneer (Full)".

6. NUMBERS ARE NEVER DISH NAMES. A row that reads only "360/-", "120", "---" or "|" is a stray
   price or a scan artefact. Drop it. Every dish name must contain at least one letter.

7. COMPLETENESS. Read the WHOLE image top to bottom — every section, every column, including rows
   partially covered by a food photo or a fold. A menu page usually has 15-60 dishes. If you return
   only 3 items from a full page, you have failed the task. Do not stop early.

8. DAMAGED / TILTED / GLARE PHOTOS. Merchants photograph laminated cards at an angle, under tube
   light, with reflections, sometimes slightly out of focus. Infer the obvious: a faded
   "7.Muton Curry(4pcs)" is "Mutton Curry (4pcs)". Correct obvious OCR slips in spelling, but NEVER
   invent a dish that is not printed, and never invent a price.

VEGETARIAN CLASSIFICATION:
- is_veg false: chicken, murgh, mutton, gosht, lamb, keema, fish, machhli, prawn, jhinga, crab,
  egg, anda, pork, beef, duck, seafood, and kabab/kebab/tikka made of meat.
- is_veg true: paneer, dal, aloo, gobi, sabzi, mushroom, soya, rice, breads, chaat, beverages,
  chai, coffee, lassi, sweets, desserts.

CATEGORY:
- Use the printed section heading when there is one ("Mutton", "Chicken", "Starters").
- Otherwise choose one of: Starters, Soups, Main Course, Biryani & Rice, Breads & Roti,
  Chinese, South Indian, Tandoor, Chaat & Snacks, Beverages, Desserts, Combos & Thali.

RESPONSE — return ONLY valid JSON. No markdown, no backticks, no commentary:
{
  "detected_document_type": "menu",
  "items": [
    {
      "dish_name": "Chicken Hydrabadi (5pcs)",
      "price_paise": 32000,
      "category": "Chicken",
      "is_veg": false
    }
  ]
}

Every dish printed on the card must appear exactly once in "items". Never return an empty array
when dishes are visible.`;
}

/**
 * Builds the prompt for a PURCHASE BILL / supplier invoice / mandi parcha.
 */
function buildBillPrompt(vertical) {
  return `You are an expert reader of Indian wholesale purchase documents for a "${vertical}" business.
The merchant has photographed a supplier invoice, distributor bill, mandi parcha, delivery challan or
a handwritten notebook slip, and wants the stock loaded into their inventory.

YOUR JOB: extract EVERY line item, with quantity and purchase rate.

${LANGUAGE_RULES}

${PRICE_RULES}

VERTICAL-SPECIFIC READING:

1. GROCERY / KIRANA / GENERAL STORE:
   - Keep Brand + Product + Pack size together: "Aashirvaad Shuddh Chakki Atta 5kg",
     "Fortune Sunlite Refined Oil 1L", "Tata Salt 1kg", "Maggi 2-Min Masala 70g".
   - Units: kg, g, gm, ltr, ml, pcs, pkt, box, bag, dozen, tin, bottle, case, crate, bora.

2. PHARMACY / MEDICAL DISTRIBUTOR:
   - Medicine name + strength: "Dolo 650mg", "Azithral 500mg", "Pan-D 40mg".
   - Capture batch_number, and expiry_date converted to YYYY-MM-DD (an "11/27" expiry is 2027-11-30;
     always use the LAST day of that month).
   - Packaging: strip, box, bottle, vial, tube, sachet.

3. APPAREL / GARMENTS / FOOTWEAR:
   - Style/item + size (S/M/L/XL/XXL or 28/30/32/34/38/40) + colour: "Denim Jeans 32 Blue".

4. ELECTRONICS / MOBILE / HARDWARE:
   - The model number is part of the name: "Boat Rockerz 450 Bluetooth Headphone".

5. MANDI PARCHA / HANDWRITTEN SLIP:
   - Read Hindi/Hinglish handwriting: "चना दाल 50kg @ 68 = 3400" is chana dal, quantity 50, unit kg,
     purchase rate 6800 paise per kg.
   - A line of the form "<item> <qty> @ <rate> = <total>" means the rate is PER UNIT. Return that
     per-unit rate in purchase_price_paise, not the line total.

QUANTITY & RATE:
- quantity is how many units were RECEIVED (a number, may be decimal such as 2.5).
- purchase_price_paise is the rate for ONE unit, excluding tax where the bill separates it.
- mrp_paise is the printed MRP when the bill shows one, else 0.
- selling_price_paise is the merchant's retail price when the bill shows one, else 0.
  Leave it 0 rather than guessing — the app applies its own markup.
- barcode: only if an EAN/UPC of 8-14 digits is actually printed. Otherwise "".

SKIP these rows entirely: column headers, Sub Total, Total, Grand Total, Round Off, Discount,
CGST/SGST/IGST/tax rows, "Amount in words", terms & conditions, and signature lines.

RESPONSE — return ONLY valid JSON. No markdown, no backticks, no commentary:
{
  "supplier_name": "Supplier or vendor name, else empty string",
  "bill_number": "Invoice/bill number, else empty string",
  "bill_date": "YYYY-MM-DD, else empty string",
  "detected_document_type": "invoice | slip | handwritten | catalog",
  "items": [
    {
      "product_name": "Aashirvaad Atta 5kg",
      "quantity": 2,
      "unit": "pcs",
      "purchase_price_paise": 26000,
      "mrp_paise": 30000,
      "selling_price_paise": 0,
      "category_name": "Grocery & Staples",
      "barcode": "",
      "expiry_date": "",
      "batch_number": ""
    }
  ]
}

Never return an empty items array when line items are visible.`;
}

/** Picks the right prompt for what the merchant actually uploaded. */
function buildUniversalAiPrompt(kind, clientVertical) {
  const vertical = (clientVertical || "general retail").toLowerCase();
  return kind === "menu" ? buildMenuPrompt(vertical) : buildBillPrompt(vertical);
}


/**
 * Pulls the JSON object out of a model response.
 *
 * `response_mime_type: application/json` makes a bare object the normal case,
 * but a model that ignores it (or wraps the object in a ```json fence, or adds
 * a sentence of commentary) used to take the whole scan down with a
 * SyntaxError. Falling back to the outermost {...} span recovers those.
 */
function parseModelJson(text) {
  const cleaned = String(text || "")
    .replace(/```json/gi, "")
    .replace(/```/g, "")
    .trim();

  try {
    return JSON.parse(cleaned);
  } catch (_) {
    const first = cleaned.indexOf("{");
    const last = cleaned.lastIndexOf("}");
    if (first === -1 || last <= first) {
      throw new Error("no JSON object in response");
    }
    return JSON.parse(cleaned.slice(first, last + 1));
  }
}


/**
 * Column headers and table furniture that a menu OCR pass turns into "dishes".
 *
 * This is the server-side half of a guard the app also applies. A merchant
 * reported a mutton menu coming back as "Rate ₹320", "Mutton Hydrabadi(4pcs)
 * ₹440" and "360/- ₹380" — a column header, one real dish, and a stray price
 * cell. Two of those three rows are caught here.
 */
const NON_ITEM_WORDS = new Set([
  "rate", "rates", "item", "items", "price", "prices", "mrp", "amount",
  "qty", "quantity", "total", "subtotal", "sub total", "grand total",
  "sr", "sr no", "s no", "sno", "no", "serial", "serial no",
  "dish", "dishes", "name", "menu", "veg", "non veg", "nonveg",
  "half", "full", "plate", "new", "special", "category", "description",
  "particulars", "hsn", "gst", "cgst", "sgst", "igst", "tax", "discount",
  "round off", "roundoff", "net", "net amount", "signature", "our menu",
  "food menu", "price list", "rate list", "rate card",
]);

/**
 * Folds a name down to the form the blacklist is written in: lowercase, no
 * punctuation, single spaces. Without this, "Rate" was caught but "Rate/-",
 * "Sr. No" and "S.NO" — the spellings menus actually print — were not.
 */
function headerKey(name) {
  return String(name)
    .toLowerCase()
    .replace(/[^\p{L}\p{N}]+/gu, " ")
    .trim()
    .replace(/\s+/g, " ");
}

/** A usable name has to contain at least one letter in SOME script. */
const HAS_LETTER = /\p{L}/u;

/**
 * Normalizes one extracted row into the shape the app expects, or returns null
 * if the row is not a real item.
 *
 * It emits BOTH naming conventions on purpose:
 *   - `product_name` / `selling_price_paise` / `category_name`  (bill shape)
 *   - `dish_name` / `price_paise` / `category`                  (menu shape)
 *
 * The menu scan was returning perfectly extracted dishes that the app then
 * threw away: the server sent `product_name` + `selling_price_paise`, and
 * ExtractedMenuItem.fromJson read `dish_name` + `price_paise`, so every dish
 * fell through to its defaults and the merchant saw seventeen rows of
 * "Menu Item ₹0.00". The app now reads both shapes too, but emitting both
 * here is what fixes the phones that already have the old build installed —
 * they need a function redeploy, not a Play Store rollout.
 */
function normalizeExtractedItem(raw, kind) {
  if (!raw || typeof raw !== "object") return null;

  let name = String(
    raw.dish_name || raw.product_name || raw.name || raw.item_name || raw.item || ""
  ).trim();

  // Strip leading numbering: "21.", "1)", "#5", "- ", "1 -"
  name = name.replace(/^[\d#]+\s*[.)\-:\s]+\s*/, "").trim();
  // Collapse the whitespace OCR sprinkles through letter-spaced headings.
  name = name.replace(/\s{2,}/g, " ").trim();

  if (!name || !HAS_LETTER.test(name)) return null;
  if (NON_ITEM_WORDS.has(headerKey(name))) return null;

  const paise = (v) => {
    const n = Number(v);
    return Number.isFinite(n) && n > 0 ? Math.round(n) : 0;
  };

  let sellPaise = paise(raw.price_paise) || paise(raw.selling_price_paise);
  let buyPaise = paise(raw.purchase_price_paise);
  let mrpPaise = paise(raw.mrp_paise);

  if (kind === "menu") {
    // The one price on a menu card is what the customer pays. There is no
    // wholesale cost on a menu, so mirroring it across all three fields is the
    // honest reading.
    if (sellPaise === 0) sellPaise = Math.max(buyPaise, mrpPaise);
    buyPaise = sellPaise;
    mrpPaise = sellPaise;
  } else {
    // A bill is the opposite case, and conflating the two costs real money.
    // Copying the purchase rate into selling_price_paise looks harmless, but
    // ExtractedBillItem.fromJson only applies the app's default markup when
    // selling_price_paise is 0 — so a filled-in "selling price" that is really
    // the cost price makes the merchant stock every AI-inwarded item at zero
    // margin. A rate the bill did not print stays 0.
    if (buyPaise === 0 && sellPaise > 0) {
      // A rate card or price-only slip: the single number is the cost.
      buyPaise = sellPaise;
      sellPaise = 0;
    }
  }

  const category = String(raw.category || raw.category_name || "General").trim() || "General";

  // Smart non-veg detection across Indian cuisines.
  const lowerName = name.toLowerCase();
  const lowerCat = category.toLowerCase();
  const nonVegTerms = [
    "chicken", "mutton", "fish", "egg", "anda", "murgh", "gosht", "keema",
    "prawn", "jhinga", "crab", "pork", "beef", "non-veg", "seafood", "kabab",
    "kebab", "tikka", "duck", "meat", "lamb", "machhli", "machli",
  ];
  const isExplicitlyNonVeg = nonVegTerms.some(
    (term) => lowerName.includes(term) || lowerCat.includes(term)
  );

  let isVeg = raw.is_veg;
  if (isExplicitlyNonVeg) {
    isVeg = false;
  } else if (isVeg === undefined || isVeg === null) {
    isVeg = true;
  } else {
    isVeg = Boolean(isVeg);
  }

  // A dish with no price is not reviewable — the merchant cannot tell whether
  // the app read ₹0 or failed to read at all. A bill line can legitimately
  // have no rate yet (the app applies its own markup), so only menus insist.
  if (kind === "menu" && sellPaise <= 0) return null;

  const qty = Number(raw.quantity) > 0 ? Number(raw.quantity) : 1;
  const unit = String(raw.unit || "pcs").trim().toLowerCase() || "pcs";

  return {
    // Bill shape.
    product_name: name,
    quantity: qty,
    unit,
    purchase_price_paise: buyPaise,
    mrp_paise: mrpPaise,
    selling_price_paise: sellPaise,
    category_name: category,
    // Menu shape — same values, the names ExtractedMenuItem.fromJson reads.
    dish_name: name,
    price_paise: sellPaise,
    category,
    is_veg: isVeg,
    barcode: String(raw.barcode || "").trim(),
    expiry_date: String(raw.expiry_date || "").trim(),
    batch_number: String(raw.batch_number || "").trim(),
  };
}



/**
 * The day boundary merchants actually experience, for the daily scan quota.
 *
 * Cloud Run runs in UTC, so a plain toISOString() day would roll over at
 * 5:30 AM IST — in the middle of a dairy or a bakery's morning inward, with
 * the shopkeeper's "daily" scans resetting at an hour that means nothing to
 * them. IST is UTC+5:30 with no DST, so a fixed offset is exact.
 */
function istDayKey(now = new Date()) {
  const ist = new Date(now.getTime() + (5 * 60 + 30) * 60 * 1000);
  return ist.toISOString().slice(0, 10); // YYYY-MM-DD in IST
}

/** Daily AI picture-scan allowance, per business. */
const FREE_DAILY_IMAGE_SCANS = 10;
const PRO_DAILY_IMAGE_SCANS = 100;

module.exports = {
  istDayKey,
  FREE_DAILY_IMAGE_SCANS,
  PRO_DAILY_IMAGE_SCANS,
  DEFAULT_AI_MODELS,
  resolveModels,
  buildMenuPrompt,
  buildBillPrompt,
  buildUniversalAiPrompt,
  parseModelJson,
  normalizeExtractedItem,
  NON_ITEM_WORDS,
  headerKey,
};
