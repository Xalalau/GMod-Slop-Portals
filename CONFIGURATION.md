> **RC3 preview notice:** The RC2 record below is historical where superseded. See [2026.09.08-field-rc3-preview](docs/FIELD_FIXES_PREVIEW.md) for the current F00–F10 scope, incomplete integration and two retained sound-test failures. Older successful test counts do not describe this preview.
Current gameplay follow-up: native crowbar/stunstick continuation and RPG guidance obey `seamless_portals_damage` plus both endpoint damage features. RPG guidance additionally obeys `seamless_portals_projectiles`. See [implementation and validation limits](docs/BUG_FIXES_2026-09-08.md).


# Configuration — Custom RC2

This document describes `2026.09.08-custom-rc2`, not RC1. Existing internal rendering/dimension defaults remain unless listed here. User-visible sound and damage defaults are on.

## Server/shared switches

| ConVar | Default | Contract |
|---|---:|---|
| `seamless_portals_global_trace` | 1 | Bounded portal-aware `util.TraceLine` while usable links exist; set 0 to deactivate/restore an owned detour. |
| `seamless_portals_damage` | 1 | Hitscan continuation and clone-to-real damage forwarding. |
| `seamless_portals_soundrelay_server` | 1 | Send spatial source sounds to exit-room recipients. |
| `sbox_maxseamless_portals` | 20 | Creator/Fitter quota; not a universal gun/Hammer/duplication quota. |
| `seamless_portals_pvs_maxdistance` | 500 | Server cap on accepted draw-distance multiplier. |
| `seamless_portals_pvs_maxorigins` | 8 | Portal visibility origins per player pass. |
| `seamless_portals_debug_movement` | 0 | Movement ring diagnostics. |
| `seamless_portals_debug_sweeps` | 0 | Bounded fast-crossing observations, not a CCD implementation. |

The archived migration marker `seamless_portals_custom_profile_server` starts at 0. On the first RC2 load it enables the first three switches and sets the marker to 2. Subsequent loads retain chosen values. Console/superadmins may run `seamless_portals_apply_custom_defaults` to reapply the requested profile. It does not override per-portal disables.

## Client switches

| ConVar | Default | Contract |
|---|---:|---|
| `seamless_portals_soundrelay` | 1 | Hear portal-relayed spatial sounds. |
| `seamless_portals_skyfallback` | 1 | Six-face fallback when the portal view has no visible 2D sky. |
| `seamless_portals_drawdistance` | 250 | Userinfo multiplier, bounded 0–2000; also depends on portal dimensions. |
| `seamless_portals_maxrender` | 6 | Scene cap; 0 renders none. |
| `seamless_portals_refreshrate` | 1 | Frames between updates, not hertz; 1 means every frame. |
| `seamless_portals_render_budget_ms` | 0 | Optional soft CPU time cap; 0 disables it. Not a GPU timer. |
| `seamless_portals_drawviewer` | 1 | Local player visibility in portal views. |

Client migration marker: `seamless_portals_custom_profile_client`, 0→2 once. Reapply command: `seamless_portals_apply_custom_client_defaults`. These retain later user choices. PVS origin budgets and client scene caps are separate services; matching numerical caps is not proof of visibility correctness.

## Per-portal features and new portal defaults

| Public feature name | Legacy-compatible NWBool | Enabled default | Creation userinfo option |
|---|---|---|---|
| `players` | `disablePlayerTeleport` (inverted) | true | `seamless_portals_feature_players` |
| `props` | `disablePropTeleport` (inverted) | true | `seamless_portals_feature_props` |
| `damage` | `disableDamageTransfer` (inverted) | true | `seamless_portals_feature_damage` |
| `sound` | `disableSoundTransfer` (inverted) | true | `seamless_portals_feature_sound` |
| `funnel` | `enableFunneling` | false | `seamless_portals_feature_funnel` |

Portal Creator/Fitter offer checkboxes. **Portal Behavior** applies, copies and resets these options. Existing geometric Creator/Resizer options remain: width/height 100, depth 8, sides 4, backface visible. API dimension range is 1–1000, sides 3–100; tool thickness UI is 1–100. Polygon size retains upstream radius semantics outside the four-sided case.

Use validated setters server-side instead of directly writing NWBool flags when possible. Setters also save duplication data and immediately retire disabled prop traversal state.

```lua
SeamlessPortals.SetFeature(portal, "props", false)
SeamlessPortals.SetFeature(portal, "players", true)
SeamlessPortals.SetFeature(portal, "sound", true)
SeamlessPortals.SetFeature(portal, "damage", true)
SeamlessPortals.SetFeature(portal, "funnel", true)
local enabled = SeamlessPortals.FeatureEnabled(portal, "sound")
```

