# Frag grenade crossing fix

Native `npc_grenade_frag` grenades could bounce off a linked portal during a
normal fast throw. The projectile adapter predicted one physics step, but the
grenade also casts a forward ray after that step. Its native bounce could reverse
the velocity before the adapter's next tick.

`projectiles.lua` now predicts both steps for this class. The existing checks for
source obstacles, both apertures, enabled endpoint damage features and a clear
exit still govern transfer. Other projectile classes retain their prediction
interval. The grenade entity, owner, physics body and native fuse are preserved.

The extra ray is visible in Valve's
[CGrenadeFrag::VPhysicsUpdate implementation](https://github.com/ValveSoftware/source-sdk-2013/blob/master/src/game/server/hl2/grenade_frag.cpp).
Native probes below reproduced the corresponding early velocity reversal.

## Validation on 2026-09-08

Evidence run: `grenade_20260908_084531`, under `data/seamless_tests/`.
Fresh probes confirmed the existing dedicated multiplayer Sandbox server on
`gm_flatgrass` and the separate singleplayer server/client on `gm_construct`.
Gameplay cases ran on the dedicated server; monitored smoke checks ran in all
three realms. Tick interval was 0.015 seconds, gravity was 600, and damage and
projectile transport were enabled.

- Baseline: five of 18 throws failed to transfer; another rebounded before
  eventually transferring. Failures included straight and oblique fast throws.
- Fixed: all 18 repeated throws transferred without a preceding collision.
  These used speeds of 80, 300 and 1000 units/s, with gravity and spin, through
  free-standing, wall and floor entrances.
- A further 18 throws passed at 600, 1200 and 2000 units/s, straight and at
  45 degrees, through wall, floor and downward-facing entrances. Physics body,
  fuse deadline and angular velocity were retained at transfer. An earlier
  diagnostic aimed nine oblique trajectories outside the opening; all nine
  were refused. The final matrix aimed them through the opening.
- Eight refusal cases passed: source obstacle, blocked exit, aperture miss,
  approach from behind, movement away, either endpoint disabled, and unlinking.
- Captured Lua errors were empty. Temporary entities, hooks and timers were
  removed and the playground was returned to its idle comment.
- Offline regressions F-T42–F-T46 cover the early native ray, obstacles, endpoint
  switches, approach direction and the bounded, class-specific prediction.
- Validation of the isolated commit contents: 258 offline checks passed;
  existing sound failures C-T42 and C-T43 remained. All 46 field regressions,
  58 normalized Lua syntax checks and 11 Python syntax checks passed. Textual
  gates and staged whitespace checks passed. GLua-configured LuaLS reported the
  same two pre-existing type warnings as the unchanged projectile source.

These were automated native probes using spawned grenades. Manual weapon throws,
graphical inspection and a second multiplayer observer were not tested. This
fix does not change the addon's preview release status or claim support for
third-party grenade classes.
