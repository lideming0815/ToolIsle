#!/usr/bin/env python3
"""Build and check the pinned Thaw helper without opening its UI."""

import argparse
import fcntl
import hashlib
import json
import os
import posixpath
from pathlib import Path
import plistlib
import shutil
import subprocess
import sys
import tarfile


HERE = Path(__file__).resolve().parent
ROOT = HERE.parent.parent
CACHE = ROOT / ".build" / "thaw"
LOCK = json.loads((HERE / "lock.json").read_text())
PATCH = HERE / LOCK["patch"]


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def run(*args, cwd=None, env=None, stdout=None):
    print("+ " + " ".join(map(str, args)), flush=True)
    subprocess.run(list(map(str, args)), cwd=cwd, env=env, stdout=stdout, check=True)


def assert_recipe_unchanged(recipe):
    for name, contents in recipe.items():
        if (HERE / name).read_bytes() != contents:
            raise RuntimeError(f"Thaw recipe changed during the build ({name}); rebuild before packaging.")


def assert_restricted_entitlements(contents, component):
    entitlements = plistlib.loads(contents) if contents else {}
    for key in ("com.apple.security.get-task-allow", "com.apple.security.cs.disable-library-validation"):
        if entitlements.get(key):
            raise RuntimeError(f"Release component has forbidden entitlement {key}: {component}")


def assert_no_sparkle(app, env):
    executable = app / "Contents/MacOS/Thaw"
    libraries = subprocess.run(["xcrun", "otool", "-L", str(executable)],
                               env=env, capture_output=True, text=True, check=True).stdout
    if "sparkle.framework" in libraries.lower() or (app / "Contents/Frameworks/Sparkle.framework").exists():
        raise RuntimeError("Managed helper must neither link nor embed Sparkle.")


def check_launch(app):
    try:
        result = subprocess.run([str(app / "Contents/MacOS/Thaw"), "--toolisle-launch-check"],
                                capture_output=True, text=True, timeout=15)
    except subprocess.TimeoutExpired as error:
        raise RuntimeError("Signed helper launch check timed out before packaging.") from error
    if result.returncode != 0 or result.stdout.strip() != "ToolIsle Thaw launch check passed":
        raise RuntimeError(f"Signed helper launch check failed (exit {result.returncode}): "
                           f"{result.stdout.strip()} {result.stderr.strip()}")


def prepare(recipe):
    CACHE.mkdir(parents=True, exist_ok=True)
    archive = CACHE / "upstream.tar.gz"
    if not archive.exists():
        pending = CACHE / "upstream.tar.gz.download"
        run("curl", "--fail", "--location", "--show-error", "--max-time", "180",
            LOCK["archive_url"], "--output", pending)
        if digest(pending) != LOCK["archive_sha256"]:
            raise RuntimeError("Downloaded Thaw archive differs from lock.json; refusing to build.")
        pending.replace(archive)
    if digest(archive) != LOCK["archive_sha256"]:
        raise RuntimeError("Cached Thaw archive differs from lock.json; refusing to build.")

    source = CACHE / "source"
    # Always reconstruct both trees: manual cache edits must never reach a DMG.
    # Only downloaded dependencies and DerivedData are reused between builds.
    if source.exists():
        shutil.rmtree(source)
    source.mkdir()
    # Upstream fuzzing fixtures use relative links to the real parser.
    # Permit only members and links that remain below the archive root.
    with tarfile.open(archive, "r:gz") as tar:
        members = tar.getmembers()
        for item in members:
            path = Path(item.name)
            if path.is_absolute() or ".." in path.parts:
                raise RuntimeError(f"Unsafe source archive member: {item.name}")
            if item.issym() or item.islnk():
                target = posixpath.normpath(posixpath.join(posixpath.dirname(item.name), item.linkname)
                                           if item.issym() else item.linkname)
                if target.startswith("/") or Path(target).parts[0] != path.parts[0]:
                    raise RuntimeError(f"Unsafe source archive link: {item.name}")
        run("tar", "-xzf", archive, "--strip-components=1", "-C", source)
    work = CACHE / "work"
    if work.exists():
        shutil.rmtree(work)
    shutil.copytree(source, work, symlinks=True)
    # Apply from the repository root so Git does not omit paths below .build.
    # Use the captured bytes, so an editor cannot change the patch as Git reads it.
    frozen_patch = CACHE / "distribution.patch"
    frozen_patch.write_bytes(recipe[PATCH.name])
    directory = str(work.relative_to(ROOT))
    run("git", "apply", "--check", "--directory=" + directory, frozen_patch, cwd=ROOT)
    run("git", "apply", "--directory=" + directory, frozen_patch, cwd=ROOT)
    return work, archive


