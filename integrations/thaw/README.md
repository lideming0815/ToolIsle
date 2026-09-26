# Embedded Thaw distribution

This integration pins Thaw 2.0.1 to the commit and source archive digest in `lock.json`. The unmodified upstream is cached under `.build/thaw/source`; a separate `.build/thaw/work` receives `toolisle-distribution.patch`. Never edit either cache as the maintained source of a change.

```sh
python3 integrations/thaw/build.py --prepare-only
python3 integrations/thaw/build.py --output /absolute/stage/BangsBuddy.app/Contents/Helpers/Thaw.app
```

The builder requires macOS, Xcode and network access to resolve the exact Swift package versions in the upstream lock. It defaults to `/Applications/Xcode.app` without changing the machine's active developer directory. Builds are arm64 Release with local ad-hoc signing, matching the current ToolIsle DMG workflow. Hardened runtime remains enabled; debugger attachment and library-validation exemption entitlements are rejected for both the helper and its internal XPC. A nonblocking lock rejects concurrent builds that would share the source/work trees. The default output is `.build/thaw/products/Thaw.app`.

After final signing, the builder runs the actual executable with `--toolisle-launch-check` and requires the expected sentinel and a successful exit within 15 seconds. This managed-only entry returns before AppKit, AppState, layout or permissions initialize, so it verifies real dynamic loading without opening a window or changing menu bar state. The builder does not install the result. Successful output has passed signature, dynamic dependency and launch checks; GUI, TCC and callback behavior still require separate validation.

The host must embed the complete resulting `.app`, then sign the outer app last. The helper keeps the Thaw name, native settings and normal termination. Its identity is `com.toolisle.Thaw`, and its internal XPC identity is `com.toolisle.Thaw.MenuBarItemService`. `thaw://` remains registered; the host must dispatch to the exact embedded application path. Defaults, profile files, image cache, diagnostics and interprocess notification names are isolated from the independently installed Thaw.

## Deliberate upstream differences

- A `ToolIsleManagedComponent` Info.plist marker gates the integrated distribution behavior. Complete ToolIsle app replacements own updates; independent update checks, consent sheet and controls are disabled. `TOOLISLE_MANAGED` compiles a small disabled `UpdatesManager` without importing Sparkle; the original manager remains under `#else` and shared `UpdateChannel` types remain available. The patched distribution project removes Sparkle's framework link and product dependency while preserving the upstream package source and pin. There is no Sparkle binary in the helper and no library-validation bypass. This avoids the pre-main dyld failure that a hardened ad-hoc process encountered when loading the unused framework.
- The helper does not expose its own login registration control. Startup is managed by ToolIsle. The advanced Thaw window and its regular/accessory activation behavior remain upstream behavior.
- Both native helper restart menu entries are hidden. In the managed build, `restartSelf()` presents a notice to restart through ToolIsle and returns before launching or exiting a process; repeated calls are gated while the notice is open. Normal helper termination remains intact, so the host can await layout restoration before it restarts. In this pinned upstream, only the two menus call `restartSelf()`; permission polling does not.
- Settings URI is registered as enabled by default before AppState creation. An explicit user choice to disable it is preserved. No caller is preauthorized: normal sender detection, approval dialog, whitelist and code-signing identity checks remain intact.
- The internal XPC code-signing checks are unchanged. Upstream explicitly accepts its existing no-team path for ad-hoc builds; signed builds require the same team. Settings URI also distinguishes an inspected no-team signature from an unavailable identity and rejects the latter. Those static facts do not replace testing the distributed app's identity resolution.
- Bundle/service identifiers and storage/notification namespaces are changed together. The one SourcePIDCache edit changes only its own-app identifier; no menu-bar algorithms are changed.
- Embedded source stamping records the locked upstream commit rather than the host repository's Git HEAD.

`Resources/ToolIsleIntegration` contains this build recipe, lock, explicit patch, unmodified upstream source archive and upstream GPLv3 license. The archive contains upstream source, notices, acknowledgements and its dependency lock. Preserve those materials when distributing the helper. The outer product's notices and license obligations remain the publisher's responsibility.

## Updating the upstream baseline

Review a new version, update `lock.json` (including the downloaded archive's SHA256), rebase the explicit patch and rebuild. Do not silently accept a new archive digest. Each build reconstructs source and work from the verified archive and reapplies captured patch bytes, so manual cache edits cannot leak into a release. The old Thaw.app build product is removed before compilation so deleted dependencies cannot survive in a reused bundle; dependency downloads and other DerivedData remain reusable. The recipe is captured before preparation, packaged from the same bytes, and checked again after compilation and signing. Editing the lock, patch, recipe or README during a build fails that run instead of describing unbuilt changes as the result. Validate the host's URI contract, permissions, normal exit, nested signatures, disabled component updates and replacement-upgrade behavior before distributing a changed baseline.
