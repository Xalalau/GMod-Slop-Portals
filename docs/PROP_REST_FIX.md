# Loose prop settling at vertical portals — 2026-09-08

Loose props spanning a portal could keep rocking or spinning after contact with
both floors. A low-speed resting tolerance alone helped an upright barrel but
still reproduced sustained rotation with a tilted bucket.

`lua/entities/seamless_portal_clone.lua` now couples linear motion at each
physics body's mass center. It converts both angular velocities into the same
physical frame before averaging and converts the result back into the clone's
frame. Local angular vectors are interchangeable only while both poses match;
contact corrections can make those poses differ. See the Facepunch references
for [GetMassCenter](https://wiki.facepunch.com/gmod/PhysObj:GetMassCenter),
[GetAngleVelocity](https://wiki.facepunch.com/gmod/PhysObj:GetAngleVelocity) and
[LocalToWorldVector](https://wiki.facepunch.com/gmod/PhysObj:LocalToWorldVector).

When both bodies have friction contacts, the coupling tolerates 0.5 Source units
of center separation and an angular surface displacement of two units, capped
at three degrees. Only error beyond that margin produces a correction. A narrow
additional settling band lets coherent bodies with small velocities settle
without repeated velocity writes. Matching sleeping bodies remain asleep;
missing support, larger motion or a divergent pose resumes synchronization.

The change does not call `Sleep`, freeze loose props, increase their mass or
friction, add damping, choose a resting side, or reposition a freely moving
body. Motion enablement is written only when its state changes. The existing
held/constrained path and the real physics object's identity are retained.
The earlier floor/collision-pair fix is recorded separately in
[PROP_FLOOR_FIX.md](PROP_FLOOR_FIX.md), commit `99cecd3`.

## Native evidence

Monitored hotload probes ran in the existing singleplayer Sandbox session on
`gm_construct`, with fresh server/client output, `sv_gravity = 600` and
`phys_timescale = 1`. No desktop input, map change or restart was used.
Rectangular vertical portals measured `(100, 147.1, 8)`; the final pair used the
opposing walls at X = ±1014.96875, Y = -430, Z = -93.86875.

Eight twelve-second cases retained the same real PhysObj with motion enabled
throughout. No sample reported a player hold interfering with the fixture.

| Case | Observed result |
|---|---|
| Tilted bucket, trash bin, paint can, crate, upright barrel | Native sleep; zero linear/angular velocity and one unchanged position/owner throughout the last three seconds |
| Push the sleeping real barrel | Woke, moved, then returned to native sleep |
| Push its sleeping remote clone | Real barrel woke, moved, then returned to native sleep |
| Remove supporting props | Fell about 40 units, landed and continued rolling freely |

The push probes set an initial velocity; they establish wake/response, not
subjective resistance under native E, physgun or gravity-gun controls. The
supported barrel still had small residual motion before its supports were
removed (about 0.55 units/s), so that case does not establish sleep on arbitrary
prop assemblies. The initial support fixture intersected the portal's top rim
and was rejected; the final fixture fits inside the aperture.

All five resting model cases and both push cases retained a clone at the seam.
Their late samples show no side alternation. Native smoke passed in both realms
and the final monitors recorded no Lua errors. Floor-plane clearance in the
wall probes ranged down to -1.39 units during contact; these probes do not
establish zero penetration for every collision vertex or map surface.

Evidence is under
`garrysmod/data/seamless_tests/prop_rest_20260908_091941/`, particularly
`final_acceptance_server.json`, `final_acceptance_client.json` and their error
logs. `baseline_server.json` records the original continuing barrel rotation;
`contactslop_server.json` still reproduces bucket rotation, while
`angularframe_server.json` records sleep for bucket, trash bin and paint can.

## Offline checks and limits

`validation/regression_tests.py` adds P51–P59 for settling without writes,
contact loss, remote wake/response, mass-center offsets, contact torque,
large-error correction, angular reference frames and changed sleeping poses.
In-memory counterfactuals removing the relevant protections fail P51, P54, P55
and P57. These are explicit Lua API doubles, not a native physics simulation.

Manual Garry's Mod testing was not performed by the agent. Dedicated multiplayer
observers, differently oriented/scaled portal pairs, constrained assemblies and
broad native pickup/release acceptance remain unvalidated. The preview release
status is unchanged.
