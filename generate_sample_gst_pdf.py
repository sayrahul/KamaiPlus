import subprocess
import os

html_content = """<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<title>TAX INVOICE - KamaiPlus</title>
<style>
  @page {
    size: A4;
    margin: 12mm 15mm;
  }
  * {
    box-sizing: border-box;
    margin: 0;
    padding: 0;
    font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, Helvetica, Arial, sans-serif;
  }
  body {
    color: #1e293b;
    font-size: 11px;
    background: #fff;
    padding: 15px;
  }
  .header-table {
    width: 100%;
    border-collapse: collapse;
    margin-bottom: 12px;
  }
  .store-title {
    font-size: 20px;
    font-weight: 800;
    color: #0284c7;
    letter-spacing: 0.5px;
  }
  .store-meta {
    font-size: 10.5px;
    color: #475569;
    line-height: 1.4;
    margin-top: 3px;
  }
  .invoice-badge-box {
    text-align: right;
    vertical-align: top;
  }
  .invoice-title-badge {
    display: inline-block;
    background: #0284c7;
    color: white;
    font-size: 13px;
    font-weight: 700;
    padding: 4px 12px;
    border-radius: 4px;
    text-transform: uppercase;
    letter-spacing: 1px;
  }
  .invoice-meta {
    margin-top: 6px;
    font-size: 10.5px;
    color: #334155;
    line-height: 1.5;
  }
  .b2b-box {
    width: 100%;
    border: 1px solid #cbd5e1;
    border-radius: 6px;
    margin-bottom: 14px;
    background: #f8fafc;
  }
  .b2b-table {
    width: 100%;
    border-collapse: collapse;
  }
  .b2b-table td {
    padding: 8px 12px;
    vertical-align: top;
    width: 50%;
  }
  .b2b-label {
    font-size: 9.5px;
    font-weight: 700;
    color: #64748b;
    text-transform: uppercase;
    letter-spacing: 0.5px;
    margin-bottom: 2px;
  }
  .b2b-name {
    font-size: 12px;
    font-weight: 700;
    color: #0f172a;
  }
  .b2b-detail {
    font-size: 10.5px;
    color: #334155;
    line-height: 1.4;
  }
  .highlight-gstin {
    font-weight: 700;
    color: #0284c7;
  }
  .items-table {
    width: 100%;
    border-collapse: collapse;
    margin-bottom: 12px;
  }
  .items-table th {
    background: #0284c7;
    color: white;
    font-weight: 700;
    font-size: 10px;
    padding: 7px 6px;
    text-align: left;
    border: 1px solid #0284c7;
    text-transform: uppercase;
  }
  .items-table td {
    padding: 7px 6px;
    font-size: 10px;
    border-bottom: 1px solid #e2e8f0;
    border-left: 1px solid #f1f5f9;
    border-right: 1px solid #f1f5f9;
  }
  .items-table tr:nth-child(even) {
    background: #f8fafc;
  }
  .text-right { text-align: right; }
  .text-center { text-align: center; }
  .bold { font-weight: 700; }
  
  .tax-summary-table {
    width: 100%;
    border-collapse: collapse;
    margin-bottom: 12px;
    font-size: 9.5px;
  }
  .tax-summary-table th {
    background: #f1f5f9;
    color: #475569;
    font-weight: 700;
    padding: 5px 6px;
    border: 1px solid #cbd5e1;
  }
  .tax-summary-table td {
    padding: 5px 6px;
    border: 1px solid #e2e8f0;
  }

  .footer-grid {
    width: 100%;
    border-collapse: collapse;
    margin-top: 6px;
  }
  .footer-grid td {
    vertical-align: top;
  }
  .totals-box {
    width: 100%;
    border-collapse: collapse;
  }
  .totals-box td {
    padding: 4px 8px;
    font-size: 10.5px;
  }
  .grand-total-row {
    background: #0284c7;
    color: white;
    font-size: 13px;
    font-weight: 800;
  }
  .grand-total-row td {
    padding: 8px 10px;
  }
  .amount-words-box {
    background: #f1f5f9;
    border-left: 3px solid #0284c7;
    padding: 6px 10px;
    font-size: 10px;
    margin-bottom: 10px;
  }
  .sign-box {
    margin-top: 25px;
    text-align: right;
    padding-right: 10px;
  }
  .sign-line {
    border-top: 1px solid #94a3b8;
    width: 180px;
    display: inline-block;
    margin-top: 35px;
  }
</style>
</head>
<body>

<!-- Header -->
<table class="header-table">
  <tr>
    <td style="width: 60%; vertical-align: top;">
      <div class="store-title">SHREE GANESH ENTERPRISES</div>
      <div class="store-meta">
        Shop 12-14, New Market Yard, Market Road, Pune, Maharashtra - 411001<br>
        <strong>Phone:</strong> +91 98220 12345 &nbsp;|&nbsp; <strong>Email:</strong> contact@ganeshent.in<br>
        <strong>GSTIN:</strong> <span class="highlight-gstin">27AAAAA0000A1Z5</span> &nbsp;|&nbsp; <strong>State Code:</strong> 27 (Maharashtra)
      </div>
    </td>
    <td class="invoice-badge-box">
      <div class="invoice-title-badge">TAX INVOICE</div>
      <div class="invoice-meta">
        <strong>Invoice No:</strong> #INV-2026-0842<br>
        <strong>Invoice Date:</strong> 11 Sep 2026, 02:30 PM<br>
        <strong>Payment Mode:</strong> <span style="color:#059669; font-weight:700;">PAID (UPI)</span><br>
        <strong>Place of Supply:</strong> 27 (Maharashtra)
      </div>
    </td>
  </tr>
</table>

<!-- B2B Bill To & Ship To Details -->
<div class="b2b-box">
  <table class="b2b-table">
    <tr>
      <td style="border-right: 1px solid #cbd5e1;">
        <div class="b2b-label">Billed To (Buyer / Customer)</div>
        <div class="b2b-name">Arihant Retail Traders Pvt Ltd</div>
        <div class="b2b-detail">
          Plot 45, MIDC Bhosari Industrial Area, Pune, Maharashtra - 411026<br>
          <strong>Phone:</strong> +91 98901 98765<br>
          <strong>Buyer GSTIN:</strong> <span class="highlight-gstin">27AAACA1234F1Z8</span><br>
          <strong>State:</strong> Maharashtra (Code: 27)
        </div>
      </td>
      <td>
        <div class="b2b-label">Dispatch / Transportation Details</div>
        <div class="b2b-detail" style="margin-top: 4px;">
          <strong>Reverse Charge (RCM):</strong> No<br>
          <strong>Transport Mode:</strong> Road / Delivery Van<br>
          <strong>Vehicle No:</strong> MH 12 QX 4521<br>
          <strong>Due Date:</strong> Immediate (Paid)
        </div>
      </td>
    </tr>
  </table>
</div>

<!-- Itemized Table with HSN & GST Breakup -->
<table class="items-table">
  <thead>
    <tr>
      <th class="text-center" style="width: 5%;">#</th>
      <th style="width: 33%;">Item Description</th>
      <th class="text-center" style="width: 9%;">HSN/SAC</th>
      <th class="text-center" style="width: 7%;">Qty</th>
      <th class="text-right" style="width: 10%;">Unit Rate</th>
      <th class="text-right" style="width: 11%;">Taxable Val</th>
      <th class="text-center" style="width: 12%;">GST Split</th>
      <th class="text-right" style="width: 13%;">Total (₹)</th>
    </tr>
  </thead>
  <tbody>
    <tr>
      <td class="text-center">1</td>
      <td class="bold">Aashirvaad Shudh Chakki Atta (10kg)</td>
      <td class="text-center">1101</td>
      <td class="text-center">10 Bgs</td>
      <td class="text-right">₹420.00</td>
      <td class="text-right">₹4,000.00</td>
      <td class="text-center">CGST 2.5% + SGST 2.5%<br><span style="color:#64748b; font-size:9px;">(₹200.00)</span></td>
      <td class="text-right bold">₹4,200.00</td>
    </tr>
    <tr>
      <td class="text-center">2</td>
      <td class="bold">Fortune Sunlite Sunflower Oil (15L Tin)</td>
      <td class="text-center">1512</td>
      <td class="text-center">4 Tins</td>
      <td class="text-right">₹1,850.00</td>
      <td class="text-right">₹7,047.62</td>
      <td class="text-center">CGST 2.5% + SGST 2.5%<br><span style="color:#64748b; font-size:9px;">(₹352.38)</span></td>
      <td class="text-right bold">₹7,400.00</td>
    </tr>
    <tr>
      <td class="text-center">3</td>
      <td class="bold">Dettol Antiseptic Liquid (500ml)</td>
      <td class="text-center">3004</td>
      <td class="text-center">12 Pcs</td>
      <td class="text-right">₹195.00</td>
      <td class="text-right">₹1,983.05</td>
      <td class="text-center">CGST 9% + SGST 9%<br><span style="color:#64748b; font-size:9px;">(₹356.95)</span></td>
      <td class="text-right bold">₹2,340.00</td>
    </tr>
    <tr>
      <td class="text-center">4</td>
      <td class="bold">Cadbury Dairy Milk Silk Chocolate (Pack)</td>
      <td class="text-center">1806</td>
      <td class="text-center">6 Pcs</td>
      <td class="text-right">₹175.00</td>
      <td class="text-right">₹889.83</td>
      <td class="text-center">CGST 9% + SGST 9%<br><span style="color:#64748b; font-size:9px;">(₹160.17)</span></td>
      <td class="text-right bold">₹1,050.00</td>
    </tr>
  </tbody>
</table>

<!-- Amount in Words -->
<div class="amount-words-box">
  <strong>Amount in Words:</strong> Indian Rupees Fourteen Thousand Nine Hundred Ninety Only.
</div>

<!-- GST Tax Slab Breakup Table (Statutory Requirement) -->
<div style="font-size: 10px; font-weight: 700; color: #475569; margin-bottom: 4px; text-transform: uppercase;">
  Tax Slab Breakup (GST Summary)
</div>
<table class="tax-summary-table">
  <thead>
    <tr>
      <th class="text-center">HSN/SAC</th>
      <th class="text-right">Taxable Value (₹)</th>
      <th class="text-center">CGST Rate</th>
      <th class="text-right">CGST Amt (₹)</th>
      <th class="text-center">SGST Rate</th>
      <th class="text-right">SGST Amt (₹)</th>
      <th class="text-right">Total Tax (₹)</th>
    </tr>
  </thead>
  <tbody>
    <tr>
      <td class="text-center">1101, 1512 (5%)</td>
      <td class="text-right">₹11,047.62</td>
      <td class="text-center">2.5%</td>
      <td class="text-right">₹276.19</td>
      <td class="text-center">2.5%</td>
      <td class="text-right">₹276.19</td>
      <td class="text-right bold">₹552.38</td>
    </tr>
    <tr>
      <td class="text-center">3004, 1806 (18%)</td>
      <td class="text-right">₹2,872.88</td>
      <td class="text-center">9.0%</td>
      <td class="text-right">₹258.56</td>
      <td class="text-center">9.0%</td>
      <td class="text-right">₹258.56</td>
      <td class="text-right bold">₹517.12</td>
    </tr>
    <tr style="background:#f8fafc; font-weight:700;">
      <td class="text-center">Total</td>
      <td class="text-right">₹13,920.50</td>
      <td class="text-center">-</td>
      <td class="text-right">₹534.75</td>
      <td class="text-center">-</td>
      <td class="text-right">₹534.75</td>
      <td class="text-right bold" style="color:#0284c7;">₹1,069.50</td>
    </tr>
  </tbody>
</table>

<!-- Bottom Grid: UPI / Terms + Totals -->
<table class="footer-grid">
  <tr>
    <td style="width: 52%; padding-right: 15px;">
      <div style="border: 1px solid #cbd5e1; border-radius: 6px; padding: 8px 10px; background: #f8fafc; margin-bottom: 8px;">
        <div style="font-size: 10px; font-weight: 700; color: #0f172a;">Instant UPI Payment & Verification</div>
        <div style="font-size: 9.5px; color: #475569; margin-top: 2px;">
          UPI VPA: <strong>ganeshent@icici</strong> &nbsp;|&nbsp; Verified Merchant<br>
          <span style="color:#059669; font-weight:600;">✓ Instant digital confirmation via Kamai+ POS</span>
        </div>
      </div>
      <div style="font-size: 9px; color: #64748b; line-height: 1.4;">
        <strong>Terms & Conditions:</strong><br>
        1. Goods once sold will not be taken back without valid invoice within 7 days.<br>
        2. Subject to Pune Jurisdiction only.<br>
        3. This is a computer generated statutory GST Tax Invoice.
      </div>
    </td>
    <td style="width: 48%;">
      <table class="totals-box">
        <tr>
          <td style="color:#64748b;">Total Taxable Amount:</td>
          <td class="text-right bold">₹13,920.50</td>
        </tr>
        <tr>
          <td style="color:#64748b;">CGST (Central Tax):</td>
          <td class="text-right">₹534.75</td>
        </tr>
        <tr>
          <td style="color:#64748b;">SGST (State Tax):</td>
          <td class="text-right">₹534.75</td>
        </tr>
        <tr>
          <td style="color:#64748b;">Round Off:</td>
          <td class="text-right">(-) ₹0.00</td>
        </tr>
        <tr class="grand-total-row">
          <td>GRAND TOTAL:</td>
          <td class="text-right">₹14,990.00</td>
        </tr>
      </table>
      
      <div class="sign-box">
        <div style="font-size: 10px; font-weight:700; color:#0f172a;">For SHREE GANESH ENTERPRISES</div>
        <div class="sign-line"></div><br>
        <span style="font-size: 8.5px; color:#64748b; font-weight:600; text-transform:uppercase;">Authorised Signatory</span>
      </div>
    </td>
  </tr>
</table>

<!-- Kamai+ Platform Branding Strip -->
<div style="margin-top: 18px; border: 1px solid #e2e8f0; background: #f8fafc; border-radius: 6px; padding: 6px 12px; display: flex; align-items: center; justify-content: space-between;">
  <div style="display: flex; align-items: center; gap: 8px;">
    <span style="background: #0284c7; color: white; font-weight: 800; font-size: 9px; padding: 2px 7px; border-radius: 4px; letter-spacing: 0.5px;">⚡ KAMAI+ POS</span>
    <span style="font-size: 9.5px; color: #475569; font-weight: 600;">India's #1 Retail POS & GST Billing App</span>
  </div>
  <div style="font-size: 9.5px; font-weight: 700; color: #0284c7;">
    www.kamaiplus.com
  </div>
</div>

<div style="margin-top: 8px; text-align: center; font-size: 8.5px; color: #94a3b8;">
  Page 1 of 1 • Statutory Electronic Invoice generated via KamaiPlus Android
</div>

</body>
</html>
"""

html_path = "sample_gst_tax_invoice.html"
pdf_path = "sample_gst_tax_invoice.pdf"

with open(html_path, "w", encoding="utf-8") as f:
    f.write(html_content)

edge_path = r"C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe"
cmd = [
    edge_path,
    "--headless",
    "--disable-gpu",
    f"--print-to-pdf={os.path.abspath(pdf_path)}",
    "--no-pdf-header-footer",
    os.path.abspath(html_path)
]

res = subprocess.run(cmd, capture_output=True, text=True)
print("PDF Export status:", res.returncode)
print("File exists:", os.path.exists(pdf_path))
