# MDReader

A native macOS markdown reader/editor. Open markdown files in tabs (filename on
the tab), view each as raw **Source**, rendered **Reader**, or side-by-side
**Split** with two-way synced scrolling, edit, and save.

Built with Swift + SwiftUI and **no Xcode required** — the whole project builds
with Command Line Tools via SwiftPM and a Makefile.

## Features

- **Tabs**: native macOS window tabs via `DocumentGroup` — dirty-dot,
  close-confirm, Cmd+S / Cmd+Shift+S / Cmd+O / Cmd+N / Cmd+W all standard.
- **Three view modes per tab**: Source (⌘1), Reader (⌘2), Split (⌘3) — toolbar
  segmented control or the View menu.
- **Source editor**: NSTextView with quiet markdown syntax highlighting,
  granular undo, smart-substitutions off, SF Mono.
- **Reader**: WKWebView rendering GFM (tables, task lists, strikethrough,
  autolinks), highlight.js code blocks, Mermaid diagrams, and KaTeX math —
  fully offline (all JS/CSS vendored). Raw HTML is escaped. Links open in your
  browser; relative images resolve against the document's folder.
- **Two-way scroll sync** in Split mode.
- **External change watching**: edits made on disk by other programs reload
  cleanly, or show a Reload / Keep-mine banner if you have unsaved edits.
- **Status bar**: line/column, word count, reading time.

## Build & run

Requires macOS 14+ and Xcode Command Line Tools (`xcode-select --install`).

```bash
make run        # build, assemble dist/MDReader.app, launch
make test       # full test suite (functionality + UI-component + webview)
make install    # install to /Applications and make MDReader the DEFAULT
                # app for .md/.markdown — double-click opens MDReader
make clean
```

Always launch the assembled app (`make run`), never the bare binary —
document handling needs the bundle's Info.plist.

## Layout

- `Sources/MDReaderKit/` — all logic and views (library, testable)
- `Sources/MDReader/` — `@main` app entry only
- `Sources/MDReaderKit/Resources/web/` — preview page + vendored libraries
- `Tests/MDReaderTests/` — Swift Testing suite (`make test`)
- `packaging/` — Info.plist, AppIcon.icns
- `scripts/` — vendor fetcher, icon generator, default-handler setter, test runner

## Upgrading the web libraries

Versions are pinned in `scripts/fetch-web-libs.sh` (markdown-it, KaTeX,
highlight.js, mermaid, @vscode/markdown-it-katex, github-markdown-css,
markdown-it-task-lists). Bump the pins, run the script, run `make test`
(the preview tests exercise the real pipeline), and commit the vendor output:

```bash
scripts/fetch-web-libs.sh && make test
```

Note: `@vscode/markdown-it-katex` is used instead of markdown-it-texmath
because texmath's `$` handling mangles prose like "$5 or $10"; the VS Code
plugin handles currency correctly (covered by `PreviewRenderTests`).

## Testing without Xcode

Command Line Tools ship Swift Testing but not XCTest, and SwiftPM doesn't wire
the framework up automatically — `scripts/test.sh` (used by `make test`)
passes the needed framework/plugin/rpath flags under CLT and falls back to
plain `swift test` when full Xcode is installed (e.g. on CI).

## CI

`.github/workflows/ci.yml` builds, tests, assembles, verifies the signature,
and uploads `MDReader.zip` as an artifact on every push/PR to `main`. The
artifact is a build-health check; install locally with `make install`
(a downloaded ad-hoc-signed app would be blocked by Gatekeeper).
