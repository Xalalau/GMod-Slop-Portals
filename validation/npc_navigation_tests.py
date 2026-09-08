#!/usr/bin/env python3
"""NPC portal routing contracts with API doubles, not native AI acceptance."""
import argparse
import json
from pathlib import Path

from lua_support import Lua, normalize


def main(root, output):
    here = Path(__file__).resolve().parent
    base = (here / "stubs.lua").read_text() + (here / "custom_stubs.lua").read_text()

    def source(path):
        return "\ndo\n" + normalize((root / path).read_text()) + "\nend\n"

    for name in ("core", "features", "aperture", "crossing", "holding"):
        base += source(f"lua/seamless_portals/{name}.lua")
    transform = (root / "lua/entities/seamless_portal/sh_init.lua").read_text()
    transform = transform[transform.index("SeamlessPortals.TransformPortal = function"):]
    base += normalize(transform[:transform.index("-- Only render the portals")])
    base += r"""
MOVETYPE_STEP,CAP_MOVE_GROUND,NPC_STATE_SCRIPT,MASK_NPCSOLID=3,1,7,123
SCHED_FORCED_GO_RUN,SCHED_CHASE_ENEMY,D_HT,FL_NOTARGET=72,17,1,128
SCHED_NPC_FREEZE=73
local vector_meta=getmetatable(Vector())
function vector_meta:Length2DSqr() return self.x*self.x+self.y*self.y end
function vector_meta:Length2D() return math.sqrt(self:Length2DSqr()) end
CreateConVar('seamless_portals_npc_distance','2048')
CreateConVar('ai_disabled','0');CreateConVar('ai_ignoreplayers','0')
local SP=SeamlessPortals
SP.NPCAttention={}
function SP.ClearNPCAttention(npc) SP.NPCAttention[npc]=nil end
function SP.FindNPCTarget() return nil end
local target=player()
target.pos=Vector(1160,0,.0625)
function target:IsNPC() return false end
function target:IsFlagSet() return self.notarget or false end
local a,b=pair()
for _,p in ipairs({a,b}) do
 p.forward=Vector(0,0,-1);p.right=Vector(0,-1,0);p.up=Vector(1,0,0)
 p.size=Vector(128,128,8)
end
a.pos,b.pos=Vector(0,0,48),Vector(1000,0,48)
local npc=prop(Vector(160,0,.0625))
npc.lo,npc.hi=Vector(-12,-12,0),Vector(12,12,24)
npc.enemy=target;npc.last=Vector(50,60,0);npc.schedule=0;npc.schedule_writes=0
function npc:IsNPC() return true end
function npc:IsScripted() return self.scripted or false end
function npc:Health() return self.health or 100 end
function npc:GetNPCState() return self.state or 0 end
function npc:GetMoveType() return MOVETYPE_STEP end
function npc:CapabilitiesGet() return CAP_MOVE_GROUND end
function npc:GetCollisionBounds() return Vector(self.lo),Vector(self.hi) end
function npc:GetStepHeight() return 18 end
function npc:GetPathDistanceToGoal() return self.native_distance or 0 end
function npc:Visible() return not self.occluded end
function npc:IsUnreachable() return self.unreachable or false end
function npc:GetEnemy() return self.enemy end
function npc:GetGoalTarget() return self.goal_target or NULL end
function npc:Disposition() return self.friendly and 3 or D_HT end
function npc:GetInternalVariable(key) assert(key=='m_vecLastPosition');return self.last end
function npc:SetLastPosition(v) self.last=Vector(v) end
function npc:IsCurrentSchedule(s) return self.schedule==s end
function npc:SetSchedule(s) self.schedule=s;self.schedule_writes=self.schedule_writes+1 end
function npc:ClearSchedule() self.schedule=0 end
function npc:ClearGoal() self.goal_cleared=true end
function npc:GetVelocity() return Vector(-30,0,0) end
function npc:SetLocalVelocity(v) self.velocity=Vector(v) end
function npc:GetSequence() return self.sequence or 0 end
function npc:SetSequence(s) self.sequence=s end
function npc:GetCycle() return self.cycle or 0 end
function npc:SetCycle(c) self.cycle=c end
function npc:GetPlaybackRate() return self.rate or 1 end
function npc:SetPlaybackRate(r) self.rate=r end
function npc:NavSetGoalPos(p) self.nav_goal=Vector(p) end
function npc:GetMoveDelay() return (self.wait_until or 0)-CurTime() end
function npc:SetMoveDelay(d) self.wait_until=CurTime()+d end
function npc:SetEnemy(e) self.enemy=e end
function npc:UpdateEnemyMemory(e,pos) self.memory={entity=e,pos=Vector(pos)} end
local exit_blocked,source_blocked,corridor_blocked=false,false,false
local sweeps={}
util.TraceHull=function(d)
 assert(d.SeamlessIgnore and d.mask==MASK_NPCSOLID)
 sweeps[#sweeps+1]=d
 if exit_blocked and d.start.x>900 then return {Hit=true,StartSolid=true} end
 if source_blocked and d.start.x<100 and d.start.z<1 then return {Hit=true} end
 if d.start.z>=0 and d.endpos.z<0 then
  return {Hit=true,HitPos=Vector(d.endpos.x,d.endpos.y,0),HitNormal=Vector(0,0,1)}
 end
 return {Hit=false}
end
SP.RawTraceLine=function(d) assert(d.SeamlessIgnore);return {Hit=corridor_blocked} end
local transfers=0
hook.Add('SeamlessPortalsTeleported','test',function(e,entry,exit,kind)
 assert(e==npc and entry==a and exit==b and kind=='npc');transfers=transfers+1
end)
local function start()
 assert(SP.UpdateNPCNavigation(npc,{target}),'route not acquired')
 return assert(SP.NPCNavigation[npc])
end
local function advance(seconds)
 NOW=NOW+seconds;hook.Run('Think')
end
"""
    module = source("lua/seamless_portals/npc_navigation.lua")
    visual = r"""
SERVER,CLIENT=false,true
render={clipping=false,planes={}}
function render.EnableClipping(v) local old=render.clipping;render.clipping=v;return old end
function render.PushCustomClipPlane(normal,dist) table.insert(render.planes,{normal=normal,dist=dist}) end
function render.PopCustomClipPlane() assert(#render.planes>0);table.remove(render.planes) end
function npc:GetActiveWeapon() return self.weapon or NULL end
function npc:GetRenderOrigin() return self.render_origin end
function npc:GetRenderAngles() return self.render_angle end
function npc:SetRenderOrigin(v) self.render_origin=v end
function npc:SetRenderAngles(v) self.render_angle=v end
function npc:InvalidateBoneCache() end
function npc:GetSequenceCount() return 10 end
local function appearance(e)
 for key,value in pairs({Model='models/zombie.mdl',ModelScale=1,Skin=2,Material='',Color={r=255,g=255,b=255,a=255},RenderMode=0}) do
  e[key]=value
  e['Get'..key]=function(self) return self[key] end
  e['Set'..key]=function(self,v) self[key]=v end
 end
 function e:GetNumBodyGroups() return 2 end
 function e:GetBodygroup(i) return i+1 end
 function e:GetMaterials() return {'body'} end
 function e:GetSubMaterial() return 'skin_override' end
 function e:GetNumPoseParameters() return 0 end
end
appearance(npc)
function Lerp(f,a,b) return a+(b-a)*f end
function LerpVector(f,a,b) return a+(b-a)*f end
function LerpAngle(f,a,b) return Angle(Lerp(f,a.p,b.p),Lerp(f,a.y,b.y),Lerp(f,a.r,b.r)) end
function LocalToWorld(p,a,o,ang) return o+p,Angle(a.p+ang.p,a.y+ang.y,a.r+ang.r) end
function WorldToLocal(p,a,o,ang) return p-o,Angle(a.p-ang.p,a.y-ang.y,a.r-ang.r) end
local function boneMatrix(pos)
 local m={position=Vector(pos),angle=Angle(),scale=Vector(1,1,1)}
 function m:GetTranslation() return Vector(self.position) end
 function m:SetTranslation(v) self.position=Vector(v) end
 function m:GetAngles() return Angle(self.angle) end
 function m:SetAngles(v) self.angle=Angle(v) end
 function m:GetScale() return Vector(self.scale) end
 function m:SetScale(v) self.scale=Vector(v) end
 return m
end
function npc:SetupBones() self.matrix=boneMatrix(self:GetPos()+Vector(0,0,15)) end
function npc:GetBoneCount() return 2 end
function npc:GetBoneMatrix() return self.matrix end
function npc:DrawModel() error('real NPC must not be drawn at the virtual pose') end
function npc:SetIK() error('real NPC IK must remain untouched') end
local draws,models={},{}
local fail_create,fail_material
function ClientsideModel(path)
 if fail_create==#models+1 then return NULL end
 local e=prop();appearance(e);models[#models+1]=e
 e.bodygroups={};e.submaterials={}
 function e:SetIK(v) self.ik=v end
 function e:SetModel(v) assert(self.ik==false,'IK disabled before model change');self.Model=v end
 function e:SetMaterial(v) if fail_material then error('injected copy setup failure') end self.Material=v end
 function e:SetBodygroup(i,v) self.bodygroups[i]=v end
 function e:SetSubMaterial(i,v) self.submaterials[i]=v end
 function e:SetParent(p) self.parent=p end
 function e:AddEffects(flags) self.effects=flags end
 function e:GetAngles() return self.angle or Angle() end
 e.GetSequence,e.SetSequence=npc.GetSequence,npc.SetSequence
 e.GetCycle,e.SetCycle=npc.GetCycle,npc.SetCycle
 e.SetPlaybackRate=npc.SetPlaybackRate
 function e:AddCallback(_,fn) self.bone_callback=fn end
 function e:InvalidateBoneCache() end
 function e:SetupBones()
  self.matrix=boneMatrix(self:GetPos()+Vector(0,0,5))
  if self.bone_callback then self:bone_callback(2) end
 end
 function e:GetBoneName(i) return i==0 and 'pelvis' or '__INVALIDBONE__' end
 function e:GetBoneParent() return -1 end
 function e:GetBoneMatrix() return self.matrix end
 function e:SetBoneMatrix(i,m) assert(i==0,'invalid bone written');self.matrix=m end
 function e:DrawModel()
  assert(render.clipping and #render.planes==1)
  draws[#draws+1]={pos=Vector(self:GetPos()),plane=render.planes[1],sequence=self:GetSequence(),cycle=self:GetCycle(),bone=self.matrix:GetTranslation()}
  if self.fail_draw then error('injected model draw failure') end
 end
 return e
end
npc.pos=Vector(1014,0,.5)
local function transition()
 assert(SP.BeginNPCTransition(npc,a,b,npc:GetPos(),Vector(-27,0,0),Vector(0,0,12),Angle(),NOW,.6))
 return SP.NPCTransitions[npc]
end
""" + source("lua/seamless_portals/npc_transition.lua")
    cases = [
        ("N-T39", "The held NPC exit copy keeps its animation and bone-merged weapon without moving the source", visual + "\nENT={}\n" + source("lua/entities/seamless_portal_clone.lua") + r"""
EF_BONEMERGE=1
npc.weapon=prop();appearance(npc.weapon)
npc.sequence=4;npc.cycle=.375
local before=Vector(npc:GetPos())
local clone=prop()
for key,value in pairs(ENT) do clone[key]=value end
function clone:GetChild() return npc end
function clone:GetPortal1() return a end
function clone:GetPortal2() return b end
clone:Draw()
local visual=assert(clone.SEAMLESS_PORTALS_NPC_VISUAL)
assert(#visual.models==2 and #draws==2)
assert(visual.models[2].parent==visual.models[1] and visual.models[2].effects==EF_BONEMERGE)
assert(draws[1].sequence==4 and draws[1].cycle==.375)
nearvec(draws[1].pos,(SP.TransformPortal(a,b,before)))
assert(visual.models[1].ik==false and visual.models[2].ik==false)
assert(npc:GetSequence()==4 and npc:GetCycle()==.375);nearvec(npc:GetPos(),before)
assert(not render.clipping and #render.planes==0)
visual.models[1].fail_draw=true
clone:Draw()
assert(not clone.SEAMLESS_PORTALS_NPC_VISUAL)
for _,model in ipairs(visual.models) do assert(not IsValid(model)) end
assert(not render.clipping and #render.planes==0)
fail_material=true
clone:Draw()
assert(not clone.SEAMLESS_PORTALS_NPC_VISUAL)
for _,model in ipairs(models) do assert(not IsValid(model)) end
assert(not render.clipping and #render.planes==0)
"""),
        ("N-T38", "Native navigation yields to a confirmed NPC physgun hold", r"""
SP.RecordHold(target,npc,'physgun')
assert(not SP.FindNPCPortalRoute(npc,target))
assert(not SP.UpdateNPCNavigation(npc,{target}) and npc.schedule_writes==0)
SP.ClearHold(target,npc)
assert(SP.FindNPCPortalRoute(npc,target))
"""),
        ("N-T01", "Select a shorter walkable route without restarting the native schedule", r"""
local r=start();assert(r.entry==a and r.exit==b)
assert(npc.schedule==SCHED_FORCED_GO_RUN and npc.schedule_writes==1)
assert(SP.UpdateNPCNavigation(npc,{target}) and npc.schedule_writes==1)
assert(not SP.TransferNPCThroughPortal(npc,r) and transfers==0)
"""),
        ("N-T02", "Transfer the same torso at the lip and resume the real enemy once", r"""
local r=start();npc.pos=Vector(r.approach);npc.pos.z=.0625
local body=npc:GetPhysicsObject()
assert(SP.TransferNPCThroughPortal(npc,r))
assert(npc:GetPhysicsObject()==body and npc:GetEnemy()==target and transfers==1)
assert(npc.schedule==SCHED_CHASE_ENEMY and npc.memory.entity==target)
nearvec(npc:GetVelocity(),Vector(-30,0,0));nearvec(npc.velocity,Vector(30,0,0))
assert(not SP.TransferNPCThroughPortal(npc,r) and transfers==1)
"""),
        ("N-T03", "A small floor clearance allows the torso through a slightly raised lip", r"""
a.size,b.size=Vector(100,100,8),Vector(100,100,8)
a.pos.z,b.pos.z=50.3,50.3
local r=start();npc.pos=Vector(r.approach);npc.pos.z=.0625
assert(SP.TransferNPCThroughPortal(npc,r))
local lifted=false
for _,s in ipairs(sweeps) do
 if s.start.z==.0625 and s.endpos.z>.4 then lifted=true end
end
assert(lifted and transfers==1)
"""),
        ("N-T04", "The approach may start behind the entry but cannot transfer there", r"""
npc.pos=Vector(-20,0,.0625)
local r=start();assert(not SP.TransferNPCThroughPortal(npc,r))
npc.pos=Vector(r.approach);assert(SP.TransferNPCThroughPortal(npc,r))
"""),
        ("N-T05", "A shorter native route keeps control of the NPC", r"""
npc.pos=Vector(1100,0,.0625)
assert(not SP.FindNPCPortalRoute(npc,target))
assert(not SP.UpdateNPCNavigation(npc,{target}) and npc.schedule_writes==0)
"""),
        ("N-T06", "Exit blockage rejects admission and blocks a pending transfer", r"""
exit_blocked=true;assert(not SP.FindNPCPortalRoute(npc,target))
exit_blocked=false;local r=start();npc.pos=Vector(r.approach)
local before=Vector(npc.pos);exit_blocked=true
assert(not SP.TransferNPCThroughPortal(npc,r));nearvec(npc.pos,before);assert(transfers==0)
"""),
        ("N-T07", "Source obstructions and the exit corridor cannot be skipped", r"""
local r=start();npc.pos=Vector(r.approach);local before=Vector(npc.pos)
source_blocked=true;assert(not SP.TransferNPCThroughPortal(npc,r))
source_blocked=false;corridor_blocked=true;assert(not SP.TransferNPCThroughPortal(npc,r))
nearvec(npc.pos,before);assert(transfers==0)
"""),
        ("N-T08", "Full hull admission rejects small apertures and unsupported orientation", r"""
a.size,b.size=Vector(20,20,8),Vector(20,20,8)
assert(not SP.FindNPCPortalRoute(npc,target))
a.size,b.size=Vector(128,128,8),Vector(128,128,8)
b.up=Vector(0,0,1);assert(not SP.FindNPCPortalRoute(npc,target))
b.up=Vector(1,0,0);b.forward=Vector(0,0,1);assert(not SP.FindNPCPortalRoute(npc,target))
"""),
        ("N-T09", "Endpoint opt-outs and geometry edits cancel pending traversal", r"""
local r=start();SP.SetFeature(b,'props',false);advance(.1)
assert(not SP.NPCNavigation[npc] and npc.schedule==0 and transfers==0)
nearvec(npc.last,Vector(50,60,0))
SP.SetFeature(b,'props',true);advance(3);r=start();b.pos.x=b.pos.x+1
assert(not SP.TransferNPCThroughPortal(npc,r));advance(.1);assert(not SP.NPCNavigation[npc])
"""),
        ("N-T10", "Deletion and unlinking retire the route without a transfer", r"""
local r=start();b.valid=false;advance(.1);assert(not SP.NPCNavigation[npc])
b.valid=true;advance(3);r=start();a:SetExitPortal(NULL);advance(.1)
assert(not SP.NPCNavigation[npc] and transfers==0)
"""),
        ("N-T11", "AI switches and changed relationships cancel pursuit", r"""
local r=start();GetConVar('ai_ignoreplayers'):SetInt(1);advance(.1)
assert(not SP.NPCNavigation[npc]);GetConVar('ai_ignoreplayers'):SetInt(0);advance(3)
r=start();npc.friendly=true;advance(.1);assert(not SP.NPCNavigation[npc])
npc.friendly=false;advance(3);r=start();GetConVar('ai_disabled'):SetInt(1);advance(.1)
assert(not SP.NPCNavigation[npc] and transfers==0)
"""),
        ("N-T12", "Scripted and dead NPCs are never steered", r"""
npc.scripted=true;assert(not SP.UpdateNPCNavigation(npc,{target}))
npc.scripted=false;npc.health=0;assert(not SP.UpdateNPCNavigation(npc,{target}))
assert(npc.schedule_writes==0)
"""),
        ("N-T13", "Another controller retains its replacement schedule and destination", r"""
start();npc.last=Vector(999,888,0);npc.schedule=99;advance(.5)
assert(not SP.NPCNavigation[npc] and npc.schedule==99)
nearvec(npc.last,Vector(999,888,0))
"""),
        ("N-T14", "Stalled approaches time out and respect the retry cooldown", r"""
start();advance(3.1);assert(not SP.NPCNavigation[npc] and npc.schedule==0)
assert(not SP.UpdateNPCNavigation(npc,{target}));advance(2.1);start()
"""),
        ("N-T15", "Native follow goals survive transfer without inventing hostility", r"""
npc.enemy=NULL;npc.goal_target=target;npc.friendly=true
local r=start();assert(r.kind=='goal');npc.pos=Vector(r.approach)
assert(SP.TransferNPCThroughPortal(npc,r) and npc.enemy==NULL)
nearvec(npc.last,target:GetPos());assert(npc.schedule==SCHED_FORCED_GO_RUN)
"""),
        ("N-T16", "Reload restores owned state and map cleanup removes routes", r"""
start()
""" + module + r"""
assert(not SP.NPCNavigation[npc] and npc.schedule==0)
nearvec(npc.last,Vector(50,60,0));start();hook.Run('PostCleanupMap')
assert(not SP.NPCNavigation[npc])
"""),
        ("N-T17", "An unreachable nearby target does not cause a portal loop", r"""
local r=start();npc.pos=Vector(r.approach);assert(SP.TransferNPCThroughPortal(npc,r))
npc.occluded=true;npc.unreachable=true;advance(3)
assert(not SP.FindNPCPortalRoute(npc,target))
assert(not SP.UpdateNPCNavigation(npc,{target}))
npc.native_distance=9999
assert(not SP.FindNPCPortalRoute(npc,target),'a long native path must not reverse progress')
"""),
        ("N-T18", "The middle of a transition draws complementary clipped body halves", visual + r"""
local r=transition();NOW=NOW+.3;SP.DrawNPCTransition(npc,r)
assert(#draws==2 and not render.clipping and #render.planes==0)
near(SP.PlaneDistance(a,draws[1].pos),-.5,1e-6)
near(SP.PlaneDistance(b,draws[2].pos),.5,1e-6)
assert(npc:GetRenderOrigin()==nil and npc:GetRenderAngles()==nil)
NOW=NOW+1;hook.Run('Think');assert(npc.RenderOverride==nil and not SP.NPCTransitions[npc])
"""),
        ("N-T19", "An interrupted draw restores clipping, pose and the previous renderer", visual + r"""
local previous=function(e) e:DrawModel() end
npc.RenderOverride=previous;npc.render_origin=Vector(1,2,3);npc.render_angle=Angle(4,5,6)
local r=transition();r.models[1].fail_draw=true;SP.DrawNPCTransition(npc,r)
assert(LAST_ERROR:find('injected model draw failure',1,true))
assert(npc.RenderOverride==previous and not SP.NPCTransitions[npc])
assert(not render.clipping and #render.planes==0)
nearvec(npc:GetRenderOrigin(),Vector(1,2,3));assert(npc:GetRenderAngles()==Angle(4,5,6))
"""),
        ("N-T20", "Another renderer and an invalidated portal retain correct cleanup ownership", visual + r"""
transition();local other=function() end;npc.RenderOverride=other
hook.Run('Think');assert(npc.RenderOverride==other and not SP.NPCTransitions[npc])
transition();b.valid=false;hook.Run('Think')
assert(npc.RenderOverride==other and not SP.NPCTransitions[npc])
"""),
        ("N-T21", "The crossing gait follows distance and restores the native animation", visual + r"""
npc:SetSequence(3);npc:SetCycle(.2)
assert(SP.BeginNPCTransition(npc,a,b,npc:GetPos(),Vector(-27,0,0),Vector(0,0,12),Angle(),NOW,.6,
 {sequence=2,cycle=.1,distance=36}))
local r=SP.NPCTransitions[npc]
NOW=NOW+.15;SP.DrawNPCTransition(npc,r)
near(draws[1].cycle,.1+6.75/36,1e-6);assert(draws[1].sequence==2)
assert(npc:GetSequence()==3 and npc:GetCycle()==.2)
local distance=r.distance;SP.DrawNPCTransition(npc,r);assert(r.distance==distance)
NOW=NOW+.15;SP.DrawNPCTransition(npc,r)
near(draws[5].cycle,.1+13.5/36,1e-6)
r.models[1].fail_draw=true;SP.DrawNPCTransition(npc,r)
assert(npc:GetSequence()==3 and npc:GetCycle()==.2 and npc.RenderOverride==nil)
"""),
        ("N-T22", "Pursuit resumes without forcing an extra native animation restart", r"""
SP.SendNPCTransition=function() return 1,{rate=1,sequence=2,endCycle=.7} end
local r=start();npc.pos=Vector(r.approach);assert(SP.TransferNPCThroughPortal(npc,r))
assert(npc.schedule==SCHED_NPC_FREEZE and SP.NPCPassages[npc] and transfers==1)
nearvec(npc.nav_goal,npc:GetPos());near(npc:GetMoveDelay(),1.1,1e-6)
npc.rate=0;advance(.9)
assert(SP.UpdateNPCNavigation(npc,{target}) and npc.schedule==SCHED_NPC_FREEZE)
npc.sequence=8;npc.cycle=.4
advance(.2)
assert(not SP.NPCPassages[npc] and npc.schedule==SCHED_CHASE_ENEMY)
assert(npc.rate==1 and transfers==1)
assert(npc.sequence==8 and npc.cycle==.4,'native animation was forced before activity selection')
assert(npc:GetMoveDelay()==0)
"""),
        ("N-T23", "Cleanup and endpoint opt-outs cannot leave the NPC frozen", r"""
SP.SendNPCTransition=function() return 1,{rate=1,sequence=2,endCycle=.7} end
local r=start();npc.pos=Vector(r.approach);assert(SP.TransferNPCThroughPortal(npc,r))
npc.rate=0;SP.SetFeature(b,'props',false);advance(.1)
assert(npc.rate==1 and npc.schedule==SCHED_CHASE_ENEMY and not SP.NPCPassages[npc])
assert(npc:GetMoveDelay()==0)
SP.SetFeature(b,'props',true);npc.pos=Vector(160,0,.0625);advance(3)
r=start();npc.pos=Vector(r.approach);assert(SP.TransferNPCThroughPortal(npc,r))
npc.rate=0;SP.CleanupNPCNavigation()
assert(npc.rate==1 and npc.schedule==SCHED_CHASE_ENEMY and not SP.NPCPassages[npc])
assert(npc:GetMoveDelay()==0)
"""),
        ("N-T24", "An external schedule and deleted NPC are not overwritten on passage cleanup", r"""
SP.SendNPCTransition=function() return 1,{rate=1,sequence=2,endCycle=.7} end
local r=start();npc.pos=Vector(r.approach);assert(SP.TransferNPCThroughPortal(npc,r))
npc.schedule=99;npc.rate=.5;npc:SetMoveDelay(10);advance(.1)
assert(npc.schedule==99 and npc.rate==.5 and not SP.NPCPassages[npc])
near(npc:GetMoveDelay(),9.9,1e-6)
npc.pos=Vector(160,0,.0625);advance(3)
r=start();npc.pos=Vector(r.approach);assert(SP.TransferNPCThroughPortal(npc,r))
npc.valid=false;advance(.1);assert(not SP.NPCPassages[npc])
"""),
        ("N-T25", "Crossing duration uses normal movement speed without a fast time cap", "\nlocal function loadTransition()\n" + source("lua/seamless_portals/npc_transition.lua") + r"""
end
loadTransition()
function net.Broadcast() net.Send() end
function npc:GetIdealMoveSpeed() return 30 end
function npc:GetSequenceGroundSpeed() return 30 end
function npc:SequenceDuration() return 1.2 end
npc.cycle=.2
local duration,animation=SP.SendNPCTransition(npc,a,b,Vector(13,0,.5),Vector(1014,0,.5),Angle())
near(duration,.9,1e-6);near(animation.endCycle,.95,1e-6)
assert(#net.messages==1)
"""),
        ("N-T26", "Visual copies disable IK and preserve appearance without changing the real NPC", visual + r"""
local r=transition();local copy=r.models[1]
assert(copy.ik==false and copy.nodraw and copy:GetModel()==npc:GetModel())
assert(copy:GetSkin()==2 and copy.bodygroups[1]==2 and copy.submaterials[0]=='skin_override')
npc.SetSequence=function() error('native sequence changed') end
npc.SetCycle=function() error('native cycle changed') end
SP.DrawNPCTransition(npc,r);SP.CleanupNPCTransitions()
assert(not IsValid(copy) and npc.RenderOverride==nil)
"""),
        ("N-T27", "The final visual pose blends toward native bones across sequence changes", visual + r"""
local r=transition();npc.sequence=8;npc.cycle=.1
NOW=NOW+.725;SP.DrawNPCTransition(npc,r)
near(r.blend,.5,1e-6);near(draws[2].bone.z,npc.pos.z+10,1e-6)
assert(npc:GetSequence()==8 and npc:GetCycle()==.1 and npc.RenderOverride~=nil)
NOW=NOW+.12;SP.DrawNPCTransition(npc,r)
near(draws[4].bone.z,npc.pos.z+14.8,1e-6)
NOW=NOW+.01;hook.Run('Think');assert(not SP.NPCTransitions[npc])
"""),
        ("N-T28", "Copy allocation or setup failures restore renderers and remove partial models", visual + r"""
fail_material=true
assert(not SP.BeginNPCTransition(npc,a,b,npc:GetPos(),Vector(-27,0,0),Vector(0,0,12),Angle(),NOW,.6))
assert(not IsValid(models[1]) and npc.RenderOverride==nil and not SP.NPCTransitions[npc])
fail_material=false;npc.weapon=npc;fail_create=3
assert(not SP.BeginNPCTransition(npc,a,b,npc:GetPos(),Vector(-27,0,0),Vector(0,0,12),Angle(),NOW,.6))
assert(not IsValid(models[2]) and npc.RenderOverride==nil and not SP.NPCTransitions[npc])
"""),
        ("N-T29", "Blending bent limbs preserves joint lengths instead of shrinking them", visual + r"""
function LocalToWorld(p,a,o,ang)
 local yaw=math.rad(ang.y);local c,s=math.cos(yaw),math.sin(yaw)
 return o+Vector(p.x*c-p.y*s,p.x*s+p.y*c,p.z),Angle(a.p+ang.p,a.y+ang.y,a.r+ang.r)
end
function WorldToLocal(p,a,o,ang)
 local q=p-o;local yaw=math.rad(ang.y);local c,s=math.cos(yaw),math.sin(yaw)
 return Vector(q.x*c+q.y*s,-q.x*s+q.y*c,q.z),Angle(a.p-ang.p,a.y-ang.y,a.r-ang.r)
end
local r=transition();local copy=r.models[1]
function npc:SetupBones()
 self.bones={[0]=boneMatrix(self:GetPos()),[1]=boneMatrix(self:GetPos()+Vector(0,10,0))}
 for _,m in pairs(self.bones) do m:SetAngles(Angle(0,90,0)) end
end
function npc:GetBoneMatrix(i) return self.bones[i] end
function copy:GetBoneName(i) return i==0 and 'hip' or 'foot' end
function copy:GetBoneParent(i) return i-1 end
function copy:GetBoneMatrix(i) return self.bones[i] end
function copy:SetBoneMatrix(i,m) self.bones[i]=m end
function copy:SetupBones()
 self.bones={[0]=boneMatrix(self:GetPos()),[1]=boneMatrix(self:GetPos()+Vector(10,0,0))}
 self:bone_callback(2)
 self.matrix=self.bones[0]
end
NOW=NOW+.725;SP.DrawNPCTransition(npc,r)
local hip,foot=copy.bones[0]:GetTranslation(),copy.bones[1]:GetTranslation()
near(hip:Distance(foot),10,1e-5)
nearvec(foot-hip,Vector(math.sqrt(50),math.sqrt(50),0),1e-5)
NOW=NOW+.125;SP.DrawNPCTransition(npc,r)
nearvec(copy.bones[1]:GetTranslation(),npc.bones[1]:GetTranslation(),1e-5)
"""),
        ("N-T30", "Wider portals add bounded horizontal crossing points", r"""
local previous=0
for _,size in ipairs({100,256,512,1000}) do
 a.size,b.size=Vector(size,size,8),Vector(size,size,8)
 local points=SP.NPCPortalRoutePoints(npc,a,b)
 assert(#points>previous and #points<=9);previous=#points
 for _,point in ipairs(points) do
  near(point.z,a.pos.z,1e-6);near(SP.PlaneDistance(a,point),0,1e-6)
 end
end
"""),
        ("N-T31", "An NPC approaching the side crosses there instead of detouring to center", r"""
a.size,b.size=Vector(512,512,8),Vector(512,512,8)
npc.pos.y=160;target.pos.y=-160
local r=start();assert(r.approach.y>100 and r.destination.y< -100)
npc.pos=Vector(r.approach);assert(SP.TransferNPCThroughPortal(npc,r))
near(npc.pos.y,r.destination.y,1e-6);assert(transfers==1)
"""),
        ("N-T32", "A blocked central entry or exit leaves clear side crossings available", r"""
a.size,b.size=Vector(256,256,8),Vector(256,256,8)
local raw=util.TraceHull
local blockEntry=false
util.TraceHull=function(d)
 if math.abs(d.start.y)<24 and (blockEntry and d.start.x<100 or not blockEntry and d.start.x>900) then
  return {Hit=true,StartSolid=true}
 end
 return raw(d)
end
for _,entryBlocked in ipairs({false,true}) do
 blockEntry=entryBlocked
 local r=assert(SP.FindNPCPortalRoute(npc,target))
 assert(math.abs(r.approach.y)>32 and math.abs(r.destination.y)>32)
end
"""),
        ("N-T33", "The smaller endpoint and native hull limit crossing density", r"""
a.size,b.size=Vector(512,512,8),Vector(100,100,8)
assert(#SP.NPCPortalRoutePoints(npc,a,b)==1)
a.size,b.size=Vector(100,100,8),Vector(512,512,8)
assert(#SP.NPCPortalRoutePoints(npc,a,b)==1)
a.size,b.size=Vector(256,256,8),Vector(256,256,8)
assert(#SP.NPCPortalRoutePoints(npc,a,b)>1)
npc.lo,npc.hi=Vector(-60,-60,0),Vector(60,60,24)
assert(#SP.NPCPortalRoutePoints(npc,a,b)==1)
"""),
        ("N-T34", "Resizing invalidates the old route and the next attempt uses the added width", r"""
local r=start();near(r.approach.y,0,1e-6)
a.size,b.size=Vector(512,512,8),Vector(512,512,8)
assert(not SP.TransferNPCThroughPortal(npc,r));advance(.1)
assert(not SP.NPCNavigation[npc]);advance(2.1)
npc.pos.y=160;target.pos.y=-160
r=start();assert(r.approach.y>100 and r.destination.y< -100)
"""),
        ("N-T35", "Side candidates still fit the polygon and blocked searches remain bounded", r"""
a.size,b.size=Vector(128,512,8),Vector(128,512,8);a.sides=32;b.sides=32
npc.pos.y=320;target.pos.y=-320
local r=assert(SP.FindNPCPortalRoute(npc,target))
for _,pose in ipairs({{a,r.approach},{b,r.destination}}) do
 for x=0,1 do for y=0,1 do for z=0,1 do
  assert(SP.InAperture(pose[1],pose[2]+Vector(x==0 and npc.lo.x or npc.hi.x,y==0 and npc.lo.y or npc.hi.y,z==0 and npc.lo.z or npc.hi.z)))
 end end end
end
local checks=0
util.TraceHull=function() checks=checks+1;return {Hit=true,StartSolid=true} end
assert(not SP.FindNPCPortalRoute(npc,target));assert(checks<=12)
"""),
        ("N-T36", "The exit continues the measured incoming direction instead of pushing straight forward", r"""
local r=start();npc.pos=Vector(r.approach)
local source=Vector(npc.pos);r.samplePosition=source+Vector(10,-5,0)
local sent
SP.SendNPCTransition=function(e,entry,exit,from,to)
 sent={source=Vector(from),destination=Vector(to)}
end
advance(.1)
assert(transfers==1 and sent)
local center=(npc.lo+npc.hi)*.5
local origin=SP.TransformPortal(a,b,source+center)-center
local displacement=sent.destination-origin;displacement.z=0
local expected=SP.TransformDirection(a,b,Vector(-10,5,0):GetNormalized(),false)
near(displacement:GetNormalized():Dot(expected),1,1e-6)
assert(math.abs(sent.destination.y)>10,'exit lost the lateral movement')
"""),
        ("N-T37", "An obstructed diagonal exit is refused without falling back to a straight shove", r"""
local r=start();npc.pos=Vector(r.approach);r.direction=Vector(-1,.5,0):GetNormalized()
local before=Vector(npc.pos);local raw=util.TraceHull
util.TraceHull=function(d)
 if d.start.x>900 and d.start.y< -8 then return {Hit=true,StartSolid=true} end
 return raw(d)
end
assert(not SP.TransferNPCThroughPortal(npc,r));nearvec(npc.pos,before);assert(transfers==0)
util.TraceHull=raw;r.direction=Vector(-.11,.99,0):GetNormalized()
assert(not SP.TransferNPCThroughPortal(npc,r),'diagonal passage must fit the aperture')
nearvec(npc.pos,before);assert(transfers==0)
"""),
    ]
    lua, results = Lua(), []
    for name, title, code in cases:
        try:
            assert lua.check(base + module + code + '\nreturn "passed"', True, name) == "passed"
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
