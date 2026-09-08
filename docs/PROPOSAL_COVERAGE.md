> **RC3 preview notice:** The RC2 record below is historical where superseded. See [2026.09.08-field-rc3-preview](FIELD_FIXES_PREVIEW.md) for the current F00–F10 scope, incomplete integration and two retained sound-test failures. Older successful test counts do not describe this preview.

# Current proposal coverage — Custom RC2

82 ordered stages: B01–B34, R01–R10, O01–O12, INT01–INT11, C01–C15. The first 67 diffs are preserved; C stages deliberately supersede selected RC1 restrictions. `AppliedProposalCount=56` still denotes original findings, not the stage count.

Native acceptance is pending for every engine-dependent feature. The authoritative current root document is `PATCH_PROPOSALS.md` in the complete bundle.

| Original ID | Custom follow-ups | Current interpretation |
|---|---|---|
| B01 | None | Retained RC1 implementation/guards; no new native certification. |
| B02 | None | Retained RC1 implementation/guards; no new native certification. |
| B03 | None | Retained RC1 implementation/guards; no new native certification. |
| B04 | None | Retained RC1 implementation/guards; no new native certification. |
| B05 | None | Retained RC1 implementation/guards; no new native certification. |
| B06 | None | Retained RC1 implementation/guards; no new native certification. |
| B07 | None | Retained RC1 implementation/guards; no new native certification. |
| B08 | C02 | Four-side exclusion replaced by polygon aperture/border implementation. |
| B09 | C06, C07 | Blanket constraint refusal replaced by validated rigid-group and carry transactions. |
| B10 | C06 | Retained RC1 implementation/guards; no new native certification. |
| B11 | C03 | Retained RC1 implementation/guards; no new native certification. |
| B12 | C03 | Retained RC1 implementation/guards; no new native certification. |
| B13 | C03 | Retained RC1 implementation/guards; no new native certification. |
| B14 | C04 | Retained RC1 implementation/guards; no new native certification. |
| B15 | C04 | Single-center-ray refusal replaced by per-actual-pellet continuation. |
| B16 | None | Retained RC1 implementation/guards; no new native certification. |
| B17 | None | Retained RC1 implementation/guards; no new native certification. |
| B18 | None | Retained RC1 implementation/guards; no new native certification. |
| B19 | None | Retained RC1 implementation/guards; no new native certification. |
| B20 | None | Retained RC1 implementation/guards; no new native certification. |
| B21 | None | Retained RC1 implementation/guards; no new native certification. |
| B22 | None | Retained RC1 implementation/guards; no new native certification. |
| B23 | None | Retained RC1 implementation/guards; no new native certification. |
| B24 | None | Retained RC1 implementation/guards; no new native certification. |
| B25 | None | Retained RC1 implementation/guards; no new native certification. |
| B26 | C06 | Retained RC1 implementation/guards; no new native certification. |
| B27 | C06 | Retained RC1 implementation/guards; no new native certification. |
| B28 | C01, C11, C15 | Retained RC1 implementation/guards; no new native certification. |
| B29 | None | Retained RC1 implementation/guards; no new native certification. |
| B30 | None | Retained RC1 implementation/guards; no new native certification. |
| B31 | None | Retained RC1 implementation/guards; no new native certification. |
| B32 | C09 | Retained RC1 implementation/guards; no new native certification. |
| B33 | C01, C11 | Retained RC1 implementation/guards; no new native certification. |
| B34 | C04 | Retained RC1 implementation/guards; no new native certification. |
| R01 | C06 | Retained RC1 implementation/guards; no new native certification. |
| R02 | C10 | Retained RC1 implementation/guards; no new native certification. |
| R03 | C01 | Retained RC1 implementation/guards; no new native certification. |
| R04 | C06 | Retained RC1 implementation/guards; no new native certification. |
| R05 | C11 | Retained RC1 implementation/guards; no new native certification. |
| R06 | C07, C08, C09 | Carry, tick-normalized funneling, vector momentum and ACK bridge; native prediction/controller tests pending. |
| R07 | None | Retained RC1 implementation/guards; no new native certification. |
| R08 | None | Retained RC1 implementation/guards; no new native certification. |
| R09 | C05, C11 | Default-on server/client spatial relay; complete native loop/stop lifecycle still absent. |
| R10 | C02 | Retained RC1 implementation/guards; no new native certification. |
| O01 | C10 | Retained RC1 implementation/guards; no new native certification. |
| O02 | C10 | Retained RC1 implementation/guards; no new native certification. |
| O03 | None | Retained RC1 implementation/guards; no new native certification. |
| O04 | None | Retained RC1 implementation/guards; no new native certification. |
| O05 | None | Retained RC1 implementation/guards; no new native certification. |
| O06 | C08, C14 | Retained RC1 implementation/guards; no new native certification. |
| O07 | None | Retained RC1 implementation/guards; no new native certification. |
| O08 | C05 | Retained RC1 implementation/guards; no new native certification. |
| O09 | None | Retained RC1 implementation/guards; no new native certification. |
| O10 | C03 | Explicit APIs retained; dynamic global traversal is now enabled by default. |
| O11 | C15 | Retained RC1 implementation/guards; no new native certification. |
| O12 | C11, C15 | Retained RC1 implementation/guards; no new native certification. |
| INT01 | None | Retained RC1 implementation/guards; no new native certification. |
| INT02 | None | Retained RC1 implementation/guards; no new native certification. |
| INT03 | None | Retained RC1 implementation/guards; no new native certification. |
| INT04 | None | Retained RC1 implementation/guards; no new native certification. |
| INT05 | None | Retained RC1 implementation/guards; no new native certification. |
| INT06 | None | Retained RC1 implementation/guards; no new native certification. |
| INT07 | None | Retained RC1 implementation/guards; no new native certification. |
| INT08 | None | Retained RC1 implementation/guards; no new native certification. |
| INT09 | None | Retained RC1 implementation/guards; no new native certification. |
| INT10 | None | Retained RC1 implementation/guards; no new native certification. |
| INT11 | C15 | Retained RC1 implementation/guards; no new native certification. |

