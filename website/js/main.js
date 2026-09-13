/**
 * KamaiPlus Official Web Platform - Interactive Logic
 * Handles Billing Simulator, ROI Calculator, Vertical Tabs, FAQ & Modals
 */

document.addEventListener('DOMContentLoaded', () => {
  initBillingSimulator();
  initRoiCalculator();
  initVerticalTabs();
  initFaqAccordion();
  initMobileMenu();
  initReceiptModal();
});

/* ==========================================================================
   1. Interactive POS Billing Simulator (Integer Paise Math)
   ========================================================================== */
function initBillingSimulator() {
  const sampleProducts = [
    { id: 'p1', name: 'Aashirvaad Atta 5kg', cat: 'Grocery', paise: 21000, icon: '🌾', barcode: '8901030382941' },
    { id: 'p2', name: 'Amul Taaza Milk 1L', cat: 'Dairy', paise: 5600, icon: '🥛', barcode: '8901262010053' },
    { id: 'p3', name: 'Basmati Rice 1kg', cat: 'Grains', paise: 8500, icon: '🍚', barcode: '8906007280014' },
    { id: 'p4', name: 'Tata Salt 1kg', cat: 'Essentials', paise: 2800, icon: '🧂', barcode: '8904004400276' },
    { id: 'p5', name: 'Fortune Sunlite 1L', cat: 'Edible Oil', paise: 13500, icon: '🌻', barcode: '8906007281123' },
    { id: 'p6', name: 'Surf Excel Quick 1kg', cat: 'Detergent', paise: 14500, icon: '🧼', barcode: '8901030582911' }
  ];

  let cart = [
    { ...sampleProducts[0], qty: 1 },
    { ...sampleProducts[1], qty: 2 }
  ];

  let selectedTenderPaise = 0; // 0 = Exact or UPI

  // Render Product Grid
  const gridEl = document.getElementById('sim-products-grid');
  if (gridEl) {
    gridEl.innerHTML = sampleProducts.map(p => `
      <div class="sim-product-card" data-id="${p.id}">
        <div class="sim-prod-icon">${p.icon}</div>
        <div class="sim-prod-name">${p.name}</div>
        <div class="sim-prod-cat">${p.cat}</div>
        <div class="sim-prod-price">
          <span>₹${(p.paise / 100).toFixed(2)}</span>
          <span class="sim-add-badge">+ Add</span>
        </div>
      </div>
    `).join('');

    gridEl.querySelectorAll('.sim-product-card').forEach(card => {
      card.addEventListener('click', () => {
        const prodId = card.getAttribute('data-id');
        const prod = sampleProducts.find(p => p.id === prodId);
        if (prod) addToCart(prod);
      });
    });
  }

  // Barcode Input Simulator
  const barcodeInput = document.getElementById('sim-barcode-input');
  const barcodeBtn = document.getElementById('sim-barcode-btn');
  if (barcodeBtn && barcodeInput) {
    const triggerBarcode = () => {
      const code = barcodeInput.value.trim();
      const matched = sampleProducts.find(p => p.barcode === code || p.id === code);
      if (matched) {
        addToCart(matched);
        barcodeInput.value = '';
        barcodeInput.placeholder = '✅ Item scanned: ' + matched.name;
        setTimeout(() => { barcodeInput.placeholder = 'Scan barcode (e.g. 8901030382941)...'; }, 2000);
      } else {
        // Fallback: add random product to demonstrate scan speed
        const randomProd = sampleProducts[Math.floor(Math.random() * sampleProducts.length)];
        addToCart(randomProd);
        barcodeInput.value = '';
        barcodeInput.placeholder = '⚡ Scanned: ' + randomProd.name;
        setTimeout(() => { barcodeInput.placeholder = 'Scan barcode (e.g. 8901030382941)...'; }, 2000);
      }
    };
    barcodeBtn.addEventListener('click', triggerBarcode);
    barcodeInput.addEventListener('keypress', (e) => {
      if (e.key === 'Enter') triggerBarcode();
    });
  }

  function addToCart(prod) {
    const existing = cart.find(item => item.id === prod.id);
    if (existing) {
      existing.qty += 1;
    } else {
      cart.push({ ...prod, qty: 1 });
    }
    renderCart();
  }

  function updateQty(id, delta) {
    const item = cart.find(i => i.id === id);
    if (item) {
      item.qty += delta;
      if (item.qty <= 0) {
        cart = cart.filter(i => i.id !== id);
      }
    }
    renderCart();
  }

  function renderCart() {
    const listEl = document.getElementById('sim-cart-list');
    const countEl = document.getElementById('sim-cart-count');
    const subtotalEl = document.getElementById('sim-subtotal-val');
    const taxEl = document.getElementById('sim-tax-val');
    const totalEl = document.getElementById('sim-total-val');
    const changeRowEl = document.getElementById('sim-change-row');
    const changeValEl = document.getElementById('sim-change-val');

    if (!listEl) return;

    if (cart.length === 0) {
      listEl.innerHTML = `
        <div style="text-align: center; padding: 2rem 0; color: #64748B;">
          <div style="font-size: 2rem; margin-bottom: 0.5rem;">🛒</div>
          <p style="font-size: 0.9rem;">Cart is empty. Tap items to add!</p>
        </div>
      `;
      if (countEl) countEl.textContent = '0 items';
      if (subtotalEl) subtotalEl.textContent = '₹0.00';
      if (taxEl) taxEl.textContent = '₹0.00';
      if (totalEl) totalEl.textContent = '₹0.00';
      if (changeRowEl) changeRowEl.style.display = 'none';
      return;
    }

    let subtotalPaise = 0;
    let totalItems = 0;

    listEl.innerHTML = cart.map(item => {
      const itemTotalPaise = item.paise * item.qty;
      subtotalPaise += itemTotalPaise;
      totalItems += item.qty;

      return `
        <div class="sim-cart-item">
          <div class="sim-item-info">
            <span class="sim-item-title">${item.name}</span>
            <span class="sim-item-meta">₹${(item.paise / 100).toFixed(2)} × ${item.qty}</span>
          </div>
          <div class="sim-item-actions">
            <button class="sim-qty-btn" data-action="dec" data-id="${item.id}">-</button>
            <span style="font-weight: bold; font-size: 0.9rem;">${item.qty}</span>
            <button class="sim-qty-btn" data-action="inc" data-id="${item.id}">+</button>
            <span class="sim-item-price">₹${(itemTotalPaise / 100).toFixed(2)}</span>
          </div>
        </div>
      `;
    }).join('');

    // Attach qty listeners
    listEl.querySelectorAll('.sim-qty-btn').forEach(btn => {
      btn.addEventListener('click', () => {
        const id = btn.getAttribute('data-id');
        const action = btn.getAttribute('data-action');
        updateQty(id, action === 'inc' ? 1 : -1);
      });
    });

    const taxPaise = Math.round(subtotalPaise * 0.05); // 5% sample GST
    const grandTotalPaise = subtotalPaise + taxPaise;

    if (countEl) countEl.textContent = `${totalItems} items`;
    if (subtotalEl) subtotalEl.textContent = `₹${(subtotalPaise / 100).toFixed(2)}`;
    if (taxEl) taxEl.textContent = `₹${(taxPaise / 100).toFixed(2)}`;
    if (totalEl) totalEl.textContent = `₹${(grandTotalPaise / 100).toFixed(2)}`;

    // Change calculation
    if (selectedTenderPaise > grandTotalPaise && changeRowEl && changeValEl) {
      const changePaise = selectedTenderPaise - grandTotalPaise;
      changeValEl.textContent = `₹${(changePaise / 100).toFixed(2)}`;
      changeRowEl.style.display = 'flex';
    } else if (changeRowEl) {
      changeRowEl.style.display = 'none';
    }
  }

  // Cash Tender Chips
  const chips = document.querySelectorAll('.sim-chip');
  chips.forEach(chip => {
    chip.addEventListener('click', () => {
      chips.forEach(c => c.classList.remove('active'));
      chip.classList.add('active');
      const val = chip.getAttribute('data-val');
      if (val === 'exact' || val === 'upi') {
        selectedTenderPaise = 0;
      } else {
        selectedTenderPaise = parseInt(val, 10) * 100;
      }
      renderCart();
    });
  });

  // Print Bill / Checkout Trigger
  const checkoutBtn = document.getElementById('sim-checkout-btn');
  if (checkoutBtn) {
    checkoutBtn.addEventListener('click', () => {
      if (cart.length === 0) {
        alert('Please add at least one item to generate bill preview.');
        return;
      }
      showReceiptModal(cart);
    });
  }

  renderCart();
}

