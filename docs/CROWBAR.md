# Crowbar portal impacts — 2026-09-08

The native crowbar now uses its miss animation when a portal has no reachable target. Its separate flesh-hit sound is suppressed on the portal in both realms, before portal audio relay. The existing server continuation still applies damage once and emits the impact at the remote target. Floor and wall impacts explicitly set the world entity index: `IsValid(worldspawn)` is false, and a fresh `EffectData()` can retain the entity set by an earlier effect.

The 75-unit trace budget includes the distance to the entry and the remaining transformed segment. Damage must be enabled globally and at both endpoints. Cover, backface admission and hop limits still use the existing segmented trace. The crowbar's native attack timing, player gesture, ordinary local hits and other weapons remain under their existing handlers. No portal collider or movement/physics behavior is changed.

The shared sound check matches the native line trace, shortened melee hull and nearest corner refinement at aperture edges. Animation correction runs in `DoAnimationEvent`, after the native swing selects its viewmodel sequence, without replacing the gamemode's gesture handler. Server hit results survive target removal until that animation event. The damage continuation remains server-only; the loader now sends the shared melee module to clients.

## Verification

For the isolated commit source, `check_source.py` passes and `validate_release.py` reports **228 passing checks, two failures**, with **57/57 normalized Lua syntax checks**. The failures remain C-T42 and C-T43 in the existing sound suite. The 51 field regressions pass, including ten new crowbar checks for audio vetoes in both realms, local-hit preservation, hull refinement, range, cover/settings, world effect data, miss animations and target removal. Six separate AI helper checks pass with an idle playground. These checks use API doubles, not the engine.

LuaLS ran with LuaJIT, GLua syntax extensions and GMod definitions on the four affected Lua files. It reported no melee diagnostics and 17 warnings in existing sound code about nil inference and ConVar flag types; this is not a clean project-wide diagnostic result.

Fresh probes used the existing dedicated multiplayer Sandbox session on `gm_flatgrass` and the existing singleplayer server/client on `gm_construct`. The run ID is `crowbar_20260908_075834`, under `data/seamless_tests`. Native smoke passed in all three tested realms, and the final `final2_*` error logs are empty. Two temporary probe errors involving realm-specific APIs were corrected before the final smoke pass.

Dedicated native crowbar swings used a bot in an isolated test area, with damage enabled. The observed cases were:

| Case | Result |
|---|---|
| Nearby remote crate | One 10-damage hit and one remote effect per swing; hit animation retained. |
| Remote crate beyond range | No remote damage/effect; `ACT_VM_MISSCENTER` after the next swing. |
| Remote ground and vertical map wall | World impact effects at the traced surface with entity index 0; hit animation retained. |
| Exit damage disabled | No remote damage/effect; miss animation. |
| Crate in front of the entry | Ordinary native damage and hit animation. |

The baseline captured the erroneous `Weapon_Crowbar.Melee_Hit` sound for empty remote paths. Follow-up probes confirmed the sound veto and native hit/miss sequence correction. Synchronous server/client checks also confirmed that successive `EffectData()` wrappers retain the previously assigned entity, motivating the explicit world reset.

The crowbar probe, bot, temporary entities and instrumentation were removed. Other concurrently active test probes were preserved. Manual graphical testing by the agent and a second multiplayer observer were not run. Automatic client file delivery after a clean restart remains untested; the running client was hotloaded explicitly. This does not change the RC3 preview's release acceptance status.

API references: [EntityEmitSound veto](https://wiki.facepunch.com/gmod/GM:EntityEmitSound), [DoAnimationEvent](https://wiki.facepunch.com/gmod/GM:DoAnimationEvent), [world entity index in effect data](https://wiki.facepunch.com/gmod/CEffectData:SetEntIndex).
