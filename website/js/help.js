/**
 * KamaiPlus Help Center - Interactive Logic
 * Supports Multi-language toggle (English <-> Hindi), Live Search, Category filtering & Copyable Permalinks
 */

document.addEventListener('DOMContentLoaded', () => {
  initLanguageToggle();
  initHelpSearch();
  initHelpCategoryFilter();
  initAnchorHighlight();
  initCopyPermalink();
  initMobileMenu();
});

/* ==========================================================================
   1. Multi-Language (English <-> Hindi) Support
   ========================================================================== */
let currentLang = localStorage.getItem('kamaiplus_lang') || 'en';

function initLanguageToggle() {
  const toggleBtns = document.querySelectorAll('.btn-lang-toggle');
  
  applyLanguage(currentLang);

  toggleBtns.forEach(btn => {
    btn.addEventListener('click', () => {
      currentLang = currentLang === 'en' ? 'hi' : 'en';
      localStorage.setItem('kamaiplus_lang', currentLang);
      applyLanguage(currentLang);
    });
  });
}

function applyLanguage(lang) {
  // Update toggle button text
  const toggleBtns = document.querySelectorAll('.btn-lang-toggle');
  toggleBtns.forEach(btn => {
    btn.innerHTML = lang === 'en' 
      ? '<span>🌐</span> <span style="font-weight: bold;">हिंदी</span>' 
      : '<span>🌐</span> <span style="font-weight: bold;">English</span>';
  });

  // Switch all elements with data-en and data-hi
  const translatables = document.querySelectorAll('[data-en][data-hi]');
  translatables.forEach(el => {
    el.innerHTML = lang === 'en' ? el.getAttribute('data-en') : el.getAttribute('data-hi');
  });

  // Switch placeholders
  const searchInputs = document.querySelectorAll('.help-search-input');
  searchInputs.forEach(input => {
    input.placeholder = lang === 'en'
      ? 'Search guides (e.g. Printer setup, Barcode scan, Khata, GST bill)...'
      : 'गाइड खोजें (जैसे प्रिंटर सेटअप, बारकोड स्कैन, खाता, GST बिल)...';
  });
}

/* ==========================================================================
   2. Live Instant Help Search
   ========================================================================== */
function initHelpSearch() {
  const searchInput = document.getElementById('help-search-input');
  const articles = document.querySelectorAll('.help-article-section');
  const noResultEl = document.getElementById('help-no-results');

  if (!searchInput) return;

  searchInput.addEventListener('input', (e) => {
    const query = e.target.value.toLowerCase().trim();
    let visibleCount = 0;

    articles.forEach(article => {
      const text = article.textContent.toLowerCase();
      const keywords = article.getAttribute('data-keywords') || '';
      
      if (query === '' || text.includes(query) || keywords.toLowerCase().includes(query)) {
        article.style.display = 'block';
        visibleCount++;
      } else {
        article.style.display = 'none';
      }
    });

    if (noResultEl) {
      noResultEl.style.display = visibleCount === 0 ? 'block' : 'none';
    }
  });
}

/* ==========================================================================
   3. Help Category Filtering
   ========================================================================== */
function initHelpCategoryFilter() {
  const catLinks = document.querySelectorAll('.help-nav-link');
  const articles = document.querySelectorAll('.help-article-section');

  catLinks.forEach(link => {
    link.addEventListener('click', (e) => {
      const cat = link.getAttribute('data-category');
      if (!cat) return; // Anchor link inside page

      e.preventDefault();
      catLinks.forEach(l => l.classList.remove('active'));
      link.classList.add('active');

      articles.forEach(art => {
        const artCat = art.getAttribute('data-category');
        if (cat === 'all' || artCat === cat) {
          art.style.display = 'block';
        } else {
          art.style.display = 'none';
        }
      });

      // Clear search input if category filter is clicked
      const searchInput = document.getElementById('help-search-input');
      if (searchInput) searchInput.value = '';
    });
  });
}

/* ==========================================================================
   4. Deep Anchor Scrolling & Glow Animation
   ========================================================================== */
function initAnchorHighlight() {
  const hash = window.location.hash;
  if (hash) {
    setTimeout(() => {
      const target = document.querySelector(hash);
      if (target) {
        target.scrollIntoView({ behavior: 'smooth', block: 'start' });
        target.style.boxShadow = '0 0 35px rgba(16, 185, 129, 0.5)';
        target.style.borderColor = '#10B981';
        setTimeout(() => {
          target.style.boxShadow = '';
          target.style.borderColor = '';
        }, 3000);
      }
    }, 200);
  }
}

/* ==========================================================================
   5. Copy Direct Shareable Anchor Link for Merchant Support
   ========================================================================== */
function initCopyPermalink() {
  const copyBtns = document.querySelectorAll('.help-anchor-btn');

  copyBtns.forEach(btn => {
    btn.addEventListener('click', (e) => {
      e.stopPropagation();
      const anchorId = btn.getAttribute('data-anchor');
      const fullUrl = `${window.location.origin}${window.location.pathname}#${anchorId}`;

      navigator.clipboard.writeText(fullUrl).then(() => {
        const originalText = btn.innerHTML;
        btn.innerHTML = '✅ Copied!';
        btn.style.color = '#10B981';
        btn.style.borderColor = '#10B981';

        setTimeout(() => {
          btn.innerHTML = originalText;
          btn.style.color = '';
          btn.style.borderColor = '';
        }, 2200);
      }).catch(() => {
        prompt('Copy this help link to send to merchant:', fullUrl);
      });
    });
  });
}

/* ==========================================================================
   6. Mobile Navigation Drawer
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
