# Field fixes — RC3 preview status

**Build:** `2026.09.08-field-rc3-preview`. **Status: PREVIEW — INCOMPLETE, NOT A VALIDATED RELEASE.**

This package applies the 11 previously delivered preliminary F00–F10 diffs to the complete RC2 source. Those diffs are unchanged. F11 adds packaging metadata/documentation only. The total series is **94 cumulative patches: 82 previous stages + 11 field-fix stages + 1 packaging stage**.

The latest user request was to receive the ZIP. No pending gameplay integration was silently claimed to be finished during packaging. The ten reported behaviors are still acceptance targets, not ten verified fixes.

## Verification and remaining failures

The inherited offline suite was rerun: **126 passed, 2 failed**. Regression: 45/45; integration: 23/23; custom: 58/60. Adapted syntax: **42/42 Lua files**. Textual gates and Python syntax passed. These checks use a Lua runtime with explicit substitutes for engine APIs; they are not native Garry's Mod compilation, physics, rendering, networking or AI tests.

The retained failures are **C-T42 — Sound recursion from an extension veto hook is bounded** and **C-T43 — Sound opt-out and per-tick network budget**. The prior expectations need investigation alongside the revised sound implementation. They have not been changed, suppressed or counted as passed. No dedicated F00–F10 executable regression suite was added for this preview.

Current evidence is in the full bundle at `patches/evidence/rc3_preview/`. RC2 evidence is historical. Patch reconstruction/hashes can pass even though behavioral tests fail: these are separate checks.

## Field-fix scope

| Patch | User case | Preliminary implementation | Important boundary |
|---|---|---|---|
| F00 — Shared crossing geometry and visibility | Infrastructure | Shared aperture, crossing and two-segment visibility helpers for the following field fixes. | Geometry helpers do not implement or validate engine collision behavior. |
| F01 — Blast damage propagation | 1 | Adds a blast propagation path, Lua blast adapters and adapters for selected native explosion sources, with distance/visibility and duplicate-path handling. | Recursion handling still needs to distinguish relayed damage from a new real chain-reaction explosion. This is not universal native explosion coverage. |
| F02 — Persistent held-object crossing state | 2 | Adds held-object crossing state and integrates it with player carry transactions; no additional drop/regrab fix was implemented while packaging. | Actual native E/physgun controller behavior remains unverified. This stage is complemented by F03, not an independent complete solution. |
| F03 — Object admission, clipping and held proxy collision | 2, 3 | Uses oriented bounds for admission, retention tolerance, front-plane clipping, a physical exit proxy and separate proxy collision control. | Clone collision restoration still needs integration review against the new collision ownership path. Exact contacts and controller behavior require GMod. |
| F04 — Sound origin, sentence and fire-loop adapters | 4 | Falls back to the emitting entity position, revises relay range and adds sentence handling and a start/update/stop protocol for burning-prop loops. | C-T42 and C-T43 fail in the unchanged prior test suite. Failures are retained, not waived. Fire loops are a specific adapter, not universal native audio lifecycle support. |
| F05 — Segmented hitscan tracers | 5 | Suppresses the continued native tracer path and builds separate visual segments from the actual hitscan path. | Generic tracer appearance; arbitrary third-party tracer renderers and network prediction have not been tested. |
| F06 — Selected native projectile transport | 6 | Adds a predictive crossing path for known native projectile classes, moving the existing entity rather than replacing its owner, timer or callbacks. | Not a universal projectile API or complete continuous collision solver; native impacts and high-speed contacts remain unverified. |
| F07 — Visible indication before the portal has a valid view | 7 | Adds an outline/indication when the portal has no valid rendered view, including creation without an opaque back. | Native depth, rendering order and visibility conditions still need a visual test. |
| F08 — Self-hittable bullet continuation emitter | 8 | Continues bullets from an inert emitter while retaining original damage attribution and callbacks, instead of firing again from the original attacker. | Damage permissions, immunity and gamemode hooks still apply; native self-hit behavior is unverified. |
| F09 — Local physgun effect in mirrored views | 9 | Adds a mirrored-view local effect path with the glow placed at the viewmodel attachment without moving the weapon to the opposite side. | Local beam uses a screen overlay; arbitrary SWEP effects and native render-hook ordering are not validated. |
| F10 — Experimental NPC attention and aiming adapter | 10 | Adds portal-path visibility and target handling for selected native NPCs and adjusts the bullet direction at the firing origin. | Does not implement portal navigation or universal NPC/NextBot support; AI schedules and native targeting remain unverified. |
| F11 — Preview packaging metadata and status documentation | Packaging only | Updates version/count metadata, adds this preview status, labels older RC2 contracts as historical and aligns the existing manual smoke count with the packaged series. | No gameplay fix, failing-test suppression or dedicated field-fix test suite is added in this stage. |

## Unfinished integration — do not treat as resolved

Blast recursion must be reviewed for chain-reaction explosions. Clone collision recovery must be reconciled with the new held-proxy collision ownership. Native E and physgun carry must demonstrate correct behavior when stopping, retracting, releasing and crossing at an angle; the proxy path does not prove native controller correctness.

The fire loop adapter is not universal native loop/voice/music handling. Tracer appearance is generic. The mirrored local physgun beam uses an overlay. The NPC adapter does not provide navigation or universal NextBot support. Existing restrictions on physical self-mirror and unsupported constrained assemblies remain unless explicitly changed by a field patch.

## Native acceptance checklist (not executed here)

### F00 — Shared crossing geometry and visibility

Check front/back approach, rotated endpoints, aperture edges and obstructions on both sides.

### F01 — Blast damage propagation

Compare a nearby barrel with an equivalent portal-separated barrel; test cover, range, duplicate paths and chain reactions.

### F02 — Persistent held-object crossing state

With a small E-held prop, stop before the portal, extend/retract the prop, release it, then cross and back out.

### F03 — Object admission, clipping and held proxy collision

Repeat E/physgun entry at multiple angles and distances; test a blocked exit, withdrawing the prop, release and portal removal.

### F04 — Sound origin, sentence and fire-loop adapters

Test NPC speech, ignited props, extinguishing, entity/portal deletion, sound opt-out, recursion and network budgets.

### F05 — Segmented hitscan tracers

Fire both ways through separated portals with pistol, automatic weapon and shotgun; verify no world-space connecting diagonal.

### F06 — Selected native projectile transport

Test RPG, grenade, crossbow bolt and AR2 energy ball at several speeds, angles and portal orientations.

### F07 — Visible indication before the portal has a valid view

Create an unlinked/no-back portal in open space and confirm the marker is visible before and after linking.

### F08 — Self-hittable bullet continuation emitter

Aim at your own exposed body through a portal and compare with god mode, damage-disabled endpoints and multiplayer permissions.

### F09 — Local physgun effect in mirrored views

Compare normal/mirrored first-person physgun idle and holding effects at several viewmodel FOVs; check third-person views separately.

### F10 — Experimental NPC attention and aiming adapter

Test friendly/hostile NPCs, looking and firing through the portal, cover on each side, target death and portal deletion.

## Installation for isolated testing

Close the game/server. Keep a backup outside the active addons directory. Disable previous Workshop, custom, RC1 and RC2 copies. Copy only `seamless/` to `garrysmod/addons/seamless/`, then restart server and clients with matching code. The folder is already patched. Do not install `patches/baseline/` or apply the patches again to `seamless/`.

Use a disposable test map/session. This preview is not recommended for a production server. Native performance gains and absence of bugs have not been established.
