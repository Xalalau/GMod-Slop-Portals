> **RC3 preview notice:** The RC2 record below is historical where superseded. See [2026.09.08-field-rc3-preview](docs/FIELD_FIXES_PREVIEW.md) for the current F00–F10 scope, incomplete integration and two retained sound-test failures. Older successful test counts do not describe this preview.

# Seamless Portals — Custom RC2 release notes

**Version:** `2026.09.08-custom-rc2`. **Bundle:** `complete-2-custom`. **Stage count:** 82 = 56 original proposals + 11 RC1 integration stages + 15 custom stages.

## What changed from RC1

Sound, hitscan damage and dynamic portal-aware line traces are enabled by default. Constrained group transfer, held-player transfer, nonrectangular cutout borders, per-portal behavior controls, custom funneling, usage callbacks, a ping-aware ACK bridge and six-face sky fallback are integrated into the newer architecture. Clone-to-real damage now uses independent DamageInfo. A dedicated Portal Behavior tool controls new user-facing features.

The carry route synchronizes the player and real held group without calling native drop/regrab or rebuilding the real physics object. It validates fit/obstruction/ownership and attempts Lua rollback on a write failure. This replaces feature exclusions; it does not turn an untested native controller into a certified feature.

## What is not claimed

No native Garry’s Mod execution, controller test, engine rendering/physics test or benchmark was performed. E/physgun retention remains pending native acceptance. Physical self-mirror/directed groups, remote-proxy grab handoff, generic explosion transfer, arbitrary projectile/SWEP compatibility, complete native sound lifecycle and continuous collision detection are not implemented. World anchors, unsupported members and obstructed/oversized groups are refused without deleting their constraints. Held/group dimensions are preserved rather than rescaled across unequal portals.

## Evidence

128 offline checks passed (45 + 23 + 60), including source-level actual Move-hook tests with doubles. 31 Lua files passed normalized syntax checks. The complete series and consolidated patch reconstruct the same delivered source, verified by per-file hashes. English comparison, configuration, native test matrix and per-patch documents are included.

Install only `seamless/`. The custom upload is preserved as reference, not as another addon to mount. A one-time versioned migration enables the requested default sound/damage/trace profile; later choices persist. See `CONFIGURATION.md`, `docs/CUSTOM_COMPARISON.md` and `docs/TESTING.md`.
