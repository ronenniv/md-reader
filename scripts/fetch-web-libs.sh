#!/usr/bin/env bash
# Fetches the pinned web libraries used by the preview pane into the vendor
# directory. The output is COMMITTED to git so builds are offline and
# reproducible — re-run this script only to upgrade versions.
set -euo pipefail
cd "$(dirname "$0")/.."

VENDOR="Sources/MDReaderKit/Resources/web/vendor"
CDN="https://cdn.jsdelivr.net/npm"

MARKDOWN_IT=15.0.1
TASK_LISTS=2.1.1
MDIT_KATEX=1.1.2
KATEX=0.18.4
HLJS=11.12.0
MERMAID=11.17.2
GH_MD_CSS=5.9.0

rm -rf "$VENDOR"
mkdir -p "$VENDOR"/{markdown-it,markdown-it-task-lists,markdown-it-katex,katex,highlightjs,mermaid,github-markdown-css}

fetch() {
  echo "  fetching $2"
  curl -fsSL "$1" -o "$2"
}

fetch "$CDN/markdown-it@$MARKDOWN_IT/dist/browser/markdown-it.umd.min.js" "$VENDOR/markdown-it/markdown-it.umd.min.js"
fetch "$CDN/markdown-it-task-lists@$TASK_LISTS/dist/markdown-it-task-lists.min.js" "$VENDOR/markdown-it-task-lists/markdown-it-task-lists.min.js"
# @vscode/markdown-it-katex ships CommonJS only; wrap it in an IIFE with a
# minimal require/exports shim so it loads as a plain <script> and exposes
# window.markdownItKatex. Its sole dependency is katex (window.katex).
echo "  fetching @vscode/markdown-it-katex $MDIT_KATEX (wrapping CJS for the browser)"
CJS=$(mktemp)
curl -fsSL "$CDN/@vscode/markdown-it-katex@$MDIT_KATEX/dist/index.js" -o "$CJS"
{
  printf '(function () {\nvar exports = {};\nvar module = { exports: exports };\nvar require = function (name) {\n  if (name === "katex") return window.katex;\n  throw new Error("unknown module: " + name);\n};\n'
  cat "$CJS"
  printf '\nwindow.markdownItKatex = module.exports.default || module.exports;\n})();\n'
} > "$VENDOR/markdown-it-katex/markdown-it-katex.browser.js"
rm -f "$CJS"
fetch "$CDN/@highlightjs/cdn-assets@$HLJS/highlight.min.js" "$VENDOR/highlightjs/highlight.min.js"
fetch "$CDN/@highlightjs/cdn-assets@$HLJS/styles/github.min.css" "$VENDOR/highlightjs/github.min.css"
fetch "$CDN/@highlightjs/cdn-assets@$HLJS/styles/github-dark.min.css" "$VENDOR/highlightjs/github-dark.min.css"
fetch "$CDN/mermaid@$MERMAID/dist/mermaid.min.js" "$VENDOR/mermaid/mermaid.min.js"
fetch "$CDN/github-markdown-css@$GH_MD_CSS/github-markdown.css" "$VENDOR/github-markdown-css/github-markdown.css"

# KaTeX must include its fonts for offline math rendering — pull the npm tarball.
echo "  fetching katex $KATEX (tarball incl. fonts)"
TMP=$(mktemp -d)
curl -fsSL "https://registry.npmjs.org/katex/-/katex-$KATEX.tgz" -o "$TMP/katex.tgz"
tar -xzf "$TMP/katex.tgz" -C "$TMP"
cp "$TMP/package/dist/katex.min.js" "$VENDOR/katex/"
cp "$TMP/package/dist/katex.min.css" "$VENDOR/katex/"
cp -R "$TMP/package/dist/fonts" "$VENDOR/katex/fonts"
rm -rf "$TMP"

cat > "$VENDOR/VERSIONS.txt" <<EOF
markdown-it $MARKDOWN_IT
markdown-it-task-lists $TASK_LISTS
@vscode/markdown-it-katex $MDIT_KATEX (wrapped CJS->browser global markdownItKatex)
katex $KATEX
highlight.js $HLJS (cdn-assets common-languages build)
mermaid $MERMAID
github-markdown-css $GH_MD_CSS
fetched $(date -u +%Y-%m-%dT%H:%M:%SZ)
EOF

echo "done. vendor size: $(du -sh "$VENDOR" | cut -f1)"
