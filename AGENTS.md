# AGENTS.md

Instructions for agents working on Seamless Portals, a Garry's Mod addon for linked portal views, player/prop transport, portal tools, and supported trace, damage, sound, projectile, and NPC interactions.

## Context and Project Map

- Start with `README.md` and `docs/FIELD_FIXES_PREVIEW.md`. The current source identifies itself as `2026.09.08-field-rc3-preview` / `PREVIEW_INCOMPLETE` in `lua/seamless_portals/core.lua`.
- This is an already integrated addon mounted at `garrysmod/addons/seamless`. Do not reapply historical patches or mount a second copy alongside it.
- `CONFIGURATION.md`, `HAMMER.md`, `docs/TESTING.md`, and `docs/CUSTOM_COMPARISON.md` describe configuration, map integration, validation, and inherited behavior. Read their RC3 notices: some RC2 contracts and successful test counts are historical.
- This checkout has Git metadata and retains the upstream history. It has no `addon.json`, `TODO.txt`, or full-bundle `patches/` directory. Use the local validation tools below; bundle reconstruction commands require the separate bundle.
- Preserve `LICENSE` and the upstream/custom attribution in `NOTICE.md`.
- Use the Facepunch wiki for uncertain GLua/GMod behavior, realms, hooks, physics, prediction, rendering, ConVars, networking, tools, or Workshop packaging: https://wiki.facepunch.com/gmod

Read the affected implementation and its callers before changing behavior:

| Area | Files |
|---|---|
| Early initialization and shared API | `lua/autorun/000_seamless_portals_core.lua`, `lua/seamless_portals/core.lua` |
| Geometry and per-portal features | `lua/seamless_portals/aperture.lua`, `crossing.lua`, `features.lua`; `lua/entities/seamless_portal/sh_init.lua` |
| Portal lifecycle, clones, and cutouts | `lua/entities/seamless_portal/init.lua`, `cl_init.lua`; `lua/entities/seamless_portal_clone.lua`, `seamless_portal_cutout.lua` |
| Player movement and held/constrained props | `lua/autorun/sh_player_teleport.lua`; `lua/seamless_portals/holding.lua`, `transport.lua`, `carry.lua`, `held_proxy.lua`, `funneling.lua` |
| Detours, traces, damage, audio, and NPC adapters | `lua/autorun/sh_detours.lua`; `lua/seamless_portals/traces.lua`, `bullets.lua`, `bullet_emitter.lua`, `tracers.lua`, `blasts.lua`, `projectiles.lua`, `sound.lua`, `sound_loops.lua`, `npc_awareness.lua` |
| Rendering and visibility | `lua/autorun/client/cl_render_core.lua`, `cl_seamless_entity_clip.lua`, `cl_seamless_mirror_physgun.lua`; `lua/autorun/server/sv_portals_pvs.lua`; `lua/seamless_portals/skybox.lua`; `lua/cl_portal_flashlight.lua` |
| Tools, weapon, and configuration | `lua/weapons/gmod_tool/stools/portal_*_tool.lua`, `lua/weapons/portal_gun.lua`; `lua/seamless_portals/client_config.lua`, `tool_features.lua`, `custom_defaults.lua`; `./seamless_portals.fgd` |
| Diagnostics and development helpers | `lua/autorun/sh_seamless_diagnostics.lua`, `lua/autorun/ai_tools_init.lua`, `lua/ai_tools/` |
| Offline validation and native smoke | `tools/check_source.py`, `tools/validate_release.py`, `validation/ai_tools_tests.lua`, `validation/`, `lua/seamless_portals/tests/smoke.lua` |

Bare filenames in a table cell share the preceding directory.

## Coding Rules

