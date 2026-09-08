# Seamless Portals — RC3 field-fix preview

**Version:** `2026.09.08-field-rc3-preview`. **PREVIEW: incomplete integration, not engine-validated.**

The addon is already integrated: the previous 82 patches, preliminary **F00–F10**, and documentation/metadata stage **F11**, for 94 cumulative patches. F00–F10 are byte-identical to the individual diffs previously delivered. Packaging has not finished their pending gameplay fixes.

## Installation

For isolated testing, copy only `seamless/` into `garrysmod/addons/`. Disable older Workshop/custom/RC copies, keep backups outside the active addons directory, and restart the game/server and clients. Do not install the patch baseline or apply patches again to the integrated addon.

## Current status

Read [FIELD_FIXES_PREVIEW.md](docs/FIELD_FIXES_PREVIEW.md) for the ten reports, preliminary changes, unresolved integration issues and native acceptance checklist. **126 inherited offline tests passed; 2 sound tests failed; 42 adapted Lua syntax checks passed. No native Garry's Mod execution was performed here.**

Pending issues include blast chain-reaction recursion, clone collision restoration, native held-object behavior, and the dedicated field-fix test suite. The audio, projectile and NPC paths are bounded adapters, not universal engine replacements. The older RC2 contracts in the remaining documents are explicitly marked as historical where superseded.

Sound and damage remain enabled by the inherited default policy. The new preliminary paths must still be tested in the game. Do not interpret enabling a feature as verification that it works.

## Development verification

From the full bundle root, run `python patches/verify_bundle.py --bundle . --results ../seamless-structure-check` to verify reconstruction only. Run `python seamless/tools/validate_release.py seamless --results ../seamless-offline-check` separately for the inherited tests; this preview currently returns a failure status for the two sound tests. Do not discard that status.

No Python or Lua development library is needed by the addon at runtime. Those are only for the supplied offline tooling. The inherited manual smoke file checks a subset and is not a complete F00–F10 acceptance test.
