// Mobile bottom tab bar (Home · Tours · Products · Profile) for the customer site.
// Include after i18n.js on every customer page: <script src="mobile-tabbar.js" defer></script>
// Shown only at phone widths (≤768px); desktop keeps the normal top navbar.
// Also marks the current page's link in the top navbar (.nav-links a.active).
(function () {
  'use strict';

  // Supabase keeps the session here (supabase-js default storage key for this project).
  var AUTH_KEY = 'sb-nkrpkfqibsudqsonljve-auth-token';
  function signedIn() {
    try { return !!localStorage.getItem(AUTH_KEY); } catch (e) { return false; }
  }

  var ICONS = {
    home:     '<path d="M3 10.5 12 3l9 7.5"/><path d="M5 9.5V20a1 1 0 0 0 1 1h4v-6h4v6h4a1 1 0 0 0 1-1V9.5"/>',
    trips:    '<rect x="3" y="7" width="18" height="13" rx="2"/><path d="M8 7V5a2 2 0 0 1 2-2h4a2 2 0 0 1 2 2v2"/><path d="M3 13h18"/>',
    products: '<rect x="3" y="8" width="18" height="4" rx="1"/><path d="M12 8v13"/><path d="M19 12v7a2 2 0 0 1-2 2H7a2 2 0 0 1-2-2v-7"/><path d="M7.5 8a2.5 2.5 0 0 1 0-5C10 3 12 8 12 8s2-5 4.5-5a2.5 2.5 0 0 1 0 5"/>',
    profile:  '<circle cx="12" cy="8" r="4"/><path d="M4 21c0-4.4 3.6-8 8-8s8 3.6 8 8"/>'
  };

  var TABS = [
    { id: 'home',     href: 'index.html',      label: 'nav.home',        fb: 'Home',    pages: ['', 'index.html', 'index'] },
    { id: 'trips',    href: 'trips.html',      label: 'tabbar.tours',    fb: 'Tours',   pages: ['trips.html', 'trip.html', 'trips', 'trip'] },
    { id: 'products', href: 'free-gifts.html', label: 'tabbar.products', fb: 'Gifts',   pages: ['free-gifts.html', 'free-gifts'] },
    { id: 'profile',  href: null,              label: 'tabbar.profile',  fb: 'Profile', pages: ['dashboard.html', 'login.html', 'dashboard', 'login'] }
  ];
  var CSS =
    '.tc-tabbar{display:none}' +
    '@media (max-width:768px){' +
      'body.has-tc-tabbar{padding-bottom:calc(92px + env(safe-area-inset-bottom,0px))}' +
      // Toasts sit above the bar; their hidden state (translateY(80px)) would then land inside
      // the bar as an empty pill, so push hidden ones fully off-screen.
      'body.has-tc-tabbar .toast{bottom:calc(104px + env(safe-area-inset-bottom,0px))}' +
      'body.has-tc-tabbar .toast:not(.show){transform:translateX(-50%) translateY(calc(100% + 140px + env(safe-area-inset-bottom,0px)))}' +
      '.tc-tabbar{display:flex;position:fixed;left:12px;right:12px;top:auto;bottom:calc(10px + env(safe-area-inset-bottom,0px));z-index:90;' +
        'background:rgba(255,255,255,0.97);border-radius:22px;padding:6px;gap:2px;' +
        'box-shadow:0 10px 34px rgba(15,37,87,0.16),0 0 0 1px rgba(15,37,87,0.05);backdrop-filter:blur(14px)}' +
      '.tc-tabbar a{flex:1;min-width:0;display:flex;flex-direction:column;align-items:center;justify-content:center;gap:3px;' +
        'height:58px;border-radius:16px;text-decoration:none;color:#7b879c;font-family:"Nunito",sans-serif;font-size:0.68rem;' +
        'font-weight:700;-webkit-tap-highlight-color:transparent;transition:background .2s,color .2s}' +
      '.tc-tabbar a span{max-width:100%;overflow:hidden;text-overflow:ellipsis;white-space:nowrap}' +
      '.tc-tabbar svg{width:23px;height:23px;fill:none;stroke:currentColor;stroke-width:1.8;stroke-linecap:round;stroke-linejoin:round}' +
      '.tc-tabbar a.active{color:#1f6fd6;background:#e8f1fd}' +
      '.tc-tabbar a.active svg{stroke-width:2.2}' +
    '}';

  function label(key, fallback) {
    var t = window.TC_I18N && TC_I18N.t ? TC_I18N.t(key) : '';
    return t && t !== key ? t : fallback;
  }
  function svg(id) { return '<svg viewBox="0 0 24 24" aria-hidden="true">' + ICONS[id] + '</svg>'; }

  function markNavActive(page) {
    var links = document.querySelectorAll('.navbar .nav-links a[href]');
    if (!links.length) return;
    links.forEach(function (a) {
      var href = (a.getAttribute('href') || '').split('#')[0].split('?')[0].toLowerCase();
      if (!href) return;
      var same = href === page || href.replace('.html', '') === page.replace('.html', '') ||
                 (href === 'index.html' && page === '') || (href === 'trips.html' && (page === 'trip.html' || page === 'trip'));
      if (same) a.classList.add('active');
    });
  }

  function build() {
    var page = (location.pathname.split('/').pop() || '').toLowerCase();
    markNavActive(page);
    if (document.querySelector('.tc-tabbar')) return;
    var style = document.createElement('style');
    style.textContent = CSS;
    document.head.appendChild(style);

    // A div, not <nav>: some pages style every <nav> as their fixed top navbar.
    var nav = document.createElement('div');
    nav.className = 'tc-tabbar';
    nav.setAttribute('role', 'navigation');
    nav.setAttribute('aria-label', 'Main');
    nav.innerHTML = TABS.map(function (t) {
      var href = t.href || (signedIn() ? 'dashboard.html' : 'login.html');
      var active = t.pages.indexOf(page) !== -1;
      return '<a href="' + href + '" data-tab="' + t.id + '"' + (active ? ' class="active" aria-current="page"' : '') + '>' +
        svg(t.id) + '<span data-tab-label="' + t.label + '" data-fb="' + t.fb + '">' + label(t.label, t.fb) + '</span></a>';
    }).join('');

    document.body.appendChild(nav);
    document.body.classList.add('has-tc-tabbar');

    // Labels follow the language switcher.
    if (window.TC_I18N && TC_I18N.onChange) {
      TC_I18N.onChange(function () {
        document.querySelectorAll('.tc-tabbar [data-tab-label]').forEach(function (el) {
          el.textContent = label(el.getAttribute('data-tab-label'), el.getAttribute('data-fb'));
        });
      });
    }
  }

  if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', build);
  else build();
})();
