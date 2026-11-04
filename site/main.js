// Promo Studio website. No dependencies: language, theme and the page's animations.
(function () {
  var root = document.documentElement;
  var still = window.matchMedia('(prefers-reduced-motion: reduce)').matches;
  var hasIO = 'IntersectionObserver' in window;
  var $ = function (s, el) { return (el || document).querySelector(s); };
  var $$ = function (s, el) { return Array.prototype.slice.call((el || document).querySelectorAll(s)); };

  function store(key, value) { try { localStorage.setItem(key, value); } catch (e) {} }

  /* ---------- Language ---------- */

  // English lives in the page and is read once, so switching back restores it.
  var names = {};
  $$('[data-lang]').forEach(function (b) { names[b.dataset.lang] = b.textContent; });
  var en = {};
  $$('[data-i18n]').forEach(function (el) { en[el.dataset.i18n] = el.innerHTML; });
  var attrs = [];
  $$('[data-i18n-attr]').forEach(function (el) {
    el.dataset.i18nAttr.split(';').forEach(function (pair) {
      var p = pair.split(':');
      attrs.push({ el: el, attr: p[0], key: p[1] });
      en[p[1]] = en[p[1]] != null ? en[p[1]] : el.getAttribute(p[0]);
    });
  });
  en['meta.title'] = document.title;
  var description = $('meta[name="description"]');
  en['meta.description'] = description.getAttribute('content');

  var current = 'en';
  function t(key) {
    var table = (window.PS_I18N || {})[current];
    return table && table[key] != null ? table[key] : en[key];
  }

  function apply(lang) {
    current = lang;
    root.lang = lang;
    $$('[data-i18n]').forEach(function (el) { el.innerHTML = t(el.dataset.i18n); });
    attrs.forEach(function (a) { a.el.setAttribute(a.attr, t(a.key)); });
    document.title = t('meta.title');
    description.setAttribute('content', t('meta.description'));
    $('#lang-current').textContent = names[lang];
    $$('[data-lang]').forEach(function (b) { b.setAttribute('aria-current', String(b.dataset.lang === lang)); });
    document.dispatchEvent(new Event('ps-lang'));
  }

  function load(lang, done) {
    if (lang === 'en' || (window.PS_I18N || {})[lang]) return done();
    var s = document.createElement('script');
    s.src = 'i18n/' + lang + '.js';
    s.onload = done;
    s.onerror = function () { lang = 'en'; done(); };
    document.head.appendChild(s);
  }

  var langBtn = $('#lang-btn');
  var langMenu = $('#lang-menu');
  function menu(open) {
    langMenu.hidden = !open;
    langBtn.setAttribute('aria-expanded', String(open));
  }
  langBtn.addEventListener('click', function () { menu(langMenu.hidden); });
  document.addEventListener('click', function (e) { if (!$('#lang').contains(e.target)) menu(false); });
  document.addEventListener('keydown', function (e) {
    if (e.key === 'Escape' && !langMenu.hidden) { menu(false); langBtn.focus(); }
  });
  $$('[data-lang]').forEach(function (b) {
    b.addEventListener('click', function () {
      var lang = b.dataset.lang;
      store('ps-lang', lang);
      menu(false);
      load(lang, function () { apply((window.PS_I18N || {})[lang] || lang === 'en' ? lang : 'en'); });
    });
  });
  apply((window.PS_I18N || {})[window.PS_LANG] ? window.PS_LANG : 'en');

  /* ---------- Theme ---------- */

  var dark = window.matchMedia('(prefers-color-scheme: dark)');
  $('#theme-toggle').addEventListener('click', function () {
    var now = root.dataset.theme || (dark.matches ? 'dark' : 'light');
    var next = now === 'dark' ? 'light' : 'dark';
    root.dataset.theme = next;
    store('ps-theme', next);
  });

  /* ---------- Download ---------- */

  var copy = $('#copy');
  copy.addEventListener('click', function () {
    if (!navigator.clipboard) return;
    navigator.clipboard.writeText($('#brew').textContent).then(function () {
      copy.textContent = t('ui.copied');
      setTimeout(function () { copy.innerHTML = t('download.copy'); }, 1600);
    }, function () {});
  });

  // The page never goes stale on the version: GitHub says which one is latest.
  if (window.fetch) {
    fetch('https://api.github.com/repos/ardasnturk/promo-studio/releases/latest')
      .then(function (r) { return r.ok ? r.json() : null; })
      .then(function (j) { if (j && j.tag_name) $('#version').textContent = j.tag_name.replace(/^v/, ''); })
      .catch(function () {});
  }

  /* ---------- Marquees: duplicate the content so the loop has no seam ---------- */

  $$('[data-marquee], [data-marquee-y]').forEach(function (track) {
    Array.prototype.slice.call(track.children).forEach(function (item) {
      var copy = item.cloneNode(true);
      copy.setAttribute('aria-hidden', 'true');
      track.appendChild(copy);
    });
  });

  /* ---------- Videos play only on screen, and not with reduced motion ---------- */

  if (hasIO && !still) {
    var playing = new IntersectionObserver(function (entries) {
      entries.forEach(function (e) {
        if (e.isIntersecting) e.target.play().catch(function () {});
        else e.target.pause();
      });
    }, { threshold: 0.1 });
    $$('video').forEach(function (v) { playing.observe(v); });
  }

  /* ---------- Reveal on scroll ---------- */

  var items = $$('.rv');
  if (hasIO && !still) {
    var reveal = new IntersectionObserver(function (entries) {
      entries.forEach(function (e) {
        if (!e.isIntersecting) return;
        e.target.classList.add('in');
        reveal.unobserve(e.target);
      });
    }, { threshold: 0.12, rootMargin: '0px 0px -6% 0px' });
    items.forEach(function (el) { reveal.observe(el); });
  } else {
    items.forEach(function (el) { el.classList.add('in'); });
  }

  /* ---------- Scroll: the nav's playhead and the hero's fan ---------- */

  var playhead = $('#playhead');
  var fan = $('#fan');
  var ticking = false;
  var mx = 0, my = 0;
  function paint() {
    ticking = false;
    var y = window.scrollY;
    var max = document.documentElement.scrollHeight - window.innerHeight;
    playhead.style.setProperty('--p', max > 0 ? (y / max).toFixed(4) : 0);
    if (!still) {
      var spread = Math.min(y / 500, 1);
      fan.style.setProperty('--spread', spread.toFixed(3));
      fan.style.setProperty('--mx', mx.toFixed(3));
      fan.style.setProperty('--my', my.toFixed(3));
    }
  }
  function schedule() { if (!ticking) { ticking = true; requestAnimationFrame(paint); } }
  window.addEventListener('scroll', schedule, { passive: true });
  window.addEventListener('resize', schedule, { passive: true });
  if (!still && window.matchMedia('(hover: hover)').matches) {
    window.addEventListener('pointermove', function (e) {
      mx = e.clientX / window.innerWidth - 0.5;
      my = e.clientY / window.innerHeight - 0.5;
      schedule();
    }, { passive: true });
  }
  paint();

  /* ---------- Hero: a prompt types itself and moves through the steps ---------- */

  var typed = $('#typed');
  var steps = $$('#stepper li');
  var promptRun = 0;

  function wait(ms, run) {
    return new Promise(function (res, rej) {
      setTimeout(function () { run === promptRun ? res() : rej(); }, ms);
    });
  }
  async function promptLoop(run) {
    var i = 0;
    for (;;) {
      var text = t('hero.p' + (i % 3 + 1)).replace(/&amp;/g, '&');
      var chars = Array.from(text);
      steps.forEach(function (s) { s.className = ''; });
      for (var c = 1; c <= chars.length; c++) {
        typed.textContent = chars.slice(0, c).join('');
        await wait(26 + Math.random() * 34, run);
      }
      await wait(500, run);
      for (var s = 0; s < steps.length; s++) {
        steps[s].className = 'now';
        await wait(1000, run);
        steps[s].className = 'done';
      }
      await wait(1400, run);
      for (var d = chars.length; d >= 0; d -= 2) {
        typed.textContent = chars.slice(0, Math.max(d, 0)).join('');
        await wait(12, run);
      }
      i++;
    }
  }
  function startPrompt() {
    promptRun++;
    if (still) {
      typed.textContent = t('hero.p1');
      steps.forEach(function (s) { s.className = 'done'; });
      return;
    }
    promptLoop(promptRun).catch(function () {});
  }
  startPrompt();
  document.addEventListener('ps-lang', startPrompt);

  /* ---------- How it works: the step nearest the middle sets the stage ---------- */

  var flowSteps = $$('.flow-step');
  var panels = $$('.panel');
  function showStep(n) {
    flowSteps.forEach(function (s, i) { s.classList.toggle('on', i === n); });
    panels.forEach(function (p, i) { p.classList.toggle('on', i === n); });
  }
  showStep(0);
  if (hasIO) {
    var stepper = new IntersectionObserver(function (entries) {
      entries.forEach(function (e) { if (e.isIntersecting) showStep(Number(e.target.dataset.step)); });
    }, { rootMargin: '-45% 0px -45% 0px' });
    flowSteps.forEach(function (s) { stepper.observe(s); });
  }

  /* ---------- Formats: the phone reshapes to each one ---------- */

  var device = $('#device');
  var ratio = $('#ratio');
  var tabs = $$('#fmt-tabs [role="tab"]');
  var ratios = { reel: '9:16', story: '9:16', post: '4:5', carousel: '4:5' };
  var fmtTimer = null;
  function showFormat(tab) {
    tabs.forEach(function (b) {
      var on = b === tab;
      b.setAttribute('aria-selected', String(on));
      b.tabIndex = on ? 0 : -1;
    });
    device.dataset.fmt = tab.dataset.fmt;
    ratio.textContent = ratios[tab.dataset.fmt];
    $('#fmt-panel').setAttribute('aria-labelledby', tab.id);
  }
  function stopAuto() { clearInterval(fmtTimer); fmtTimer = null; }
  showFormat(tabs[0]);
  tabs.forEach(function (b, i) {
    b.addEventListener('click', function () { stopAuto(); showFormat(b); });
    b.addEventListener('keydown', function (e) {
      var d = e.key === 'ArrowDown' || e.key === 'ArrowRight' ? 1 : e.key === 'ArrowUp' || e.key === 'ArrowLeft' ? -1 : 0;
      if (!d) return;
      e.preventDefault();
      stopAuto();
      var next = tabs[(i + d + tabs.length) % tabs.length];
      showFormat(next);
      next.focus();
    });
  });
  if (hasIO && !still) {
    new IntersectionObserver(function (entries) {
      var seen = entries[entries.length - 1].isIntersecting;
      if (seen && !fmtTimer && fmtTimer !== 0) {
        fmtTimer = setInterval(function () {
          var at = tabs.findIndex(function (b) { return b.getAttribute('aria-selected') === 'true'; });
          showFormat(tabs[(at + 1) % tabs.length]);
        }, 4200);
      } else if (!seen && fmtTimer) {
        clearInterval(fmtTimer);
        fmtTimer = null;
      }
    }, { threshold: 0.4 }).observe($('#formats'));
    $('#fmt-tabs').addEventListener('pointerdown', function () { stopAuto(); fmtTimer = 0; });
  }

  /* ---------- Planned posts: the plan runs, and stops where you said it should ---------- */

  var nodes = $$('#line li');
  var approve = $('#auto-approve');
  var post = $('#auto-post');
  var switches = { 'auto-approve': approve, 'auto-post': post };
  function gates() {
    nodes.forEach(function (n) {
      var g = n.dataset.gate;
      if (g) n.classList.toggle('held', !switches[g].checked);
    });
  }
  var planRun = 0;
  async function planLoop(run) {
    var pause = function (ms) {
      return new Promise(function (res, rej) {
        setTimeout(function () { run === planRun ? res() : rej(); }, ms);
      });
    };
    for (;;) {
      nodes.forEach(function (n) { n.classList.remove('done', 'now'); });
      await pause(500);
      for (var i = 0; i < nodes.length; i++) {
        var n = nodes[i];
        n.classList.add('now');
        await pause(n.dataset.gate && !switches[n.dataset.gate].checked ? 2600 : 1000);
        n.classList.remove('now');
        n.classList.add('done');
      }
      await pause(2200);
    }
  }
  function startPlan() {
    planRun++;
    gates();
    if (still) { nodes.forEach(function (n) { n.classList.add('done'); }); return; }
    planLoop(planRun).catch(function () {});
  }
  [approve, post].forEach(function (s) { s.addEventListener('change', startPlan); });
  if (hasIO && !still) {
    new IntersectionObserver(function (entries) {
      if (entries[entries.length - 1].isIntersecting) startPlan();
      else planRun++;
    }, { threshold: 0.3 }).observe($('#plan'));
  } else {
    startPlan();
  }

  /* ---------- Features: the light follows the pointer, the language tile cycles ---------- */

  if (!still && window.matchMedia('(hover: hover)').matches) {
    $$('[data-spot]').forEach(function (el) {
      el.addEventListener('pointermove', function (e) {
        var r = el.getBoundingClientRect();
        el.style.setProperty('--x', (e.clientX - r.left) + 'px');
        el.style.setProperty('--y', (e.clientY - r.top) + 'px');
      });
    });
  }

  var cycle = $('#lang-cycle');
  if (!still) {
    var hello = Object.keys(names).map(function (k) { return names[k]; });
    var at = 0;
    setInterval(function () {
      if (document.hidden) return;
      cycle.classList.add('out');
      setTimeout(function () {
        at = (at + 1) % hello.length;
        cycle.textContent = hello[at];
        cycle.classList.remove('out');
      }, 260);
    }, 1800);
  }
})();
