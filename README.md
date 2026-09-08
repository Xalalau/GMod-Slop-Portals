# Seamless Portals — RC3 field-fix preview

**Version:** `2026.09.08-field-rc3-preview`. **PREVIEW: incomplete integration, not engine-validated.**

The addon includes the previous 82 patches, preliminary **F00–F10**, and documentation/metadata stage **F11**, for 94 historical patch stages. Subsequent local gameplay fixes are recorded separately in [Gameplay fixes and measured results](docs/BUG_FIXES_2026-09-08.md); they do not change the historical stage count or preview release status.

## Installation

For isolated testing, copy only `seamless/` into `garrysmod/addons/`. Disable older Workshop/custom/RC copies, keep backups outside the active addons directory, and restart the game/server and clients. Do not install the patch baseline or apply patches again to the integrated addon.

## Current status

Read [FIELD_FIXES_PREVIEW.md](docs/FIELD_FIXES_PREVIEW.md) for the original preview reports and acceptance checklist, and the [local follow-up](docs/BUG_FIXES_2026-09-08.md) for current evidence. **144 offline tests pass; C-T42 and C-T43 remain failing sound tests; 51/51 normalized Lua syntax checks pass.** Automated native probes ran on a dedicated LAN Sandbox server on `gm_flatgrass`. Manual graphical-client checks and a second multiplayer observer remain pending.

The local changes cover blast damage storage, physgun retention, linked backface visibility, melee impacts, AR2 projectile alignment and RPG guidance, with 18 field regressions. Comprehensive native chain reactions, clone collision restoration, constrained/blocked carry, visual/audio behavior and multiplayer prediction remain acceptance work. The audio, projectile and NPC paths are bounded adapters. The older RC2 contracts in the remaining documents are historical where superseded.

Sound and damage remain enabled by the inherited default policy. The new preliminary paths must still be tested in the game. Do not interpret enabling a feature as verification that it works.

## Development verification

From this addon root, run `python3 tools/check_source.py .` and `python3 tools/validate_release.py . --results /tmp/seamless-validation`. The full validator returns a failure status for the two sound tests. Do not discard that status. The separate historical bundle contains its own reconstruction verifier; it does not reconstruct the later local commits.

No Python or Lua development library is needed by the addon at runtime. Those are only for the supplied offline tooling. The inherited manual smoke file checks a subset and is not a complete F00–F10 acceptance test.
