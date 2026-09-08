> **RC3 preview notice:** The RC2 record below is historical where superseded. See [2026.09.08-field-rc3-preview](FIELD_FIXES_PREVIEW.md) for the current F00–F10 scope, incomplete integration and two retained sound-test failures. Older successful test counts do not describe this preview.

# Validation and native acceptance — Custom RC2

## Executed offline evidence

Runtime `2026.09.08-custom-rc2`. **128 checks passed**: P01–P45, I01–I23, C-T01–C-T60. **31/31** Lua files passed normalized syntax checks; seven Python files passed compilation checks. Final evidence is supplied in the complete bundle under `patches/evidence/rc2/`.

The Lua adapter uses Lua 5.4 with explicit GMod API doubles, not the native engine. Executable snippets normalize operators but reject GLua `continue`; whole-file syntax replaces it with a placeholder that is never executed. New modules are loaded inside separate function scopes so a module’s early `return` cannot bypass the test body. All executable suites require their final assertion sentinel. Physics methods record/mutate test-double state; they do not simulate constraints, collisions, controllers or engine scheduling.

Selected RC1 test expectations were deliberately superseded: polygon prop support instead of four-side rejection; dynamic default-on traces instead of opt-in; actual-pellet continuation instead of refusing spread/hull/multiple bullets; validated graph admission instead of blanket rejection. Old patch/source/evidence remains archived. Passing counts are not directly comparable as an unchanged 68-test specification.

C-T51–C-T56 load the actual shared Move hook and exercise E, physgun, a connected group, disabled props, blocked exits, nonportal hits and player self-mirror with doubles. They assert that intended Lua routes avoid drop/rebuild/motion-toggle calls, retain references, notify the expected entities and emit ACK data. **They do not prove the native controller remains attached after physics simulation.**

```sh
python tools/validate_release.py --results ../seamless-validation
# From the full bundle root:
python patches/verify_bundle.py --bundle . --results ../bundle-verification --run-tests
```

Results are written outside the source. Requirements: Python 3.10+, Git for patch reconstruction, discoverable Lua 5.4 shared library for executable tests. Build ZIP reproducibility is scoped to the same Python/zlib environment.

## Native compiler/pure smoke — supplied, not executed

On a development installation where console Lua is permitted:

```text
lua_openscript seamless_portals/tests/smoke.lua
lua_openscript_cl seamless_portals/tests/smoke.lua
```

Run the first on server, second on client with the source installed locally. The script compiles available addon sources and checks pure/public API assertions. Its success message must not be interpreted as a gameplay or controller test.

## Native acceptance matrix — all PENDING

Test a clean Sandbox map first; then the actual gamemode/addon set. Record GMod build/branch, server tick rate, map, singleplayer/listen/dedicated topology, client/server hashes, latency/loss, portal shape/orientation/size and relevant convars. Inspect both server and client consoles. “Looks correct once” is not enough.