/* ==========================================================================
   2. Retail ROI & Udhar Recovery Calculator
   ========================================================================== */
function initRoiCalculator() {
  const billsInput = document.getElementById('roi-bills-slider');
  const basketInput = document.getElementById('roi-basket-slider');
  const billsDisplay = document.getElementById('roi-bills-val');
  const basketDisplay = document.getElementById('roi-basket-val');

  const hoursDisplay = document.getElementById('roi-hours-saved');
  const lossDisplay = document.getElementById('roi-loss-prevented');
  const monthlyRevenueDisplay = document.getElementById('roi-monthly-rev');

  if (!billsInput || !basketInput) return;

  function calculate() {
    const dailyBills = parseInt(billsInput.value, 10);
    const avgBasket = parseInt(basketInput.value, 10);

    if (billsDisplay) billsDisplay.textContent = `${dailyBills} bills/day`;
    if (basketDisplay) basketDisplay.textContent = `₹${avgBasket}`;

    // Calculation formulas
    // Approx 25 seconds saved per bill vs manual paper/pen billing
    const secondsSaved = dailyBills * 25;
    const hoursSavedPerDay = (secondsSaved / 3600).toFixed(1);

    // Monthly business turnover
    const monthlyTurnover = dailyBills * avgBasket * 30;

    // Typical unorganized retail inventory loss / missed billing is ~2.8%
    // KamaiPlus barcode + batch lock prevents this loss
    const lossPrevented = Math.round(monthlyTurnover * 0.028);

    if (hoursDisplay) hoursDisplay.textContent = `${hoursSavedPerDay} hrs / day`;
    if (lossDisplay) lossDisplay.textContent = `₹${lossPrevented.toLocaleString('en-IN')}`;
    if (monthlyRevenueDisplay) monthlyRevenueDisplay.textContent = `₹${monthlyTurnover.toLocaleString('en-IN')}`;
  }

  billsInput.addEventListener('input', calculate);
  basketInput.addEventListener('input', calculate);
  calculate();
}