- Make small GLua changes compatible with Sandbox-derived gamemodes. Keep gameplay state under `SeamlessPortals` (usually `local SP = SeamlessPortals`) or the owning entity; avoid new loose globals.
- Preserve the early core loader and the separate autorun/entity entry points. Server logic must remain server-side; rendering/UI must remain client-side. Send shared/client dependencies with `AddCSLuaFile` before client includes.
- Read the actual include order before adding dependencies. Core loads features, aperture, and crossing helpers; the early autorun loads transport/holding/carry helpers; `sh_detours.lua` loads the trace, damage, audio, and related adapters.
- Preserve public APIs, entity class names, ConVars, network names, NetworkVar slots, duplication keys, and Hammer keys/inputs unless migration is requested. Use the existing `seamless_portals_`, `SEAMLESS_PORTALS_`, or `SeamlessPortals` naming convention for new runtime registrations.
- Register settings in the owning module. Shared tool geometry settings use `client_config.lua` / `SP.ClientConVars`; per-portal behavior uses `features.lua` and `tool_features.lua`. Wire relevant tool controls, duplication, Hammer support, and `CONFIGURATION.md` together. Preserve the versioned defaults migration in `custom_defaults.lua` and later user choices.
- Use `SP.IsPortal`, `SP.IsLiveEntity`, and `IsValid` as appropriate before touching removable entities or physics objects, especially in delayed callbacks. Do not admit portals already marked for deletion.
- Keep movement, physics, rendering, trace, sound, and NPC hot paths bounded. Reuse portal registries and existing budgets; avoid broad `ents.GetAll()` scans without a demonstrated need.
- Keep client input bounded and validated, with authoritative server checks for mutations. Preserve ownership/protection, quota, and `CanTool` checks, including rechecking the actual target after a portal-aware trace is retargeted.
- Make hooks, timers, helpers, and detours safe to reload and clean up. Do not overwrite another addon's wrapper when restoring a detour; restore the saved base only while the owned wrapper is still outermost.
- Prefer plain Lua/GMod APIs over runtime dependencies. Keep comments short and useful.

## Behavior Invariants

- Validate finite dimensions and integral side counts with the shared helpers. Keep aperture geometry consistent across rendering, traces, physical cutouts, and transport admission. Preserve compatible linked aspect ratios and coherent `Configure` / `ConfigurePair` updates.
- Respect features at both portal endpoints through `SP.LinkAllows`. Prefer `SP.SetFeature` over raw NWBool writes so inverted legacy flags, duplication, and traversal cleanup remain consistent.
- Player movement crosses client prediction and server authority. Preserve transition ordering, mirror state, velocity/angle transforms, and completed-transfer notifications without duplicating them during predicted retries.
- Held/group transfer must preserve the real entity, physics bodies, constraints, and native hold. Do not fix transport by deleting constraints, rebuilding physics, or silently dropping/regrabbing. Refuse unsupported, oversized, anchored, or blocked groups while retaining the hold. Keep rigid held/group size policy distinct from loose-prop scaling.
- Restore collision, clipping, clones, proxies, and pending traversal state on exit, withdrawal, release, disable, resize, unlink, removal, and map cleanup. Collision ownership across clone and held-proxy paths is a known integration concern.
- Preserve trace filters, output identity, hop/range budgets, and raw-trace escape paths. Damage continuation must retain attribution/callback intent and avoid duplicate hits, effects, or recursive relays.
- Restore render targets, clipping, stencil, depth, and other changed render state on all paths. Keep client rendering budgets and server PVS budgets separate.
- Treat sound, blast, projectile, and NPC implementations as bounded adapters. Extend documented support only with evidence; the current NPC adapter does not provide portal navigation or universal NextBot support.

## Language

- Reply to users in their language.
- Keep code comments, identifiers, technical docs, menu text, and default commit messages in concise English unless asked otherwise.

## Runtime Workflow

