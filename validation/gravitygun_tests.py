#!/usr/bin/env python3
"""Gravity-gun regressions using explicit engine doubles, not native acceptance."""
import argparse
import json
from pathlib import Path
from lua_support import Lua, normalize


def main(root, output):
    root = root.resolve()
    here = Path(__file__).resolve().parent
    runtime, results = Lua(), []

    def source(path, start=None, end=None):
        text = (root / path).read_text()
        if start:
            text = text[text.index(start):]
        if end:
            text = text[:text.index(end)]
        return 'do\nlocal function module()\n' + normalize(text) + '\nend\nmodule()\nend\n'

    base = (here / 'stubs.lua').read_text() + (here / 'custom_stubs.lua').read_text()
    for name in ('core', 'features', 'aperture', 'crossing', 'traces', 'transport', 'holding'):
        base += source('lua/seamless_portals/' + name + '.lua')
    base += source('lua/entities/seamless_portal/sh_init.lua', 'SeamlessPortals.TransformPortal = function', '-- Only render the portals')
    base += r'''
MASK_SHOT,CONTENTS_GRATE=117,32
MASK_SOLID_BRUSHONLY=16395
math.NormalizeAngle=function(n) return (n+180)%360-180 end
getmetatable(Vector()).Length2D=function(v) return math.sqrt(v.x*v.x+v.y*v.y) end
FVPHYSICS_PLAYER_HELD,FVPHYSICS_NO_PLAYER_PICKUP,FVPHYSICS_WAS_THROWN=4,128,256
EFL_NO_PHYSCANNON_INTERACTION=1
ACT_VM_SECONDARYATTACK,IN_ATTACK,IN_ATTACK2=182,1,2
local SP=SeamlessPortals
SP.RawTraceLine=function(data) return {Hit=false,Fraction=1,HitPos=data.endpos} end
local a,b=pair();local p=player();local weapon=prop();local target=prop(Vector(200,0,50))
function p:GetShootPos() return Vector(0,0,60) end
function p:GetAimVector() return Vector(0,0,-1) end
function p:GetActiveWeapon() return weapon end
function p:GetGroundEntity() return NULL end
function p:KeyDown(key) return self.buttons==key end
function p:ViewPunch() self.punches=(self.punches or 0)+1 end
function weapon:GetClass() return 'weapon_physcannon' end
function weapon:GetInternalVariable() return self.active end
function weapon:SendWeaponAnim(activity) self.animation=activity end
function weapon:SetNextSecondaryFire(time) self.secondary=time end
function target:GetMoveType() return MOVETYPE_VPHYSICS end
function target:IsEFlagSet() return self.excluded end
function target:WorldSpaceCenter() return self:GetPos() end
function target:SetPhysicsAttacker(attacker) self.attacker=attacker end
local body=target:GetPhysicsObject();body.mass=30;body.forces={}
function body:GetMesh() return nil end
function body:GetAABB() return Vector(-20,-20,-20),Vector(20,20,20) end
function body:GetMass() return self.mass end
function body:HasGameFlag(flag) return bit.band(self.flags or 0,flag)~=0 end
function body:AddGameFlag(flag) self.flags=bit.bor(self.flags or 0,flag) end
function body:ApplyForceCenter(force) self.forces[#self.forces+1]=Vector(force) end
function body:ApplyForceOffset(force,point) self.offset=Vector(force);self.point=Vector(point) end
local effects=0
SP.SendBulletVisual=function(context) effects=effects+1;assert(context.name=="seamless_gravitygun") end
function EffectData() return setmetatable({},{__index=function() return function() end end}) end
util.Effect=function() effects=effects+1 end
hook.Add('GravGunPunt','test_permission',function(_,ent) if ent==target then return target.permission~=false end end)
hook.Add('GravGunPickupAllowed','test_permission',function(_,ent) if ent==target then return target.permission~=false end end)
local distance=50
local blocker=false
SP.TraceLine=function(data)
 if data.start.x<100 then
  if blocker then return {Hit=true,Entity=target,StartPos=data.start,HitPos=Vector(0,0,40),Fraction=.1} end
  return {Hit=true,Entity=a,StartPos=data.start,HitPos=Vector(),HitNormal=a:GetUp(),Fraction=60/(data.start-data.endpos):Length()}
 end
 local hit=distance<=data.endpos.z
 return {Hit=hit,Entity=hit and target or NULL,StartPos=data.start,
  HitPos=hit and Vector(200,0,distance) or data.endpos,HitNormal=Vector(0,0,-1),
  Fraction=hit and (distance-data.start.z)/(data.endpos.z-data.start.z) or 1}
end
'''
    module = source('lua/seamless_portals/gravitygun.lua')

    def test(number, title, code, client=False):
        try:
            realm = 'SERVER=false;CLIENT=true\n' if client else ''
            runtime.check(base + realm + module + code + '\nreturn "passed"', True, number)
            status, observed = 'PASS', 'assertions passed'
        except Exception as exc:
            status, observed = 'FAIL', str(exc)
        results.append(dict(id=number, title=title, status=status, observed=observed))
        print(status, number, title)
        if status == 'FAIL':
            print(observed)

    test('G-T01', 'Punt spends range on both sides and transforms the direction', r'''
local plan=SP.TraceGravityGun(p,false)
assert(plan.entity==target);nearvec(plan.origin,Vector(200,0,-60));nearvec(plan.direction,Vector(0,0,1))
distance=191;assert(SP.TraceGravityGun(p,false)==nil)
distance=939;assert(SP.TraceGravityGun(p,true).entity==target)
distance=941;assert(SP.TraceGravityGun(p,true)==nil)
''')
    test('G-T02', 'Punt applies native mass-weighted forces to the existing body', r'''
local pos=target:GetPos()
assert(hook.Run('GravGunPunt',p,a)==false)
assert(target:GetPhysicsObject()==body and #body.forces==1)
nearvec(body.forces[1],Vector(0,0,15000));nearvec(body.offset,Vector(0,0,18000))
nearvec(body.point,Vector(200,0,50));nearvec(target:GetPos(),pos)
assert(target.attacker==p and body:HasGameFlag(FVPHYSICS_WAS_THROWN))
assert(effects==1 and p.punches==1 and weapon.animation==ACT_VM_SECONDARYATTACK)
''')
    test('G-T03', 'Pull nudges the real body toward the unfolded player without attaching', r'''
local pos=target:GetPos()
assert(SP.PullThroughPortal(p));assert(#body.forces==1)
nearvec(body.forces[1],Vector(0,0,-4000*30.5/50))
nearvec(target:GetPos(),pos);assert(not SP.GetHeldRecord(p) and not target:IsPlayerHolding())
''')
    test('G-T04', 'Ordinary local targets and held launches remain native', r'''
blocker=true
assert(hook.Run('GravGunPunt',p,target)==true)
assert(not SP.PuntThroughPortal(p) and not SP.PullThroughPortal(p))
blocker=false;weapon.active=true
assert(not SP.PuntThroughPortal(p) and not SP.PullThroughPortal(p))
assert(#body.forces==0 and effects==0)
''')
    test('G-T05', 'Permission polls never move or pick up portals and their proxies', r'''
for i=1,20 do assert(hook.Run('GravGunPickupAllowed',p,a)==false) end
local clone=prop();function clone:GetClass() return 'seamless_portal_clone' end
assert(hook.Run('GravGunPickupAllowed',p,clone)==false)
assert(#body.forces==0 and not SP.GetHeldRecord(p))
''')
    test('G-T06', 'Remote permission vetoes block both force paths', r'''
target.permission=false
assert(not SP.PuntThroughPortal(p) and not SP.PullThroughPortal(p))
assert(#body.forces==0 and effects==0)
''')
    test('G-T07', 'Endpoint disable and cover stop remote forces', r'''
SP.SetFeature(a,'props',false)
assert(not SP.PuntThroughPortal(p) and not SP.PullThroughPortal(p))
SP.SetFeature(a,'props',true);SP.SetFeature(b,'props',false)
assert(not SP.PuntThroughPortal(p) and not SP.PullThroughPortal(p))
SP.SetFeature(b,'props',true);blocker=true
assert(not SP.PuntThroughPortal(p) and not SP.PullThroughPortal(p));assert(#body.forces==0)
''')
    test('G-T08', 'Pickup limits, frozen bodies and competing holds are respected', r'''
body.mass=251;assert(not SP.PullThroughPortal(p))
body.mass=30;body.motion=false;assert(not SP.PullThroughPortal(p) and not SP.PuntThroughPortal(p))
body.motion=true;body.flags=FVPHYSICS_NO_PLAYER_PICKUP;assert(not SP.PullThroughPortal(p))
body.flags=FVPHYSICS_PLAYER_HELD;assert(not SP.PullThroughPortal(p) and not SP.PuntThroughPortal(p))
body.flags=0;target.excluded=true;assert(not SP.PullThroughPortal(p) and not SP.PuntThroughPortal(p))
assert(#body.forces==0)
''')
    test('G-T09', 'A visible clone maps back to the original entity and force point', r'''
local clone=prop()
function clone:GetClass() return 'seamless_portal_clone' end
function clone:GetPortal1() return b end
function clone:GetPortal2() return a end
function clone:GetChild() return target end
SP.TraceLine=function(data) return {Hit=true,Entity=clone,StartPos=data.start,HitPos=Vector(0,0,10),HitNormal=Vector(0,0,1)} end
local plan=SP.TraceGravityGun(p,true)
assert(plan.entity==target);nearvec(plan.hit,Vector(200,0,-10));nearvec(plan.direction,Vector(0,0,1))
assert(SP.PullThroughPortal(p));assert(#body.forces==1)
''')
    test('G-T10', 'Permission callbacks cannot remove physics or unlink before force application', r'''
hook.Add('GravGunPunt','test_permission',function() b.exit=NULL;return true end)
assert(not SP.PuntThroughPortal(p));assert(#body.forces==0)
b.exit=a
hook.Add('GravGunPunt','test_permission',function() target.bodies={physics(Vector())};return true end)
assert(not SP.PuntThroughPortal(p));assert(#body.forces==0)
''')
    test('G-T11', 'Recursive and failing permission callbacks release the guard', r'''
hook.Add('GravGunPunt','test_permission',function()
 assert(not SP.PuntThroughPortal(p));error('expected permission failure')
end)
assert(not SP.PuntThroughPortal(p));assert(#body.forces==0)
hook.Add('GravGunPunt','test_permission',function() return true end)
assert(SP.PuntThroughPortal(p));assert(#body.forces==1)
''')
    test('G-T12', 'Pull polling is limited to ten per second and stops on release or hold', r'''
p.buttons=IN_ATTACK2
for i=1,20 do hook.Run('PlayerPostThink',p) end
assert(#body.forces==1)
NOW=NOW+.11;hook.Run('PlayerPostThink',p);assert(#body.forces==2)
NOW=NOW+.11;p.buttons=nil;hook.Run('PlayerPostThink',p);assert(#body.forces==2)
p.buttons=IN_ATTACK2;weapon.active=true;hook.Run('PlayerPostThink',p);assert(#body.forces==2)
''')
    test('G-T13', 'Client feedback follows the confirmed shot without applying physics', r'''
assert(not SP.PuntThroughPortal(p))
function weapon:GetOwner() return p end
function LocalPlayer() return p end
SP.GravityGunPuntFeedback(weapon)
assert(#body.forces==0 and effects==0 and p.punches==nil)
assert(weapon.animation==ACT_VM_SECONDARYATTACK)
''', client=True)
    test('G-T14', 'False portal weight sounds are suppressed without muting normal gravity-gun sounds', r'''
local event={OriginalSoundName='Weapon_PhysCannon.TooHeavy',Entity=p}
SP.RawTraceLine=function() return {Hit=true,Entity=a} end
assert(SP.SuppressPortalGravitySound(event))
event.OriginalSoundName='Weapon_PhysCannon.Launch';assert(not SP.SuppressPortalGravitySound(event))
event.OriginalSoundName='Weapon_PhysCannon.TooHeavy'
SP.RawTraceLine=function() return {Hit=true,Entity=target} end
assert(not SP.SuppressPortalGravitySound(event))
''')
    test('G-T15', 'World-anchored constraints are retained and refuse remote pulling', r'''
target.constraints={{Type='Weld',Entity={{World=true,Entity=WORLD}}}}
assert(not SP.PullThroughPortal(p));assert(#target.constraints==1 and #body.forces==0)
''')
    test('G-T16', 'Native helper targets and invalid physics mass are never manipulated', r'''
SP.NativePickupTargets={[target]={}}
assert(not SP.PullThroughPortal(p) and not SP.PuntThroughPortal(p))
SP.NativePickupTargets={};body.mass=0/0
assert(not SP.PullThroughPortal(p) and not SP.PuntThroughPortal(p));assert(#body.forces==0)
''')
    test('G-T17', 'Visual legs stop at the aperture and resume at the exit', r'''
local plan=SP.TraceGravityGun(p,false)
assert(#plan.segments==2)
nearvec(plan.segments[1].start,p:GetShootPos());nearvec(plan.segments[1].finish,Vector())
nearvec(plan.segments[2].start,Vector(200,0,.05));nearvec(plan.segments[2].finish,plan.hit)
''')
    visuals = r'''
local materials,beams,sprites,sparks={},{},{},{}
function CreateMaterial(name,shader,values)
 local mat={shader=shader,values=values,SetInt=function(self,key,value) self[key]=value end}
 materials[name]=mat;return mat
end
function Material(name) return name end
function Color(r,g,b,a) return {r=r,g=g,b=b,a=a or 255} end
function LocalPlayer() return p end
function weapon:GetOwner() return p end
function p:ShouldDrawLocalPlayer() return true end
function weapon:LookupAttachment() return 1 end
function weapon:GetAttachment() return {Pos=Vector(2,0,60)} end
local effect
function EffectData()
 effect={};return setmetatable(effect,{__index=function(_,key)
  return function(self,value) self[key]=value end
 end})
end
util.Effect=function(name) assert(name=='Sparks');sparks[#sparks+1]=effect end
render={SetMaterial=function() end,
 DrawBeam=function(start,finish,width) beams[#beams+1]={start=start,finish=finish,width=width} end,
 DrawSprite=function(pos,width) sprites[#sprites+1]={pos=pos,width=width} end}
''' + source('lua/seamless_portals/tracers.lua')
    test('G-T18', 'Gravity beam is additive, animated and sparks only at the final hit', visuals + r'''
local path={{start=p:GetShootPos(),finish=Vector()},{start=Vector(200,0,.05),finish=Vector(200,0,50)}}
SP.EmitBulletVisual('seamless_gravitygun',path,weapon)
assert(#SP.TracerSegments==2 and #sparks==1 and weapon.animation==ACT_VM_SECONDARYATTACK)
nearvec(sparks[1].SetOrigin,path[2].finish);near(sparks[1].SetMagnitude,3)
assert(materials.seamless_portals_gravity_beam.values['$additive']=='1')
assert(materials.seamless_portals_gravity_glow.values['$additive']=='1')
hook.Run('PostDrawTranslucentRenderables',false,false)
assert(#beams==2 and #sprites==1);nearvec(beams[1].start,Vector(2,0,60))
nearvec(beams[1].finish,Vector());nearvec(beams[2].start,path[2].start)
NOW=NOW+.04;hook.Run('PostDrawTranslucentRenderables',false,false)
assert(materials.seamless_portals_gravity_beam['$frame']==1)
NOW=NOW+.12;hook.Run('Think');assert(#SP.TracerSegments==0)
''', client=True)
    bridge = r'''
target.holding=true;SP.RecordHold(p,target,'gravgun')
local hold=SP.GetHeldRecord(p)
local item={entity=target,bodies={{phys=body,index=0,pos=Vector(200,0,50),ang=Angle(),
 newpos=Vector(800,400,50),newang=Angle(),newvel=Vector(20,0,0),angular=Vector(),motion=true}}}
local plan={root=target,holder=p,items={item}}
local later={};timer.Simple=function(_,fn) later[#later+1]=fn end
function body:Sleep() self.sleeping=true end
function body:Wake() self.sleeping=false end
body:SetPos(item.bodies[1].newpos)
'''
    test('G-T19', 'A gravity-gun transfer preserves the native hold across its next target update', bridge + r'''
SP.PrepareGravityGunTransfer(plan);assert(body.sleeping and SP.GravityCarryTransfers[p])
hook.Run('StartCommand',p);nearvec(body:GetPos(),item.bodies[1].pos)
assert(SP.GetHeldRecord(p)==hold and target:GetPhysicsObject()==body and target:IsPlayerHolding())
hook.Run('SetupMove',p);nearvec(body:GetPos(),item.bodies[1].newpos)
assert(not body.sleeping and not SP.GravityCarryTransfers[p])
nearvec(body:GetVelocity(),Vector(20,0,0))
for _,fn in ipairs(later) do fn() end
nearvec(body:GetPos(),item.bodies[1].newpos)
''')
    test('G-T20', 'Transfer cleanup restores the destination and leaves other native hold types untouched', bridge + r'''
SP.Holds[p].kind='physgun';SP.PrepareGravityGunTransfer(plan)
assert(not SP.GravityCarryTransfers[p] and not body.sleeping)
SP.Holds[p].kind='gravgun';SP.PrepareGravityGunTransfer(plan);hook.Run('StartCommand',p)
hook.Run('GravGunOnDropped',p,target)
nearvec(body:GetPos(),item.bodies[1].newpos);assert(not body.sleeping and not SP.GravityCarryTransfers[p])
''')
    test('G-T21', 'An interrupted movement callback and replaced physics cannot strand a transferred body', bridge + r'''
SP.PrepareGravityGunTransfer(plan);hook.Run('StartCommand',p)
for _,fn in ipairs(later) do fn() end
nearvec(body:GetPos(),item.bodies[1].newpos);assert(not body.sleeping and not SP.GravityCarryTransfers[p])
SP.PrepareGravityGunTransfer(plan)
body.valid=false
hook.Run('StartCommand',p);assert(not SP.GravityCarryTransfers[p])
''')
    grip = r'''
target.holding=true
if SERVER then SP.RecordHold(p,target,'gravgun') else p:SetNWEntity('seamless_portals_held',target) end
p.hi=Vector(16,16,72);p.offset=Vector(0,0,64)
function p:GetCurrentViewOffset() return Vector(self.offset) end
function p:SetCurrentViewOffset(v) self.offset=Vector(v) end
function p:GetShootPos() return self:GetPos()+self:GetCurrentViewOffset() end
local look=Vector(0,0,-1)
function p:EyeAngles() return {p=0,Forward=function() return look end} end
local later={};timer.Simple=function(_,fn) later[#later+1]=fn end
local wall,cover=false,false
SP.RawTraceLine=function(data)
 local length=(data.endpos-data.start):Length()
 local hit=wall and (length>70 or cover)
 return {Fraction=hit and .1 or 1,Hit=hit,HitPos=hit and data.start+(data.endpos-data.start)*.1 or data.endpos}
end
local original=Vector(p.offset)
local normal=24+math.sqrt(512)+20
'''
    test('G-T22', 'Portal wall compensation keeps the native grip distance and restores the eye before movement', grip + r'''
p:SetPos(Vector(0,0,-30));wall=true
SP.PrepareGravityGunGrip(p)
assert(SP.GravityGripOffsets[p]);near((p.offset-original):Length(),normal-(normal-24)*.5)
local nativeEnd=p:GetShootPos()+look*((normal-24)*.5)
nearvec(nativeEnd,p:GetPos()+original+look*normal)
hook.Run('SetupMove',p);nearvec(p.offset,original)
assert(not SP.GravityGripOffsets[p] and target:IsPlayerHolding() and target:GetPhysicsObject()==body)
''')
    test('G-T23', 'A temporarily narrowed player hull does not pull the object toward the face', grip + r'''
p.SEAMLESS_PORTALS_HULL_MAXS=Vector(p.hi);p.hi=Vector(4,4,64.8)
SP.PrepareGravityGunGrip(p)
near((p.offset-original):Length(),math.sqrt(512)-math.sqrt(32))
local nativeEnd=p:GetShootPos()+look*(24+math.sqrt(32)+20)
nearvec(nativeEnd,p:GetPos()+original+look*normal)
hook.Run('SetupMove',p);nearvec(p.offset,original)
''')
    test('G-T24', 'Ordinary walls, cover, closed links and portal backfaces retain the native grip', grip + r'''
p:SetPos(Vector(0,0,-30));wall=true
SP.SetFeature(b,'props',false);SP.PrepareGravityGunGrip(p);assert(not SP.GravityGripOffsets[p])
SP.SetFeature(b,'props',true);b.exit=NULL;SP.PrepareGravityGunGrip(p);assert(not SP.GravityGripOffsets[p])
b.exit=a;cover=true;SP.PrepareGravityGunGrip(p);assert(not SP.GravityGripOffsets[p])
cover=false;look=Vector(0,0,1);SP.PrepareGravityGunGrip(p);assert(not SP.GravityGripOffsets[p])
look=Vector(0,0,-1);p:SetPos(Vector(100,0,-30));SP.PrepareGravityGunGrip(p);assert(not SP.GravityGripOffsets[p])
nearvec(p.offset,original)
''')
    test('G-T25', 'Grip cleanup survives interrupted movement, release, reload and competing view offsets', grip + r'''
p.SEAMLESS_PORTALS_HULL_MAXS=Vector(p.hi);p.hi=Vector(4,4,64.8)
SP.PrepareGravityGunGrip(p);for _,fn in ipairs(later) do fn() end
nearvec(p.offset,original);assert(not SP.GravityGripOffsets[p])
SP.PrepareGravityGunGrip(p);p:SetCurrentViewOffset(Vector(1,2,3));SP.RestoreGravityGunGrip(p)
nearvec(p.offset,Vector(1,2,3));p:SetCurrentViewOffset(original)
SP.PrepareGravityGunGrip(p);SP.ClearGravityGunGrips();nearvec(p.offset,original)
SP.PrepareGravityGunGrip(p);hook.Run('GravGunOnDropped',p,target)
nearvec(p.offset,original);assert(not SP.GravityGripOffsets[p])
''')
    test('G-T26', 'The client predicts the same grip correction and restores it before movement', grip + r'''
p.SEAMLESS_PORTALS_HULL_MAXS=Vector(p.hi);p.hi=Vector(4,4,64.8)
hook.Run('StartCommand',p);assert(SP.GravityGripOffsets[p])
near((p.offset-original):Length(),math.sqrt(512)-math.sqrt(32))
hook.Run('SetupMove',p);nearvec(p.offset,original)
assert(#body.forces==0 and target:GetPhysicsObject()==body)
''', client=True)
    test('G-T27', 'Physics mesh support follows the grip direction and bounds cached work', grip + r'''
local reads=0
function body:GetMesh() reads=reads+1;return {{pos=Vector(0,0,12)},{pos=Vector(0,0,-4)}} end
p.SEAMLESS_PORTALS_HULL_MAXS=Vector(p.hi);p.hi=Vector(4,4,64.8)
for i=1,4 do SP.PrepareGravityGunGrip(p);SP.RestoreGravityGunGrip(p) end
assert(reads==1)
function target:GetPhysicsObject() return self.replacement end
target.replacement=physics(Vector())
function target.replacement:GetMesh() local mesh={} for i=1,4097 do mesh[i]={pos=Vector()} end return mesh end
SP.PrepareGravityGunGrip(p);assert(not SP.GravityGripOffsets[p]);nearvec(p.offset,original)
''')
    test('G-T30', 'Thin-wall grip preserves rotation and restores the hull before movement', grip + r'''
look=Vector(1,0,0)
p.dlo,p.dhi=Vector(p.lo),Vector(p.hi)
local lo,hi=p:GetHull();local dlo,dhi=p:GetHullDuck()
local originalAngles=p:EyeAngles()
function p:SetEyeAngles() error('Grip must not change rotation') end
SP.FirstCrossing=function(start,delta) return {entry=a,exit=b,point=start+delta:GetNormalized()*20} end
SP.RawTraceLine=function(data)
 local dx=data.endpos.x-data.start.x
 local fraction=1
 if data.start.x<25 and data.endpos.x>=25 then fraction=(25-data.start.x)/dx end
 return {Fraction=fraction,Hit=fraction<1,HitPos=data.start+(data.endpos-data.start)*fraction}
end
local start=p:GetShootPos()
SP.PrepareGravityGunGrip(p)
local pending=SP.GravityGripOffsets[p]
assert(pending and pending.hulls and not pending.angles)
local radius=p:OBBMaxs():Length2D()+20
local nativeTrace=SP.RawTraceLine({start=p:GetShootPos(),endpos=p:GetShootPos()+look*(24+2*radius)})
local nativeDistance=nativeTrace.Fraction<.5 and .5*radius or 24+radius
local endpoint=p:GetShootPos()+look*nativeDistance
local delta=Vector(endpoint.x-p:GetPos().x,endpoint.y-p:GetPos().y,0)
if delta:Length()<radius then endpoint=endpoint+delta:GetNormalized()*(radius-delta:Length()) end
nearvec(endpoint,start+Vector(normal,0,0))
hook.Run('SetupMove',p)
nearvec(p.offset,original)
local alo,ahi=p:GetHull();local adlo,adhi=p:GetHullDuck()
nearvec(alo,lo);nearvec(ahi,hi);nearvec(adlo,dlo);nearvec(adhi,dhi)
SP.PrepareGravityGunGrip(p)
p:SetHull(Vector(-8,-8,0),Vector(8,8,60))
SP.RestoreGravityGunGrip(p)
nearvec(p:OBBMaxs(),Vector(8,8,60))
''')
    collision = r'''
local function collisionEntity(ent,custom)
 ent.custom=custom;ent.rules=0
 function ent:GetCustomCollisionCheck() return self.custom end
 function ent:SetCustomCollisionCheck(v) self.custom=v end
 function ent:CollisionRulesChanged() self.rules=self.rules+1 end
 function ent:SetNWEntity(key,value) self[key]=value end
end
collisionEntity(target,false)
'''
    test('G-T31', 'Passage collision excludes only the holder and restores root, handle and proxy on release', collision + r'''
local handle,clone=prop(),prop()
collisionEntity(handle,true);collisionEntity(clone,false)
target.SEAMLESS_PORTALS_CLONE=clone
target.holding=true;SP.RecordHold(p,target,'gravgun')
local record=SP.GetHeldRecord(p);record.entry=a;record.group={target,handle}
SP.RefreshGravityPassageOwners()
for _,ent in ipairs({target,handle,clone}) do
 assert(hook.Run('ShouldCollide',p,ent)==false and hook.Run('ShouldCollide',ent,p)==false)
 assert(hook.Run('ShouldCollide',ent,player())==nil)
 assert(ent.custom and ent.rules==1)
end
SP.RefreshGravityPassageOwners();assert(target.rules==1)
SP.ClearHold(p);SP.RefreshGravityPassageOwners()
for _,ent in ipairs({target,handle,clone}) do
 assert(hook.Run('ShouldCollide',p,ent)==nil and ent.rules==2)
 assert(not SP.GravityPassageOwners[ent])
end
assert(not target.custom and handle.custom and not clone.custom)
''')
    test('G-T32', 'Replicated collision changes invalidate cached pairs and preserve existing custom checks', collision + r'''
hook.Run('EntityNetworkedVarChanged',target,'seamless_portals_gravity_passage_holder',NULL,p)
assert(hook.Run('ShouldCollide',p,target)==false and target.custom and target.rules==1)
hook.Run('EntityNetworkedVarChanged',target,'seamless_portals_gravity_passage_holder',p,NULL)
assert(hook.Run('ShouldCollide',p,target)==nil and not target.custom and target.rules==2)
target.custom=true
SP.SetGravityPassageOwner(target,p);SP.ClearGravityPassageOwners()
assert(target.custom and target.rules==4)
''', client=True)
    test('G-T28', 'A gravity-held prop emerges from a wall exit without ignoring an obstacle after it',
         source('lua/seamless_portals/held_proxy.lua') + r'''
function LerpVector(t,a,b) return a+(b-a)*t end
target:SetPos(Vector(0,0,-2))
local record={kind='gravgun',entity=target,player=p,group={target},entry=a,exit=b}
target.SEAMLESS_PORTALS_CARRY=record
local clone=prop();local position=SP.TransformPortal(a,b,target:GetPos())
local original=Vector(target:GetPos())
local restored=0;SP.RestoreCarryContact=function() restored=restored+1 end
for _,blocked in ipairs({false,true}) do
 target:SetPos(original)
 clone.SEAMLESS_PORTALS_PROXY_LAST={position=position-Vector(0,0,10)}
 local calls=0
 util.TraceHull=function(data)
  calls=calls+1
  if calls==1 then return {Hit=true,StartSolid=true,AllSolid=false,FractionLeftSolid=.5} end
  return {Hit=blocked,StartSolid=false,AllSolid=false,Fraction=blocked and .5 or 1}
 end
 local result=SP.ClampHeldProxy(clone,target,a,b,position,Angle())
 assert(calls==2 and restored==0)
 if blocked then assert(result.z<position.z) else nearvec(result,position);nearvec(target:GetPos(),original) end
end
util.TraceHull=function() return {Hit=true,StartSolid=true,AllSolid=true,FractionLeftSolid=.5} end
SP.ClampHeldProxy(clone,target,a,b,position,Angle());assert(restored==1)
''')
    test('G-T29', 'Native remote gravity selection retains range, mass and target permission checks',
         source('lua/seamless_portals/remote_pickup.lua') + r'''
function p:EyePos() return p:GetShootPos() end
p.buttons=IN_ATTACK2
local meshes=0
function body:WorldToLocal(point) return point-self:GetPos() end
function body:GetMeshConvexes() meshes=meshes+1;return nil end
local poll=hook.GetTable().PlayerPostThink.seamless_portals_native_remote_pickup
local function attempt() NOW=NOW+.2;poll(p) end
attempt();assert(meshes==1 and not SP.GetHeldRecord(p))
distance=191;attempt();assert(meshes==1)
distance=50;body.mass=251;attempt();assert(meshes==1)
body.mass=30;body.motion=false;attempt();assert(meshes==1)
body.motion=true;target.permission=false;attempt();assert(meshes==1)
target.permission=true
hook.Add('GravGunPickupAllowed','test_permission',function() body.motion=false;return true end)
attempt();assert(meshes==1)
assert(target:GetPhysicsObject()==body and not SP.GetHeldRecord(p))
''')
    report = dict(native_gmod_tested=False, tests=results,
                  passed=sum(r['status'] == 'PASS' for r in results),
                  failed=sum(r['status'] == 'FAIL' for r in results))
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(json.dumps(report, indent=2) + '\n')
    return int(bool(report['failed']))


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('source', type=Path)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    raise SystemExit(main(args.source, args.output))
