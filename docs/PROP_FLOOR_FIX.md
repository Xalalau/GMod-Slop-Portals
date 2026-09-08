# Prop floor collision fix — 2026-09-08

Loose barrels could sink through the floor while entering a portal or after
being released across its plane. Two independent faults caused this:

- Cutout surface probes used `Lerp` with fractions outside `[0, 1]`. GMod
  [clamps those fractions](https://wiki.facepunch.com/gmod/Global.Lerp), so the
  probes stopped at the aperture border and missed floors slightly below it.
  Explicit interpolation now reaches the intended surrounding surfaces.
- The reused `logic_collision_pair` remembers whether its last input succeeded.
  An enable following another enable could silently skip a different pair,
  leaving a returning prop or proxy without support. The helper's `m_succeeded`
  cache is now reset before each input; admission fails if that reset fails.
  This cache is visible in Valve's
  [native implementation](https://github.com/ValveSoftware/source-sdk-2013/blob/master/src/game/server/logicentities.cpp).

Cutouts record their mesh revision. Existing meshes from before this fix are
retired through the normal traversal cleanup and rebuilt on the next update.
The real prop and its physics body are retained; the fix adds no drop/regrab,
constraint deletion, velocity clamp or artificial upward offset.

Implementation: `lua/entities/seamless_portal_cutout.lua` and the mesh revision
check in `lua/entities/seamless_portal/init.lua`. Regression coverage is in
`validation/regression_tests.py`, P46–P50. These five checks fail against the
corresponding previous implementations and pass with the fixes.

## Observed native results

Fresh hotload contact was confirmed in server and client realms of the existing
singleplayer Sandbox session on `gm_construct`. No map change, restart or
desktop input was used. The updated entity definitions were explicitly
registered through the monitored playground before acceptance testing.

The original wall drop fell below Z = -3442 with the nearby floor around
Z = -144. Correcting surface probes alone still reproduced the return-crossing
failure. After both fixes, five six-second cases completed with 201 samples
each. Clearance measures the lowest collision-mesh vertex against the traced
local floor plane, including the sloped terrain at the exit.

| Case | Transfers | Minimum floor clearance, Source units | Result |
|---|---:|---:|---|
| Roll through a freestanding pair | 1 | 0.220 | Remained above ground |
| Roll through a wall pair | 1 | 0.100 | Remained above ground |
| Drop across the plane and cross back | 2 | 0.119 | Remained above ground |
| Unlink the pair during the drop | 1 | 0.236 | Settled on the floor |
| Remove the pair during the drop | 1 | 0.236 | Settled on the floor |

Every sample retained the original PhysObj. All five cases ended without a
clone or cutout membership. Native smoke passed in both realms and the error
monitors recorded no Lua errors. Temporary test entities and timers were
removed. This task's playground block was removed; probes belonging to other
concurrent tasks were preserved.

Evidence: `garrysmod/data/seamless_tests/prop_floor_20260908_090002/`, especially
`baseline_server.json`, `acceptance_server.json`, `acceptance_client.json` and
the corresponding error logs. The fixture uses
`models/props_c17/oildrum001.mdl`, rectangular portals sized `(100, 147.1, 8)`,
`sv_gravity = 600` and `phys_timescale = 1`.

## Offline checks and remaining acceptance

`check_source.py` and `git diff --check` passed. The full validator recorded
308 passing checks, the two existing C-T42/C-T43 sound failures, and 61/61
normalized Lua syntax checks. Results are outside the addon at
`/tmp/seamless-prop-floor-validation`. Other tasks were editing this checkout,
so these totals describe that validation snapshot.

LuaLS was run with LuaJIT/GLua syntax support and GMod definitions. Dynamic
entity fields and the shared `ENT` definitions still produce diagnostics;
this is not a clean whole-addon LuaLS report.

Manual Garry's Mod testing was not performed. The drop fixture starts a loose
barrel at the crossing plane; it does not validate native E/physgun controller
release. Dedicated multiplayer observers, constrained carry, other prop
models, high-speed traversal, differently sized portals and broad map geometry
remain acceptance work. These results do not change the preview release status.
