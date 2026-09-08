> **RC3 preview notice:** The RC2 record below is historical where superseded. See [2026.09.08-field-rc3-preview](FIELD_FIXES_PREVIEW.md) for the current F00–F10 scope, incomplete integration and two retained sound-test failures. Older successful test counts do not describe this preview.

# Custom/main/RC1 comparison — evidence, not a checkbox verdict

Checked main snapshot: `ec2a714a940465fb8fb113e052c60e1186ec27e5`, commit time 2026-09-06 23:34:19 UTC. It matches the originally uploaded baseline. “Master” in the conversation is treated as this checked upstream **main** snapshot, not an assumed different branch.

Inputs: original `seamless.zip`; the previous complete RC1 bundle; and `mee-portals(1).zip` (seven Lua files). All seven custom files were read. The custom’s SEv bootstrap, `sev_portal` entity, network framework, RT allocation and mirror implementation are absent; the upload cannot establish complete runnable parity by itself.

**Important correction:** source patterns are not a substitute for observed native gameplay. The user reports upstream can carry props through, imperfectly. The previous comparison’s unconditional negative cells did not establish impossibility. RC1’s new constraint/four-side restrictions were explicit regressions in scope; the skip-held and DropObject patterns already existed in the baseline. RC2 implements an intentional carry-preserving route rather than describing a disablement as a feature fix.

| Capability / claim | RC1 | Checked upstream main | Supplied custom | Custom RC2 |
|---|---|---|---|---|
| E-held crossing | Skips held prop transfer; player DropObject route; not a continuous-hold implementation | Same relevant skip/drop source pattern; user reports partial in-game success | Prop tick skips IsPlayerHolding; group transfer ForcePlayerDrop | New joint Move/held transaction, no forced drop; native retention unverified |
| Physgun-held crossing | Not reliably established by source-only review | User reports partial success; a blanket impossible label was unjustified | Held prop skipped; native controller handoff absent from upload | Confirmed pickup tracking; joint transaction and view update; native retention unverified |
| Loose prop crossing | Restricted to four-sided reciprocal pairs | Existing partial clone/transfer path | Direct teleport of eligible physics entities | Legacy loose path retained, polygon restriction replaced |
| Partial physical clone | Present for eligible props | Present | Not found in supplied seven files | Retained; constrained/held source authoritative, one-way proxy projection |
| Simple bullet passage | One zero-spread, zero-hull bullet only | Center-ray redirection | Center-ray redirection | Per-actual-pellet callback continuation, default on |
| Spread / multiple pellets | Deliberately not redirected | Center-ray batch rewrite can misroute spread | Same central-ray limitation | Native spread determines impact; each continuation is one pellet; engine weapon tests pending |
| Global util.TraceLine | Optional and wrapper left installed | Global detour | Portal-count-driven install/restore every second | Default on only with usable links; composable ownership; up to eight hops |
| Clone damage → real | Present | Present | No clone path shown | Retained with independent DamageInfo and per-portal damage controls |
| Generic explosions | Not implemented | Not implemented | Not implemented | Not implemented; hitscan and clone damage are not generic radial propagation |
| Whole constrained graph | Refused by RC1 containment | No deliberate atomic graph transaction; original constraint removal is destructive | GetAllConstrainedEntities and per-member transform/drop | Rigid graph preflight/commit; each physical body preserved; unsafe graphs blocked |
| Relative group position | No supported graph route | No deliberate graph preservation contract | Per-entity mapping; scale differences may alter joint separation | One rigid mapping/common offset preserves relative distance without resizing joints |
| Per-member velocity | Not as a supported group | Not as a deliberate graph operation | Transforms individual entity velocities | Transforms each PhysObj linear velocity; preserves local angular velocity |
| ForcePlayerDrop per member | Not a group feature | Drop exists in loose transfer route | Yes, present in group loop | Intentionally absent from carry/assembly commits; forced drop is not a feature to preserve |
| Funneling | Absent | Absent in checked snapshot | Present in movement source | Ported with tick normalization and speed preservation |
| Per-portal enableFunneling | Absent | Absent | NWBool default false | Retained through compatible NWBool, API, tool and Hammer |
| Lateral movement weakens funnel | Absent | Absent | 0.01 blend rather than 0.05 | Equivalent relative behavior normalized across tick intervals |
| disablePropTeleport | No equivalent user flag | No equivalent flag located | NWBool default false | Retained independently of players, sound and damage |
| Player-only portal | Not a separate public switch | Not a separate public switch located | Props disable without changing player path | Independent flags; held-player crossing blocks rather than stranding prop |
| No-portals trace restoration | Wrapper remains, internally disabled | Permanent detour | Restores original function when no portals | Restores owned original function; respects later wrapper ownership |
| Ping-aware camera | Different fixed bridge/lerp system | Different fixed bridge/lerp system | Explicit Ping + missing custom SEv networking | Bounded ping/tick bridge plus ordered multiplayer ACK; engine latency tests pending |
| Entry/exit usage callbacks | Hammer outputs | Hammer outputs | Calls RunPlyUsageCallbacks; registration implementation absent | Documented callback registry and protected notifications plus outputs |
| Six-face 2D sky fallback | No custom fallback | Different renderer sky path | Draws six faces when visibility check fails | Fallback ported; newer compositor retained |
| Separate RT per portal | Two-target compositor instead | Two-target compositor instead | PortalRTs usage; allocation/bootstrap absent | Two-target compositor deliberately retained; not a missing visible feature |
| Distance render ordering | Present | Present | Periodic sorted portal list | Retained with cached metrics/budget |
| Stationary prop prefilter | Different local cutout architecture | Different local cutout architecture | Present, but velocity incorrectly checked using IsValid | Existing local admission/idle optimizations retained; no all-map half-second rescan copied |
| Half-second prop preselection | No matching timer | No matching timer | Present | Not copied: local cutout admission remains at tick frequency |
| Sound passage | Off and allowlist required | Client-side relocation relay | Client-side relocation relay | Default on; server-to-exit PAS plus client-local events; independent emitters |
| Remote visibility / PVS | Present, bounded | Present | Present | Newer PVS service retained; sound now separately reaches exit recipients |
| Self-mirror / dimension | Present | Present | Movement/render calls present; ToggleMirror bootstrap missing | Player/render/trace self-link retained; physical held/assembly self-link blocked |
| Old SEv map-instance schema | Not supported | Not supported | Depends on omitted framework/entity files | Not automatically migrated; use seamless_portal/API/Hammer |
| Hide tools/gun/entities | Not the default | Tools/gun exposed | License states custom removed/hidden them | New tools and gun intentionally retained; hiding is deployment-specific, not restored by default |

