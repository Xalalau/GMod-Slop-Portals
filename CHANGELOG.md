> **RC3 preview notice:** The RC2 record below is historical where superseded. See [2026.09.08-field-rc3-preview](docs/FIELD_FIXES_PREVIEW.md) for the current F00–F10 scope, incomplete integration and two retained sound-test failures. Older successful test counts do not describe this preview.

# Changelog

## 2026.09.08-custom-rc2 — complete-2-custom

- Added cumulative C01–C15: custom behavior and defaults, polygon prop support, actual-pellet bullets, exit-region sound, rigid groups, E/physgun carry route, funneling, ACK camera bridge, sky fallback and user controls.
- Corrected integration faults found by tests: callback order, border winding, destination aperture/multiple returns, sound recursion/PAS/channel cleanup, local damage-force metadata, world NoCollide handling, native-controller-safe pose writes and retired proxies.
- Expanded to 128 offline checks and 31 adapted Lua syntax checks, including full Move-hook tests with explicit doubles. Native acceptance remains pending.
- Replaced the RC1 support-policy exclusions where implemented; preserved old patches and evidence as history rather than silently changing prior diffs.

## Historical entries below — not the current support policy


## Complete bundle revision 1

- Consolidated the installed addon, 67 cumulative individual patches and current English proposal/implementation document into one archive.
- Split the former monolithic integration diff into INT01–INT11 and linked follow-ups to all affected original proposal IDs.
- Corrected stale proposal wording for clone scaling, reciprocal-only prop cutouts, best-effort collision restoration and same-frame flashlight reuse.
- Included a self-contained pristine working-tree baseline, full-series/consolidated reconstruction verifier, fresh offline results and content hashes.
- Preserved runtime Lua, original assets, FGD, license and the integrated RC1 runtime version unchanged. Native engine validation and performance measurement remain pending.

## 2026.09.07-integrated-rc1

Applied the complete 56-proposal review series to the addon working tree. See the source package's `docs/PROPOSAL_COVERAGE.md` for every B/R/O identifier; inclusion is not equivalent to native verification.

### Correctness and compatibility

Input/mesh bounds, delayed coherent geometry reconciliation, pair-link invariants and unlink metadata, custom player hull/flashlight ownership, trace filter/output/segment contracts, remaining bullet distance, render cap/flag/viewport corrections, weapon API/cooldowns, placement validation, fitter raw traces, precise configuration copying, relative scale handling, tool quotas, link target validation and prop Hammer outputs.

### Failure containment and diagnostics

Checked native allocations, lazy collision helpers, render-state cleanup, guarded callbacks/dependencies, resizer permission alignment, movement/sweep diagnostics, compatible-aspect link policy, opt-in one-shot sound relay and sampled-triangle validation. Constrained/nonrectangular prop transfer and unsupported bullet forms are refused rather than approximated destructively.

### Optimization proposals integrated

CPU scene budgeting/metrics, cached candidate metrics, configuration batching, idle transfer-work skipping, generation-mark membership, direction-only transforms, owned flashlight reuse, bounded PVS origins, bounded mesh ownership, an explicit portal trace API, clean reproducible packaging and centralized settings/regression gates. No benchmark-backed speedup is claimed.

### Additional integration work

Immediate/idempotent cutout retirement before deferred entity removal; deletion-mark checks; geometry-failure deactivation/recovery; best-effort collision-restoration retry without overriding a new owner; both-endpoint cutout readiness; reciprocal-only prop-cutout transfer; stale player-hull release on unlink; child clip-plane ownership; failed clone-coupling release; physics activation/reacquisition after scaling; same-frame flashlight source-pose reset; link-tool failure feedback through return/stage behavior; atomic source-safe ZIP creation.

### Validation

45 existing regression checks and 23 new integration checks passed. All 19 Lua files passed adapted syntax checks. Native smoke is supplied but unexecuted. No Garry's Mod, VPhysics, multiplayer, native renderer, GPU or performance validation was performed.
