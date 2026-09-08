# Gravity gun through portals

The normal `weapon_physcannon` can punt and pull movable physics props through a
reciprocal portal pair with prop traversal enabled at both endpoints. The portal
and its visual clones cannot be picked up or receive the native punt.

- Primary fire traces through up to four portal links and applies the native
  mass-weighted impulse to the real physics bodies, in the transformed aim
  direction. Range is spent on both sides of each portal.
- Secondary fire can start a native hold through one portal pair within the
  normal grab reach, spending range on both sides. Farther targets are pulled
  toward the player's unfolded position with the native pull force and
  light-object mass adjustment until they enter grab reach.
- Permission checks target the real entity. Frozen, already held, parented,
  excluded or unsupported targets are refused. Pulling also respects the native
  mass limit and rejects world-anchored constraint groups without changing them.
- Local interactions and launching an already held object continue through the
  native weapon. Existing aperture, group-size and exit-obstruction checks apply
  to carried objects.

The adapter reads `physcannon_tracelength`, `physcannon_pullforce` and
`physcannon_maxmass`. Pull reach is four times punt reach. Remote pull work is
limited to ten attempts per second per active weapon; physics bodies and portal
hops have explicit limits. This is support for ordinary movable physics items,
not universal support for NPCs, the supercharged gun or scripted weapons.

Remote pickup shares the existing native selection-handle adapter in
`remote_pickup.lua`. A hidden handle with the target's physics mesh is welded
to the original body before the native gravity gun selects it. The real group
is unfolded into the holder's room and represented at the exit by its existing
portal proxy. A confirmed `GravGunOnPickedUp` records the real target and its
native controller separately. The same hold survives the player's crossing;
release removes only the owned handle and weld. Original entities, physics
bodies and constraints remain intact. The handle keeps its original collision
bounds while selected because the gravity gun stores their center as its grip.

## Feedback and native carry

The confirmed punt sends a segmented orange beam through the existing bounded
tracer channel, including the shooter and observers in the path's PVS. The first
leg uses the weapon muzzle; later legs start at their exits. Additive animated
materials, a fading impact glow and sparks preserve transparency. The receiving
client plays the native firing animation. The false portal `TooHeavy` sound is
suppressed without muting normal gravity-gun sounds.

The native grab controller evaluates its previous target before updating it for
the player's new location. A large portal displacement otherwise produces a
backward impulse followed by an automatic drop. A completed gravity-gun transfer
sleeps the existing bodies for that stale physics step. During the next command,
`StartCommand` temporarily rebases only their physics poses for the native error
sample; `SetupMove` restores the committed destination before physics advances.
A fallback and lifecycle hooks restore any interrupted rebase. The pending table
survives reloads. No controller is detached, no object is re-grabbed, and no motion
flag, original PhysObj or constraint is replaced.

The grip also retains its natural reach when approaching the opening. The
native controller otherwise contracts it at the brush wall behind the portal
and when the player hull narrows for traversal. A shared command adapter
calculates the normal grip radius from the original player hull and the held
physics mesh. It temporarily offsets the native controller's eye origin during
`ItemPreFrame`, restoring the actual view offset in `SetupMove` before movement,
firing and rendering. Ordinary cover and disabled, reversed or invalid links
still use the native wall response. Interrupted commands, release and reload
restore the offset without overwriting a newer value from another addon.

Mesh support is cached per physics object, with at most 4,096 triangle vertices;
spheres use their physics bounds. More complex meshes retain the native grip.

## Evidence (2026-09-08)

Fresh monitored hotload probes used the existing dedicated multiplayer Sandbox
`gm_flatgrass` session and the existing singleplayer `gm_construct` server/client.
Native input was generated only for a temporary test bot; no desktop input,
focus change or map restart was used.

Run: `gravitygun_20260908_081545` under `data/seamless_tests`.

- Remote punt moved the original crate away from the exit; remote pull crossed
  the crate and produced a single native pickup retained for the observation.
- A wall-mounted portal initially reproduced a backward kick, automatic drop
  and return through the portal. The completed bridge retained the native hold
  for ten seconds with the original physics body (`bridge3_dedicated.json`).
- A welded crate and can crossed to a 90-degree exit, retained both physics
  bodies and the original weld, then launched on native primary fire. Their
  final separation was 24.015 units for an initial 24-unit weld
  (`bridge4_dedicated.json`). Only the intended launch caused a drop event.
