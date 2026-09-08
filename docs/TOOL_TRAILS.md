# Trail Tool portal crossings

`tool_trails.lua` splits Sandbox Trail Tool effects after completed loose-prop,
rigid-group and supported-projectile transfers. The old trail stays visible at
the source position while its native points expire. A new trail follows the
object at the exit. Rapid crossings retain each unexpired segment; retired
replacements are removed after the configured lifetime plus a small cleanup
margin.

The original `SToolTrail` entity remains the tool's undo/cleanup handle. Its
rendering is disabled only after its history expires. Undo, right-click removal,
reapplication, cleanup and parent deletion remove its replacements, including
segments still fading. Material, color, alpha, width, lifetime and duplication
data are preserved. Failed transport commits do not split the trail.

## Native attachment limitation

The server wraps `util.SpriteTrail` for attachment zero, creating the same native
sprite with ordinary parenting. A temporary `info_target` supplies the native
factory's required attachment and is removed immediately after the sprite is
reparented. Nonzero attachments retain the original factory behavior. The
wrapper is installed once and survives reloads without replacing a later
addon's wrapper.

This is necessary because native sprite attachment handles cannot be cleared
with `SetSaveValue`; merely calling `SetParent(NULL)` leaves rendering attached
to the original object. Sources: [GMod SpriteTrail API](https://wiki.facepunch.com/gmod/util.SpriteTrail)
and [native sprite-trail renderer](https://github.com/ValveSoftware/source-sdk-2013/blob/master/src/game/shared/SpriteTrail.cpp).

**Trails created before this module loaded must be reapplied once.** Their
existing native point history cannot be rebound. They are left untouched by
this adapter. Existing portal instances also need the updated entity code when
hotloading; normal startup loads it automatically.

## Validation, 2026-09-08

- The whole-workspace validator passed 315 checks and all 61 normalized Lua
  syntax checks. The two pre-existing sound failures, C-T42 and C-T43, remain.
- The isolated commit passed 284 checks and 60/60 normalized Lua syntax
  checks, with the same two sound failures. All six helper checks passed.
  GLua-configured LuaLS reported no issues in the new module and loader.
- Nine focused offline cases (`TT-T01`–`TT-T09`) cover native-factory ownership,
  visible retirement, source positions, repeated crossings, expiry, failed
  allocation, rollback, projectiles, removal and reload.
- Automated native probes used the existing dedicated multiplayer Sandbox
  `gm_flatgrass` server and singleplayer `gm_construct` server/client. No session
  was restarted. Tick interval was 0.015 seconds; gravity was 600.
- Loose-prop and welded-group transfers retained the real physics bodies and
  weld. Blocked exits retained their original trail. Undo, right-click removal,
  reapplication, duplication and parent cleanup passed native lifecycle checks.
- Three immediate splits kept their earlier segments alive before expiry and
  removed retired replacements afterward while retaining the active trail.
- Client samples with portals 800 units apart showed the moving source trail
  retain 21 native points after crossing, then fall to one as they expired.
  Its visible render bounds stayed below 97 units. The original handle remained
  visible for its configured 2.5-second lifetime before becoming hidden.
- Probe evidence is under DATA `seamless_tests/tool_trails_20260908_091016/`.
  `fade1`/`fade2` had empty captured error logs. `fade3` additionally refreshed
  the portal entity definition for the listen server; a concurrent playground
  probe raised an unrelated missing `GetTable` error during that run.

The user confirmed that the visible behavior worked after this change.
A dedicated multiplayer client observer, clean-startup file delivery and broad
addon compatibility were not tested. This is focused
native evidence, not full preview acceptance.
