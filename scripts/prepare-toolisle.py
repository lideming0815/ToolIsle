#!/usr/bin/env python3
"""Prepare the isolated ToolIsle target. No credentials or network requests."""
from pathlib import Path
import re
import shutil
import sys
import json

root = Path(__file__).resolve().parents[1]
resources = root / 'ToolIsle/App/Resources'
resources.mkdir(parents=True, exist_ok=True)
for name in ['LICENSE', 'NOTICE', 'COPYRIGHT_ASSETS', 'TRADEMARKS']:
    shutil.copy2(root / name, resources / name)
(resources / 'THIRD_PARTY_LICENSES').write_text('ToolIsle uses MarkdownUI 2.4.1 (MIT).\nThe build script adds the full license notices of resolved dependencies to the application.\nOriginal Atoll notices remain in NOTICE and COPYRIGHT_ASSETS.\n', encoding='utf-8')

# SwiftUI is macOS-only; keep the pure core and its tests buildable on Linux.
(root / 'Package.swift').write_text('''// swift-tools-version: 6.0
import PackageDescription
var products: [Product] = [.library(name: "ToolIsleCore", targets: ["ToolIsleCore"])]
var dependencies: [Package.Dependency] = []
var targets: [Target] = [
    .target(name: "ToolIsleCore", path: "ToolIsle/Core"),
    .testTarget(name: "ToolIsleCoreTests", dependencies: ["ToolIsleCore"], path: "ToolIsle/Tests")
]
#if os(macOS)
products.append(.executable(name: "ToolIsle", targets: ["ToolIsleApp"]))
dependencies.append(.package(url: "https://github.com/gonzalezreal/swift-markdown-ui", exact: "2.4.1"))
targets.append(.executableTarget(name: "ToolIsleApp", dependencies: ["ToolIsleCore", .product(name: "MarkdownUI", package: "swift-markdown-ui")], path: "ToolIsle/App", resources: [.copy("Resources")]))
#endif
let package = Package(name: "ToolIsle", platforms: [.macOS(.v14)], products: products, dependencies: dependencies, targets: targets, swiftLanguageModes: [.v5])
''', encoding='utf-8')

# Preserve upstream source and acknowledgements; deactivate its release automations.
for workflow in (root / '.github/workflows').glob('*.yml'):
    if workflow.name.startswith('toolisle-'):
        continue
    workflow.rename(workflow.with_suffix('.yml.disabled'))
for name in ['toolisle-source-review.yml']:
    (root / '.github/workflows' / name).unlink(missing_ok=True)
for path in (root / '.github').glob('toolisle-foundation.*.b64'):
    path.unlink()
funding = root / '.github/FUNDING.yml'
if funding.exists(): funding.rename(root / '.github/FUNDING.upstream.yml.disabled')

# Small defensive fixes kept here so regenerating an earlier source snapshot is safe.
p = root / 'ToolIsle/App/GiteeViews.swift'
s = p.read_text()
s = s.replace('($0.type != "dir", $0.name) < ($1.type != "dir", $1.name)', '($0.type == "dir" && $1.type != "dir") || ($0.type == $1.type && $0.name.localizedStandardCompare($1.name) == .orderedAscending)')
p.write_text(s)
p = root / 'ToolIsle/Core/GiteeClient.swift'
s = p.read_text().replace('cache.removeValue(forKey: url.absoluteString); throw GiteeError.forbidden', 'try? clearCache(); throw GiteeError.forbidden').replace('cache.removeValue(forKey: url.absoluteString); throw GiteeError.notFound', 'try? clearCache(); throw GiteeError.notFound')
s = s.replace('query: [.init(name: "ref", value: ref)]', 'query: ref.isEmpty ? [] : [.init(name: "ref", value: ref)]')
p.write_text(s)

# Export the supplied vector exactly, with safe padding, not an AI-redrawn replacement.
if '--skip-icons' not in sys.argv:
    import cairosvg
    from PIL import Image, ImageDraw, ImageFont
    import io
    svg = (root / 'ToolIsle/Brand/toolisle-logo.svg').read_text()
    padded = svg.replace('viewBox="0 0 64 64"', 'viewBox="-7 -7 78 78"')
    mono = re.sub(r'#[0-9a-fA-F]{6}', '#000000', padded)
    for name, vector, size in [('AppIcon', padded, 1024), ('MenuBarTemplate', mono, 36)]:
        cairosvg.svg2png(bytestring=vector.encode(), write_to=str(resources / (name + '.png')), output_width=size, output_height=size)
    dev = Image.open(resources / 'AppIcon.png').convert('RGBA')
    draw = ImageDraw.Draw(dev)
    draw.rounded_rectangle((690, 770, 990, 920), radius=28, fill='white', outline='#5148d6', width=6)
    draw.text((738, 793), 'DEV', font=ImageFont.load_default(size=90), fill='#5148d6')
    dev.save(resources / 'AppIconDev.png')
    for name in ['AppIcon', 'AppIconDev']:
        folder = resources / (name + '.iconset'); folder.mkdir(exist_ok=True)
        image = Image.open(resources / (name + '.png'))
        for size in [16, 32, 128, 256, 512]:
            for scale in [1, 2]:
                suffix = '@2x' if scale == 2 else ''
                image.resize((size * scale, size * scale), Image.Resampling.LANCZOS).save(folder / f'icon_{size}x{size}{suffix}.png')
    (root / '.github/assets/toolisle-logo.svg').write_text(svg)

old_readme = root / 'Docs/Upstream-Atoll-ReadMe.md'
old_readme.parent.mkdir(exist_ok=True)
if not old_readme.exists(): shutil.copy2(root / 'ReadMe.md', old_readme)
shutil.copy2(root / 'ToolIsle/README.md', root / 'ReadMe.md')
(root / 'ToolIsle/VERSION').write_text('0.2.0\n')
gitignore = root / '.gitignore'
s = gitignore.read_text()
for entry in ['/.build/', '/dist/', '/.swiftpm/', '/ToolIsleArtifacts/']:
    if entry not in s: s += '\n' + entry
# Package.resolved belongs in source control for reproducible dependency resolution.
gitignore.write_text(s + '\n')
print('ToolIsle source, branding, legal notices and workflow isolation prepared.')
