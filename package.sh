#!/usr/bin/env bash
# Build the Windows release package: deploy/dist/InventorySystem-<YYYY.MM.DD>.zip
#
# Usage: ./deploy/package.sh [--allow-dirty] [--compress=<max|none>]
#   --allow-dirty     package even if Backend/ or Frontend/ has uncommitted changes
#   --compress=max    smallest zip (zip -9, slower)
#   --compress=none   store files uncompressed (zip -0, fastest, biggest)
#   (no --compress)   zip's default level (-6)
#
# Needs: dotnet (SDK 9+), dotnet-ef, npm, zip, git. Runs on Linux; the output only runs on Windows x64.
# Secrets never enter the package: the dev appsettings.json and Frontend .env are left out, and
# tools\Setup.bat writes fresh ones on the office PC.
set -euo pipefail

deploy="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
root="$(dirname "$deploy")"
backend="$root/Backend"
frontend="$root/Frontend"

die() {
  echo "package.sh: $*" >&2
  exit 1
}

allow_dirty=false
zip_level=-6
for arg in "$@"; do
  case "$arg" in
  --allow-dirty) allow_dirty=true ;;
  --compress=max) zip_level=-9 ;;
  --compress=none) zip_level=-0 ;;
  *) die "unknown option '$arg' (see the usage at the top of this script)" ;;
  esac
done

step() {
  echo
  echo "==> $*"
}

for tool in dotnet npm zip git; do
  command -v "$tool" >/dev/null || die "'$tool' is not installed"
done
dotnet ef --version >/dev/null 2>&1 || die "'dotnet-ef' is not installed (dotnet tool install --global dotnet-ef)"

for repo in "$backend" "$frontend"; do
  if [[ -n "$(git -C "$repo" status --porcelain)" ]] && ! $allow_dirty; then
    die "$(basename "$repo") has uncommitted changes; commit them or pass --allow-dirty"
  fi
done

# The package ships the committed installation-manual.pdf, so it must be built from the current
# sources. Checked before the long build so a stale PDF fails fast.
manual_pdf="docs/installation-manual.pdf"
[[ "$(git -C "$deploy" rev-parse --is-shallow-repository)" == false ]] ||
  die "deploy/ is a shallow clone; the manual check needs the full history (fetch-depth: 0)"
for src in docs/installation-manual.typ docs/capstone-style.typ; do
  stale="$manual_pdf is older than $src; run 'typst compile docs/installation-manual.typ' in deploy/ and commit the PDF"
  if [[ -n "$(git -C "$deploy" status --porcelain -- "$src" "$manual_pdf")" ]]; then
    # Edited but not committed: only the file times can tell.
    [[ "$deploy/$manual_pdf" -nt "$deploy/$src" ]] || die "$stale"
  else
    # Committed: the PDF's last commit must not come before the source's last commit.
    src_commit="$(git -C "$deploy" log -1 --format=%H -- "$src")"
    pdf_commit="$(git -C "$deploy" log -1 --format=%H -- "$manual_pdf")"
    [[ -n "$pdf_commit" ]] || die "$manual_pdf is not committed"
    if [[ "$src_commit" != "$pdf_commit" ]] && git -C "$deploy" merge-base --is-ancestor "$pdf_commit" "$src_commit"; then
      die "$stale"
    fi
  fi
done

backend_version="$(sed -n 's:.*<Version>\(.*\)</Version>.*:\1:p' "$backend/ERP.csproj" | head -1)"
frontend_version="$(sed -n 's/^  "version": "\(.*\)",$/\1/p' "$frontend/package.json")"
[[ -n "$backend_version" && -n "$frontend_version" ]] || die "could not read the app versions"

date_tag="$(date +%Y.%m.%d)"
name="InventorySystem-$date_tag"
build="$deploy/build"
stage="$build/$name"
dist="$deploy/dist"

step "Cleaning $build"
rm -rf "$build"
mkdir -p "$stage" "$dist"

# --- Backend --------------------------------------------------------------------------------------
# Build from the committed tree (git archive), so local edits and the dev appsettings.json never
# reach the package. The copy gets the placeholder template as its appsettings.json.
step "Exporting Backend $backend_version"
src="$build/src/Backend"
mkdir -p "$src"
if $allow_dirty; then
  # Working tree as-is, minus build output and dumps.
  tar -C "$backend" --exclude=./bin --exclude=./obj --exclude='*.backup' -cf - . | tar -C "$src" -xf -
else
  git -C "$backend" archive HEAD | tar -C "$src" -xf -
fi
cp "$deploy/config/appsettings.template.json" "$src/appsettings.json"
rm -f "$src/appsettings.Development.json"

