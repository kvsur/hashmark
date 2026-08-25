(function () {
  'use strict';

  var scriptPromises = Object.create(null);
  var katexReady = null;
  var renderGeneration = 0;

  marked.setOptions({ gfm: true, breaks: false });

  function loadScript(source) {
    if (scriptPromises[source]) return scriptPromises[source];
    scriptPromises[source] = new Promise(function (resolve, reject) {
      var script = document.createElement('script');
      script.src = source;
      script.async = true;
      script.onload = resolve;
      script.onerror = function () { reject(new Error('Unable to load ' + source)); };
      document.head.appendChild(script);
    });
    return scriptPromises[source];
  }

  async function ensureKatex(markdown) {
    // Avoid parsing the KaTeX bundle for ordinary documents that contain no math delimiters.
    if (!markdown.includes('$')) return;
    if (!katexReady) {
      katexReady = loadScript('katex.min.js')
        .then(function () { return loadScript('marked-katex.umd.js'); })
        .then(function () {
          marked.use(markedKatex({
            throwOnError: false,
            strict: 'ignore',
            trust: false,
            // CJK prose does not normally put spaces around math delimiters.
            // Accept forms such as `$a$、$b$` and display math embedded in a paragraph.
            nonStandard: true
          }));
        });
    }
    await katexReady;
  }

  function highlightCode(root) {
    root.querySelectorAll('pre code:not(.language-mermaid)').forEach(function (block) {
      try { hljs.highlightElement(block); } catch (error) {}
    });
  }

  async function renderMermaid(root, generation) {
    var candidates = Array.from(root.querySelectorAll('pre code.language-mermaid'));
    if (!candidates.length) return;

    await loadScript('mermaid.min.js');
    if (generation !== renderGeneration) return;

    var isDark = window.matchMedia('(prefers-color-scheme: dark)').matches;
    mermaid.initialize({
      startOnLoad: false,
      securityLevel: 'strict',
      suppressErrorRendering: true,
      theme: isDark ? 'dark' : 'default',
      htmlLabels: false,
      flowchart: { useMaxWidth: true, htmlLabels: false }
    });

    var nodes = [];
    var fallbacks = [];
    for (var index = 0; index < candidates.length; index += 1) {
      if (generation !== renderGeneration) return;
      var code = candidates[index];
      var source = code.textContent || '';
      var valid = false;
      try {
        valid = Boolean(await mermaid.parse(source, { suppressErrors: true }));
      } catch (error) {}
      // Invalid diagrams stay as readable fenced code instead of becoming a broken empty panel.
      if (!valid || !code.parentElement) continue;

      var pre = code.parentElement;
      var host = document.createElement('div');
      host.className = 'mermaid';
      host.textContent = source;
      pre.replaceWith(host);
      nodes.push(host);
      fallbacks.push(pre);
    }

    if (!nodes.length || generation !== renderGeneration) return;
    try {
      await mermaid.run({ nodes: nodes, suppressErrors: true });
      if (generation === renderGeneration && window.MermaidViewer) {
        window.MermaidViewer.enhance(nodes);
      }
    } catch (error) {
      nodes.forEach(function (node, index) {
        if (node.isConnected) node.replaceWith(fallbacks[index]);
      });
    }
  }

  async function render(root, markdown, options) {
    options = options || {};
    var generation = ++renderGeneration;
    var source = markdown || '';

    // A source edit replaces the diagram DOM. Return any SVG currently shown in the viewer first.
    if (window.MermaidViewer) window.MermaidViewer.close();

    try { await ensureKatex(source); } catch (error) {}
    if (generation !== renderGeneration) return null;

    root.innerHTML = marked.parse(source);
    if (options.highlight !== false) highlightCode(root);

    // KaTeX fonts influence both formula height and Mermaid label measurement.
    if (document.fonts && document.fonts.ready) await document.fonts.ready;
    if (generation !== renderGeneration) return null;

    if (options.mermaid !== false) {
      try { await renderMermaid(root, generation); } catch (error) {}
    }
    if (generation !== renderGeneration) return null;

    return Math.ceil(document.documentElement.scrollHeight);
  }

  window.MarkdownRenderer = { render: render };
})();