| ID | Scenario and expected observation |
|---|---|
| N01 | Pick up a small real prop with E; walk through wall→wall repeatedly, turn and reverse. Hold must remain, prop stay in front, no hidden drop/regrab and no error. Compare PhysObj identity and entity index. |
| N02 | Repeat with physgun while holding primary fire; vary hold distance, rotate prop, crouch, reverse/back through, release immediately after crossing. Inspect native beam target and controller; run `seamless_portals_transport_status`. |
| N03 | Hold one member of a welded pair and a rope/axis assembly. Every member must transfer together, preserve local separation/constraint identity and continue moving without explosive impulse. Compare all physical bodies. |
| N04 | Block the exit with world/props, oversize the assembly, disable entry/exit props, or create a physical world anchor. Expect a reported block with player and held group kept at entry; no constraint deletion, unwanted drop or persistent world no-collision. |
| N05 | Wall→floor, floor→wall, ceiling/tilted pairs, crouched hulls, low/high speed, non-unit player hull/scale, consecutive portals. Check camera, grip target, collision restoration, falling and no stuck hull. |
| N06 | Dedicated multiplayer with a second observer at increasing latency and artificial loss/jitter; cross twice rapidly. Check ACK ordering, no repeated mirror toggle, native grip, prediction correction and observers. |
| N07 | Sides 3/4/6/50/100, thin/thick portals, rotated endpoints and Portal Gun placement. Validate cutout borders/contacts at polygon corners and silhouette, not only center. |
| N08 | Pistol, native shotgun, multiple-pellet weapon, HullSize weapon and a FireBullets SWEP with callback/IgnoreEntity; oblique rays, eight-link chain and range exhaustion. Confirm one final damage per pellet, attacker/inflictor/type/force, no duplicate tracer/effects, no ammo double consumption and correct lag compensation. |
| N09 | Per-portal/global damage disabled; shoot clone and real entity. Check no forwarding when disabled and independent DamageInfo/callback intent when enabled. Generic explosion crossing is not an expected pass. |
| N10 | Emit a server spatial sound near entry while listener is at exit and source outside listener PVS. Check sound arrives from expected virtual direction once; source position never changes. Repeat with client-only emit, rapid identical events and unrelated sound addons. |
| N11 | Explicit stop flags, named-channel replacement, unlink/delete/map cleanup and toggling relay off. Inspect emitter cleanup, loop expiry limits and source uniqueness. Document unsolved native StopSound/ambient/voice/music cases rather than calling them supported. |
| N12 | Self-linked portal on client/server with and without held prop: player-only mirror retained, absolute mirror state stable; held crossing deliberately blocked without dropping. Test nested/multiple mirror views. |
| N13 | Missing 2D sky, six sky faces, ordinary 2D/3D sky, water, halos, stencil and custom render hooks. Fallback must not overwrite foreground geometry or leak clip/depth state. |
| N14 | Toggle funnel per portal; compare no lateral input versus strafe and several tick rates. Speed magnitude preserved; low-speed walking unaffected; no assistance when disabled. |
| N15 | Creator/Fitter/Behavior/Resizer with a protection addon. Editing entry after a portal-aware trace must still call CanTool for that entry. Try denied ownership, copy, reset, duplication and Hammer key/input changes. |
| N16 | Upgrade from archived RC1 opt-outs; verify one-time enabled custom profile, then disable by choice and restart to prove choices persist. Check clients and server separately. |
| N17 | Cleanup/removal/resize/unlink during admitted props and immediately around a transfer. Check native collisions and clone/clip/helper cleanup; then cleanly stop/restart the addon. |
| N18 | Dense world with many portals, stationary props and active groups. Measure frame/tick percentiles, physics time, allocations, networking and render scenes. Compare identical scenes with baseline; do not infer performance from code size or test counts. |
| N19 | Frozen or multi-body members, invalid parent/occupied vehicle and competing holders. Verify explicit rejection or the documented supported path; confirm other players’ controllers are not stolen. |
| N20 | Unequal-size portals: loose-prop scale path separately from held/constrained rigid-size policy. Verify player-scale addon interactions and grip offset after authoritative movement. |

Each row needs its own recorded PASS/FAIL, reproduction and native logs. None has been run in this session. In particular N01–N06 are **release gates** for the user’s continuous-carry requirement.

## Failure collection and rollback

`seamless_portals_transport_status` prints the last server carry sample: kind, native-hold retained/released, same PhysObj references and tick. Enable movement diagnostics before reproduction and use `seamless_portals_dump_movement`. Sweep diagnostics observe only bounded samples, not universal CCD. Preserve the error log and exact hashes.

On a failure, stop the test, close the game/server and replace the whole addon with the backup. Do not apply a historical patch to an already integrated tree. Replacing Lua does not undo archived convars, saved duplications or all engine state. Keep old and new active addon copies mutually exclusive.