## Source pointers

The preserved uploaded custom is in the bundle’s `patches/reference/custom/mee-portals/`. Its `sv_prop_teleport.lua` contains the half-second scan, held skip, constraint collection and per-member ForcePlayerDrop. `sh_portal_movement.lua` contains funneling, independent prop-disable checks, callback calls, ping handling and SEv networking dependencies. `detours/sh_detours.lua` contains center-ray bullets and count-driven trace replacement. `detours/cl_detours.lua` contains the client source-relocation sound path. `cl_render_core.lua` contains PortalRTs usage, sky faces and the halo override. `license.lua` records attribution and the older upstream lineage.

The matching baseline paths are in `patches/baseline/lua/`. Current implementation pointers are `seamless_portals/{features,aperture,traces,bullets,sound,holding,transport,funneling,skybox}.lua`, `autorun/sh_player_teleport.lua`, `entities/seamless_portal_clone.lua`, and the Portal Behavior tool. Every current Lua file is in the syntax manifest; hashes in the bundle fix which code was reviewed.

## What “implemented” means here

The code now contains these behaviors and the offline harness exercises selected contracts. It does not mean native E/physgun retention, cutout contacts, lag compensation, render ordering or source/recipient sound behavior have been observed. The native acceptance matrix is a release gate, not a completed test log. No zero-bug claim, universal SWEP compatibility or measured speedup is made.

The migration is not an upstream rebase onto another old framework. It keeps the new entity/render/PVS architecture and ports useful behavior. Lower-level implementation details such as a global timer, forced drops or one RT per portal are not preserved when they conflict with that goal.