/* ==========================================================================
   3. Vertical Business Tab Switcher
   ========================================================================== */
function initVerticalTabs() {
  const tabBtns = document.querySelectorAll('.v-tab-btn');
  const tabPanes = document.querySelectorAll('.v-tab-content');

  if (tabBtns.length === 0) return;

  tabBtns.forEach(btn => {
    btn.addEventListener('click', () => {
      const targetId = btn.getAttribute('data-tab');

      tabBtns.forEach(b => b.classList.remove('active'));
      tabPanes.forEach(p => p.classList.remove('active'));

      btn.classList.add('active');
      const targetPane = document.getElementById(`v-tab-${targetId}`);
      if (targetPane) {
        targetPane.classList.add('active');
      }
    });
  });
}

/* ==========================================================================
   4. FAQ Accordion
   ========================================================================== */
function initFaqAccordion() {
  const faqItems = document.querySelectorAll('.faq-item');

  faqItems.forEach(item => {
    const q = item.querySelector('.faq-question');
    if (q) {
      q.addEventListener('click', () => {
        const isActive = item.classList.contains('active');
        faqItems.forEach(i => i.classList.remove('active'));
        if (!isActive) {
          item.classList.add('active');
        }
      });
    }
  });
}

/* ==========================================================================
   5. Mobile Menu Toggle
   ========================================================================== */
function initMobileMenu() {
  const menuBtn = document.getElementById('mobile-menu-btn');
  const drawer = document.getElementById('mobile-nav-drawer');

  if (menuBtn && drawer) {
    menuBtn.addEventListener('click', () => {
      drawer.classList.toggle('active');
    });

    drawer.querySelectorAll('a').forEach(link => {
      link.addEventListener('click', () => {
        drawer.classList.remove('active');
      });
    });
  }
}

