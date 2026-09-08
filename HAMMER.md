# Custom RC2 behavior additions

The current FGD adds `disablePropTeleport`, `disablePlayerTeleport`, `disableDamageTransfer`, `disableSoundTransfer` (all stored default 0, meaning enabled), and `enableFunneling` (default 0, meaning off). Matching Enable/Disable inputs are documented in [CONFIGURATION.md](CONFIGURATION.md). Player and prop outputs remain `OnTeleportFrom` / `OnTeleportTo`. A held player is blocked as a unit when prop transfer is disabled; it is not forcibly dropped.

Old SEv map-instance schemas and the missing `sev_portal` class are not automatically migrated. Keep `seamless_portal` entities in this build. Directed links support the existing player/render/trace use cases, not physical held/assembly transport.

## Retained geometry and linking guide

# Using Seamless Portals with Hammer

## Setup
Before using Seamless Portals with Hammer, you have to install an additional FGD.
Firstly, drop the seamless_portals.fgd file into your GarrysMod\bin folder.
Then, for it to show up on Hammer, open Tools->Options->Game Configurations->Game Data files, press Add and choose the seamless_portals.fgd file.

![](https://i.imgur.com/tpkzAEG.png)

## Placing Portals
You can create a portal by placing a seamless_portal entity.

You have to calculate the portal position and size yourself. X and Y are height and length, they are simple.
For example, if you want your portal to fit into a 128x128 hole, just set X and Y to 127.9 and place the entity into the middle.
The Z size is how thick the back of the portal is. You will likely want to keep this greater than 7 to avoid flickering during teleport.
If you see Z-fighting, just place the portal further away from the wall or slightly adjust the scale of the Z axis.
The portal angles have to point from the portal surface side. You can see which way the entity is pointing by selecting it in the 2D view.

To connect your portals, you must name them with unique names and link them with the Linked Portal property.

### An example of two portals:
![](https://i.imgur.com/R8oYKH8.png)
![](https://i.imgur.com/yDXoxfJ.png)

Now the portals are set up. If you compile the map and run it with the addon turned on, you will see your portals working properly.

### Final result:
![](https://i.imgur.com/pGVx7lb.png)

# Mapping Tips
1. Do not make your portals super thin, they should be at least 8 units thick (z axis) to avoid flashing, thicker if possible
2. Portals effectively rerender the entire scene, so try and keep whatever world geometry is visible from a portal semi optimized.
3. Ensure the wall geometry around each portal seam is basically perfect, so you don't get stuck mid-teleport. Ground too, though the portals will attempt to extrude you upward as best they can.


# Integrated RC1 compatibility notes

The `link` keyvalue and `Link` input require a unique target name resolving to another portal. Links are directed; use reciprocal endpoint names for two-way pairs. Width/height aspect ratios must match. Rendering, player and eligible line-trace paths are retained for directed links, but **physics prop cutouts require distinct reciprocal four-sided pairs**. Nonrectangular portals and nonreciprocal directed networks do not admit props in this build.

`OnTeleportFrom` and `OnTeleportTo` are emitted after a completed supported prop transfer as well as for players. Native output timing, map conversion and the sampled geometry still need testing on the actual map. The original legacy format conversion is retained; this build does not implement a canonical-polygon migration. See `RELEASE_NOTES.md` before replacing an addon used by an existing map.
