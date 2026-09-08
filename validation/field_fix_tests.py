#!/usr/bin/env python3
"""Focused field regressions with explicit API doubles; not native acceptance."""
import argparse
import json
from pathlib import Path
from lua_support import Lua, normalize


def main(root, output):
    root = root.resolve()
    here = Path(__file__).resolve().parent
    lua, results = Lua(), []

    def src(path, start=None, stop=None):
        text = (root / path).read_text()
        if start:
            text = text[text.index(start):]
        if stop:
            text = text[:text.index(stop)]
        return 'do\nlocal function module()\n' + normalize(text) + '\nend\nmodule()\nend\n'

    base = (here / 'stubs.lua').read_text() + (here / 'custom_stubs.lua').read_text()
    base += src('lua/seamless_portals/core.lua') + src('lua/seamless_portals/features.lua')
    base += src('lua/seamless_portals/aperture.lua')
    base += src('lua/entities/seamless_portal/sh_init.lua', 'SeamlessPortals.TransformPortal = function', '-- Only render the portals')
    base += src('lua/seamless_portals/crossing.lua')
    base += '''
DMG_BLAST,DMG_CLUB,MASK_SHOT,MASK_SHOT_HULL=64,128,117,119
PLAYERANIMEVENT_ATTACK_PRIMARY,ACT_VM_MISSCENTER=0,197
angle_zero=Angle()
function LocalToWorld(pos,ang,origin,rotation) return origin+pos,ang end
bit.bnot=function(n) return ~n end
local oldDamage=DamageInfo
function DamageInfo()
 local d=oldDamage()
 for _,name in ipairs({'BaseDamage','MaxDamage','DamageBonus','ReportedPosition','Weapon'}) do
  d[name]=name=='ReportedPosition' and Vector() or name=='Weapon' and NULL or 0
  d['Get'..name]=function(self) return self[name] end
  d['Set'..name]=function(self,v) self[name]=v end
 end
 function d:IsDamageType(kind) return bit.band(self.DamageType,kind)~=0 end
 function d:IsExplosionDamage() return self:IsDamageType(DMG_BLAST) end
 return d
end
ents={FindByClass=function() return {} end,GetAll=function() return {} end,FindInSphere=function() return {} end}
util.BlastDamage=function() return 'native' end
util.BlastDamageInfo=function() return 'native' end
local oldProp=prop
function prop(...)
 local e=oldProp(...)
 function e:OBBCenter() return (self.lo+self.hi)/2 end
 function e:NearestPoint() return self:GetPos() end
 function e:GetOwner() return self.owner or NULL end
 function e:GetVelocity() return self:GetPhysicsObject():GetVelocity() end
 function e:TakeDamageInfo(d) self.damage=(self.damage or 0)+d:GetDamage() end
 function e:DeleteOnRemove() end
 function e:GetNoDraw() return self.nodraw or false end
 function e:SetNWEntity(key,value) self.nwentities=self.nwentities or {};self.nwentities[key]=value end
 function e:GetNWEntity(key) return self.nwentities and self.nwentities[key] or NULL end
 function e:SetOwner(owner) self.owner=owner end
 function e:SetKeyValue() end
 function e:SetMoveType() end
 function e:SetLocalVelocity(v) self.bodies[1]:SetVelocity(v) end
 for _,phys in ipairs(e.bodies) do phys.SetVelocityInstantaneous=phys.SetVelocity end
 return e
end
'''
    modules = {name: src('lua/seamless_portals/' + name + '.lua') for name in
               ['blasts', 'holding', 'carry', 'projectiles', 'traces', 'melee', 'rpg_guidance', 'bullets']}

    def test(id, title, code, load=''):
        try:
            result = lua.check(base + load + code + '\nreturn "passed"', True, id)
            assert result == 'passed'
            status, observed = 'PASS', 'assertions passed'
        except Exception as exc:
            status, observed = 'FAIL', str(exc)
        results.append(dict(id=id, title=title, status=status, observed=observed))

    test('F-T01', 'Damage snapshot survives reused native allocation and missing actors', '''
local original=DamageInfo
local shared={}
DamageInfo=function()
 for k in pairs(shared) do shared[k]=nil end
 for k,v in pairs(original()) do shared[k]=v end
 function shared:SetAttacker(v) assert(v~=NULL);self.Attacker=v end
 function shared:SetInflictor(v) assert(v~=NULL);self.Inflictor=v end
 return shared
end
local d=DamageInfo() d:SetDamage(123) d:SetDamageForce(Vector(1,2,3))
local result=SeamlessPortals.CopyDamage(d)
assert(result:GetDamage()==123 and result:GetAttacker()==WORLD and result:GetInflictor()==WORLD)
nearvec(result:GetDamageForce(),Vector(1,2,3))
''')
    blast = '''
local SP=SeamlessPortals
local a,b=pair()
function b:BoundingRadius() return 70 end
function a:BoundingRadius() return 70 end
local d=DamageInfo() d:SetDamage(100) d:SetDamageType(DMG_BLAST)
local source=prop(Vector(0,0,20)) d:SetInflictor(source) d:SetAttacker(source)
local target=prop(Vector(200,0,20))
ents.FindInSphere=function() return {target} end
SP.PortalSight=function() return {distance=40} end
local event=SP.NewBlastEvent(d,Vector(0,0,20),200)
'''
    test('F-T02', 'Queued blast retains metadata after another damage event', blast + '''
d:SetDamage(999) d:SetDamageForce(Vector(999,0,0))
assert(SP.RelayBlast(event)) near(target.damage,80)
assert(event.info.Damage==100 and event.info.Inflictor==source)
''', modules['blasts'])
    test('F-T03', 'Blast strongest path subtracts damage already taken directly', blast + '''
event.direct[target]=60
assert(SP.RelayBlast(event)) near(target.damage,20)
''', modules['blasts'])
    test('F-T04', 'Explosion respects endpoint opt-out and range', blast + '''
SP.SetFeature(b,'damage',false) assert(SP.RelayBlast(event));assert(not target.damage)
assert(SP.BlastPathDamage(event,{distance=200})==0)
''', modules['blasts'])
    test('F-T05', 'Native chain explosion is queued during synthetic damage', blast + '''
local secondary=prop(Vector(200,0,25))
function secondary:GetInternalVariable(key) if key=='m_explodeDamage' then return 40 elseif key=='m_explodeRadius' then return 100 end end
function target:TakeDamageInfo(info)
 SP.ObserveNativeBlast(self,info,true)
 local chain=DamageInfo() chain:SetDamageType(DMG_BLAST) chain:SetDamage(40) chain:SetInflictor(secondary)
 SP.ObserveNativeBlast(source,chain,true)
end
assert(SP.RelayBlast(event))
local count=0
SP.RelayBlast=function(e) count=count+1;assert(e.info.Inflictor==secondary) end
SP.FlushBlastEvents() assert(count==1)
''', modules['blasts'])
    test('F-T06', 'Blast wrapper reload keeps identity and current handler', '''
local a,b=pair();local own=util.BlastDamage
''' + modules['blasts'] + '''
assert(util.BlastDamage==own)
assert(util.BlastDamage(WORLD,WORLD,Vector(0,0,10),100,25)=='native')
local count=0;SeamlessPortals.RelayBlast=function(e) count=count+1;assert(e.damage==25) end
SeamlessPortals.FlushBlastEvents();assert(count==1)
''', modules['blasts'])
    test('F-T07', 'Repeated pickup preserves the active carry corridor', '''
local p,e=player(),prop();e.holding=true
local SP=SeamlessPortals;SP.RecordHold(p,e,'physgun')
local record=SP.GetHeldRecord(p);record.entry=portal();record.crossed=true
SP.RecordHold(p,e,'physgun')
assert(SP.GetHeldRecord(p)==record and record.entry and record.crossed)
SP.RecordHold(p,record.entry,'physgun');assert(SP.GetHeldRecord(p)==record)
assert(SP.HasTrackedHold(e))
''', modules['holding'])
    test('F-T08', 'Portal pickup veto retains the existing object and release clears it', '''
local p,e=player(),prop();e.holding=true
local SP=SeamlessPortals;SP.RecordHold(p,e,'physgun');local a=portal()
assert(hook.Run('PhysgunPickup',p,a)==false)
assert(SP.GetHeldRecord(p).entity==e)
hook.Run('PhysgunDrop',p,e);assert(not SP.HasTrackedHold(e))
''', modules['holding'])
    projectile = '''
local SP=SeamlessPortals;local a,b=pair()
local e=prop(Vector(0,0,4))
function e:GetClass() return 'prop_combine_ball' end
local phys=e:GetPhysicsObject();phys.vel=Vector(80,25,-200)
SP.RawTraceLine=function(d) return {Hit=false,StartSolid=false,AllSolid=false,Fraction=1} end
local before=SP.TransformPortal(a,b,e:GetPos())
local dir=SP.TransformDirection(a,b,phys.vel,false):GetNormalized()
'''
    test('F-T09', 'Oblique energy ball keeps its ray, owner and physics body', projectile + '''
assert(SP.TransferProjectile(e,.025,{}))
local offset=e:GetPos()-before
nearvec(offset-dir*offset:Dot(dir),Vector(),1e-6)
assert(e:GetPhysicsObject()==phys and e:GetOwner()==NULL)
''', modules['projectiles'])
    test('F-T10', 'Projectile exit obstacle refuses transfer without mutation', projectile + '''
local before=e:GetPos()
util.TraceHull=function() return {Hit=true} end
assert(not SP.TransferProjectile(e,.025,{}));nearvec(e:GetPos(),before)
''', modules['projectiles'])
    test('F-T11', 'Damage trace respects endpoint switches', '''
local a,b=pair();SeamlessPortals.SetFeature(b,'damage',false)
local calls=0
local tr=SeamlessPortals.TracePortalLine({start=Vector(0,0,10),endpos=Vector(0,0,-50),SeamlessFeature='damage'},function(d)
 calls=calls+1;return {Hit=true,Entity=a,HitPos=Vector(),HitNormal=Vector(0,0,1),Fraction=.2}
end)
assert(calls==1 and not tr.SeamlessSegments)
''', modules['traces'])
    render_setup = r'''
CLIENT=true;SERVER=false
local lines,meshes,textures=0,0,0
function Color() return {} end
function Material() return {} end
function Matrix() return {Identity=function() end,SetScale=function() end} end
function ScrW() return 800 end
function ScrH() return 600 end
local eye=Vector(0,0,-20)
function EyePos() return eye end
render=setmetatable({DrawLine=function() lines=lines+1 end,
 DrawTextureToScreen=function() textures=textures+1 end},{__index=function() return function() end end})
cam={}
'''
    renderer = src('lua/entities/seamless_portal/cl_init.lua', 'local drawMat', 'function ENT:Draw(flags)')
    test('F-T12', 'No-back render responds to linking, unlinking and the viewing side', render_setup + renderer + r'''
local a,b=pair()
function a:GetDisableBackface() return true end
function a:DrawModel() meshes=meshes+1 end
function a:DrawModelMesh() meshes=meshes+1 end
function a:DrawStenciled(...) return ENT.DrawStenciled(self,...) end
a.SEAMLESS_PORTALS_RENDERED=true
a:DrawStenciled({});assert(lines==0 and meshes==0 and textures==0)
a.exit=NULL;a:DrawStenciled({});assert(lines>0 and textures==0)
lines=0;a.exit=b;a:DrawStenciled({});assert(lines==0 and meshes==0)
eye=Vector(0,0,20);a:DrawStenciled({});assert(textures==1)
''')
    melee_fixture = r'''
local SP=SeamlessPortals;local a,b=pair();local p=player();local weapon=prop()
function weapon:GetClass() return 'weapon_crowbar' end
function p:GetActiveWeapon() return weapon end
function p:GetShootPos() return Vector(0,0,30) end
local target=prop(Vector(200,0,20))
local hits,effects=0,0
function target:DispatchTraceAttack(info,tr,dir)
 hits=hits+1;assert(info:GetAttacker()==p and info:GetWeapon()==weapon)
 near(info:GetDamage(),10);nearvec(dir,Vector(0,0,1))
end
function EffectData() return setmetatable({},{__index=function() return function() end end}) end
util.Effect=function() effects=effects+1 end
local first={Hit=true,Entity=a,StartPos=p:GetShootPos(),HitPos=Vector(),HitNormal=a:GetUp()}
local last={Hit=true,Entity=target,StartPos=Vector(200,0,.05),HitPos=Vector(200,0,20),HitNormal=Vector(0,0,-1)}
SP.TracePortalLine=function(data)
 near(data.start:Distance(data.endpos),75);assert(data.SeamlessFeature=='damage')
 return {Hit=last.Hit,Entity=last.Entity,HitPos=last.HitPos,SeamlessSegments={first,last}}
end
local d=DamageInfo();d:SetAttacker(p);d:SetDamage(10);d:SetDamageType(DMG_CLUB)
'''
    test('F-T13', 'Crowbar damages the remote target exactly once', melee_fixture + r'''
assert(SP.RelayPortalMelee(a,d,Vector(0,0,-1),first));assert(hits==1 and effects==1)
''', modules['traces'] + modules['melee'])
    test('F-T14', 'Empty melee path has no damage or impact; bullets use their own path', melee_fixture + r'''
last.Hit=false;last.Entity=NULL
assert(not SP.RelayPortalMelee(a,d,Vector(0,0,-1),first));assert(hits==0 and effects==0)
d:SetDamageType(2);last.Hit=true;last.Entity=target
assert(not SP.RelayPortalMelee(a,d,Vector(0,0,-1),first));assert(hits==0 and effects==0)
''', modules['traces'] + modules['melee'])
    melee_sound = r'''
local SP=SeamlessPortals;local a,b=pair();local p=player();local weapon=prop()
function p:GetShootPos() return Vector(0,0,30) end
function p:GetAimVector() return Vector(0,0,-1) end
function p:GetActiveWeapon() return weapon end
function weapon:GetClass() return 'weapon_crowbar' end
weapon.owner=p
local event={OriginalSoundName='Weapon_Crowbar.Melee_Hit',SoundName='physics/flesh/flesh_impact_bullet3.wav',Entity=p}
local calls=0
SP.RawTraceLine=function(data)
 calls=calls+1;assert(data.SeamlessIgnore and data.mask==MASK_SHOT_HULL and data.filter==p)
 near(data.start:Distance(data.endpos),75)
 return {Hit=true,Entity=a,HitPos=Vector()}
end
'''
    for realm in ('server', 'client'):
        load = ('' if realm == 'server' else 'CLIENT=true;SERVER=false\n') + modules['melee']
        load += src('lua/seamless_portals/sound.lua')
        test('F-T42' if realm == 'server' else 'F-T43',
             'Crowbar portal impact is vetoed before audio relay in the ' + realm, melee_sound + r'''
local paths=0;SP.SoundPaths=function() paths=paths+1;return {} end
assert(hook.Run('EntityEmitSound',event)==false)
assert(calls==1 and paths==0 and #net.messages==0)
CVARS.seamless_portals_soundrelay_server.value=0
SP.SetFeature(a,'damage',false);a.exit=NULL
assert(hook.Run('EntityEmitSound',event)==false)
event.Entity=weapon;assert(hook.Run('EntityEmitSound',event)==false)
assert(calls==3 and paths==0 and #net.messages==0)
''', load)
    test('F-T44', 'Melee sound guard preserves swings, other weapons and local impacts', melee_sound + r'''
event.OriginalSoundName='Weapon_Crowbar.Single'
assert(not SP.SuppressPortalMeleeSound(event) and calls==0)
event.OriginalSoundName=nil
assert(not SP.SuppressPortalMeleeSound(event) and calls==0)
event.OriginalSoundName='Weapon_Crowbar.Melee_Hit'
function weapon:GetClass() return 'weapon_pistol' end
assert(not SP.SuppressPortalMeleeSound(event) and calls==0)
function weapon:GetClass() return 'weapon_crowbar' end
local target=prop()
SP.RawTraceLine=function() return {Hit=true,Entity=target} end
assert(not SP.SuppressPortalMeleeSound(event))
event.Entity=NULL;assert(not SP.SuppressPortalMeleeSound(event))
''', modules['melee'])
    test('F-T45', 'Native hull edge refinement keeps the nearest real surface sound', melee_sound + r'''
local target=prop()
SP.RawTraceLine=function(data)
 calls=calls+1
 if calls==3 then return {Hit=true,Entity=a,HitPos=Vector(0,0,10)} end
 if calls==4 then return {Hit=true,Entity=target,HitPos=Vector(0,0,20)} end
 return {Hit=false}
end
util.TraceHull=function(data)
 near(data.start:Distance(data.endpos),75-1.732*16)
 nearvec(data.mins,Vector(-16,-16,-16));nearvec(data.maxs,Vector(16,16,16))
 return {Hit=true,Entity=a,HitPos=Vector(0,0,15)}
end
assert(not SP.SuppressPortalMeleeSound(event) and calls==10)
calls=0
SP.RawTraceLine=function() calls=calls+1;return {Hit=false} end
assert(SP.SuppressPortalMeleeSound(event) and calls==10)
''', modules['melee'])
    melee_range = r'''
local SP=SeamlessPortals;local a,b=pair();local p=player();local weapon=prop()
function weapon:GetClass() return 'weapon_crowbar' end
function p:GetActiveWeapon() return weapon end
function p:GetShootPos() return Vector(0,0,30) end
local target=prop();local hits,effects=0,0
function target:DispatchTraceAttack(info,tr,dir)
 hits=hits+1;near(info:GetDamage(),10);assert(info:GetAttacker()==p)
 nearvec(dir,Vector(0,0,1))
end
function EffectData() return setmetatable({},{__index=function() return function() end end}) end
util.Effect=function() effects=effects+1 end
local d=DamageInfo();d:SetAttacker(p);d:SetDamage(10);d:SetDamageType(DMG_CLUB)
local first={Hit=true,Entity=a,StartPos=p:GetShootPos(),HitPos=Vector(),HitNormal=a:GetUp(),Fraction=.4}
local distance=44.9
SP.TraceLine=function(data)
 if data.start.x<100 then return first end
 near(data.endpos.z,45);assert(data.filter(b)==false and data.filter(p)==false)
 local hit=distance<=data.endpos.z
 return {Hit=hit,Entity=hit and target or NULL,StartPos=data.start,
  HitPos=hit and Vector(200,0,distance) or data.endpos,HitNormal=Vector(0,0,-1),
  Fraction=hit and (distance-data.start.z)/(data.endpos.z-data.start.z) or 1}
end
'''
    test('F-T46', 'Crowbar continuation spends its range on both sides of the portal', melee_range + r'''
assert(SP.RelayPortalMelee(a,d,Vector(0,0,-1),first));assert(hits==1 and effects==1)
distance=45.1
assert(not SP.RelayPortalMelee(a,d,Vector(0,0,-1),first));assert(hits==1 and effects==1)
''', modules['traces'] + modules['melee'])
    test('F-T47', 'Crowbar respects damage switches, backfaces and intervening cover', melee_range + r'''
SP.SetFeature(b,'damage',false)
assert(not SP.RelayPortalMelee(a,d,Vector(0,0,-1),first))
SP.SetFeature(b,'damage',true);SP.SetFeature(a,'damage',false)
assert(not SP.RelayPortalMelee(a,d,Vector(0,0,-1),first))
SP.SetFeature(a,'damage',true)
local cv=CreateConVar('seamless_portals_damage','0')
assert(not SP.RelayPortalMelee(a,d,Vector(0,0,-1),first));cv.value=1
assert(not SP.RelayPortalMelee(a,d,Vector(0,0,1),first))
SP.TraceLine=function(data) return {Hit=true,Entity=WORLD,HitPos=Vector(0,0,20)} end
assert(not SP.RelayPortalMelee(a,d,Vector(0,0,-1),first))
assert(hits==0 and effects==0)
''', modules['traces'] + modules['melee'])
    test('F-T48', 'Remote floor and wall effects explicitly address worldspawn', melee_fixture + r'''
WORLD.valid=false;last.Entity=WORLD;last.HitWorld=true;last.HitBoxBone=7
local effect
function EffectData()
 effect={}
 return setmetatable(effect,{__index=function(_,key)
  return function(self,value) self[key]=value end
 end})
end
assert(SP.RelayPortalMelee(a,d,Vector(0,0,-1),first))
assert(hits==0 and effects==1 and effect.SetEntIndex==0 and effect.SetHitBox==7)
nearvec(effect.SetOrigin,last.HitPos);nearvec(effect.SetNormal,last.HitNormal)
''', modules['traces'] + modules['melee'])
    for realm in ('server', 'client'):
        test('F-T49' if realm == 'server' else 'F-T50',
             'Crowbar animation follows the remote hit in the ' + realm, melee_sound + r'''
local animations=0;weapon.nextattack=123
function weapon:SendWeaponAnim(activity)
 animations=animations+1;assert(activity==ACT_VM_MISSCENTER)
end
local result={Hit=false,Entity=NULL,SeamlessSegments={{Entity=a},{Entity=NULL}}}
SP.TracePortalLine=function() return result end
assert(hook.Run('DoAnimationEvent',p,PLAYERANIMEVENT_ATTACK_PRIMARY)==nil)
assert(animations==1 and weapon.nextattack==123)
result.Hit=true;result.Entity=WORLD;WORLD.valid=false;result.HitWorld=true
hook.Run('DoAnimationEvent',p,PLAYERANIMEVENT_ATTACK_PRIMARY);assert(animations==1)
result.Entity=a
hook.Run('DoAnimationEvent',p,PLAYERANIMEVENT_ATTACK_PRIMARY);assert(animations==2)
SP.RawTraceLine=function() return {Hit=true,Entity=prop()} end
hook.Run('DoAnimationEvent',p,PLAYERANIMEVENT_ATTACK_PRIMARY);assert(animations==2)
''', ('' if realm == 'server' else 'CLIENT=true;SERVER=false\n') + modules['melee'])
    test('F-T51', 'A remote kill retains its hit animation without tracing through the removed target', melee_fixture + r'''
local animations=0
function weapon:SendWeaponAnim() animations=animations+1 end
assert(SP.RelayPortalMelee(a,d,Vector(0,0,-1),first))
target.valid=false
SP.TracePortalLine=function() error('hit result was lost') end
SP.RawTraceLine=function() error('native impact was lost') end
hook.Run('DoAnimationEvent',p,PLAYERANIMEVENT_ATTACK_PRIMARY)
assert(animations==0 and hits==1)
''', modules['traces'] + modules['melee'])
    rpg_fixture = r'''
local SP=SeamlessPortals;local a,b=pair();local p=player();local weapon=prop()
function weapon:GetClass() return 'weapon_rpg' end
function p:GetShootPos() return Vector(0,0,30) end
function p:GetAimVector() return Vector(0,0,-1) end
function p:GetActiveWeapon() return weapon end
function weapon:GetInternalVariable() return nil end
local dot=prop();dot.owner=p;dot.values={m_bIsOn=true,m_hTargetEnt=a,m_vecSurfaceNormal=Vector(0,0,1)}
function dot:GetClass() return 'env_laserdot' end
function dot:GetInternalVariable(k) return self.values[k] end
function dot:SetSaveValue(k,v) self.values[k]=v;return true end
hook.Run('OnEntityCreated',dot)
local missile=prop();missile.owner=p
function missile:GetClass() return 'rpg_missile' end
ents.Create=function(class) assert(class=='info_target', 'guidance must not create a second aim sprite');local e=prop();e.values={};function e:Spawn() end;function e:SetSaveValue(k,v) self.values[k]=v end;return e end
local endpoint=Vector(210,10,20)
SP.TracePortalLine=function() return {SeamlessSegments={{Entity=a},{HitPos=endpoint,StartPos=Vector(200,0,.05)}}} end
hook.Run('SeamlessPortalsProjectileTransferred',missile,a,b)
local record=SP.RPGGuidance[missile]
'''
    test('F-T15', 'RPG uses the real owner laser when the weapon handle is unavailable', rpg_fixture + r'''
assert(SP.UpdateRPGGuidance(missile,record));nearvec(record.target:GetPos(),endpoint)
assert(not IsValid(record.laser) and not dot:GetNoDraw(), "only the client aim renderer draws the guidance point")
assert(dot:GetNWEntity("seamless_portals_rpg_owner")==p)
assert(missile:GetOwner()==p and dot:GetOwner()==record.target)
SP.ClearRPGGuidance(missile);assert(not SP.RPGGuidance[missile])
assert(dot:GetNWEntity("seamless_portals_rpg_owner")==NULL)
assert(dot:GetOwner()==p and not dot:GetNoDraw() and not IsValid(record.target) and not IsValid(record.laser))
''', modules['rpg_guidance'])
    test('F-T17', 'RPG cleanup restores the original laser after its helper is removed first', rpg_fixture + r'''
assert(SP.UpdateRPGGuidance(missile,record))
record.target.valid=false;dot:SetOwner(NULL)
SP.ClearRPGGuidance(missile)
assert(dot:GetOwner()==p and not dot:GetNoDraw() and not SP.RPGGuidance[missile])
''', modules['rpg_guidance'])
    test('F-T16', 'RPG endpoint disable retires the owned guidance target', rpg_fixture + r'''
assert(SP.UpdateRPGGuidance(missile,record))
SP.SetFeature(b,'damage',false)
assert(not SP.UpdateRPGGuidance(missile,record));assert(not SP.RPGGuidance[missile] and not IsValid(record.target))
''', modules['rpg_guidance'])
    collision = src('lua/entities/seamless_portal/sh_init.lua', 'local flashlight_extents', 'SeamlessPortals.Portals =')
    test('F-T18', 'Nearly coplanar long rays skip phantom portal impacts; crossing and hull traces remain', r'''
local p=portal();p.up=Vector(-4e-8,1,0);p.pos=Vector(600,0,0)
''' + collision + r'''
assert(ENT.TestCollision(p,Vector(),Vector(56756,0,0),false,Vector(),MASK_SHOT)==false)
assert(ENT.TestCollision(p,Vector(600,10,0),Vector(0,-30,0),false,Vector(),MASK_SHOT)==true)
assert(ENT.TestCollision(p,Vector(),Vector(56756,0,0),true,Vector(1,1,1),MASK_SHOT)==true)
''')
    test('F-T19', 'Returning shots can hit their owner while preserving unrelated exclusions', r'''
local SP=SeamlessPortals;local a,b=pair();local p=player();local foreign=prop()
local data={Src=Vector(0,0,10),Dir=Vector(0,0,-1),Damage=17,IgnoreEntity=p}
local tr={Hit=true,Entity=a,StartPos=data.Src,HitPos=Vector(),HitNormal=a:GetUp()}
local captured
SP.FirePortalContinuation=function(shooter,bullet) captured=bullet end
local d=DamageInfo();d:SetDamage(17)
SP.PortalBulletCallback(p,data,nil,0)(p,tr,d)
assert(captured and captured.IgnoreEntity==nil and captured.Attacker==p)
assert(data.IgnoreEntity==p)
data.IgnoreEntity=foreign
SP.PortalBulletCallback(p,data,nil,0)(p,tr,d)
assert(captured.IgnoreEntity==foreign)
''', modules['traces'] + modules['bullets'])
    tool_fixture = r'''
local SP=SeamlessPortals;local a,b=pair();local p=player();local weapon=prop()
function weapon:GetClass() return 'gmod_tool' end
weapon.owner=p
function p:GetShootPos() return Vector(0,0,30) end
function p:GetAimVector() return Vector(0,0,-1) end
local emitted={}
function EffectData()
 local e={}
 for _,name in ipairs({'Origin','Start','Entity','Attachment'}) do
  e['Set'..name]=function(self,v) self[name]=v end
  e['Get'..name]=function(self) return self[name] end
 end
 return e
end
util.Effect=function(name,data,flag) emitted[#emitted+1]={name=name,data=data,flag=flag} end
local effect=EffectData();effect:SetEntity(weapon);effect:SetAttachment(1);effect:SetStart(p:GetShootPos());effect:SetOrigin(Vector(200,0,20))
local segments={{StartPos=p:GetShootPos(),HitPos=Vector()},{StartPos=Vector(200,0,.05),HitPos=effect:GetOrigin()}}
SP.TracePortalLine=function() return {HitPos=effect:GetOrigin(),SeamlessSegments=segments} end
'''
    test('F-T20', 'Tool feedback splits at the portal and keeps the muzzle attachment on the first leg', tool_fixture + src('lua/seamless_portals/tool_effects.lua') + r'''
util.Effect('ToolTracer',effect,true)
assert(#emitted==2 and emitted[1].flag==true and emitted[2].flag==true)
nearvec(emitted[1].data:GetOrigin(),Vector())
nearvec(emitted[2].data:GetStart(),Vector(200,0,.05))
assert(emitted[1].data:GetEntity()==weapon and emitted[1].data:GetAttachment()==1)
assert(not IsValid(emitted[2].data:GetEntity()) and emitted[2].data:GetAttachment()==0 and effect:GetEntity()==weapon)
nearvec(effect:GetOrigin(),Vector(200,0,20))
''')
    test('F-T21', 'Tool effect adapter preserves unrelated effects and reload ownership', tool_fixture + src('lua/seamless_portals/tool_effects.lua') + r'''
local owned=util.Effect
''' + src('lua/seamless_portals/tool_effects.lua') + r'''
assert(util.Effect==owned)
util.Effect('Impact',effect,false);assert(#emitted==1 and emitted[1].data==effect)
SP.TracePortalLine=function() return {HitPos=Vector(0,0,50)} end
util.Effect('ToolTracer',effect,true);assert(#emitted==2 and emitted[2].data==effect)
local foreign=function() end;util.Effect=foreign
hook.Run('ShutDown');assert(util.Effect==foreign)
''')
    bolt_fixture = r'''
local SP=SeamlessPortals;local a,b=pair();local p=player();local bolt=prop(Vector(200,0,20))
function bolt:GetClass() return 'crossbow_bolt' end
function bolt:GetInternalVariable(key) assert(key=='m_iDamage');return 100 end
bolt.owner=p;bolt:GetPhysicsObject().vel=Vector(100,0,0)
local hits,sounds=0,0
function bolt:EmitSound() sounds=sounds+1 end
function p:DispatchTraceAttack(d,tr,dir)
 hits=hits+1;assert(d:GetAttacker()==p and d:GetInflictor()==bolt and d:GetDamage()==100)
 assert(tr.Entity==p);nearvec(dir,Vector(1,0,0))
end
local target=p
SP.RawTraceLine=function(d)
 assert(d.SeamlessIgnore and d.filter(p) and not d.filter(bolt))
 return {Hit=true,Entity=target,HitPos=Vector(210,0,20)}
end
DMG_BULLET,DMG_NEVERGIB=2,4096
'''
    test('F-T22', 'Returning crossbow bolt hits its owner once with native damage and attribution', bolt_fixture + r'''
local record={returning=true}
assert(SP.TraceReturningBolt(bolt,record,.015))
assert(hits==1 and sounds==1 and not IsValid(bolt))
assert(not SP.TraceReturningBolt(bolt,record,.015) and hits==1)
''', modules['projectiles'])
    test('F-T23', 'Owner damage requires a transfer and cannot pass another collision', bolt_fixture + r'''
assert(not SP.TraceReturningBolt(bolt,{},.015))
target=WORLD;assert(not SP.TraceReturningBolt(bolt,{returning=true},.015))
assert(hits==0 and sounds==0 and IsValid(bolt) and bolt:GetOwner()==p)
''', modules['projectiles'])
    test('F-T24', 'Physgun skips Sandbox halo collection only while its target is crossing', r'''
CLIENT=true;SERVER=false
function Material() return {} end
local p=player();function LocalPlayer() return p end
local SP=SeamlessPortals;SP.ToggleMirror=function() return false end
''' + src('lua/autorun/client/cl_seamless_mirror_physgun.lua') + r'''
local a,b=pair();local e=prop()
function e:GetNWEntity() return self.clip or NULL end
function e:SetNWEntity(key,value) self.clip=value end
assert(SP.MirrorPhysgunContext(p,NULL,true,e,0,Vector())==nil)
e:SetNWEntity('seamless_portals_clip_entry',a)
assert(SP.MirrorPhysgunContext(p,NULL,true,e,0,Vector())==true)
e:SetNWEntity('seamless_portals_clip_entry',NULL)
assert(SP.MirrorPhysgunContext(p,NULL,true,e,0,Vector())==nil)
''')
    test('F-T25', 'Tracer streaks keep muzzle ownership, speed and portal clipping', r'''
SERVER=false;CLIENT=true
function Material(name) return name end
function Color(r,g,b,a) return {r=r,g=g,b=b,a=a or 255} end
local clock=0
function CurTime() return clock end
local observer=player();function LocalPlayer() return observer end
''' + src('lua/seamless_portals/tracers.lua') + r'''
local SP=SeamlessPortals
local weapon=prop();function weapon:LookupAttachment() return 1 end
function weapon:GetAttachment() return {Pos=Vector(0,2,47)} end
local a={start=Vector(0,0,50),finish=Vector(0,0,0)}
local b={start=Vector(200,0,0),finish=Vector(50000,-50000,30000)}
SP.EmitBulletVisual('Tracer',{a,b},weapon)
local first,last=SP.TracerSegments[1],SP.TracerSegments[2]
assert(#SP.TracerSegments==2 and first.speed==5000 and last.speed==5000)
nearvec(first.start,Vector(0,2,47));nearvec(first.finish,a.finish)
nearvec(last.start,b.start);nearvec(last.finish,b.finish);nearvec(a.start,Vector(0,0,50))
local p,q=SP.SampleBulletTracer(first,0)
nearvec(p,first.start);nearvec(q,first.finish)
assert(SP.SampleBulletTracer(first,0.02)==nil, 'Short entry leg must end at the portal')
local p0,q0=SP.SampleBulletTracer(last,0)
local p1,q1=SP.SampleBulletTracer(last,0.01)
near(p1:Distance(p0),50);near(q1:Distance(q0),50)
near(q0:Distance(p0),96)
assert(SP.SampleBulletTracer(last,last.length/last.speed)==nil)
function weapon:GetAttachment() return {Pos=Vector(9999,9999,9999)} end
nearvec(SP.BulletMuzzlePoint(a.start,weapon),a.start)
weapon.owner=observer
function observer:ShouldDrawLocalPlayer() return false end
nearvec(SP.BulletMuzzlePoint(a.start,weapon),a.start)
''')
    test('F-T26', 'Tool effects detach continuation even when native EffectData storage is reused', tool_fixture + r'''
local shared=effect
function EffectData() return shared end
util.Effect=function(name,data)
 emitted[#emitted+1]={entity=data:GetEntity(),attachment=data:GetAttachment(),start=Vector(data:GetStart()),finish=Vector(data:GetOrigin())}
end
''' + src('lua/seamless_portals/tool_effects.lua') + r'''
util.Effect('ToolTracer',effect,true)
assert(#emitted==2 and emitted[1].entity==weapon and emitted[1].attachment==1)
assert(not IsValid(emitted[2].entity) and emitted[2].attachment==0)
nearvec(emitted[2].start,Vector(200,0,.05));nearvec(emitted[2].finish,Vector(200,0,20))
assert(effect:GetEntity()==weapon and effect:GetAttachment()==1)
nearvec(effect:GetOrigin(),Vector(200,0,20))
''')
    test('F-T27', 'Camera click filters its own near camera and restores trace wrappers on failure', tool_fixture + src('lua/seamless_portals/tool_effects.lua') + r'''
function weapon:GetMode() return 'camera' end
local own=prop(Vector(0,0,30));local far=prop(Vector(200,0,0));local foreign=prop();local other=prop(Vector(0,0,30))
for _,ent in ipairs({own,far,other}) do function ent:GetClass() return 'gmod_cameraprop' end end
function own:GetPlayer() return p end
function far:GetPlayer() return p end
function other:GetPlayer() return foreign end
local output={}
local input={start=p:GetShootPos(),endpos=Vector(0,0,-100),filter={foreign},output=output,mask=123}
local original=input.filter
local result={Hit=true,Entity=a}
local line=function(data)
 assert(data.output==output and data.mask==123 and data.whitelist==false)
 assert(not data.filter(own) and not data.filter(foreign))
 assert(data.filter(other) and data.filter(far) and data.filter(a))
 return result
end
local hull=function() error('unexpected hull') end
util.TraceLine=line;util.TraceHull=hull
local got=SP.CameraToolTrace(weapon,function(self) assert(self==weapon);return util.TraceLine(input) end)
assert(got==result and util.TraceLine==line and util.TraceHull==hull and input.filter==original)
assert(not pcall(SP.CameraToolTrace,weapon,function() error('injected tool trace failure') end))
assert(util.TraceLine==line and util.TraceHull==hull)
''')
    test('F-T28', 'Tool feedback retains the accepted path after a tool removes its target', tool_fixture + src('lua/seamless_portals/tool_effects.lua') + r'''
function weapon:GetMode() return 'remover' end
local trace={HitPos=Vector(200,0,20),SeamlessSegments=segments}
assert(SP.CameraToolTrace(weapon,function() return trace end)==trace)
SP.TracePortalLine=function() error('must not retrace after target removal') end
trace.HitPos:Set(Vector(900,0,0))
util.Effect('ToolTracer',effect,true)
assert(#emitted==2)
nearvec(emitted[2].data:GetOrigin(),Vector(200,0,20))
assert(not IsValid(emitted[2].data:GetEntity()))
''')
    test('F-T29', 'Sandbox world-hit hull retry reaches the far map instead of replacing it with the portal', tool_fixture + r'''
function weapon:GetMode() return 'creator' end
local calls=0
local function raw(data)
 calls=calls+1
 if data.start.x<100 then
  return {Hit=true,HitWorld=false,Entity=a,StartPos=Vector(data.start),HitPos=Vector(),HitNormal=Vector(0,0,1),Fraction=.5}
 end
 return {Hit=true,HitWorld=true,Entity=NULL,StartPos=Vector(data.start),HitPos=Vector(200,0,20),HitNormal=Vector(0,0,-1),Fraction=.5}
end
SP.TraceLine=raw;util.TraceLine=raw;util.TraceHull=raw
''' + src('lua/seamless_portals/traces.lua') + src('lua/seamless_portals/tool_effects.lua') + r'''
local data={start=p:GetShootPos(),endpos=Vector(0,0,-100),mins=Vector(),maxs=Vector(),mask=123,filter={p}}
local function native()
 local trace=util.TraceLine(data)
 if not trace.Hit or not IsValid(trace.Entity) then
  local retry=util.TraceHull(data)
  if IsValid(retry.Entity) then trace=retry end
 end
 return trace
end
local broken=native()
assert(broken.Entity==a and not broken.SeamlessSegments)
local trace=SP.CameraToolTrace(weapon,native)
assert(trace.HitWorld and not IsValid(trace.Entity) and #trace.SeamlessSegments==2)
nearvec(trace.HitPos,Vector(200,0,20))
util.Effect('ToolTracer',effect,true)
assert(#emitted==2);nearvec(emitted[2].data:GetOrigin(),trace.HitPos)
assert(util.TraceHull==raw and util.TraceLine==SP.TraceOwnership.wrapper)
assert(calls<12)
''')
    npc_fixture = r'''
local SP=SeamlessPortals
D_HT,D_FR,D_LI,D_NU=1,2,3,4
NPC_STATE_IDLE,NPC_STATE_COMBAT,NPC_STATE_SCRIPT=1,3,5
SCHED_RANGE_ATTACK1,SOLID_NONE=16,0
COND={NEW_ENEMY=1,SEE_ENEMY=2,ENEMY_OCCLUDED=3}
local a,b=pair()
local target=player();target:SetPos(Vector(200,0,20))
function target:WorldSpaceCenter() return self:GetPos()+Vector(0,0,4) end
player={GetAll=function() return {target} end}
local function native_npc(class)
 local e=prop(Vector(0,0,30))
 e.life=0;e.health=100;e.state=NPC_STATE_IDLE;e.enemy=NULL;e.relations={}
 function e:IsNPC() return true end
 function e:GetClass() return class end
 function e:GetInternalVariable(key)
  if key=='m_lifeState' then return self.life end
  if key=='m_bEnabled' then return self.enabled end
 end
 function e:GetSpawnFlags() return self.flags or 0 end
 function e:Health() return self.health end
 function e:IsScripted() return self.scripted or false end
 function e:GetNPCState() return self.state end
 function e:SetNPCState(v) self.state=v end
 function e:EyePos() return self:GetPos() end
 function e:WorldSpaceCenter() return self:GetPos() end
 function e:IsInViewCone() return not self.outside_cone end
 function e:SetEyeTarget(v) self.eye_target=v end
 function e:Disposition(other) return self.relations[other] or D_HT end
 function e:AddEntityRelationship(other,v) self.relations[other]=v end
 function e:GetActiveWeapon() return self.weapon or NULL end
 function e:GetEnemy() return self.enemy end
 function e:SetEnemy(v) self.enemy=v end
 function e:Visible() return self.visible or false end
 function e:ClearEnemyMemory(v) self.cleared=v end
 function e:UpdateEnemyMemory(v,pos) self.remembered=v;self.remembered_pos=pos end
 function e:SetCondition() end
 function e:ClearCondition() end
 function e:SetIdealYaw() end
 function e:SetSchedule(v) self.schedule=v;self.schedules=(self.schedules or 0)+1 end
 return e
end
local made={}
function ents.Create(class)
 assert(class=='npc_bullseye')
 local proxy=native_npc(class);made[#made+1]=proxy
 function proxy:Spawn() end
 function proxy:SetSolid(v) self.solid=v end
 function proxy:SetSaveValue() end
 function proxy:SetCollisionBounds() end
 return proxy
end
local occluded=false
function SP.PortalSight()
 if not occluded then return {point=Vector(),virtual=Vector(0,0,-20),distance=50} end
end
function SP.UpdateNPCNavigation() return false end
''' + src('lua/seamless_portals/npc_awareness.lua')
    test('F-T30', 'Native NPCs without held weapons acquire a hostile portal target without forced gun schedules', npc_fixture + r'''
for _,class in ipairs({'npc_antlionguard','npc_rollermine','npc_cscanner','npc_clawscanner','npc_turret_floor','npc_turret_ceiling','npc_zombie','npc_manhack'}) do
 local npc=native_npc(class)
 if class=='npc_rollermine' then npc.health=0 end
 SP.UpdateNPCAttention(npc,{target})
 local r=assert(SP.NPCAttention[npc],class)
 assert(npc:GetEnemy()==r.proxy and npc:Disposition(r.proxy)==D_HT and npc.schedule==nil)
 assert(r.proxy.solid==SOLID_NONE)
 SP.ClearNPCAttention(npc)
 assert(not IsValid(r.proxy) and npc:GetEnemy()==NULL and npc.state==NPC_STATE_IDLE)
end
local npc=native_npc('npc_combine_s');npc.weapon=prop()
SP.UpdateNPCAttention(npc,{target});SP.UpdateNPCAttention(npc,{target})
assert(npc.schedules==1 and npc.schedule==SCHED_RANGE_ATTACK1)
''')
    test('F-T31', 'Native life state rejects dying NPCs but admits live zero-health mines', npc_fixture + r'''
local npc=native_npc('npc_rollermine');npc.health=0
SP.UpdateNPCAttention(npc,{target});assert(SP.NPCAttention[npc])
npc.life=1;npc.health=100
SP.UpdateNPCAttention(npc,{target});assert(not SP.NPCAttention[npc])
npc.life=nil
SP.UpdateNPCAttention(npc,{target});assert(SP.NPCAttention[npc])
npc.health=0
SP.UpdateNPCAttention(npc,{target});assert(not SP.NPCAttention[npc])
''')
    test('F-T32', 'Losing portal sight during a native shot retains its enemy until Think retires the proxy', npc_fixture + r'''
local npc=native_npc('npc_turret_floor')
SP.UpdateNPCAttention(npc,{target})
local r=assert(SP.NPCAttention[npc]);local proxy=r.proxy
local bullet={Src=Vector(0,0,25),Dir=Vector(1,0,0)}
SP.AdjustNPCPortalBullet(npc,bullet)
nearvec(bullet.Dir,Vector(0,0,-1))
occluded=true;bullet.Dir=Vector(1,0,0)
SP.AdjustNPCPortalBullet(npc,bullet)
assert(npc:GetEnemy()==proxy and IsValid(proxy) and npc.cleared==nil)
assert(SP.NPCAttention[npc]==r and r.expires==0)
nearvec(bullet.Dir,Vector(1,0,0))
hook.Run('Think')
assert(not SP.NPCAttention[npc] and not IsValid(proxy) and npc:GetEnemy()==NULL)
assert(npc.cleared==proxy)
occluded=false;SP.UpdateNPCAttention(npc,{target})
assert(SP.NPCAttention[npc] and npc:GetEnemy()~=proxy)
''')
    test('F-T33', 'Deferred NPC attention cleanup preserves a replacement native enemy', npc_fixture + r'''
local npc=native_npc('npc_turret_floor')
SP.UpdateNPCAttention(npc,{target})
local proxy=npc:GetEnemy()
occluded=true;SP.AdjustNPCPortalBullet(npc,{Src=Vector(0,0,25),Dir=Vector(0,0,-1)})
local other=prop();npc:SetEnemy(other)
hook.Run('Think')
assert(npc:GetEnemy()==other and not IsValid(proxy) and not SP.NPCAttention[npc])
''')
    test('F-T34', 'NPC portal attention respects disposition, native FOV, scripts and disabled damage', npc_fixture + r'''
local npc=native_npc('npc_turret_floor')
npc:AddEntityRelationship(target,D_NU,99)
SP.UpdateNPCAttention(npc,{target})
assert(SP.NPCAttention[npc] and npc:GetEnemy()==NULL)
assert(npc:Disposition(SP.NPCAttention[npc].proxy)==D_NU and not npc.remembered)
npc:AddEntityRelationship(target,D_HT,99);npc.outside_cone=true
SP.UpdateNPCAttention(npc,{target});assert(not SP.NPCAttention[npc])
npc.outside_cone=false;npc.scripted=true
SP.UpdateNPCAttention(npc,{target});assert(not SP.NPCAttention[npc])
npc.scripted=false;SP.SetFeature(b,'damage',false)
SP.UpdateNPCAttention(npc,{target});assert(not SP.NPCAttention[npc])
SP.SetFeature(b,'damage',true);SP.UpdateNPCAttention(npc,{target});assert(SP.NPCAttention[npc])
CreateConVar('ai_ignoreplayers','1')
SP.UpdateNPCAttention(npc,{target});assert(not SP.NPCAttention[npc])
''')
    test('F-T35', 'Enabled wall cameras retain verified proxy interest and respect ignore-enemies flags', npc_fixture + r'''
local npc=native_npc('npc_combine_camera');npc.enabled=false
SP.UpdateNPCAttention(npc,{target});assert(not SP.NPCAttention[npc])
npc.enabled=true;npc.flags=64
SP.UpdateNPCAttention(npc,{target});assert(not SP.NPCAttention[npc])
npc.flags=0;SP.UpdateNPCAttention(npc,{target})
local proxy=assert(SP.NPCAttention[npc]).proxy
npc:AddEntityRelationship(proxy,D_NU,99)
SP.UpdateNPCAttention(npc,{target});assert(npc:Disposition(proxy)==D_HT)
occluded=true;SP.UpdateNPCAttention(npc,{target})
assert(not SP.NPCAttention[npc] and not IsValid(proxy))
''')
    test('F-T36', 'Rollermine cutout admission retains native physics and refuses rescaling before collision edits',
         src('lua/entities/seamless_portal_cutout.lua', 'local allowed_classes', 'local logic_collision_pair')
         + src('lua/entities/seamless_portal_cutout.lua', 'function ENT:AddEntity', 'function ENT:RemoveEntity') + r'''
local SP=SeamlessPortals
local a,b=pair()
local cutout=prop();cutout.ENTITIES={};cutout.SEAMLESS_PORTALS_READY=true
function cutout:GetPortal() return a end
function cutout:GetRotatedAABB(lo,hi) return lo,hi end
function cutout:NextThink() end
local mine=prop(Vector(0,0,1));local original=mine:GetPhysicsObject()
function mine:GetClass() return 'npc_rollermine' end
original:SetVelocity(Vector(0,0,-10))
function ents.FindInBox() return {mine} end
local collisions=0
function set_collision() collisions=collisions+1;return true end
restore_pending={}
cutout.SEAMLESS_PORTALS_GEOMETRY=SP.CaptureGeometry(a)
cutout:Think()
assert(cutout.ENTITIES[mine] and mine.SEAMLESS_PORTALS_CUTOUT==cutout and collisions==2)
assert(mine:GetPhysicsObject()==original)
local second=prop();function second:GetClass() return 'npc_rollermine' end
b.size=Vector(200,200,8)
assert(not cutout:AddEntity(second) and not second.SEAMLESS_PORTALS_CUTOUT and collisions==2)
local ordinary=prop()
assert(cutout:AddEntity(ordinary) and collisions==4)
''')
    test('F-T37', 'NPC enemies outrank nearby allies and remain visible when players are ignored', npc_fixture + r'''
local npc=native_npc('npc_turret_floor')
local ally=native_npc('npc_combine_s');ally:SetPos(Vector(200,0,15))
local enemy=native_npc('npc_citizen');enemy:SetPos(Vector(200,0,50))
npc:AddEntityRelationship(ally,D_LI,99);npc:AddEntityRelationship(enemy,D_HT,99)
CreateConVar('ai_ignoreplayers','1')
local found=assert(SP.FindNPCTarget(npc,{target,npc,ally,enemy}))
assert(found.target==enemy and found.player==enemy)
SP.UpdateNPCAttention(npc,{target,npc,ally,enemy})
local r=assert(SP.NPCAttention[npc]);assert(r.target==enemy and r.player==enemy)
local bullet={Src=Vector(0,0,25),Dir=Vector(1,0,0)}
SP.AdjustNPCPortalBullet(npc,bullet);nearvec(bullet.Dir,Vector(0,0,-1))
enemy.life=1
hook.Run('Think');assert(not SP.NPCAttention[npc])
''')
    test('F-T38', 'Allied NPC stand-ins remain friendly and relationship changes restore native enemy ownership', npc_fixture + r'''
local npc=native_npc('npc_combine_s');npc.weapon=prop()
local other=native_npc('npc_citizen');other:SetPos(Vector(200,0,20))
npc:AddEntityRelationship(other,D_LI,99)
SP.UpdateNPCAttention(npc,{other})
local friendly=assert(SP.NPCAttention[npc])
assert(friendly.target==other and not friendly.hostile and friendly.player==nil)
assert(npc:Disposition(friendly.proxy)==D_LI and npc:GetEnemy()==NULL)
assert(not npc.remembered and not npc.schedule and npc.state==NPC_STATE_IDLE)
npc:AddEntityRelationship(other,D_HT,99);SP.UpdateNPCAttention(npc,{other})
local hostile=assert(SP.NPCAttention[npc])
assert(hostile.hostile and npc:GetEnemy()==hostile.proxy and not IsValid(friendly.proxy))
npc:AddEntityRelationship(other,D_LI,99);SP.UpdateNPCAttention(npc,{other})
assert(not SP.NPCAttention[npc].hostile and npc:GetEnemy()==NULL and not IsValid(hostile.proxy))
''')
    test('F-T39', 'Awareness scheduler discovers other NPCs without players and excludes itself and proxy targets', npc_fixture + r'''
player.GetAll=function() return {} end
local npc=native_npc('npc_turret_floor')
local other=native_npc('npc_turret_floor');other:SetPos(Vector(200,0,20))
hook.Run('OnEntityCreated',npc);hook.Run('OnEntityCreated',other)
hook.Run('Think')
assert(SP.NPCAttention[npc] and SP.NPCAttention[npc].target==other)
assert(SP.FindNPCTarget(npc,{npc,SP.NPCAttention[npc].proxy})==nil)
''')
    test('F-T40', 'Friendly attention cannot exhaust the proxy budget needed by a hostile NPC', npc_fixture + r'''
local owners={}
for i=1,32 do
 local npc=native_npc('npc_citizen');npc:AddEntityRelationship(target,D_LI,99)
 owners[i]=npc
 SP.UpdateNPCAttention(npc,{target})
 assert(SP.NPCAttention[npc])
end
local npc=native_npc('npc_turret_floor')
SP.UpdateNPCAttention(npc,{target})
assert(SP.NPCAttention[npc] and SP.NPCAttention[npc].hostile)
local count=0;for _ in pairs(SP.NPCAttention) do count=count+1 end
assert(count==32 and #owners==32)
''')
    test('F-T41', 'NPC target batches rotate beyond the first 64 registered actors', npc_fixture + r'''
player.GetAll=function() return {} end
local last
for i=1,80 do
 last=native_npc('npc_citizen');last:SetPos(Vector(200,0,20))
 hook.Run('OnEntityCreated',last)
end
local calls,saw_last=0,false
SP.UpdateNPCAttention=function(_,actors)
 calls=calls+1;assert(#actors<=64)
 for _,ent in ipairs(actors) do if ent==last then saw_last=true end end
end
hook.Run('Think');assert(calls==8 and not saw_last)
NOW=NOW+.2;hook.Run('Think');assert(calls==16 and saw_last)
''')
    grenade_fixture = r'''
local SP=SeamlessPortals;local a,b=pair()
local e=prop(Vector(0,0,25));local phys=e:GetPhysicsObject()
function e:GetClass() return 'npc_grenade_frag' end
function e:GetInternalVariable(key) return self.internal and self.internal[key] end
phys.vel=Vector(100,0,-1000)
local initial=e:GetPos();local velocity=Vector(phys.vel)
SP.RawTraceLine=function() return {Hit=false,StartSolid=false,AllSolid=false,Fraction=1} end
'''
    test('F-T42', 'Fast frag transfers before its post-physics forward ray can bounce off the portal', grenade_fixture + r'''
local owner=player();e.owner=owner
local calls=0
hook.Add('SeamlessPortalsProjectileTransferred','grenade_test',function(ent,entry,exit)
 calls=calls+1;assert(ent==e and entry==a and exit==b)
end)
-- At 15 ms, physics stops in front, but the subsequent native ray crosses.
assert(not SP.ProjectileCrossing(e,velocity*.015))
assert(SP.PlaneCrossing(a,initial+velocity*.015,velocity*.015))
assert(SP.TransferProjectile(e,.015))
assert(e:GetPhysicsObject()==phys and e:GetOwner()==owner and calls==1)
nearvec(phys.vel,SP.TransformDirection(a,b,velocity,false))
assert(not SP.TransferProjectile(e,.015) and calls==1)
''', modules['projectiles'])
    test('F-T43', 'Frag lookahead retains source occlusion across the extra predicted step', grenade_fixture + r'''
local wall=Vector(0,0,5)
SP.RawTraceLine=function(data)
 assert(data.SeamlessIgnore and data.start.z>wall.z and data.endpos.z<wall.z)
 return {Hit=true,HitPos=wall,Fraction=.8}
end
assert(not SP.TransferProjectile(e,.015))
assert(SP.FieldCounters.projectile_source_blocked==1)
nearvec(e:GetPos(),initial);nearvec(phys.vel,velocity)
''', modules['projectiles'])
    test('F-T44', 'Frag lookahead refuses blocked exits without moving or consuming the grenade', grenade_fixture + r'''
util.TraceHull=function() return {StartSolid=true,Hit=true} end
assert(not SP.TransferProjectile(e,.015))
assert(SP.FieldCounters.projectile_exit_blocked==1 and IsValid(e))
nearvec(e:GetPos(),initial);nearvec(phys:GetPos(),initial);nearvec(phys.vel,velocity)
''', modules['projectiles'])
    test('F-T45', 'Frag prediction respects aperture edges, approach direction and endpoint switches', grenade_fixture + r'''
e:SetPos(Vector(1000,0,25));assert(not SP.TransferProjectile(e,.015))
e:SetPos(Vector(0,0,-5));assert(not SP.TransferProjectile(e,.015))
e:SetPos(initial);phys.vel=-velocity;assert(not SP.TransferProjectile(e,.015));phys.vel=velocity
for _,endpoint in ipairs({a,b}) do
 SP.SetFeature(endpoint,'damage',false);assert(not SP.TransferProjectile(e,.015))
 SP.SetFeature(endpoint,'damage',true)
end
GetConVar('seamless_portals_projectiles'):SetInt(0);assert(not SP.TransferProjectile(e,.015))
GetConVar('seamless_portals_projectiles'):SetInt(1);assert(SP.TransferProjectile(e,.015))
''', modules['projectiles'])
    test('F-T46', 'Additional prediction is bounded and confined to native frag grenades', grenade_fixture + r'''
for _,class in ipairs({'prop_combine_ball','rpg_missile','crossbow_bolt','grenade_ar2','grenade_helicopter'}) do
 function e:GetClass() return class end
 assert(not SP.TransferProjectile(e,.015),class)
end
function e:GetClass() return 'npc_grenade_frag' end
e:SetPos(Vector(0,0,120));assert(not SP.TransferProjectile(e,100))
e:SetPos(initial);assert(not SP.TransferProjectile(e,0))
assert(SP.TransferProjectile(e,.015))
''', modules['projectiles'])
    trail_fixture = grenade_fixture + r'''
local made,owned={},{}
local function sprite()
 local s=prop();s.parent=e;s.values={lifetime=.5,startwidth=8,endwidth=1,m_nAttachment=1,
  m_flTextureRes=0,m_nBrightness=255,m_flStartWidthVariance=0,m_flMinFadeLength=0,HDRColorScale=1}
 function s:GetClass() return 'env_spritetrail' end
 function s:GetParent() return self.parent end
 function s:GetInternalVariable(k) return self.values[k] end
 function s:SetSaveValue(k,v) self.values[k]=v;return true end
 function s:GetColor() return {r=255,g=0,b=0,a=255} end
 function s:GetModel() return 'sprites/bluelaser1.vmt' end
 function s:GetRenderMode() return 5 end
 function s:GetRenderFX() return 0 end
 function s:SetRenderMode(v) assert(v==5) end
 function s:SetRenderFX(v) assert(v==0) end
 return s
end
local native=sprite();local glow=prop()
e.internal={m_pGlowTrail=native,m_pMainGlow=glow,m_flDetonateTime=42}
function e:SetSaveValue() error('native sprite handles cannot be assigned in GLua') end
function e:DeleteOnRemove(child) owned[child]=true end
util.SpriteTrail=function(parent,attachment,color,additive,startwidth,endwidth,lifetime,res,model)
 assert(parent==e and attachment==1 and color.r==255 and color.g==0 and additive)
 assert(startwidth==8 and endwidth==1 and lifetime==.5 and res==0 and model==native:GetModel())
 nearvec(e:GetPos(),initial) -- Reset history before moving to the exit.
 local s=sprite();made[#made+1]=s;return s
end
'''
    test('F-T47', 'Frag crossing starts a fresh visible trail while retaining native glow and fuse ownership', trail_fixture + r'''
assert(SP.TransferProjectile(e,.015))
local trail=assert(e.SEAMLESS_PORTALS_GRENADE_TRAIL)
assert(#made==1 and trail~=native and not trail:GetNoDraw() and native:GetNoDraw())
assert(trail:GetParent()==e and owned[trail] and trail.values.m_nBrightness==255)
assert(e.internal.m_pGlowTrail==native and e.internal.m_pMainGlow==glow and e.internal.m_flDetonateTime==42)
assert(IsValid(native) and IsValid(glow) and e:GetPhysicsObject()==phys)
''', modules['projectiles'])
    test('F-T48', 'Repeated frag crossings retire the previous replacement instead of accumulating trails', trail_fixture + r'''
for i=1,3 do
 TICK=TICK+1;e:SetPos(initial);phys.vel=Vector(velocity)
 assert(SP.TransferProjectile(e,.015))
 assert(#made==i and e.SEAMLESS_PORTALS_GRENADE_TRAIL==made[i])
 for j=1,i-1 do assert(not IsValid(made[j])) end
 assert(IsValid(native) and native:GetNoDraw() and owned[made[i]])
end
''', modules['projectiles'])
    test('F-T49', 'Rejected crossings and failed trail allocation preserve the existing fuse visuals', trail_fixture + r'''
util.TraceHull=function() return {Hit=true} end
assert(not SP.TransferProjectile(e,.015) and #made==0 and not native:GetNoDraw())
util.TraceHull=function() return {Hit=false} end
util.SpriteTrail=function() return NULL end
assert(SP.TransferProjectile(e,.015) and not native:GetNoDraw())
assert(e.SEAMLESS_PORTALS_GRENADE_TRAIL==nil and IsValid(native) and IsValid(glow))
''', modules['projectiles'])
    test('F-T50', 'Missing or unrelated frag trail handles do not touch other effects', trail_fixture + r'''
native.parent=glow
assert(SP.TransferProjectile(e,.015) and #made==0 and not native:GetNoDraw())
TICK=TICK+1;e:SetPos(initial);phys.vel=Vector(velocity);native:Remove()
assert(SP.TransferProjectile(e,.015) and #made==0 and IsValid(glow))
''', modules['projectiles'])
    report = dict(native_gmod_tested=False, tests=results,
                  passed=sum(r['status'] == 'PASS' for r in results),
                  failed=sum(r['status'] == 'FAIL' for r in results))
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(json.dumps(report, indent=2) + '\n')
    for row in results:
        print(row['status'], row['id'], row['title'])
        if row['status'] == 'FAIL':
            print(row['observed'])
    return int(bool(report['failed']))


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('source', type=Path)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    raise SystemExit(main(args.source, args.output))