- For documentation-only edits, inspect the referenced files and validate the document; starting Garry's Mod or injecting probes is unnecessary.
- Before runtime work, inspect previous artifacts and their timestamps. Existing `data/seamless_tests` and legacy `data/nbc_tests` files may belong to another session/addon and do not prove this addon or its helpers are loaded.
- Use this mounted addon with older Workshop/custom copies disabled. Baseline: multiplayer/LAN Sandbox on `gm_flatgrass`; use dedicated multiplayer and a second observer for prediction/network changes. Singleplayer alone is insufficient for those paths.
- Confirm loading with a timestamped probe in each tested realm, preferably through `lua/ai_tools/sh_playground.lua` once its loading is verified. Do not rely on sandboxed `ps` to establish that the host game is running.
- The helper loader sends/includes the explicit `ai_tools/` manifest in both realms. Restart server and clients for the first NBC-to-Seamless migration; use the load probe below before relying on scratchpad hotload.
- Install error monitoring in each tested realm before executing probes, then inspect and flush captured errors after the test. Fix errors introduced by the change.
- Lua hotloads on save, but hooks/timers and persistent tables can survive. Save dependencies before consumers. Restart server and clients for new includes, loading changes, or state that cannot be safely reinitialized.
- Place test entities near the player (around 160 units) or a suitable spawn/test area. Prevent player interference where appropriate; retain intentional NPC targets for targeting tests.
- Remove temporary hooks/timers/entities and restore the playground to its original first comment line before delivery. Keep useful evidence until reviewed, then remove only artifacts belonging to the current test.

Launch a local test session when needed:

```sh
steam -applaunch 4000 -console -novid +sv_lan 1 +maxplayers 2 +gamemode sandbox +map gm_flatgrass
```

## AI/Test Helpers

`lua/autorun/ai_tools_init.lua` sends all five helper modules and the playground with `AddCSLuaFile` before including helpers in both gameplay realms. APIs are available immediately, including after a loader hotload. The explicit manifest must be updated when adding a module. The empty `sh_playground.lua` runs after `InitPostEntity` in Sandbox-derived gamemodes, when entity/player access is ready. Loader reloads rerun it only after this realm has seen that hook; for a late first include, run the playground explicitly or restart the session. Saving an already included playground can hotload it immediately, so temporary probes must guard `SERVER` / `CLIENT` and validate entities.

Helpers now own `SeamlessPortals.AI`, `SEAMLESS_PORTALS_AI_` hook/timer/network/render-target names, and `data/seamless_tests` outputs. There is no `NBC.AI` alias or dependency. Restart server and clients after migrating: legacy NBC hooks/timers and in-flight callbacks from a manually included old helper can survive hotload, and must not be removed blindly when NBC is also installed.

Loading helpers does not spawn entities, install error capture, open UI, download Workshop content, or enable extra PVS. The playground must be restored to its original first comment line before delivery. There is no `sh_error_capture_tests.lua` or inherited synthetic suite in this tree.

With console Lua enabled, verify a fresh load in **each realm**:

```text
lua_run print("Seamless AI", SeamlessPortals.AI.Realm, SeamlessPortals.AI.LoadedAt, os.date("!%Y-%m-%dT%H:%M:%SZ"))
lua_run_cl print("Seamless AI", SeamlessPortals.AI.Realm, SeamlessPortals.AI.LoadedAt, os.date("!%Y-%m-%dT%H:%M:%SZ"))
```

If the new loader was introduced mid-session, `lua_openscript autorun/ai_tools_init.lua` and `lua_openscript_cl autorun/ai_tools_init.lua` can load its APIs temporarily. A clean restart is still required to validate automatic startup and client file delivery. `LoadedAt` is the last successful loader timestamp in that realm, not proof that a specific probe ran.