/* ==========================================================================
   6. Simulated 58mm Thermal Receipt Modal
   ========================================================================== */
function initReceiptModal() {
  const modal = document.getElementById('receipt-modal');
  const closeBtn = document.getElementById('receipt-close-btn');

  if (closeBtn && modal) {
    closeBtn.addEventListener('click', () => {
      modal.classList.remove('active');
    });

    modal.addEventListener('click', (e) => {
      if (e.target === modal) modal.classList.remove('active');
    });
  }
}

function showReceiptModal(cartItems) {
  const modal = document.getElementById('receipt-modal');
  const bodyEl = document.getElementById('receipt-modal-content');
  if (!modal || !bodyEl) return;

  let subtotal = 0;
  const now = new Date();
  const dateStr = now.toLocaleDateString('en-IN', { day: '2-digit', month: 'short', year: 'numeric' });
  const timeStr = now.toLocaleTimeString('en-IN', { hour: '2-digit', minute: '2-digit' });
  const billNo = 'INV-' + Math.floor(100000 + Math.random() * 900000);

  const itemsHtml = cartItems.map(item => {
    const itemTotal = (item.paise * item.qty) / 100;
    subtotal += itemTotal;
    return `
      <div style="display: flex; justify-content: space-between; font-size: 13px; margin-bottom: 4px;">
        <span style="max-width: 190px; text-overflow: ellipsis; overflow: hidden; white-space: nowrap;">${item.name}</span>
        <span>${item.qty} × ${(item.paise/100).toFixed(0)} = ₹${itemTotal.toFixed(2)}</span>
      </div>
    `;
  }).join('');

  const tax = subtotal * 0.05;
  const grandTotal = subtotal + tax;

  bodyEl.innerHTML = `
    <div style="text-align: center; border-bottom: 1px dashed #9CA3AF; padding-bottom: 8px; margin-bottom: 8px;">
      <h3 style="font-size: 16px; font-weight: 900; color: #111827; margin-bottom: 2px;">SHREE GANESH SUPERMARKET</h3>
      <p style="font-size: 11px; color: #4B5563; margin: 0;">Main Market Road, Pune, MH</p>
      <p style="font-size: 11px; color: #4B5563; margin: 0;">GSTIN: 27AABCS1429B1Z8</p>
      <p style="font-size: 11px; color: #4B5563; margin: 0;">Bill No: <b>${billNo}</b> | ${dateStr} ${timeStr}</p>
    </div>

    <div style="margin-bottom: 8px;">
      ${itemsHtml}
    </div>

    <div style="border-top: 1px dashed #9CA3AF; padding-top: 6px; margin-bottom: 8px; font-size: 13px;">
      <div style="display: flex; justify-content: space-between; margin-bottom: 2px;">
        <span>Subtotal:</span>
        <span>₹${subtotal.toFixed(2)}</span>
      </div>
      <div style="display: flex; justify-content: space-between; margin-bottom: 2px;">
        <span>CGST (2.5%) + SGST (2.5%):</span>
        <span>₹${tax.toFixed(2)}</span>
      </div>
      <div style="display: flex; justify-content: space-between; font-weight: 900; font-size: 16px; border-top: 1px solid #111827; padding-top: 4px; margin-top: 4px;">
        <span>GRAND TOTAL:</span>
        <span>₹${grandTotal.toFixed(2)}</span>
      </div>
    </div>

    <div style="text-align: center; border-top: 1px dashed #9CA3AF; padding-top: 8px;">
      <p style="font-size: 11px; font-weight: bold; color: #111827; margin-bottom: 4px;">* INSTANT 0.8s PRINT VIA KAMAI+ *</p>
      <p style="font-size: 11px; color: #4B5563; margin: 0;">Thank You! Visit Again 🙏</p>
      <p style="font-size: 10px; color: #10B981; font-weight: bold; margin-top: 6px;">Powered by KamaiPlus POS</p>
    </div>
  `;

  modal.classList.add('active');
}
