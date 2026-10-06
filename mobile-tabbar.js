// Mobile bottom tab bar (Home · Trips · Products · Profile) for the customer site.
// Include after i18n.js on every customer page: <script src="mobile-tabbar.js" defer></script>
// Shown only at phone widths (≤768px); desktop keeps the normal top navbar.
(function () {
  'use strict';

  // Supabase keeps the session here (supabase-js default storage key for this project).
  var AUTH_KEY = 'sb-nkrpkfqibsudqsonljve-auth-token';
  function signedIn() {
    try { return !!localStorage.getItem(AUTH_KEY); } catch (e) { return false; }
  }

  var ICONS = {
    home:     '<path d="M3 10.5 12 3l9 7.5"/><path d="M5 9.5V20a1 1 0 0 0 1 1h4v-6h4v6h4a1 1 0 0 0 1-1V9.5"/>',
    trips:    '<path d="M17.8 19.2 16 11l3.5-3.5C21 6 21.5 4 21 3c-1-.5-3 0-4.5 1.5L13 8 4.8 6.2c-.5-.1-.9.1-1.1.5l-.3.5c-.2.5-.1 1 .3 1.3L9 12l-2 3H4l-1 1 3 2 2 3 1-1v-3l3-2 3.5 5.3c.3.4.8.5 1.3.3l.5-.2c.4-.3.6-.7.5-1.2z"/>',
    products: '<rect x="3" y="8" width="18" height="4" rx="1"/><path d="M12 8v13"/><path d="M19 12v7a2 2 0 0 1-2 2H7a2 2 0 0 1-2-2v-7"/><path d="M7.5 8a2.5 2.5 0 0 1 0-5C10 3 12 8 12 8s2-5 4.5-5a2.5 2.5 0 0 1 0 5"/>',
    profile:  '<circle cx="12" cy="8" r="4"/><path d="M4 21c0-4.4 3.6-8 8-8s8 3.6 8 8"/>'
  };

  var TABS = [
    { id: 'home',     href: 'index.html',      label: 'nav.home',         pages: ['', 'index.html'] },
    { id: 'trips',    href: 'trips.html',      label: 'nav.trips',        pages: ['trips.html', 'trip.html'] },
    { id: 'products', href: 'free-gifts.html', label: 'tabbar.products',  pages: ['free-gifts.html'] },
    { id: 'profile',  href: null,              label: 'tabbar.profile',   pages: ['dashboard.html', 'login.html'] }
  ];

  var CSS =
    '.tc-tabbar{display:none}' +
    '@media (max-width:768px){' +
      'body.has-tc-tabbar{padding-bottom:calc(64px + env(safe-area-inset-bottom,0px))}' +
      // Toasts sit above the bar; their hidden state (translateY(80px)) would then land inside
      // the bar as an empty pill, so push hidden ones fully off-screen.
      'body.has-tc-tabbar .toast{bottom:calc(80px + env(safe-area-inset-bottom,0px))}' +
      'body.has-tc-tabbar .toast:not(.show){transform:translateX(-50%) translateY(calc(100% + 120px + env(safe-area-inset-bottom,0px)))}' +
      '.tc-tabbar{display:flex;position:fixed;left:0;right:0;top:auto;bottom:0;z-index:90;' +
        'background:#fff;border-top:1px solid rgba(26,31,46,0.1);box-shadow:0 -6px 24px rgba(26,31,46,0.06);' +
        'padding-bottom:env(safe-area-inset-bottom,0px)}' +
      '.tc-tabbar a{flex:1;display:flex;flex-direction:column;align-items:center;justify-content:center;gap:4px;' +
        'height:64px;text-decoration:none;color:#8a8f9c;font-family:"DM Sans",sans-serif;font-size:0.66rem;' +
        'font-weight:500;letter-spacing:0.03em;-webkit-tap-highlight-color:transparent}' +
      '.tc-tabbar svg{width:22px;height:22px;fill:none;stroke:currentColor;stroke-width:1.6;stroke-linecap:round;stroke-linejoin:round}' +
      '.tc-tabbar a.active{color:#b8955a}' +
      '.tc-tabbar a.active svg{stroke-width:2}' +
    '}';

  function label(key, fallback) {
    var t = window.TC_I18N && TC_I18N.t ? TC_I18N.t(key) : '';
    return t && t !== key ? t : fallback;
  }

  function build() {
    if (document.querySelector('.tc-tabbar')) return;
    var style = document.createElement('style');
    style.textContent = CSS;
    document.head.appendChild(style);

    var page = (location.pathname.split('/').pop() || '').toLowerCase();
    // A div, not <nav>: some pages style every <nav> as their fixed top navbar.
    var nav = document.createElement('div');
    nav.className = 'tc-tabbar';
    nav.setAttribute('role', 'navigation');
    nav.setAttribute('aria-label', 'Main');
    var fallbacks = { home: 'Home', trips: 'Trips', products: 'Products', profile: 'Profile' };
    nav.innerHTML = TABS.map(function (t) {
      var href = t.href || (signedIn() ? 'dashboard.html' : 'login.html');
      var active = t.pages.indexOf(page) !== -1;
      return '<a href="' + href + '" data-tab="' + t.id + '"' + (active ? ' class="active" aria-current="page"' : '') + '>' +
        '<svg viewBox="0 0 24 24" aria-hidden="true">' + ICONS[t.id] + '</svg>' +
        '<span data-tab-label="' + t.label + '">' + label(t.label, fallbacks[t.id]) + '</span></a>';
    }).join('');
    document.body.appendChild(nav);
    document.body.classList.add('has-tc-tabbar');

    // Labels follow the language switcher.
    if (window.TC_I18N && TC_I18N.onChange) {
      TC_I18N.onChange(function () {
        nav.querySelectorAll('[data-tab-label]').forEach(function (el) {
          var id = el.parentNode.getAttribute('data-tab');
          el.textContent = label(el.getAttribute('data-tab-label'), fallbacks[id]);
        });
      });
    }
  }

  if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', build);
  else build();
})();
