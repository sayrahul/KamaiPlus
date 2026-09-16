// Run with:  npm --prefix functions test
//
// The check-digit tests below are not theoretical. Running this validator over
// the app's own seed data found that 22 of the 23 barcodes in the "curated
// Indian retail dictionary", and 115 of 368 in the seeded master catalog, have
// a wrong EAN-13 check digit — they were invented, not transcribed. No physical
// product carries a barcode with a bad check digit, so every one of those rows
// was unreachable: scanning the real Dettol bottle could never match the
// dictionary's Dettol row, and the tier looked "wired" while resolving nothing.
//
// The "real" barcodes here were each verified against Open Food Facts live.

const test = require("node:test");
const assert = require("node:assert");

const {
  hasValidCheckDigit,
  normalizeBarcode,
  gs1Region,
  buildBarcodePrompt,
  normalizeBarcodeResult,
} = require("../barcode_core");

const { istDayKey, FREE_DAILY_IMAGE_SCANS, PRO_DAILY_IMAGE_SCANS } = require("../ai_extract_core");

// ---------------------------------------------------------------------------
// Check digits
// ---------------------------------------------------------------------------

test("accepts real barcodes verified against Open Food Facts", () => {
  for (const code of [
    "8901719134845", // Parle-G Biscuit
    "8901063139329", // Britannia Bourbon
    "8902080000227", // Sting Energy
    "3017620422003", // Nutella (control)
  ]) {
    assert.strictEqual(hasValidCheckDigit(code), true, `${code} is a real barcode`);
  }
});

test("rejects the fabricated barcodes found in the app's own seed data", () => {
  for (const code of [
    "8901030383701", // "Aashirvaad Atta 5kg" in the curated dictionary
    "8901117001163", // "Dettol Antiseptic Liquid 250ml"
    "8904043901007", // "Tata Salt 1kg"
    "8901058852854", // "Maggi 2-Minute Masala Noodles 70g"
  ]) {
    assert.strictEqual(hasValidCheckDigit(code), false, `${code} has a wrong check digit`);
  }
});

test("validates UPC-A and EAN-8 as well as EAN-13", () => {
  assert.strictEqual(hasValidCheckDigit("036000291452"), true); // UPC-A
  assert.strictEqual(hasValidCheckDigit("036000291453"), false);
  assert.strictEqual(hasValidCheckDigit("96385074"), true); // EAN-8
  assert.strictEqual(hasValidCheckDigit("96385075"), false);
});

test("an ITF-14 carton code is validated on its GTIN-13 payload", () => {
  assert.strictEqual(hasValidCheckDigit("18901719134842"), true);
});

test("rejects non-numeric and wrong-length input", () => {
  for (const bad of ["", "abcdefghijklm", "123", "12345678901234567", "890171913484X"]) {
    assert.strictEqual(hasValidCheckDigit(bad), false);
  }
});

// ---------------------------------------------------------------------------
// Normalisation
// ---------------------------------------------------------------------------

test("strips scanner noise but keeps the digits", () => {
  assert.strictEqual(normalizeBarcode(" 8901719134845 "), "8901719134845");
  assert.strictEqual(normalizeBarcode("8901-7191-34845"), "8901719134845");
});

test("refuses anything that cannot be a GTIN", () => {
  assert.strictEqual(normalizeBarcode("123"), null);
  assert.strictEqual(normalizeBarcode("123456789012345"), null);
  assert.strictEqual(normalizeBarcode("SHOP-LABEL"), null);
});

// ---------------------------------------------------------------------------
// GS1 region (used only to steer the prompt)
// ---------------------------------------------------------------------------

test("890 is recognised as India", () => {
  assert.strictEqual(gs1Region("8901719134845"), "India");
});

test("ISBN prefixes are recognised as books", () => {
  assert.ok(gs1Region("9780140449136").includes("ISBN"));
});

// ---------------------------------------------------------------------------
// The prompt's honesty rule
// ---------------------------------------------------------------------------