| Module / API | Realm and behavior |
|---|---|
| `ErrorCapture.Install`, `Reset`, `Capture`, `Flush`, `Cleanup` | Call separately on server/client. Installs `OnLuaError` plus a one-second dirty-log timer only on demand. Defaults to `lua_errors_server.json` / `lua_errors_client.json` under `data/seamless_tests`, avoiding a listen-server file collision. Captures errors after installation; does not forward client errors to the server. |
| `Files.Cleanup(options)` | Either realm, local DATA filesystem. Recursively deletes the selected directory's contents; `keep` preserves named files/directories. Inspect ownership first; prefer a probe-specific subdirectory. |
| `WorldCapture.CaptureEntity`, `CapturePoint`, `CaptureAt`, `CaptureFirst`, `CapturePlayerView` | Client captures PNG + JSON; defaults to `world_capture.png` / `.json`. Offscreen captures default to at most 1024 pixels on the longest side. `FindTargets` / `SelectTarget` work in either realm; provide explicit filters to search. |
| `WorldCapture.InstallPVS`, `Cleanup` | Explicit server opt-in for offscreen client cameras. Accepts only admin requests with finite, bounded coordinates, at most ten requests/second/player and three seconds per origin. Server cleanup disables requests, clears origins and removes visibility/disconnect hooks; the pooled network name and an inert receiver remain. Client cleanup cancels pending capture hooks/timers. |
| `Menu.OpenTool(toolName, options)`, `CaptureTool(toolName, options)` | Client only; default tool is `portal_creator_tool`. Also accepts `portal_fitter_tool`, `portal_behavior_tool`, `portal_resizer_tool`, or another Sandbox tool name. Uses menu-only activation. Replaces `OpenNBCOptions` / `CaptureNBCOptions`; no NBC panel checks remain. |
| `Menu.GetActiveControlPanelTree(options)`, `Cleanup` | Client tree includes controls, text, ConVars and bounds. Cleanup cancels timers/hooks; it does not close the spawnmenu or restore cursor position. |
| `Workshop.DownloadAndExtract(wsid, options)` | Client Steamworks download/extraction, only when called; does not mount or execute downloaded Lua. Defaults to `workshop_<id>.dat`, `workshop_<id>_inspect.json`, and a timestamped extraction directory under `data/seamless_tests`. Extracted files normally gain `.dat`; `ExtractGMA(path, options)` can inspect an existing DATA archive in either realm. Download callbacks/retries cannot currently be cancelled; let them finish before deleting their output or restarting helpers. |

Example calls inside a temporary playground/probe (or prefix individual statements with `lua_run` / `lua_run_cl` in the appropriate console):

```lua
local AI = SeamlessPortals.AI
-- Run in each realm, before probes. Override logPath before Install if needed.
AI.ErrorCapture.Reset()
AI.ErrorCapture.Install()
-- After the test, persist evidence before uninstalling the monitor.
AI.ErrorCapture.Flush(true)
AI.ErrorCapture.Cleanup()

if SERVER then
    AI.WorldCapture.InstallPVS() -- Enable before a client offscreen capture.
end
if CLIENT then
    AI.WorldCapture.CaptureEntity(LocalPlayer())
    -- Or a nearby point without requesting extra PVS:
    AI.WorldCapture.CapturePoint(LocalPlayer():GetPos() + Vector(160, 0, 64), {
        cameraOrigin = LocalPlayer():EyePos(), addToPVS = false
    })
    AI.Menu.CaptureTool("portal_behavior_tool") -- Opens, waits, then captures.
    -- After opening has finished:
    AI.Menu.GetActiveControlPanelTree({ printTree = true })
    -- Call only when compatibility inspection requires this download:
    -- AI.Workshop.DownloadAndExtract("addonWsid")
end
-- After asynchronous captures finish, in each tested realm:
AI.WorldCapture.Cleanup()
AI.Menu.Cleanup()
-- Only after reviewing this probe's artifacts:
-- AI.Files.Cleanup({ dataDir = "seamless_tests/my_probe", keep = { "evidence.json" } })
```

Capture/menu methods returning `true` mean queued, not successful. Wait for `WorldCapture.lastResult.status == "done"`, `Menu.lastResult.finished`, or `Menu.lastCapture.ok`, and inspect their JSON/timestamps. A later capture replaces a pending capture of the same kind. Opening a tool changes the visible spawnmenu and may enable/move the cursor; `enableCursor = false, moveCursor = false` suppress those cursor actions for `OpenTool`. `CaptureTool(..., { open = false })` captures the currently active panel without opening one. Tree inspection proves UI structure, not tool gameplay.

Output overrides are DATA-relative: `ErrorCapture.logPath`; `Menu.logPath`, `capturePath`, `captureMetaPath`, `treePath`; capture options `imagePath` / `metaPath` (world), `path` / `metaPath` (menu), and `path` (tree); `Files.dataDir` / cleanup `dataDir`; `Workshop.dataDir` / `outputRoot` / `resultPath`. Parent directories are created for writes. Keep world captures generic by passing entities, filters, or camera positions. Separate probe directories and timestamps are still required for multiple clients sharing a filesystem.

