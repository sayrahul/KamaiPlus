// ============================================================================
// BARCODE RESOLUTION — PURE CORE
// ----------------------------------------------------------------------------
// Checksum validation, response normalisation and the Gemini prompt, with no
// Firebase and no network, so `functions/test/barcode_core.test.js` can run it.
//
// Why any of this is server-side at all: the app's own resolver queries Open
// Facts and UPCitemdb straight from the handset. That works, but every merchant
// pays the full lookup for a barcode another merchant resolved last week, and
// UPCitemdb's free tier is rate-limited per IP. Resolving here lets one
// merchant's scan populate a shared catalog for everybody, and lets a new data
// source be added by redeploy instead of a Play Store rollout.
// ============================================================================

/**
 * Validates an EAN-13 / UPC-A / EAN-8 check digit.
 *
 * Worth doing before any network call: a misread from a cheap scanner, or an
 * internal shop label, is not in any global repository, and firing five
 * parallel HTTP lookups at it stalls the counter for seconds to learn nothing.
 *
 * It also caught something real — 22 of the 23 barcodes in the app's "curated
 * Indian retail dictionary", and 115 of 368 in the seeded master catalog, fail
 * this check. Those rows are unreachable by construction: no physical product
 * carries a barcode with a wrong check digit, so scanning the actual Dettol
 * bottle could never match the dictionary's Dettol row.
 */
function hasValidCheckDigit(code) {
  if (typeof code !== "string" || !/^\d+$/.test(code)) return false;

  if (![8, 12, 13, 14].includes(code.length)) return false;

  const body = code.slice(0, -1);
  const check = Number(code[code.length - 1]);

  // EAN-13 weights its first digit 1 and alternates; EAN-8, UPC-A and GTIN-14
  // start at 3. A GTIN-14 carton code computes its OWN check digit over all 13
  // leading digits — it does not inherit the inner EAN-13's, so it cannot be
  // validated by stripping the packaging indicator and recursing.
  const startsWithOne = code.length === 13;
  let sum = 0;
  for (let i = 0; i < body.length; i++) {
    const weight = (i % 2 === 0) === startsWithOne ? 1 : 3;
    sum += Number(body[i]) * weight;
  }
  return (10 - (sum % 10)) % 10 === check;
}

/** Digits only, 8-14 long. Returns null for anything that cannot be a GTIN. */
function normalizeBarcode(raw) {
  const digits = String(raw || "").replace(/[^0-9]/g, "");
  if (digits.length < 8 || digits.length > 14) return null;
  return digits;
}

/**
 * GS1 prefix → country, used only to tell Gemini where to look. 890 is India,
 * which is the overwhelming majority of what these merchants scan.
 */
function gs1Region(barcode) {
  const p3 = barcode.slice(0, 3);
  const n = Number(p3);
  if (p3 === "890") return "India";
  if (n >= 0 && n <= 139) return "USA or Canada";
  if (n >= 300 && n <= 379) return "France";
  if (n >= 400 && n <= 440) return "Germany";
  if (n >= 500 && n <= 509) return "United Kingdom";
  if (n >= 690 && n <= 699) return "China";
  if (p3 === "888") return "Singapore";
  if (p3 === "893") return "Vietnam";
  if (p3 === "899") return "Indonesia";
  if (n >= 978 && n <= 979) return "a book (ISBN)";
  return "unknown origin";
}

/**
 * Prompt for the last-resort tier.
 *
 * The danger here is not a wrong answer, it is a confident wrong answer: a
 * merchant who saves "Parle Monaco" for a barcode that is actually a local
 * dairy's milk packet has silently corrupted their own catalog, and every
 * future scan of that item compounds it. So the prompt is written to make
 * "I don't know" the easy path, and the caller marks whatever comes back as a
 * guess for the merchant to confirm.
 */
function buildBarcodePrompt(barcode) {
  return `You are a retail barcode reference for Indian shopkeepers.

Barcode (GTIN): ${barcode}
GS1 prefix suggests: ${gs1Region(barcode)}

Identify the retail product this barcode belongs to, if and only if you actually
recognise this specific number.

CRITICAL HONESTY RULE:
- Only answer if you genuinely recognise THIS EXACT barcode number.
- Do NOT infer a product from the manufacturer prefix alone. Knowing that 8901719
  is Parle does NOT tell you which Parle product this is — that is a guess, and a
  wrong product name silently corrupts a real shop's inventory.
- If you do not recognise the exact number, return {"known": false}. That is a
  correct and useful answer. Returning a plausible-sounding invention is not.
- Never invent a price. Indian MRP is not derivable from a barcode.

If you DO recognise it, return the product as printed on the pack, in English.

Return ONLY valid JSON, no markdown, no commentary:
{
  "known": true,
  "name": "Parle-G Gold Glucose Biscuits",
  "brand": "Parle",
  "category": "Biscuits & Snacks",
  "pack_size": "1kg",
  "confidence": "high"
}
or exactly:
{"known": false}`;
}

/** Categories the app's verticals actually use, so a free-text answer lands somewhere real. */
const CATEGORY_HINTS = [
  "Atta, Rice & Dal", "Spices & Cooking Oil", "Dairy, Bread & Eggs",
  "Biscuits & Snacks", "Soaps & Detergents", "Pooja & Agarbatti",
  "Tablets & Capsules", "Syrups & Suspensions", "Ointments & Creams",
  "First Aid & Bandages", "General",
];

/**
 * Normalises whatever a tier returned into the single shape the app consumes.
 * Returns null when the row is not usable.
 */
function normalizeBarcodeResult(raw, { source, isAiGuess = false } = {}) {
  if (!raw || typeof raw !== "object") return null;

  const name = String(raw.name || raw.product_name || raw.title || "").trim();
  if (!name || !/\p{L}/u.test(name)) return null;

  const brandRaw = String(raw.brand || raw.brands || "").split(",")[0].trim();
  const packSize = String(raw.pack_size || raw.quantity || raw.size || "").trim();

  return {
    name: name.replace(/\s+/g, " ").slice(0, 120),
    brand: brandRaw ? brandRaw.slice(0, 60) : "",
    category: String(raw.category || raw.categories || "").split(",")[0].trim().slice(0, 60),
    pack_size: packSize.slice(0, 40),
    source: source || "unknown",
    // The app shows an "AI guess — please verify" badge on this, and leaves the
    // price blank. A database hit is a fact; this is a recollection.
    is_ai_guess: Boolean(isAiGuess),
  };
}

module.exports = {
  hasValidCheckDigit,
  normalizeBarcode,
  gs1Region,
  buildBarcodePrompt,
  normalizeBarcodeResult,
  CATEGORY_HINTS,
};