Both endpoints must permit a passage feature. A player carrying a prop cannot cross when props are disabled: the whole crossing is blocked while the hold is retained. A player without a held prop can still cross when players are enabled. This avoids silently dropping or stranding held objects.

`GetDisablePropTeleport`, `SetDisablePropTeleport`, `GetEnableFunneling`, `SetEnableFunneling` provide direct compatibility accessors. FGD keys use the NWBool names; inputs are `EnableProps`/`DisableProps`, `EnablePlayers`/`DisablePlayers`, `EnableDamage`/`DisableDamage`, `EnableSound`/`DisableSound`, `EnableFunneling`/`DisableFunneling`.

## Trace and geometry APIs

`SeamlessPortals.TraceLine` and `RawTraceLine` refer to the saved raw implementation (which may itself be a preceding addon’s wrapper). `TracePortalLine(data[, trace_function])` explicitly traverses up to eight links; `data.SeamlessMaxHops` accepts 0–16. `data.SeamlessIgnore=true` bypasses the global wrapper. Filters/whitelists and caller output identity are preserved. `SeamlessSegments` contains raw segment snapshots; `Fraction` belongs to the original parameterized ray and includes nudges/uniform scale. It is not the Euclidean distance of one straight line connecting the original and final endpoints.

The wrapper restores its saved base only when still outermost. If another addon wrapped it, the wrapper becomes inactive rather than clobbering that addon. Portal tools retarget a portal-crossing trace back to the raw entry portal and explicitly repeat `CanTool` permission checks for the new target.

`Configure(size, sides, disable_backface)` and `ConfigurePair(a, config_a, b, config_b)` retain validated/coherent geometry updates. Matching width/height aspect ratios are required. `ApertureVertices`, `InAperture`, `ClosestAperturePoint` expose the shared polygon contract.

## Usage callbacks and integrations

```lua
portal:AddPlyUsageCallback("myaddon.audit", function(ply, phase, other)
    -- phase is "entry" or "exit". Executed server-side after a completed move.
    print(ply, phase, other)
end)
portal:RemovePlyUsageCallback("myaddon.audit")

hook.Add("SeamlessPortalsTeleported", "myaddon.transfer", function(ent, entry, exit, kind)
    -- Observe completed transfers; do not assume a native controller has been tested.
end)
hook.Add("SeamlessPortalsTransportBlocked", "myaddon.blocked", function(ply, entry, reason)
    print("Portal transport blocked:", reason)
end)
```

Player callbacks and player/group outputs are protected against Lua callback errors. Self-mirror invokes the portal’s player callback once, with phase `entry`; normal distinct pairs invoke entry and exit callbacks. The legacy loose-prop path still emits its existing Hammer outputs directly.

`RecordHold(ply, ent, kind)` / `ClearHold(ply, ent)` are adapters for another pickup implementation. Call them **only after actual attachment/release**. They do not grant permission to pick up, construct a grab controller or bypass ownership protection. Ordinary E/physgun/gravity-gun events are already tracked.

## Audio contract

Ordinary spatial sounds no longer need allowlisting. `SeamlessPortalsAllowSoundRelay(sound_data)` may return **false** to veto. Recursion from that hook is guarded. UI/zero-level/nonspatial sound is not relayed. Sources must be on the entry’s front side and within twice its maximum size; at most two nearest paths are used. This is a bounded heuristic, not acoustic ray tracing or lossless sound coverage at arbitrary distance.

The server sends to the exit room’s PAS, not the virtual source position that may lie inside a wall. An invisible client emitter plays the virtual-position sound without moving its source. Explicit stop flags and named-channel replacement are handled; emitters retire on disable/unlink/expiry. Duration is bounded to 30 seconds; the relay cannot infer unhooked `StopSound`, arbitrary looping WAV state, delayed/skipped `SoundTime`, voice, music or ambient entity state. Server/client events within 75 ms coalesce only across realms. Identical but genuinely distinct cross-realm sounds in that window can coalesce; validate the actual sound pipeline in use.

## Carry policy and diagnostics

`PlanTransport` is a preflight for a rigid assembly; `CommitTransport` checks membership/physics identity and synchronously writes poses. It does not guarantee atomic native VPhysics behavior. Assembly sizes, local constraint lengths and local angular velocities are preserved; independent loose props keep the upstream-style scaling route. Conservative OBB aperture and destination AABB checks can block geometrically valid narrow fits. Self/directed physical transfer and remote-proxy grab handoff are excluded.

After an attempted native carry test, run `seamless_portals_transport_status` on the server (console/admin). It prints the last carry kind, a sampled native-hold state, physics-identity check and tick. It is diagnostic evidence, not an automatic fix or comprehensive pass/fail certification. Also available: `seamless_portals_dump_movement`, `seamless_portals_dump_sweeps`, `LastRenderStats`, `PVSStats[ply]`.