## Custom stages

- **C01: Custom behavior flags and callbacks.** Separate player, prop, damage, sound and funnel controls; legacy NWBool keys; duplication persistence; Hammer keys/inputs; safe entry/exit usage callbacks. Players, props, sound and damage default on. Funneling defaults off, as in the supplied custom.
- **C02: Polygon cutouts instead of a four-side exclusion.** One clockwise aperture definition for rendering, ray checks, geometric preflight and convex border prisms. Includes 50-sided Portal Gun apertures without changing their legacy size semantics. C12 corrects boundary membership and prism winding.
- **C03: Default-on segmented traces with dynamic ownership.** Up to eight traversals by default, configurable per trace from zero to sixteen; preserves filters, caller output table, original-ray fraction and segment records. The global detour installs only while usable links exist and restores the saved function when it still owns the outer function. C12/C13 fix destination aperture checking and a Lua multiple-return argument bug.
- **C04: Default-on actual-pellet bullet continuation.** Wraps the native Bullet.Callback after the actual spread ray hits a portal. Each outgoing continuation has Num=1 and zero additional spread, preserves IgnoreEntity and callback intent, reduces range, and is limited to eight crossings. C12 carries force/damage metadata per segment and retains Damage=0 ammo semantics.
- **C05: Default-on spatial sound across source/exit visibility regions.** Server EntityEmitSound events are sent to recipients in the exit room PAS, independently of source-entity PVS. Client-owned invisible emitters preserve source identity and never move the actual source. Up to two paths per event, 64 server paths per tick and 64 client emitters. Handles explicit stop flags, channel replacement, unlink cleanup and cross-realm duplicate coalescing. C12/C13 correct recursion guards, cleanup and PAS origin.
- **C06: Constraint graph transaction retaining physics identity.** Collects the constrained graph, inspects world endpoints, preflights aperture fit and exit obstruction, maps the whole assembly with one rigid transform and common clearance, and preserves each body, local angular velocity, motion state and constraint identity. Validates before writing and attempts rollback after a Lua write failure. Held/constrained proxies are one-way projections rather than controllers feeding corrections into the real object.
- **C07: Carry through with E, physgun and gravity-gun pickup records.** Tracks confirmed successful pickups rather than permission queries. The player Move hook plans and commits the held prop/group before publishing the destination player pose. It does not call DropObject, ForcePlayerDrop, PickupObject or PhysicsInit on this route. Blocked transactions keep the holder and stay on the entry side. The authoritative server also updates view angles used by a native controller.
- **C08: Per-portal, tick-normalized funneling.** Ports the custom approach guidance and weaker correction during lateral input. Runs in predicted Move, preserves speed, limits eligibility to living walking players moving faster than run speed, and normalizes the blend across tick intervals.
- **C09: Ping-aware view bridge and server carry audit.** Adds a bounded ping/tick camera bridge and ordered multiplayer transition acknowledgments, using absolute mirror state rather than a second blind toggle. Adds an admin-readable post-commit native-hold/PhysObj-identity audit. Existing singleplayer transition handling remains.
- **C10: Preserve the newer renderer; port missing-sky behavior.** Keeps the newer bounded, distance-ordered two-target compositor and existing cleanup. Uses actual polygon visibility anchors and adds cached six-face 2D sky fallback when a portal RenderView has no visible sky, without globally replacing halo.Add.
- **C11: Usable controls, one-time defaults migration and clone damage ownership.** Adds the Portal Behavior tool and creation checkboxes, raw portal targeting with a second CanTool permission check, FGD settings/inputs, one-time migration of old archived opt-out convars, and independent DamageInfo forwarding from clone to real entity.
- **C12: First integration hardening pass.** Corrects traversal callback argument order, closed clipping boundaries and top/bottom winding, exit aperture checks, recursive audio vetoes, emitter cleanup/channel ownership, per-segment bullet metadata, world NoCollide treatment, held-group admission and controller-safe commits. Retired proxies no longer run another coupling tick.
- **C13: Feature tests and validation-driven corrections.** Adds 50 custom checks and updates superseded RC1 assertions to the new requirements. Fixes Lua multiple-return expansion passing an Angle as an aperture margin; discovers sound recipients from the exit room rather than a virtual source inside a wall; uses a movement tick interval and checks the hit entity class.
- **C14: Full Move-hook tests and reliable module execution checks.** Adds ten tests covering actual player Move wiring with E/physgun/groups/obstructed exits/mirrors plus sky cleanup and budgets. Tests load source modules in function-scoped chunks, check that assertions are actually reached, and use mutable ConVar doubles. Player momentum now uses the already-tested direction transform rather than a direction→Angle→direction detour.
- **C15: Current feature contract, native acceptance and reproducible expanded bundle.** Synchronizes runtime metadata, installation/configuration/release documents, feature comparison, proposal coverage, attribution and the manual native compiler/smoke file. Completes the cumulative C category, per-patch records and source/evidence manifests.