The error monitor uses [OnLuaError](https://wiki.facepunch.com/gmod/GM:OnLuaError); tool activation follows [spawnmenu.ActivateTool](https://wiki.facepunch.com/gmod/spawnmenu.ActivateTool). Neither API establishes native rendering, physics, prediction or gameplay acceptance.

## Validation

For behavior changes, run applicable offline checks from the addon root and write results outside the mounted source:

```sh
python3 tools/check_source.py .
python3 tools/validate_release.py . --results /tmp/seamless-validation
```

- The full validator requires Python 3.10+ and a discoverable Lua 5.4 shared library. It runs textual gates, regression/integration/custom suites, normalized Lua syntax, and Python syntax checks.
- For helper/loader changes, also run `lua5.4 validation/ai_tools_tests.lua` from the addon root (requires the Lua 5.4 executable). These six separate checks execute the helper sources with API doubles: loading in both realms, idle startup, NBC isolation, reload/error-log lifecycle, PVS validation/cleanup, and correct tool-panel selection. They are not included in `validate_release.py` totals and do not prove native error-hook delivery, file transmission or rendering.
- Executable tests use Lua 5.4 with GMod API doubles. Normalization is not native GLua compilation, and doubles do not establish physics, rendering, prediction, networking, audio, or AI correctness.
- The recorded RC3 preview baseline in `docs/FIELD_FIXES_PREVIEW.md` is 126 passing tests and two failures: C-T42 (sound veto-hook recursion) and C-T43 (sound opt-out/network budget). Treat these as recorded evidence, rerun for current results, and investigate without suppressing failures or relaxing assertions merely to pass.
- Pending integration includes blast chain-reaction recursion, clone collision restoration, native E/physgun carry, and dedicated F00–F10 tests. Keep these visible until relevant checks demonstrate resolution.
- If Git metadata is available, run `git diff --check`. Otherwise compare against a saved original and check whitespace directly; do not initialize a repository just to validate an edit.
- For Lua changes, use LuaLS when available with a GLua-aware configuration (LuaJIT/Lua 5.1, runtime includes, and GMod definitions). There is currently no `.luarc.json`; unconfigured warnings are not reliable GMod diagnostics. Look in an installed LuaLS VS Code extension if the binary is absent from PATH, or suggest installation. Plain `luac -p` cannot parse all GLua syntax.

Native smoke commands for a development session with console Lua enabled:

```text
lua_openscript seamless_portals/tests/smoke.lua
lua_openscript_cl seamless_portals/tests/smoke.lua
```

The smoke script compiles its listed sources and checks a subset of APIs; it does not cover all field-fix modules or gameplay. Extend relevant coverage when changing code outside its list.

Use `docs/FIELD_FIXES_PREVIEW.md` and the applicable rows in `docs/TESTING.md` for native acceptance. Check startup errors, Creator/Fitter/Behavior/Resizer and Portal Gun, geometry/links, held and loose props, blocked exits, cleanup/collision restoration, rendering/PVS, and changed damage/audio/projectile/NPC paths. For carry/network changes, include E/physgun retention, constraints, mirror state, and multiplayer observers. Record tested realms, topology, map, relevant ConVars, and observed outcomes.

Movement/carry diagnostics include `seamless_portals_debug_movement`, `seamless_portals_dump_movement`, `seamless_portals_debug_sweeps`, `seamless_portals_dump_sweeps`, and `seamless_portals_transport_status`. Diagnostic samples are not proof of native controller retention or continuous collision detection.

## Delivery

- Report changed files, resulting behavior or documentation, validation actually run, and remaining limitations.
- Explicitly say when Garry's Mod manual testing was not run. Keep offline results distinct from native acceptance.
- Do not mark this preview engine-validated or update release claims based only on static checks or test doubles.
- Do not make commits, tags, releases, Workshop updates, ZIPs, or `.gma` artifacts unless requested.
- When packaging is requested, inspect `tools/build_release.py` and write output outside the addon. Its current allowlist includes `lua/` except paths containing a `tests` component, so `lua/ai_tools/` and its autorun loader are not automatically excluded. Review development-helper inclusion and remove temporary probes before packaging.