step "Publishing Backend (win-x64, self-contained)"
dotnet publish "$src/ERP.csproj" -c Release -r win-x64 --self-contained true \
  -p:DebugType=None -p:DebugSymbols=false -o "$stage/backend" -clp:ErrorsOnly
# Setup.bat writes the real appsettings.json; ship none.
rm -f "$stage/backend/appsettings.json" "$stage/backend/appsettings.Development.json" "$stage/backend/dotnet-tools.json"

step "Building the database migration tool (migrate.exe)"
mkdir -p "$stage/database"
# The win-x64 publish left a RID-specific restore in obj/; dotnet ef needs the plain one.
dotnet restore "$src/ERP.csproj" -v quiet
dotnet ef migrations bundle --project "$src/ERP.csproj" --startup-project "$src/ERP.csproj" \
  --configuration Release --target-runtime win-x64 --self-contained \
  --output "$stage/database/migrate.exe" --force

# --- Frontend -------------------------------------------------------------------------------------
# next build writes into the dev tree's .next/; the dirty check above keeps it equal to HEAD.
step "Building Frontend $frontend_version"
(cd "$frontend" && npm run build)
mkdir -p "$stage/frontend"
cp -a "$frontend/.next/standalone/." "$stage/frontend/"
mkdir -p "$stage/frontend/.next"
cp -a "$frontend/.next/static" "$stage/frontend/.next/static"
cp -a "$frontend/public" "$stage/frontend/public"
# Next copies .env files into standalone; the start script sets the environment itself.
rm -f "$stage/frontend"/.env*
# sharp is a Linux build and image optimisation is off, so it is never loaded on Windows.
rm -rf "$stage/frontend/node_modules/sharp" "$stage/frontend/node_modules/@img"

# --- Scripts and config ---------------------------------------------------------------------------
step "Copying scripts (CRLF line endings)"
to_crlf() { sed 's/\r$//; s/$/\r/' "$1" >"$2"; }
mkdir -p "$stage/tools" "$stage/config"
for f in "$deploy/windows/"*.bat; do
  to_crlf "$f" "$stage/$(basename "$f")"
done
for f in "$deploy/windows/tools/"*; do
  to_crlf "$f" "$stage/tools/$(basename "$f")"
done
cp "$deploy/config/appsettings.template.json" "$stage/config/"

# The committed PDF; rebuild it with `typst compile docs/installation-manual.typ` after editing the manual.
step "Copying the installation manual"
cp "$deploy/docs/installation-manual.pdf" "$stage/Installation Manual.pdf"

{
  echo "Inventory System"
  echo "Backend  $backend_version"
  echo "Frontend $frontend_version"
  echo "Built    $(date '+%Y-%m-%d %H:%M')"
} | sed 's/$/\r/' >"$stage/VERSION.txt"

# --- Checks ---------------------------------------------------------------------------------------
step "Checking the package"
[[ -f "$stage/backend/ERP.exe" ]] || die "backend/ERP.exe is missing"
[[ -f "$stage/frontend/server.js" ]] || die "frontend/server.js is missing"
[[ -f "$stage/database/migrate.exe" ]] || die "database/migrate.exe is missing"
[[ -f "$stage/Installation Manual.pdf" ]] || die "Installation Manual.pdf is missing"
[[ ! -e "$stage/backend/appsettings.json" ]] || die "backend/appsettings.json must not ship"
compgen -G "$stage/frontend/.env*" >/dev/null && die "a frontend .env file must not ship"

# Native Windows libraries the app loads at run time (QuestPDF for reports, ML.NET for the forecast).
for lib in QuestPdfSkia.dll qpdf.dll MklImports.dll MklProxyNative.dll; do
  [[ -f "$stage/backend/$lib" ]] || die "backend/$lib is missing (native win-x64 library)"
done

# No secret from the dev machine may be in the package.
dev_settings="$backend/appsettings.json"
if [[ -f "$dev_settings" ]]; then
  jwt_key="$(sed -n 's/.*"Key": *"\([^"]*\)".*/\1/p' "$dev_settings")"
  db_password="$(sed -n 's/.*Password=\([^;"]*\).*/\1/p' "$dev_settings")"
  [[ -n "$jwt_key" ]] && grep -rqF -- "$jwt_key" "$stage" && die "the dev JWT key leaked into the package"
  [[ -n "$db_password" ]] && grep -rqF -- "Password=$db_password;" "$stage" && die "the dev DB password leaked into the package"
fi

step "Zipping ($zip_level)"
zip_file="$dist/$name.zip"
rm -f "$zip_file"
(cd "$build" && zip -qr "$zip_level" "$zip_file" "$name")

echo
echo "Done: $zip_file ($(du -h "$zip_file" | cut -f1))"
echo "Backend $backend_version, Frontend $frontend_version"
