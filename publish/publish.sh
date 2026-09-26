#!/bin/bash
# Local arm64 Release build; no upload or installation.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
if [[ "${1:-}" == --help ]]; then
  echo 'Usage: ./publish/publish.sh [--check]'
  echo 'Build BangsBuddy DMG into publish/YYYY-MM-DD/HHMMSS-XXXXXX/.'
  exit 0
fi
[[ $# == 0 || ( $# == 1 && "$1" == --check ) ]] || { echo 'Unknown argument; use --help.' >&2; exit 1; }
if [[ -z "${DEVELOPER_DIR:-}" && -d /Applications/Xcode.app ]]; then
  export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
fi
for tool in xcodebuild xcrun python3 codesign hdiutil ditto; do
  command -v "$tool" >/dev/null || { echo "Missing tool: $tool" >&2; exit 1; }
done
[[ -f integrations/thaw/lock.json && -f integrations/thaw/build.py ]] || {
  echo 'Thaw integration sources are missing; cannot build a complete fusion DMG.' >&2; exit 1;
}
xcodebuild -version
if ! xcodebuild -checkFirstLaunchStatus; then
  echo 'Xcode initialization is incomplete. Review the license and complete setup in Terminal:' >&2
  printf 'sudo env DEVELOPER_DIR=%q xcodebuild -license\n' "${DEVELOPER_DIR:-$(xcode-select -p)}" >&2
  printf 'sudo env DEVELOPER_DIR=%q xcodebuild -runFirstLaunch\n' "${DEVELOPER_DIR:-$(xcode-select -p)}" >&2
  exit 1
fi
if ! xcrun --sdk macosx metal --version; then
  echo 'Metal compiler unavailable. Install the component, then rerun this script:' >&2
  printf 'env DEVELOPER_DIR=%q xcodebuild -downloadComponent MetalToolchain\n' "${DEVELOPER_DIR:-$(xcode-select -p)}" >&2
  exit 1
fi
# Fail before compilation if the checkout still contains LFS pointer files.
python3 - <<'PY'
from pathlib import Path
for root in ('DynamicIsland', 'Frameworks', 'LottieAnimations'):
    for p in Path(root).rglob('*'):
        if p.is_file():
            with p.open('rb') as f:
                if f.read(64).startswith(b'version https://git-lfs'):
                    raise SystemExit(f'LFS resource missing: {p}. Run git lfs pull first.')
PY
[[ "${1:-}" != --check ]] || { echo 'Preflight passed (dependencies and compilation not checked).'; exit 0; }
mkdir -p "$ROOT/publish/$(date +%F)"
OUT="$(mktemp -d "$ROOT/publish/$(date +%F)/$(date +%H%M%S)-XXXXXX")"
export OUT
exec > >(tee "$OUT/build.log") 2>&1
trap 'echo "Packaging failed. See $OUT/build.log" >&2' ERR
WORK="$OUT/work"
APP="$WORK/stage/BangsBuddy.app"
export APP
mkdir -p "$WORK/stage"
{ sw_vers; xcodebuild -version; uname -m; git rev-parse HEAD; } > "$OUT/environment.txt"
echo "Output: $OUT"
xcodebuild -resolvePackageDependencies -project DynamicIsland.xcodeproj -scheme DynamicIsland \
  -derivedDataPath "$WORK/DerivedData" -onlyUsePackageVersionsFromResolvedFile
xcodebuild build -project DynamicIsland.xcodeproj -scheme DynamicIsland -configuration Release \
  -destination 'platform=macOS,arch=arm64' -derivedDataPath "$WORK/DerivedData" \
  -disableAutomaticPackageResolution ARCHS=arm64 ONLY_ACTIVE_ARCH=YES \
  CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM='' CODE_SIGN_IDENTITY='-' \
  CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=YES CODE_SIGN_INJECT_BASE_ENTITLEMENTS=NO \
  OTHER_CODE_SIGN_FLAGS='--timestamp=none'
ditto "$WORK/DerivedData/Build/Products/Release/ToolIsle.app" "$APP"
python3 -B integrations/thaw/build.py --output "$APP/Contents/Helpers/Thaw.app"
codesign -d --entitlements :- "$APP" > "$OUT/entitlements.plist"
python3 - <<'PY'
import hashlib, json, os, plistlib, shutil, subprocess
from pathlib import Path
app=Path(os.environ['APP']); out=Path(os.environ['OUT'])
p=app/'Contents/Info.plist'; info=plistlib.loads(p.read_bytes())
entitlements=plistlib.loads((out/'entitlements.plist').read_bytes())
if entitlements.get('com.apple.security.get-task-allow'):
    raise SystemExit('Release build permits debugger attachment')
thaw=plistlib.loads((app/'Contents/Helpers/Thaw.app/Contents/Info.plist').read_bytes())
lock=json.loads(Path('integrations/thaw/lock.json').read_text())
patch_digest=hashlib.sha256(Path('integrations/thaw',lock['patch']).read_bytes()).hexdigest()
if (thaw['CFBundleIdentifier']!=lock['bundle_identifier']
    or thaw['CFBundleShortVersionString']!=lock['version']
    or thaw.get('ToolIsleManagedComponent') is not True
    or thaw.get('ToolIsleThawCommit')!=lock['commit']
    or thaw.get('ToolIsleThawPatchSHA256')!=patch_digest):
    raise SystemExit('Embedded Thaw does not match the integration recipe; rebuild the complete package')
# Preserve the executable, bundle identifier, entitlements and internal protocols.
for key in ('CFBundleName','CFBundleDisplayName'):
    info[key]='BangsBuddy'
for key,value in list(info.items()):
    if key.startswith('NS') and key.endswith('UsageDescription') and isinstance(value,str):
        info[key]=value.replace('ToolIsle','BangsBuddy')
p.write_bytes(plistlib.dumps(info))
r=app/'Contents/Resources'
for p in r.glob('*.lproj/InfoPlist.strings'):
    data=plistlib.loads(subprocess.check_output(['plutil','-convert','xml1','-o','-',str(p)]))
    for key in ('CFBundleName','CFBundleDisplayName'):
        data[key]='BangsBuddy'
    for key,value in list(data.items()):
        if key.endswith('UsageDescription') and isinstance(value,str):
            data[key]=value.replace('ToolIsle','BangsBuddy')
    p.write_bytes(plistlib.dumps(data,fmt=plistlib.FMT_BINARY))
movies=list(Path('DynamicIsland/BluetoothHUDAnimations').glob('*.mov'))
assert movies, 'Bluetooth animation resources missing'
(r/'BluetoothHUDAnimations').mkdir(exist_ok=True)
for p in movies:
    shutil.copy2(p,r/p.name)
    shutil.copy2(p,r/'BluetoothHUDAnimations'/p.name)
(out/'package.json').write_text(json.dumps({
    'name':'BangsBuddy','version':info['CFBundleShortVersionString'],
    'build':info['CFBundleVersion'],'bundle_id':info['CFBundleIdentifier'],
    'executable':info['CFBundleExecutable'],'architecture':'arm64','notarized':False,
    'source_commit':subprocess.check_output(['git','rev-parse','HEAD'],text=True).strip(),
    'source_state':'Built from local working tree, including uncommitted source changes',
    'source_dirty':bool(subprocess.check_output(['git','status','--porcelain'],text=True).strip()),
    'thaw':{'version':lock['version'],'commit':lock['commit'],
            'bundle_id':lock['bundle_identifier'],'archive_sha256':lock['archive_sha256'],
            'patch_sha256':thaw['ToolIsleThawPatchSHA256']}
},ensure_ascii=False,indent=2)+'\n')
PY
codesign --force --sign - --timestamp=none --options runtime --entitlements "$OUT/entitlements.plist" "$APP"
codesign --verify --deep --strict --verbose=2 "$APP"
cp LICENSE NOTICE COPYRIGHT_ASSETS "$WORK/stage/"
cp integrations/thaw/README.md "$WORK/stage/Thaw-integration.md"
cp docs/publishing.md "$WORK/stage/README.md"
ln -s /Applications "$WORK/stage/Applications"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist")"
BUILD="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$APP/Contents/Info.plist")"
DMG="BangsBuddy-${VERSION}-${BUILD}-arm64.dmg"
hdiutil create -volname BangsBuddy -srcfolder "$WORK/stage" -format UDZO "$OUT/$DMG"
hdiutil verify "$OUT/$DMG"
(cd "$OUT" && shasum -a 256 "$DMG" > SHA256SUMS.txt)
# Only remove this run's intermediate files, after successful verification.
rm -rf "$WORK"
echo "Done: $OUT/$DMG"
