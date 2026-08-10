// Show one language at a time, remembering the choice across the two pages.
//
// The page ships all four languages in the markup rather than fetching them,
// so it works offline, needs no build step, and a reader who lands here with
// JS disabled still sees every language instead of an empty page.
(function () {
  document.documentElement.classList.remove('no-js');

  var LANGS = ['ko', 'ja', 'en', 'zh'];
  var KEY = 'mykanji-lang';

  function pick() {
    var saved = null;
    try { saved = localStorage.getItem(KEY); } catch (e) { /* private mode */ }
    if (LANGS.indexOf(saved) >= 0) return saved;

    var tags = navigator.languages || [navigator.language || ''];
    for (var i = 0; i < tags.length; i++) {
      var tag = tags[i].toLowerCase();
      if (tag.indexOf('ko') === 0) return 'ko';
      if (tag.indexOf('ja') === 0) return 'ja';
      if (tag.indexOf('zh') === 0) return 'zh';
      if (tag.indexOf('en') === 0) return 'en';
    }
    return 'en';
  }

  function apply(lang) {
    var blocks = document.querySelectorAll('.l');
    for (var i = 0; i < blocks.length; i++) {
      blocks[i].classList.toggle('on', blocks[i].getAttribute('lang') === lang);
    }
    var buttons = document.querySelectorAll('nav.langs button');
    for (var j = 0; j < buttons.length; j++) {
      var mine = buttons[j].dataset.lang === lang;
      buttons[j].setAttribute('aria-current', mine ? 'true' : 'false');
    }
    // Screen readers and the browser's own translation prompt both read this.
    document.documentElement.lang = lang === 'zh' ? 'zh-Hans' : lang;
    try { localStorage.setItem(KEY, lang); } catch (e) { /* private mode */ }
  }

  document.addEventListener('click', function (event) {
    var button = event.target.closest('nav.langs button');
    if (button) apply(button.dataset.lang);
  });

  apply(pick());
})();