def build(work, archive, output, recipe):
    env = os.environ.copy()
    if not env.get("DEVELOPER_DIR") and Path("/Applications/Xcode.app").exists():
        env["DEVELOPER_DIR"] = "/Applications/Xcode.app/Contents/Developer"
    run("xcodebuild", "-version", env=env)
    run("xcodebuild", "-checkFirstLaunchStatus", env=env)
    derived = CACHE / "DerivedData"
    common = ["-project", work / "Thaw.xcodeproj", "-scheme", "Thaw",
              "-derivedDataPath", derived]
    run("xcodebuild", "-resolvePackageDependencies", *common,
        "-onlyUsePackageVersionsFromResolvedFile", env=env)
    # Reconstruct the bundle so a cached product cannot retain removed frameworks.
    # Keep DerivedData's compilation and package caches for incremental builds.
    product = derived / "Build/Products/Release/Thaw.app"
    if product.exists():
        shutil.rmtree(product)
    run("xcodebuild", "build", *common, "-configuration", "Release",
        "-destination", "platform=macOS,arch=arm64", "-disableAutomaticPackageResolution",
        "ARCHS=arm64", "ONLY_ACTIVE_ARCH=YES", "CODE_SIGN_STYLE=Manual",
        "DEVELOPMENT_TEAM=", "CODE_SIGN_IDENTITY=-", "CODE_SIGNING_REQUIRED=NO",
        "CODE_SIGNING_ALLOWED=YES", "CODE_SIGN_INJECT_BASE_ENTITLEMENTS=NO",
        "OTHER_CODE_SIGN_FLAGS=--timestamp=none",
        "SWIFT_ACTIVE_COMPILATION_CONDITIONS=$(inherited) TOOLISLE_MANAGED",
        "TOOLISLE_THAW_UPSTREAM_COMMIT=" + LOCK["commit"], env=env)
    assert_recipe_unchanged(recipe)
    if digest(archive) != LOCK["archive_sha256"]:
        raise RuntimeError("Thaw source archive changed during the build; refusing to package.")
    assert_no_sparkle(product, env)
    info_path = product / "Contents/Info.plist"
    info = plistlib.loads(info_path.read_bytes())
    if info.get("CFBundleIdentifier") != LOCK["bundle_identifier"]:
        raise RuntimeError("Unexpected helper bundle identifier.")
    if info.get("CFBundleShortVersionString") != LOCK["version"]:
        raise RuntimeError("Unexpected helper version.")
    if info.get("ToolIsleManagedComponent") is not True:
        raise RuntimeError("Helper does not carry the integrated distribution marker.")
    xpc = product / "Contents/XPCServices/MenuBarItemService.xpc/Contents/Info.plist"
    if plistlib.loads(xpc.read_bytes()).get("CFBundleIdentifier") != LOCK["xpc_bundle_identifier"]:
        raise RuntimeError("Unexpected internal XPC bundle identifier.")

    output = output.resolve()
    if output.suffix != ".app" or output == product.resolve():
        raise RuntimeError("--output must be a separate .app bundle path.")
    if output.exists():
        existing = output / "Contents/Resources/ToolIsleIntegration/lock.json"
        if not existing.is_file() or json.loads(existing.read_text()) != LOCK:
            raise RuntimeError("Refusing to replace an app not built from this integration lock.")
        shutil.rmtree(output)
    output.parent.mkdir(parents=True, exist_ok=True)
    run("ditto", product, output)
    resources = output / "Contents/Resources/ToolIsleIntegration"
    resources.mkdir(exist_ok=True)
    for name, contents in recipe.items():
        (resources / name).write_bytes(contents)
    shutil.copy2(CACHE / "source/LICENSE", resources / "UPSTREAM-LICENSE")
    shutil.copy2(archive, resources / "upstream.tar.gz")
    # Xcode's generated Info.plist phase can run after upstream's stamp phase.
    info.update(GitCommitSHA=LOCK["commit"] + "-toolisle",
                ToolIsleThawCommit=LOCK["commit"],
                ToolIsleThawPatchSHA256=hashlib.sha256(recipe[PATCH.name]).hexdigest())
    (output / "Contents/Info.plist").write_bytes(plistlib.dumps(info))

    entitlements = CACHE / "helper-entitlements.plist"
    with entitlements.open("wb") as stream:
        run("codesign", "-d", "--entitlements", ":-", product, stdout=stream)
    entitlement_arguments = ["--entitlements", entitlements] if entitlements.stat().st_size else []
    assert_restricted_entitlements(entitlements.read_bytes(), product)
    run("codesign", "--force", "--sign", "-", "--timestamp=none", "--options", "runtime",
        *entitlement_arguments, output)
    run("codesign", "--verify", "--deep", "--strict", "--verbose=2", output)
    for component in (output, output / "Contents/XPCServices/MenuBarItemService.xpc"):
        signed = subprocess.run(["codesign", "-d", "--entitlements", ":-", str(component)],
                                capture_output=True, check=True).stdout
        assert_restricted_entitlements(signed, component)
        signature = subprocess.run(["codesign", "-d", "--verbose=4", str(component)],
                                   capture_output=True, text=True, check=True).stderr
        if not any("runtime" in line for line in signature.splitlines() if line.startswith("CodeDirectory")):
            raise RuntimeError(f"Release component lacks hardened runtime: {component}")
    assert_no_sparkle(output, env)
    check_launch(output)
    assert_recipe_unchanged(recipe)
    print(f"Helper ready: {output}")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--prepare-only", action="store_true", help="Verify and patch sources without compiling")
    parser.add_argument("--output", type=Path, default=CACHE / "products/Thaw.app")
    args = parser.parse_args()
    CACHE.mkdir(parents=True, exist_ok=True)
    with (CACHE / "build.lock").open("a") as lock_file:
        try:
            fcntl.flock(lock_file, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError:
            raise RuntimeError("Another Thaw helper build is using .build/thaw; wait for it to finish.")
        recipe = {path.name: path.read_bytes() for path in
                  (HERE / "lock.json", PATCH, HERE / "README.md", HERE / "build.py")}
        if json.loads(recipe["lock.json"]) != LOCK:
            raise RuntimeError("Thaw lock changed during startup; rebuild with the new lock.")
        work, archive = prepare(recipe)
        if args.prepare_only:
            assert_recipe_unchanged(recipe)
            print(f"Prepared source: {work}")
            return
        build(work, archive, args.output, recipe)


if __name__ == "__main__":
    try:
        main()
    except (OSError, RuntimeError, subprocess.CalledProcessError) as error:
        sys.exit(f"Thaw helper build failed: {error}")