test("the prompt makes an honest 'unknown' the easy answer", () => {
  const p = buildBarcodePrompt("8901719134845");
  assert.ok(p.includes('{"known": false}'), "must offer an explicit unknown");
  assert.ok(p.includes("Do NOT infer a product from the manufacturer prefix alone"));
  assert.ok(p.includes("Never invent a price"));
  assert.ok(p.includes("8901719134845"), "the barcode itself must reach the prompt");
});

// ---------------------------------------------------------------------------
// Result normalisation
// ---------------------------------------------------------------------------

test("an Open Facts row becomes a clean product, not flagged as a guess", () => {
  const out = normalizeBarcodeResult(
    { name: "Parle-G Biscuit", brands: "Parle", categories: "Dry biscuits", quantity: "45gm" },
    { source: "Open Facts" }
  );
  assert.strictEqual(out.name, "Parle-G Biscuit");
  assert.strictEqual(out.brand, "Parle");
  assert.strictEqual(out.category, "Dry biscuits");
  assert.strictEqual(out.pack_size, "45gm");
  assert.strictEqual(out.is_ai_guess, false);
});

test("an AI row is flagged so the app can badge it", () => {
  const out = normalizeBarcodeResult(
    { name: "Parle Monaco Salted Biscuit", brand: "Parle", category: "Biscuits & Snacks" },
    { source: "AI", isAiGuess: true }
  );
  assert.strictEqual(out.is_ai_guess, true);
  assert.strictEqual(out.source, "AI");
});

test("only the first brand of a comma list survives", () => {
  const out = normalizeBarcodeResult({ name: "Nutella", brands: "Nutella, Ferrero" }, { source: "x" });
  assert.strictEqual(out.brand, "Nutella");
});

test("a nameless or letterless row is rejected", () => {
  assert.strictEqual(normalizeBarcodeResult({ name: "" }, { source: "x" }), null);
  assert.strictEqual(normalizeBarcodeResult({ name: "12345" }, { source: "x" }), null);
  assert.strictEqual(normalizeBarcodeResult(null, { source: "x" }), null);
});

test("no barcode source may supply a price", () => {
  const out = normalizeBarcodeResult(
    { name: "Parle-G", mrp_paise: 1000, selling_price_paise: 900 },
    { source: "Open Facts" }
  );
  // Online repositories carry no Indian MRP. A price must never ride along and
  // become a real shelf price the merchant never typed.
  assert.strictEqual(out.mrp_paise, undefined);
  assert.strictEqual(out.selling_price_paise, undefined);
});

test("absurdly long names are trimmed to something a counter card can show", () => {
  const out = normalizeBarcodeResult({ name: "x".repeat(400) }, { source: "x" });
  assert.ok(out.name.length <= 120);
});

// ---------------------------------------------------------------------------
// Daily scan quota
// ---------------------------------------------------------------------------

test("free and Pro daily limits are 10 and 100", () => {
  assert.strictEqual(FREE_DAILY_IMAGE_SCANS, 10);
  assert.strictEqual(PRO_DAILY_IMAGE_SCANS, 100);
});

test("the quota day rolls over at IST midnight, not UTC midnight", () => {
  // 18:30 UTC is exactly 00:00 IST the following day.
  assert.strictEqual(istDayKey(new Date("2026-09-16T18:29:00Z")), "2026-09-16");
  assert.strictEqual(istDayKey(new Date("2026-09-16T18:30:00Z")), "2026-09-17");
});

test("a shopkeeper's morning inward is never mid-reset", () => {
  // 03:00 IST on the 17th = 21:30 UTC on the 16th; both must read as the 17th,
  // so an early-morning dairy inward is not split across two quota buckets.
  assert.strictEqual(istDayKey(new Date("2026-09-16T21:30:00Z")), "2026-09-17");
  assert.strictEqual(istDayKey(new Date("2026-09-17T03:30:00Z")), "2026-09-17");
});
