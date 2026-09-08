# Context-menu actions through portals

The client selected props through the global portal trace, but Sandbox rejected
their property messages using direct world distance. `ignite` could appear in the
menu and send its message successfully while doing nothing on the server.

`seamless_portals/properties.lua`, loaded server-side by `sh_detours.lua`, extends
`properties.CanBeTargeted` for targets outside the ordinary range. It checks a
visible path through one linked portal pair with the shared aperture/occlusion
helpers and retains Sandbox's 1024-unit range plus the target's OBB allowance.
Ordinary targets retain the saved function's result. Property receivers and their
`CanProperty` permission checks still run on the actual player and entity.
The adapter follows `seamless_portals_global_trace`, checks at most 64 registered
portals and permits at most 16 visibility queries per player per server tick.
Reload and shutdown preserve later wrappers installed by other addons.

## Evidence and limits

Fresh native probes used the existing Sandbox singleplayer session on
`gm_construct`, with `seamless_portals_global_trace=1`. Run ID:
`context_20260908_084731`, under `data/seamless_tests/`.

- Before the change, the stock client `ignite:Action` message ignited the nearby
  control prop, but the remote prop stayed unlit: direct distance 1801 units,
  portal path 276 units, property filter allowed, server range check rejected.
- After the change, the same stock action ignited both test props. The remote
  prop was 1769 units away directly and 295 units along the portal path.
- The stock `extinguish:Action` message subsequently extinguished both test props.
- A server `CanProperty` veto rejected both client action messages, including a
  remote prop admitted by the adapter (1793 units directly, 270 via the portal).
- Native compile/API smoke ran on that client/server and on the existing
  dedicated `gm_flatgrass` server. No captured Lua errors occurred in these probes.

Eight passing offline regressions cover range, ordinary targets, target geometry,
occlusion, aperture/link admission, request budgets, permissions and wrapper
ownership. They run as part of `tools/validate_release.py`. The isolated commit
snapshot recorded 266 passing tests and 59/59 normalized Lua syntax checks. The two existing sound
failures, C-T42 and C-T43, remain outside this fix. LuaLS with LuaJIT/GLua definitions
reported no diagnostics for the new module; the rest of the checkout retains
existing diagnostics.

No manual C/right-click test, clean startup test or second multiplayer observer
test was performed. The dedicated server had no human clients, so its smoke result
does not establish multiplayer property-message acceptance. The fallback tests
the target's OBB center through one portal pair; chained portal views or props
whose center is occluded remain outside this adapter's coverage. This does not
change the preview's release-validation status.
