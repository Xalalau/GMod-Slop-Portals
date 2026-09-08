# Second gameplay fix batch

Status on 2026-09-08. This remains an incomplete preview. User confirmation refers to manual testing in the running game, not full dedicated multiplayer acceptance.

| Item | Status | Change / evidence |
| --- | --- | --- |
| 1. Returning self damage | Confirmed by user | `e456f51`, `8b9eaab`, `06dbcf2`: hitscan owner exclusions and returning crossbow owner hits. Dedicated native crossbow: one 25-damage leg hit, original attacker and bolt inflictor, no captured Lua errors. |
| 2. Remote physgun pickup and Alt+Shift | Assigned to another agent | Excluded from this agent's remaining scope at the user's request. |
| 3. Held physgun halo | Confirmed by user | `160d36c`: skip Sandbox halo collection during clipping; restore normal collection after exit. Client native hook transition checked. |
| 4. Tracer trajectory | Confirmed by user | Bounded moving streaks with full-precision endpoints. Capture the muzzle during viewmodel drawing and convert its projection to the world camera; out-of-draw attachment queries returned stale coordinates. Native client capture and manual portal/strafing confirmation; dedicated observer acceptance remains pending. |
| 5. Spawn overlay alignment | Confirmed by user | `358fe88`: draw the spawn refraction overlay in the current portal camera. |
| 6. Intermittent crossbow passage | Assigned to another agent | Excluded from this agent's remaining scope at the user's request. |
| 7. Grenade passage | Assigned to another agent | Excluded from this agent's remaining scope. |
| 8. Released/rolling prop physics | Assigned to another agent | Excluded from this agent's remaining scope. |
| 9. Held prop oscillation | Assigned to another agent | Excluded from this agent's remaining scope. |
| 10. FacePoser beam, marker and halo | Confirmed by user | `5eda5ed`, `358fe88`: segmented tool effects and portal camera/marker adapters. |
| 11. RPG aim rendering | Assigned to another agent | Excluded from this agent's remaining scope at the user's request. |
| 12. NPC portal navigation | Assigned to another agent | Excluded from this agent's remaining scope at the user's request. |
| 13. Light/Lamp illumination | Confirmed by user | Transmit Sandbox Light/Lamp color, range and direction with an aperture mask and cleanup on disable, unlink and removal. Up to four client projectors; dedicated observer acceptance remains pending. |
| 14. Camera tool feedback | Pending; rejected change removed | Initial `5eda5ed` was insufficient. The user rejected `3d8f67a`; it was removed from history and its changes were undone without a revert commit. Programmatic segment checks did not establish correct visual behavior. |
| 15. Trail continuity | Assigned to another agent | Excluded from this agent's remaining scope. |

Visual changes must be demonstrated in the game or confirmed by the user before committing.

The user's game was restarted during testing. Fresh control probes confirmed both realms in singleplayer Sandbox `gm_construct`. The agent's separate local dedicated session uses Sandbox `gm_flatgrass` on port 27025, with test bots and no human observer. Tests in these topologies do not replace dedicated prediction/network acceptance with a second client.

Offline suites use Lua 5.4 API doubles. The tracer validation run had 151 passing checks and the two existing sound failures C-T42/C-T43; 56 normalized Lua syntax checks passed. These totals include concurrent source changes and do not establish their native acceptance. Results and native JSON/captures are outside the addon source, under `/tmp/seamless-tracer4-*` and `data/seamless_tests/tracer4_*`. Later runs must be reported separately.
