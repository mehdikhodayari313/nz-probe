<!-- بخشی از CLAUDE.md که برای کم کردن حجم بارگذاری هر جلسه جدا شد (۱۴۰۵/۰۸/۰۳). فقط وقتی لازم است بخوان. -->

## Build / test
- Since 1405/07/27 the cloud environment allows `storage.googleapis.com` and `pub.dev`, and the environment's
  Setup script installs Flutter stable in `/opt/flutter` (+ `libsqlite3-dev`; log `/var/log/flutter-setup.log`).
  **Run locally first:** `cd price_bank && flutter pub get && flutter analyze --no-fatal-infos --no-fatal-warnings && flutter test`
  (≈1.5 min for all tests). Afterwards `git checkout analysis_options.yaml` and delete `pubspec.lock` (pub get
  rewrites/creates them; do not commit). If `flutter` is missing, the setup script failed — read its log.
- Official Dart/Flutter MCP server is configured for the project (`.mcp.json` at repo root, enabled in
  `.claude/settings.json`): tools `analyze_files` (analyzer errors per file/root), `lsp` (hover, definition,
  symbols), `pub`, `pub_dev_search`, `read_package_uris`, `rip_grep_packages`. Runtime tools (hot reload, widget
  inspector, VM service, driver) are disabled — the Windows app cannot run here. It uses the real Dart binary
  `/opt/flutter/bin/cache/dart-sdk/bin/dart` (the `/opt/flutter/bin/dart` wrapper prints a root banner on stdout,
  which breaks MCP stdio). If Flutter is not installed, the server simply fails to start; use Bash instead.
- Windows build + exe smoke test still run only in GitHub Actions (`.github/workflows/price_bank.yml`), which also
  repeats Linux analyze + `flutter test`.
- Push to `main` (paths `price_bank/**`) triggers CI. Results are pushed to branches (artifact download is blocked):
  - `ci-pb-test`: `commit.txt`, `analyze.txt`, `test.txt`
  - `ci-pb-windows`: `smoke.txt` (`RESULT: OK`)
  - `ci-pb-dist`: `price_bank_windows.zip` + `commit.txt`
  Read with `git clone -q --depth 1 -b <branch> https://github.com/mehdikhodayari313/nz-probe <dir>`;
  check `commit.txt` == pushed SHA (test ≈4 min, Windows build ≈8–10 min after push).
- Quick failure scan: `grep -E " error |warning" analyze.txt; grep -n "\[E\]\|All tests\|Some tests" test.txt`.
- `gh` works in the sandbox (`gh run list/view/rerun`). Two pushes a few minutes apart run in parallel and both
  force-push the ci-pb-* branches; the OLDER run can finish last. Always compare `commit.txt` with the released SHA;
  if it differs, `gh run rerun <run-id>` of the final commit before taking the zip.
- Exe smoke test: `price_bank.exe --smoke <report> <db> [pumps v8 xlsx] [desalter bank xlsx] [compressor bank xlsx]` (CI passes
  all three fixtures; expects 146 pumps, 9 desalters, 10 compressors / 3 quotes / 4 peers).
- Current released version: **0.9.3** (1405/08/03, no source column lost: pump ΔP, leftover specs, unheaded/extra columns; zip on `price-bank-releases`).
- Releases/tags cannot be created from Claude sessions (403). Published builds live on branch
  **`price-bank-releases`** (`price_bank_vX.Y_windows.zip` + README table) — add each new version there.
- Commit trailer (always):
  `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>` + `Claude-Session: <session url>`.
- Bump the version label in `lib/ui/shell.dart` (`نسخه‌ی ۰٫X · آفلاین`) and the README header per release.