- Client recordings of actual session punts report firing activity 182 and
  separate entry/exit beam legs. Completed player-view captures show the orange
  beam and impact without a black rectangle (`watch1_client.json`, `beam1.png`).
  Beam width, glow and spark density were subsequently increased.
- The completed gameplay probes and server/client compile smoke reported no Lua
  errors. One exploratory probe used an invalid zero-return `tostring` call;
  the probe was corrected and rerun successfully. It is not runtime addon code.

The follow-up run `gravity_distance_20260908_085728` used the same confirmed
realms and topology:

- The wall fixture reproduced a moving grip distance falling from 59.07 to
  35.07 units. With compensation, it remained 59.07 units throughout the
  approach and crossing; stationary distance remained 66.57 units
  (`baseline1_dedicated.json`, `integrated1_dedicated.json`). These moving
  measurements include the normal one-tick controller lag at 500 units/second.
- A walking bot maintained 64.85 units through the narrowed hull and a
  90-degree exit, settling at 66.65 units after stopping. The native hold and
  physics body were retained, with no drop event (`walk1_dedicated.json`).
- A welded crate and can stopped near the wall and eight units from it,
  withdrew, crossed a 90-degree exit, then launched with primary fire. Settled
  grip distance remained approximately 66.58 units, the weld and both bodies
  survived, and only the requested launch caused a drop (`wall2_dedicated.json`).
- The user's `metalbucket01a.mdl` was checked with an upward aim and a
  100-by-147.1, eight-unit-thick portal. Its settled grip distance stayed at
  54.951 units before entry, with its center 13.643 and then 45.001 units beyond
  the entrance, and after withdrawal; it was 54.952 after crossing. The exit
  proxy remained present while the player stayed before the entry, and only
  primary fire released the hold (`bucket2_dedicated.json`).
- Completed samples used the original eye offset outside the command adapter;
  gameplay probes and the final three-realm smoke reported no Lua errors.
  An exploratory read-only watcher called server-only `IsPlayerHolding` in the
  client realm; that probe was corrected and rerun. The adapter does not make
  that client call.

The later run `gravity_live_20260908_091446` reproduced the reported failure with
both endpoints on world walls (`pair1_dedicated.json`). The previous distance
tests had used an exit in open space. As the proxy emerged, its growing hull
started a sweep inside the exit wall and incorrectly restored the source handle.
Gravity-gun carry now checks the remaining sweep after leaving that initial
overlap. Solid destinations and subsequent obstacles still block movement.
The same wall-pair fixture then retained its native hold and 54.95-unit settled
distance (`pair2_dedicated.json`).

Remote pickup produced a confirmed native hold on the selection handle, retained
the original target body and continued through the wall pair, withdrawal and
native primary launch (`remote3_dedicated.json`). A second case started with the
player before the entry and the bucket about 27 units beyond it, then crossed
to a wall exit rotated 90 degrees with the same hold (`remote4_dedicated.json`).
The normal native controller and welded handle retain a small settling motion;
these checks establish roughly 55-unit reach, not a perfectly fixed per-frame
distance. Releasing with secondary fire before crossing left the real bucket at
the remote exit and removed the owned handle and weld; no native-pickup state
remained (`remote5_dedicated.json`). The completed probes reported no Lua errors.

The full offline validator recorded 312 passing checks, 61/61 normalized Lua
syntax checks and the two existing sound failures, C-T42 and C-T43. All 29 gravity
gun checks and all 20 native-pickup checks passed. LuaLS found no diagnostics in
the gravity-gun module; the shared pickup/proxy modules also have pre-existing
dynamic-entity type diagnostics under the available GLua definitions.

Offline regressions in `validation/gravitygun_tests.py` cover range, permissions,
force direction, clone mapping, pickup limits, trace/visual segmentation,
transparency/animation, native bridge ordering, grip distance, cover and
interruption cleanup in both realms. They
use Lua doubles and do not establish engine behavior.

No manual control test was performed by the agent. A dedicated human client with
a second observer, client prediction under latency, all portal orientations and
every supported constrained assembly remain outside this acceptance evidence.
The addon remains an incomplete RC3 preview.

Native reference: [Facepunch gravity-gun hooks](https://wiki.facepunch.com/gmod/GM:GravGunPunt)
and [Valve's HL2 multiplayer physcannon implementation](https://github.com/ValveSoftware/source-sdk-2013/blob/master/src/game/shared/hl2mp/weapon_physcannon.cpp).
