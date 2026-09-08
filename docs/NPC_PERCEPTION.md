# Native NPC portal perception

The attention adapter in `lua/seamless_portals/npc_awareness.lua` represents a
verified player or NPC beyond a portal with a non-solid `npc_bullseye` just in front of
the entrance. Hostile native NPCs can acquire it without holding a weapon. Only
the existing armed humanoid classes receive a forced ranged attack schedule;
guards, mines, scanners and turrets choose their native reactions.

Acquisition preserves the native view cone, script state, actor relationships,
`ai_disabled`, `ai_ignoreplayers`, endpoint feature switches and visibility on
both sides. A visible native enemy takes priority. Live Rollermines have zero
numeric health, so eligibility checks the native life state. The existing
distance, candidate and 32-proxy budgets remain in place. Ground navigation is
handled separately by [the navigation adapter](NPC_NAVIGATION.md).

Wall Combine cameras discard non-player targets after inspecting them. While a
remote player remains visible, the adapter renews the camera's interest in its
own proxy. Disabled cameras and the Ignore Enemies spawnflag remain respected.
The native tracker follows the entrance target; this does not turn the proxy
into a player or reproduce player-specific camera outputs and flash behavior.

When a shot loses its portal path, attention expires on the next server Think.
It must not clear the enemy or remove the proxy inside `EntityFireBullets`: the
native floor turret still reads its enemy after firing. Cleanup also preserves
an enemy replaced by native AI before the expired record is retired.

## Evidence on 2026-09-08

The existing local dedicated server ran Sandbox `gm_flatgrass`, with a protected
test bot, linked portals and an opaque obstruction blocking direct sight. No
human multiplayer observer was present. Fresh probes also confirmed the human
session's server and client in singleplayer Sandbox `gm_construct`.

- Native guards, ants, zombies/headcrabs, manhacks, Rollermines, both scanner
  classes and floor/ceiling turrets acquired portal targets. The camera's native
  tracking angles converged on the portal target. These observations do not
  establish every class-specific attack or scripted output.
- A floor turret fired 24 native shots during 12 forced losses and recoveries of
  the portal path. Loss occurred inside the actual shot callback. All 12 shots
  retained a valid enemy until the callback returned, then retired the proxy.
  The server completed the test without a crash or captured Lua errors.
- The user confirmed Antlion Guard/Rollermine reactions and confirmed that
  leaving the firing sentry's view no longer closes the game.
- Field regressions F-T30 through F-T35 exercise acquisition, native life state,
  deferred shot cleanup, enemy ownership and perception opt-outs with API
  doubles. They do not replace native AI acceptance.

Native evidence is outside the mounted source in
`data/seamless_tests/npc_sight_20260908_0620/`, notably `attention_4.json`,
`general_1.json`, `general_2.json`, `camera_state_2.json` and `sight_loss_1.json`.
Earlier fixture attempts in that directory include probe errors and invalid
geometry; they are not passing evidence. Large aircraft/striders, universal
NextBots, special melee attacks and full multiplayer observation remain outside
this acceptance claim.

## NPC enemies and allies

The scheduler considers players and a rotating batch of up to 64 registered NPCs
per update, retaining active targets outside that batch. NPCs cannot target
themselves or the adapter's proxies. Hostile targets take priority over nearby
allies; hostile attention can reclaim a friendly proxy when the shared 32-proxy
budget is full. `ai_ignoreplayers` excludes players without disabling NPC-to-NPC
perception.

Each stand-in receives the observer's relationship to its real target, as
reported by `Disposition(target)`. Only hostile records
assign an enemy, write enemy memory or request a ranged attack. Friendly records
provide a visible allied stand-in and an eye/yaw target without creating an
enemy. Relationship changes rebuild the owned record and retire its old proxy.
This is perception and ranged combat support, not remote healing, squad dialogue
or every scripted interaction with the real ally's class.

Native `actors_1.json` records two turrets attacking through an opaque wall and
linked portals, then stopping when made allies and resuming when made enemies.
Both had visible friendly proxies with `D_LI`, no assigned enemy and no shots
during the allied phase. Moving a target outside the aperture retired both
records; returning it restored combat without crashing.

`actors_combat_4.json` and `actors_combat_5.json` repeat the relationship test
with an armed Combine and Citizen. Both acquired the other NPC and dealt damage
through the portal. A protected bot marked `FL_NOTARGET` kept native humanoid AI
active; it was excluded from perception targets. Initial attempts without a bot
left native humanoid eye/AI updates dormant and did not establish acceptance.
F-T37 through F-T41 cover NPC targets, friendly transitions, empty player lists,
proxy prioritization and target-batch rotation with API doubles.
The user confirmed that NPC enemies now recognize and attack each other through
the portals in their running game.
An already-running native burst can finish after a relationship or sight change;
the adapter does not cancel ordinary bullets already being emitted.

## Rollermine passage

Rollermines now enter the physical cutout/clone path alongside loose physics
objects. The original entity and native physics object survive transfer, so the
mine continues its own pursuit controller on the exit side. Different-sized
links refuse mine admission: generic prop rescaling rebuilds physics and cannot
preserve this native controller. Ordinary prop scaling remains unchanged.

A dedicated six-second native pursuit test recorded 60 samples, a portal
transfer and continued pursuit/contact with the remote bot. Every sample kept
the original physics object. The user also confirmed passage through equal-sized
portals. Evidence is `roller_1.json` in the directory above; F-T36 covers class
admission and the rescaling refusal with API doubles.

## Offline validation

The final working-tree run passed all 41 field checks, the textual gates and all
58 normalized Lua syntax checks. The full validator reported 206 passes and
three failures: the existing C-T42/C-T43 sound checks and the concurrently edited
physgun `resting-contact-escape` fixture, which lacked `table.Copy`. Results are
in `/tmp/seamless-npc-final-validation/`. These totals include other agents'
navigation/physgun changes and are not a release acceptance claim.

GLua-aware LuaLS reported the same six diagnostics observed before the NPC actor
extension: custom entity fields, ConVar flag definitions and the existing
`EnableCustomCollisions` call signature. Native compilation succeeded for both
changed Lua files in the tested realms. Temporary probes and their owned hooks,
timers, entities and bots were removed after collecting evidence.
