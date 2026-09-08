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
ents.Create=function(class) assert(class=='info_target' or class=='env_sprite');local e=prop();e.values={};function e:Spawn() end;function e:SetSaveValue(k,v) self.values[k]=v end;return e end
local endpoint=Vector(210,10,20)
SP.TracePortalLine=function() return {SeamlessSegments={{Entity=a},{HitPos=endpoint,StartPos=Vector(200,0,.05)}}} end
hook.Run('SeamlessPortalsProjectileTransferred',missile,a,b)
local record=SP.RPGGuidance[missile]
'''
    test('F-T15', 'RPG uses the real owner laser when the weapon handle is unavailable', rpg_fixture + r'''
assert(SP.UpdateRPGGuidance(missile,record));nearvec(record.laser:GetPos(),endpoint)
assert(missile:GetOwner()==p and dot:GetOwner()==record.target)
SP.ClearRPGGuidance(missile);assert(not SP.RPGGuidance[missile])
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
assert(emitted[2].data:GetEntity()==nil and effect:GetEntity()==weapon)
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
