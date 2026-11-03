// Language, theme, the copy button, and playing the clips only while they're visible.
(function () {
  var root = document.documentElement;
  var strings = window.PS_STRINGS || {};

  function store(key, value) { try { localStorage.setItem(key, value); } catch (e) {} }
  function read(key) { try { return localStorage.getItem(key); } catch (e) { return null; } }

  // English lives in the page; it is read once so switching back restores it.
  var english = {};
  document.querySelectorAll('[data-i18n]').forEach(function (el) { english[el.dataset.i18n] = el.innerHTML; });
  var englishAttrs = [];
  document.querySelectorAll('[data-i18n-attr]').forEach(function (el) {
    el.dataset.i18nAttr.split(';').forEach(function (pair) {
      var parts = pair.split(':');
      englishAttrs.push({ el: el, attr: parts[0], key: parts[1], value: el.getAttribute(parts[0]) });
    });
  });
  var englishTitle = document.title;
  var description = document.querySelector('meta[name="description"]');
  var englishDescription = description.getAttribute('content');

  function setLanguage(lang) {
    var t = lang === 'en' ? null : strings[lang];
    if (lang !== 'en' && !t) lang = 'en';
    root.lang = lang;
    document.querySelectorAll('[data-i18n]').forEach(function (el) {
      var key = el.dataset.i18n;
      el.innerHTML = t && t[key] != null ? t[key] : english[key];
    });
    englishAttrs.forEach(function (a) {
      a.el.setAttribute(a.attr, t && t[a.key] != null ? t[a.key] : a.value);
    });
    document.title = t && t['meta.title'] || englishTitle;
    description.setAttribute('content', t && t['meta.description'] || englishDescription);
    document.querySelectorAll('[data-lang]').forEach(function (b) {
      b.setAttribute('aria-pressed', String(b.dataset.lang === lang));
    });
  }

  document.querySelectorAll('[data-lang]').forEach(function (b) {
    b.addEventListener('click', function () { store('ps-lang', b.dataset.lang); setLanguage(b.dataset.lang); });
  });
  var saved = read('ps-lang');
  var preferred = saved || ((navigator.language || '').toLowerCase().indexOf('tr') === 0 ? 'tr' : 'en');
  if (preferred !== 'en') setLanguage(preferred);

  // Theme: follows the system until the visitor picks one.
  var dark = window.matchMedia('(prefers-color-scheme: dark)');
  document.getElementById('theme-toggle').addEventListener('click', function () {
    var current = root.dataset.theme || (dark.matches ? 'dark' : 'light');
    var next = current === 'dark' ? 'light' : 'dark';
    root.dataset.theme = next;
    store('ps-theme', next);
  });

  var copy = document.getElementById('copy');
  copy.addEventListener('click', function () {
    var text = document.getElementById('brew').textContent;
    var done = function () {
      var label = copy.innerHTML;
      copy.textContent = root.lang === 'tr' ? 'Kopyalandı' : 'Copied';
      setTimeout(function () { copy.innerHTML = label; }, 1600);
    };
    if (navigator.clipboard) navigator.clipboard.writeText(text).then(done, function () {});
  });

  // Clips play only on screen, and not at all with reduced motion.
  var still = window.matchMedia('(prefers-reduced-motion: reduce)').matches;
  var videos = document.querySelectorAll('video');
  if ('IntersectionObserver' in window && !still) {
    var io = new IntersectionObserver(function (entries) {
      entries.forEach(function (e) {
        if (e.isIntersecting) { e.target.play().catch(function () {}); } else { e.target.pause(); }
      });
    }, { threshold: 0.25 });
    videos.forEach(function (v) { io.observe(v); });
  }

  // Sections fade in as they scroll into view.
  if ('IntersectionObserver' in window && !still) {
    var items = document.querySelectorAll('.format, .steps li, .card, .mini, .privacy-list li');
    var reveal = new IntersectionObserver(function (entries) {
      entries.forEach(function (e) { if (e.isIntersecting) { e.target.classList.add('in'); reveal.unobserve(e.target); } });
    }, { threshold: 0.15 });
    items.forEach(function (el) { el.classList.add('reveal'); reveal.observe(el); });
  }
})();
