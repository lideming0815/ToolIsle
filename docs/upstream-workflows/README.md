# Archived upstream automation

These files are unmodified copies from the Atoll-based gitee.5 baseline, retained for future upstream comparison. They are intentionally outside `.github/workflows` so merging ToolIsle into `dev` does not activate upstream publishing, repository mirroring, nightly branch writes or unauthenticated triage variables.

ToolIsle's replacement CI is `.github/workflows/toolisle-integration.yml`. It builds the original Xcode Release target and runs the original regression suite, native window lifecycles, Gitee navigation and tag UI checks on the integration branch and `dev`. No application service or updater is disabled by archiving these workflow files.
