#!/usr/bin/env python3
"""Physgun pickup regressions with API doubles, not native physics acceptance."""
import argparse
import json
from pathlib import Path

from lua_support import Lua, normalize


def main(root, output):
    here = Path(__file__).resolve().parent
    base = (here / "stubs.lua").read_text() + (here / "custom_stubs.lua").read_text()
    for name in ("core", "aperture", "crossing", "holding", "physgun_pickup"):
        base += "\ndo\n" + normalize((root / f"lua/seamless_portals/{name}.lua").read_text()) + "\nend\n"
    base += """
IN_ATTACK,IN_WALK,IN_SPEED=1,262144,131072
local p,e,a=player(),prop(),portal()
local keys={}
function p:KeyDown(key) return keys[key]==true end
"""
    cases = [
        ("npc-permission-query", "NPC handle selection preserves target permissions without recording a speculative hold", """
local SP=SeamlessPortals
function e:IsNPC() return true end
function e:GetMoveType() return 3 end
assert(hook.Run('PhysgunPickup',p,e)==false)
local raw=hook.Run
local veto=false
hook.Run=function(event,ply,ent)
 local result=raw(event,ply,ent)
 if result~=nil then return result end
 return not veto
end
assert(SP.CheckNativePickupPermission(p,e))
assert(hook.Run('PhysgunPickup',p,e)==false)
veto=true
assert(not SP.CheckNativePickupPermission(p,e))
assert(not SP.GetHeldRecord(p))
hook.Run=raw
function e:GetMoveType() return MOVETYPE_VPHYSICS end
assert(hook.Run('PhysgunPickup',p,e)==nil)
"""),
        ("npc-handle-release", "A released NPC restores its motor and removes only the temporary handle and constraint", """
local SP=SeamlessPortals
MOVETYPE_NONE=0
local handle,link=prop(),prop()
local mode=0
function e:GetMoveType() return mode end
function e:SetMoveType(v) mode=v end
local record={entity=e,group={e,handle}}
local state={plan={root=e},record=record,handle=handle,weld=link,ply=p,confirmed=true,npcMoveType=3}
record.nativePickup=state
SP.NativePickupStates[handle]=state;SP.NativePickupTargets[e]=state
local physics=e:GetPhysicsObject()
SP.ClearCarryState=function(r) assert(r==record);r.group=nil end
hook.Run('Think')
assert(mode==3 and e:GetPhysicsObject()==physics)
assert(not IsValid(handle) and not IsValid(link))
assert(not SP.NativePickupStates[handle] and not SP.NativePickupTargets[e])
"""),
        ("native-npc-hold", "Confirmed non-VPhysics NPC grabs remain tracked until the native drop hook", """
local SP=SeamlessPortals
function e:IsNPC() return true end
function e:GetMoveType() return 3 end
assert(not e:IsPlayerHolding())
hook.Run('OnPhysgunPickup',p,e)
TICK=TICK+5
assert(SP.GetHeldRecord(p).entity==e)
hook.Run('PhysgunDrop',p,e)
assert(SP.GetHeldRecord(p)==nil and not SP.HasTrackedHold(e))
function e:GetMoveType() return MOVETYPE_VPHYSICS end
hook.Run('OnPhysgunPickup',p,e)
TICK=TICK+5
assert(SP.GetHeldRecord(p)==nil)
"""),
        ("npc-beam-grip", "NPC beams use the shadow body's frame instead of the animated pelvis bone", """
CLIENT=true;SERVER=false
function Material() return {} end
local handle=prop()
handle:SetNWBool('seamless_portals_physgun_entity_grab',true)
p:SetNWEntity('seamless_portals_native_physgun_handle',handle)
p:SetNWEntity('seamless_portals_held',e)
function p:GetNWInt() return 0 end
function p:GetNWVector() return Vector(1,2,30) end
function p:EyePos() return Vector(0,0,64) end
function e:GetBoneMatrix() error('NPC shadow grip must not use animated bones') end
function e:GetNWEntity() return NULL end
""" + normalize((root / "lua/autorun/client/cl_seamless_mirror_physgun.lua").read_text()) + """
local path=SeamlessPortals.NativePhysgunSegments(p)
assert(#path==1 and path[1].finish:DistToSqr(e:LocalToWorld(Vector(1,2,30)))<0.0001)
"""),
        ("portal-view-muzzle", "The exit view keeps the main viewmodel muzzle even when it renders the local avatar", """
CLIENT=true;SERVER=false
function Material() return {} end
function LocalPlayer() return p end
function FrameNumber() return 5 end
local weapon,vm=prop(),prop()
local first=Vector(15,8,55)
function p:GetActiveWeapon() return weapon end
function p:ShouldDrawLocalPlayer() return self.thirdperson==true end
function p:GetViewModel() return vm end
function p:EyePos() return Vector(0,0,64) end
function weapon:GetClass() return 'weapon_physgun' end
function weapon:LookupAttachment() return 1 end
function vm:LookupAttachment() return 1 end
function weapon:GetAttachment() return nil end
function vm:GetAttachment() return {Pos=first} end
""" + normalize((root / "lua/autorun/client/cl_seamless_mirror_physgun.lua").read_text()) + """
local SP=SeamlessPortals
SP.CachePhysgunMuzzle()
local main=SP.PhysgunMuzzle(p,weapon)
assert(main:DistToSqr(first)<0.0001)
p.thirdperson=true;SP.Rendering=a
SP.CachePhysgunMuzzle()
assert(SP.PhysgunMuzzle(p,weapon):DistToSqr(main)<0.0001)
assert(SP.PhysgunMuzzle(p,weapon):DistToSqr(p:EyePos())>1)
SP.Rendering=nil
SP.CachePhysgunMuzzle()
assert(SP.PhysgunMuzzle(p,weapon):DistToSqr(p:EyePos())<0.0001)
"""),
        ("existing-native-beam", "An ordinary hold keeps the engine beam and adds only the directly visible exit segment", """
CLIENT=true;SERVER=false
function Material() return {} end
function LerpVector(t,a,b) return a+(b-a)*t end
local frame=10
function FrameNumber() return frame end
local b=portal();b.pos=Vector(500,0,0);a.exit=b;b.exit=a
local SP=SeamlessPortals
function SP.TransformPortal(entry,exit,point)
 local p=entry:WorldToLocal(point)
 return exit:LocalToWorld(Vector(-p.x,p.y,-p.z))
end
function p:EyePos() return Vector(0,0,100) end
function e:GetNWEntity() return a end
function e:TranslatePhysBoneToBone() return 0 end
function e:GetBoneMatrix() return nil end
e:SetPos(Vector(0,0,-100))
p:SetNWEntity('seamless_portals_held',e)
""" + normalize((root / "lua/autorun/client/cl_seamless_mirror_physgun.lua").read_text()) + """
assert(SP.MirrorPhysgunContext(p,NULL,true,e,0,Vector(0,0,5))==true)
assert(SP.NativePhysgunSegments(p)==nil)
assert(not IsValid(p:GetNWEntity('seamless_portals_native_physgun_handle')))
keys[IN_ATTACK]=true
local segments=SP.NativePhysgunExitSegments(p)
assert(segments and #segments==2 and segments.entry==a)
assert(segments[2].finish:DistToSqr(SP.TransformPortal(a,b,e:LocalToWorld(Vector(0,0,5))))<0.0001)
SP.Rendering=b
assert(SP.NativePhysgunExitSegments(p)==nil)
assert(SP.MirrorPhysgunContext(p,NULL,true,e,0,Vector(0,0,5))==true)
SP.Rendering=nil
frame=11
assert(SP.NativePhysgunExitSegments(p))
frame=12
assert(SP.NativePhysgunExitSegments(p)==nil)
frame=10
keys[IN_ATTACK]=false
assert(SP.NativePhysgunExitSegments(p)==nil)
keys[IN_ATTACK]=true
p:SetNWEntity('seamless_portals_held',NULL)
assert(SP.NativePhysgunExitSegments(p)==nil)
"""),
        ("beam-portal-continuity", "The native beam curve splits without restarting texture coordinates at the portal", """
CLIENT=true;SERVER=false
function Material() return {} end
function LerpVector(t,a,b) return a+(b-a)*t end
""" + normalize((root / "lua/autorun/client/cl_seamless_mirror_physgun.lua").read_text()) + """
local SP=SeamlessPortals
local b=portal();b.pos=Vector(500,200,0)
function SP.TransformPortal(entry,exit,point)
 local p=entry:WorldToLocal(point)
 return exit:LocalToWorld(Vector(-p.x,p.y,-p.z))
end
a.exit=b;b.exit=a
local start,finish,control=Vector(0,0,100),Vector(0,0,-100),Vector(30,0,40)
local paths=SP.BuildPhysgunBeamPaths(start,finish,control,a,b)
assert(#paths==2 and #paths[1]+#paths[2]==19)
local before,after=paths[1][#paths[1]],paths[2][1]
assert(before.t==after.t and before.t>0 and before.t<1)
assert(math.abs(SP.PlaneDistance(a,before.pos))<0.0001)
local mapped=SP.TransformPortal(a,b,before.pos)
assert(mapped:DistToSqr(after.pos)<0.0001)
assert(paths[1][1].t==0 and paths[2][#paths[2]].t==1)
local straight=SP.BuildPhysgunBeamPaths(start,finish,control)
assert(#straight==1 and #straight[1]==17)
assert(straight[1][1].pos:DistToSqr(start)<0.0001)
assert(straight[1][17].pos:DistToSqr(finish)<0.0001)
"""),
        ("resting-contact-escape", "A second pickup can leave an initial hull overlap without ignoring later obstacles", """
""" + normalize((root / "lua/seamless_portals/held_proxy.lua").read_text()) + """
local SP=SeamlessPortals
function LerpVector(t,a,b) return a+(b-a)*t end
local data={start=Vector(0,0,0),endpos=Vector(0,0,20),mins=Vector(-1,-1,-1),maxs=Vector(1,1,1),filter=p,mask=99}
for _,blocked in ipairs({false,true}) do
 local calls=0
 util.TraceHull=function(query)
  calls=calls+1
  if calls==1 then return {Hit=true,StartSolid=true,AllSolid=false,FractionLeftSolid=0.25} end
  assert(query.start.z>5 and query.start.z<5.01)
  assert(query.endpos.z==20 and query.mask==99 and query.filter==p)
  return {Hit=blocked,StartSolid=false,AllSolid=false,Fraction=blocked and 0.5 or 1}
 end
 local tr=SP.TraceHeldProxyMovement(data,true)
 assert(calls==2 and tr.Hit==blocked and not tr.StartSolid)
 if blocked then assert(tr.Fraction>0.625 and tr.Fraction<0.626) end
 assert(data.start.z==0)
end
for _,initial in ipairs({
 {Hit=true,StartSolid=true,AllSolid=true,FractionLeftSolid=0.25},
 {Hit=true,StartSolid=true,AllSolid=false,FractionLeftSolid=0},
 {Hit=true,StartSolid=true,AllSolid=false,FractionLeftSolid=1},
 {Hit=true,StartSolid=true,AllSolid=false},
 {Hit=true,StartSolid=false,AllSolid=false,Fraction=0.25}
}) do
 local calls=0
 util.TraceHull=function() calls=calls+1;return initial end
 assert(SP.TraceHeldProxyMovement(data,true)==initial and calls==1)
end
"""),
        ("native-halo-target", "Beam replacement keeps ordinary halos and excludes portal clipping", """
CLIENT=true;SERVER=false
function Material() return {} end
local calls,selected=0
local gm={DrawPhysgunBeam=function(_,_,_,_,target) calls=calls+1;selected=target end}
gmod={GetGamemode=function() return gm end}
function e:GetNWEntity() return self.clip or NULL end
""" + normalize((root / "lua/autorun/client/cl_seamless_mirror_physgun.lua").read_text()) + """
SeamlessPortals.CollectPhysgunHalo(p,NULL,true,e,0,Vector())
assert(calls==1 and selected==e)
e.clip=a
SeamlessPortals.CollectPhysgunHalo(p,NULL,true,e,0,Vector())
assert(calls==1)
e.clip=nil
local handle=prop()
p:SetNWEntity('seamless_portals_native_physgun_handle',handle)
p:SetNWEntity('seamless_portals_held',e)
SeamlessPortals.CollectPhysgunHalo(p,NULL,true,handle,0,Vector())
assert(calls==2 and selected==e)
SeamlessPortals.Rendering=true
SeamlessPortals.CollectPhysgunHalo(p,NULL,true,handle,0,Vector())
assert(calls==2)
"""),
        ("blocked-remote-release", "Rejected release retires its proxy and weld before restoring the remote pose", """
local SP=SeamlessPortals
local handle,clone,weld=prop(),prop(),prop()
local body=e:GetPhysicsObject()
local remote=Vector(500,300,80)
e.SEAMLESS_PORTALS_CLONE=clone
local plan={root=e,items={{entity=e,pos=remote,ang=Angle(),bodies={{phys=body}}}}}
local record={entity=e,entry=a,group={e,handle}}
local state={plan=plan,record=record,handle=handle,weld=weld,ply=p,confirmed=true}
record.nativePickup=state
SP.NativePickupStates[handle]=state;SP.NativePickupTargets[e]=state
SP.EndCarryCorridor=function(r,restore) assert(not restore);r.entry=nil end
local restored=false
SP.RollbackTransport=function(current)
 assert(current==plan and clone.SEAMLESS_PORTALS_RETIRED and clone.notsolid)
 assert(not IsValid(handle) and not IsValid(weld))
 assert(handle:GetPhysicsObject():GetPos()==remote)
 body:EnableMotion(false);restored=true
end
handle.holding=true
assert(not SP.RestoreNativePickupRemote(record) and not restored)
handle.holding=false
assert(SP.RestoreNativePickupRemote(record) and restored and body:IsMotionEnabled())
assert(not SP.NativePickupStates[handle] and not SP.NativePickupTargets[e])
assert(not SP.RestoreNativePickupRemote(record))
"""),
        ("aim-beam-continuation", "The unheld beam follows both portal segments and respects the portal shortcut", """
CLIENT=true;SERVER=false
function Material() return {} end
local frame=1
function FrameNumber() return frame end
local start=Vector(0,0,64)
function p:EyePos() return start end
function p:GetAimVector() return Vector(0,0,-1) end
local b=portal();a:SetExitPortal(b);b:SetExitPortal(a)
SeamlessPortals.TransformPortal=function(entry,exit,point)
 assert(entry==a and exit==b)
 return point+Vector(200,0,0)
end
local calls=0
local finish=Vector(400,0,20)
SeamlessPortals.TracePortalLine=function(data)
 calls=calls+1
 assert(data.start==start and data.endpos.z<start.z and data.SeamlessMaxHops==1)
 return {SeamlessSegments={{Entity=a,HitPos=Vector()},{Entity=e,HitPos=finish}}}
end
IN_ATTACK=1
keys[IN_ATTACK]=true
""" + normalize((root / "lua/autorun/client/cl_seamless_mirror_physgun.lua").read_text()) + """
local segments=SeamlessPortals.NativePhysgunSegments(p)
assert(#segments==2 and segments[1].start==start and segments[2].finish==finish)
assert(segments[2].start.x==200 and segments[1].finish.x==0)
assert(SeamlessPortals.NativePhysgunSegments(p)==segments and calls==1)
keys[IN_WALK],keys[IN_SPEED]=true,true
assert(not SeamlessPortals.NativePhysgunSegments(p))
keys[IN_WALK],keys[IN_SPEED]=false,false
keys[IN_ATTACK]=false
assert(not SeamlessPortals.NativePhysgunSegments(p))
"""),
        ("world-clipped-native-ray", "A wall-clipped engine ray can select a prop beyond the portal", """
local start=Vector(0,0,64)
function p:EyePos() return start end
function p:GetAimVector() return Vector(1,0,0) end
local state={ply=p,plan={tracePoint=start+Vector(100,0,0)},hit=start+Vector(300,0,0)}
local hit=SeamlessPortals.NativePhysgunSelection(state,start,Vector(120,0,0),false)
assert(hit and hit.HitPos==state.hit and hit.Fraction>0 and hit.Fraction<1)
assert(not SeamlessPortals.NativePhysgunSelection(state,start,Vector(90,0,0),false))
assert(not SeamlessPortals.NativePhysgunSelection(state,start,Vector(120,0,0),true))
assert(not SeamlessPortals.NativePhysgunSelection(state,start+Vector(0,3,0),Vector(120,0,0),false))
assert(not SeamlessPortals.NativePhysgunSelection(state,start,Vector(0,120,0),false))
state.confirmed=true
assert(not SeamlessPortals.NativePhysgunSelection(state,start,Vector(120,0,0),false))
"""),
        ("portal-modifiers", "Both movement modifiers are required to grab a portal", """
for _,buttons in ipairs({{}, {IN_WALK}, {IN_SPEED}, {IN_WALK,IN_SPEED}}) do
 keys={};for _,key in ipairs(buttons) do keys[key]=true end
 local result=hook.Run('PhysgunPickup',p,a)
 if #buttons==2 then assert(result==nil) else assert(result==false) end
end
"""),
        ("permission-chain", "Modifiers never grant pickup permission or register a hold", """
keys[IN_WALK],keys[IN_SPEED]=true,true
assert(hook.Run('PhysgunPickup',p,a)==nil)
assert(hook.Run('PhysgunPickup',p,e)==nil)
hook.Add('PhysgunPickup','test_protection',function(_,ent) if ent==a or ent==e then return false end end)
assert(hook.Run('PhysgunPickup',p,a)==false)
assert(hook.Run('PhysgunPickup',p,e)==false)
assert(SeamlessPortals.GetHeldRecord(p)==nil)
"""),
        ("confirmed-hold", "Alt and Shift cannot replace a confirmed prop hold with a portal", """
e.holding=true;SeamlessPortals.RecordHold(p,e,'physgun')
keys[IN_WALK],keys[IN_SPEED]=true,true
assert(hook.Run('PhysgunPickup',p,a)==false)
assert(SeamlessPortals.GetHeldRecord(p).entity==e)
assert(hook.Run('PhysgunPickup',p,e)==nil)
"""),
        ("native-controller-alias", "The real prop retains identity while its native controller owns the hold", """
local handle=prop()
handle.SEAMLESS_PORTALS_NATIVE_PICKUP={plan={root=e}}
handle.holding=true
SeamlessPortals.RecordHold(p,handle,'physgun')
local record=SeamlessPortals.GetHeldRecord(p)
assert(record.entity==e and record.controllerEntity==handle)
assert(not e:IsPlayerHolding() and handle:IsPlayerHolding())
assert(SeamlessPortals.HeldBy(e)==p and SeamlessPortals.HeldBy(handle)==p)
TICK=TICK+5
assert(SeamlessPortals.GetHeldRecord(p)==record)
hook.Run('PhysgunDrop',p,handle)
assert(not SeamlessPortals.GetHeldRecord(p))
assert(not SeamlessPortals.HeldBy(e) and not SeamlessPortals.HeldBy(handle))
"""),
        ("second-controller-veto", "A remote native hold excludes competing physgun, use and gravgun pickups", """
SeamlessPortals.NativePickupTargets[e]={}
assert(hook.Run('PhysgunPickup',p,e)==false)
assert(hook.Run('AllowPlayerPickup',p,e)==false)
assert(hook.Run('GravGunPickupAllowed',p,e)==false)
"""),
        ("offset-size-admission", "Initial pickup checks size without requiring the remote prop to be centered", """
local points={}
for x=0,1 do for y=0,1 do for z=0,1 do
 points[#points+1]=a:LocalToWorld(Vector(80+x*28,70+y*52,100+z*28))
end end end
assert(not SeamlessPortals.InAperture(a,points[1]))
assert(SeamlessPortals.RemotePhysgunGroupFits(a,points))
assert(not SeamlessPortals.RemotePhysgunGroupFits(a,{Vector(-60,-1,100),Vector(60,1,100)}))
"""),
    ]
    lua, results = Lua(), []
    for name, title, code in cases:
        try:
            assert lua.check(base + code + '\nreturn "passed"', True, name) == "passed"
            status, observed = "PASS", "assertions passed"
        except Exception as exc:
            status, observed = "FAIL", str(exc)
        results.append(dict(id=name, title=title, status=status, observed=observed))
        print(f"{status}: {name}: {observed}")
    report = dict(native_gmod_tested=False, tests=results,
                  passed=sum(item["status"] == "PASS" for item in results),
                  failed=sum(item["status"] == "FAIL" for item in results))
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(json.dumps(report, indent=2) + "\n")
    return bool(report["failed"])


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("source", type=Path, nargs="?", default=Path(__file__).resolve().parents[1])
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    raise SystemExit(main(args.source.resolve(), args.output.resolve()))
