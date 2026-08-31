(() => {
  'use strict';

  const content = document.getElementById('content');
  let lastText = '';
  let lineEls = [];
  let lineTops = null; // cached absolute tops, invalidated on layout changes
  let suppressScrollUntil = 0;
  let syncEnabled = false; // Swift enables this in Split mode only

  const isDark = () => window.matchMedia('(prefers-color-scheme: dark)').matches;

  mermaid.initialize({
    startOnLoad: false,
    theme: isDark() ? 'dark' : 'default',
    securityLevel: 'strict',
  });
  const mermaidCache = new Map();

  function hashString(s) {
    let h = 5381;
    for (let i = 0; i < s.length; i += 1) h = ((h << 5) + h + s.charCodeAt(i)) >>> 0;
    return h.toString(36) + '-' + s.length;
  }

  const md = window
    .markdownit({ html: false, linkify: true })
    .use(window.markdownitTaskLists)
    .use(window.markdownItKatex, { throwOnError: false });

  const escapeHtml = md.utils.escapeHtml;

  // Stamp source line numbers on block tokens for scroll sync.
  md.core.ruler.push('source_lines', (state) => {
    for (const token of state.tokens) {
      if (token.map && token.nesting !== -1 && token.type !== 'fence') {
        token.attrSet('data-line', String(token.map[0]));
      }
    }
    return true;
  });

  md.renderer.rules.fence = (tokens, idx) => {
    const token = tokens[idx];
    const info = (token.info || '').trim().split(/\s+/)[0];
    const lineAttr = token.map ? ` data-line="${token.map[0]}"` : '';
    if (info === 'mermaid') {
      const hash = hashString(token.content);
      return (
        `<div class="mermaid-diagram" data-hash="${hash}"${lineAttr}>` +
        `<pre class="mermaid-src" hidden>${escapeHtml(token.content)}</pre></div>\n`
      );
    }
    let body = null;
    if (info && window.hljs.getLanguage(info)) {
      try {
        body = window.hljs.highlight(token.content, { language: info, ignoreIllegals: true }).value;
      } catch (err) {
        body = null;
      }
    }
    if (body === null) body = escapeHtml(token.content);
    const cls = info ? ` language-${escapeHtml(info)}` : '';
    return `<pre${lineAttr}><code class="hljs${cls}">${body}</code></pre>\n`;
  };

  // Route relative image paths through the mdfile:// scheme so the app can
  // serve them from the document's folder.
  const defaultImage =
    md.renderer.rules.image || ((tokens, idx, options, env, self) => self.renderToken(tokens, idx, options));
  md.renderer.rules.image = (tokens, idx, options, env, self) => {
    const token = tokens[idx];
    const src = token.attrGet('src') || '';
    if (src && !/^[a-z][a-z0-9+.-]*:/i.test(src)) {
      token.attrSet('src', 'mdfile:///?p=' + encodeURIComponent(src));
    }
    return defaultImage(tokens, idx, options, env, self);
  };

  async function renderMermaid() {
    const nodes = content.querySelectorAll('.mermaid-diagram');
    for (const node of nodes) {
      const hash = node.dataset.hash;
      if (mermaidCache.has(hash)) {
        node.innerHTML = mermaidCache.get(hash);
        continue;
      }
      const srcEl = node.querySelector('.mermaid-src');
      if (!srcEl) continue;
      const src = srcEl.textContent;
      const renderId = 'mmd' + hash.replace(/[^a-z0-9]/gi, '') + Math.floor(Math.random() * 1e6);
      try {
        const { svg } = await mermaid.render(renderId, src);
        if (mermaidCache.size > 100) mermaidCache.clear();
        mermaidCache.set(hash, svg);
        node.innerHTML = svg;
        lineTops = null;
      } catch (err) {
        // mermaid can leave an orphaned scratch element behind on failure
        document.querySelectorAll('body > [id^="dmmd"]').forEach((el) => el.remove());
        const message = err && err.message ? err.message : String(err);
        node.innerHTML = `<div class="mermaid-error">Mermaid error: ${escapeHtml(message)}</div>`;
      }
    }
  }

  function rebuildLineMap() {
    lineEls = Array.from(content.querySelectorAll('[data-line]'))
      .map((el) => ({ line: Number(el.dataset.line), el }))
      .sort((a, b) => a.line - b.line);
    lineTops = null;
  }

  // One batched layout pass; scrolling then only binary-searches numbers
  // (repeated getBoundingClientRect during scroll causes visible jank).
  function tops() {
    if (lineTops === null) {
      const scrollY = window.scrollY;
      lineTops = lineEls.map(({ el }) => el.getBoundingClientRect().top + scrollY);
    }
    return lineTops;
  }

  function suppress(ms) {
    suppressScrollUntil = performance.now() + ms;
  }

  window.renderMarkdown = (text) => {
    lastText = text;
    const y = window.scrollY;
    content.innerHTML = md.render(text);
    rebuildLineMap();
    suppress(150);
    window.scrollTo(0, y);
    renderMermaid();
  };

  window.setSyncEnabled = (enabled) => {
    syncEnabled = !!enabled;
  };

  window.scrollToLine = (fracLine) => {
    if (!lineEls.length) return;
    suppress(150);
    const t = tops();
    let lo = 0;
    let hi = lineEls.length - 1;
    while (lo < hi) {
      const mid = (lo + hi + 1) >> 1;
      if (lineEls[mid].line <= fracLine) lo = mid;
      else hi = mid - 1;
    }
    const a = lineEls[lo];
    const aTop = t[lo];
    let y = aTop;
    if (lo + 1 < lineEls.length) {
      const b = lineEls[lo + 1];
      const k = Math.max(0, Math.min(1, (fracLine - a.line) / Math.max(1e-6, b.line - a.line)));
      y = aTop + k * (t[lo + 1] - aTop);
    } else {
      y = aTop + (fracLine - a.line) * 24;
    }
    window.scrollTo(0, Math.max(0, y - 16));
  };

  function reportScroll() {
    if (!lineEls.length) return;
    const t = tops();
    const target = window.scrollY + 16;
    let lo = 0;
    let hi = t.length - 1;
    while (lo < hi) {
      const mid = (lo + hi + 1) >> 1;
      if (t[mid] <= target) lo = mid;
      else hi = mid - 1;
    }
    const a = lineEls[lo];
    let frac = a.line;
    if (lo + 1 < lineEls.length && t[lo + 1] > t[lo]) {
      const k = Math.max(0, Math.min(1, (target - t[lo]) / (t[lo + 1] - t[lo])));
      frac = a.line + k * (lineEls[lo + 1].line - a.line);
    }
    if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.scrolled) {
      window.webkit.messageHandlers.scrolled.postMessage(frac);
    }
  }

  let scrollScheduled = false;
  window.addEventListener(
    'scroll',
    () => {
      if (!syncEnabled) return;
      if (performance.now() < suppressScrollUntil) return;
      if (scrollScheduled) return;
      scrollScheduled = true;
      requestAnimationFrame(() => {
        scrollScheduled = false;
        if (!syncEnabled) return;
        if (performance.now() < suppressScrollUntil) return;
        reportScroll();
      });
    },
    { passive: true }
  );

  // Anything that changes layout invalidates the cached positions.
  window.addEventListener('resize', () => {
    lineTops = null;
  });
  content.addEventListener(
    'load',
    () => {
      lineTops = null;
    },
    true
  );

  // Re-theme mermaid when the appearance flips.
  window.matchMedia('(prefers-color-scheme: dark)').addEventListener('change', () => {
    mermaid.initialize({
      startOnLoad: false,
      theme: isDark() ? 'dark' : 'default',
      securityLevel: 'strict',
    });
    mermaidCache.clear();
    if (lastText) window.renderMarkdown(lastText);
  });

  window.__ready = true;
  if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.ready) {
    window.webkit.messageHandlers.ready.postMessage(true);
  }
})();
