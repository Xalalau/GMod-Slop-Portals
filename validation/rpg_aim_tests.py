#!/usr/bin/env python3
"""RPG aim rendering and flight-sound contracts; API doubles are not native acceptance."""
import argparse
import json
from pathlib import Path
from lua_support import Lua, normalize


def main(root, output):
    here = Path(__file__).resolve().parent
    base = (here / 'stubs.lua').read_text() + (here / 'custom_stubs.lua').read_text()
    base += r'''
SERVER,CLIENT=false,true
local SP=SeamlessPortals or {};SeamlessPortals=SP
MASK_SHOT,CONTENTS_WINDOW=117,2
bit.bnot=function(n) return ~n end
local owner=player();local weapon=prop();local dot=prop()
function owner:IsDormant() return self.dormant or false end
function owner:GetShootPos() return Vector(10,20,30) end
function owner:GetAimVector() return Vector(1,0,0) end
function owner:GetActiveWeapon() return weapon end
function weapon:GetClass() return self.class or 'weapon_rpg' end
function dot:GetClass() return self.class or '10C_LaserDot' end
function dot:GetOwner() return self.nativeOwner or owner end
function dot:GetNWEntity() return self.guidanceOwner or NULL end
function dot:GetNoDraw() return self.hidden or false end
function dot:SetNoDraw(hidden) self.hidden=hidden end
function dot:IsDormant() return self.dormant or false end
local native,custom,traces=0,0,0
function dot:DrawModel() native=native+1 end
ents={FindByClass=function(class) return class==dot:GetClass() and {dot} or {} end}
local drawPos
render={SetMaterial=function() end,DrawSprite=function(pos) custom=custom+1;drawPos=pos end}
Material=function() return {} end
Color=function(r,g,b,a) return {r=r,g=g,b=b,a=a or 255} end
local active=true
function SP.HasTraversablePortals() return active end
local last={Hit=true,HitPos=Vector(1000,200,30),HitNormal=Vector(-1,0,0)}
local segments={{HitPos=Vector(100,20,30)},last}
function SP.TracePortalLine(data)
 traces=traces+1
 nearvec(data.start,owner:GetShootPos());nearvec(data.endpos,owner:GetShootPos()+owner:GetAimVector()*56756)
 assert(data.SeamlessFeature=='damage' and data.filter[1]==owner and data.filter[2]==weapon)
 return {SeamlessSegments=segments}
end
local function frame()
 hook.Run('PreRender');if not dot:GetNoDraw() then dot:DrawModel(0) end
 hook.Run('PostDrawTranslucentRenderables',false,false);hook.Run('PostRender')
 assert(not dot:GetNoDraw())
end
'''
    module = normalize((root / 'lua/autorun/client/cl_seamless_rpg.lua').read_text())
    cases = [
        ('R-T01', 'Portal aim replaces the native dot at the remote surface', '''
frame();assert(native==0 and custom==1 and traces==1);nearvec(drawPos,Vector(996,200,30))
hook.Run('PostDrawTranslucentRenderables',false,false);assert(traces==1)
hook.Run('PostDrawTranslucentRenderables',true,false);assert(custom==2)
hook.Run('PostDrawTranslucentRenderables',false,true);assert(custom==2)
'''),
        ('R-T02', 'Leaving a portal, switching weapon or disabling continuation restores native drawing', '''
frame();segments=nil;frame();assert(native==1 and custom==1)
segments={{},last};weapon.class='weapon_physgun';frame();assert(native==2 and custom==1)
weapon.class=nil;CreateConVar('seamless_portals_projectiles','0');frame();assert(native==3 and custom==1)
GetConVar('seamless_portals_projectiles'):SetInt(1)
CreateConVar('seamless_portals_damage','0');frame();assert(native==4 and custom==1)
GetConVar('seamless_portals_damage'):SetInt(1);active=false;frame();assert(native==5 and custom==1)
'''),
        ('R-T03', 'Sky and no-hit paths suppress the entry dot without inventing a remote surface', '''
last.HitSky=true;frame();assert(native==0 and custom==0)
last.HitSky=false;last.Hit=false;frame();assert(native==0 and custom==0)
last.Hit=true;last.StartSolid=true;frame();assert(native==1 and custom==0)
'''),
        ('R-T04', 'Hidden guidance dots and dormant owners do not acquire a second sprite', '''
dot.hidden=true;hook.Run('PreRender');hook.Run('PostDrawTranslucentRenderables',false,false)
assert(custom==0 and traces==0)
dot.hidden=false;owner.dormant=true;frame();assert(custom==0 and traces==0)
'''),
        ('R-T05', 'Cleanup restores temporary visibility without touching render overrides', """
local newer=function() end;dot.RenderOverride=newer
hook.Run('PreRender');assert(dot:GetNoDraw())
SP.CleanupRPGAimRendering();assert(not dot:GetNoDraw() and dot.RenderOverride==newer)
dot.hidden=true;hook.Run('PreRender');SP.CleanupRPGAimRendering();assert(dot:GetNoDraw())
"""),
        ('R-T06', 'Map cleanup allows subsequently networked dots to be adapted', """
frame();hook.Run('PostCleanupMap');assert(not dot:GetNoDraw())
hook.Run('NetworkEntityCreated',dot);frame();assert(native==0 and custom==2)
SP.CleanupRPGAimRendering();assert(not dot:GetNoDraw())
"""),
        ('R-T08', 'Both map and native C++ laser classes are recognized', """
for _,class in ipairs({'env_laserdot','10C_LaserDot','C_LaserDot','class C_LaserDot'}) do
 SP.CleanupRPGAimRendering();dot.class=class
 hook.Run('NetworkEntityCreated',dot);assert(SP.RPGAimRendering.lasers[dot])
end
"""),
        ('R-T07', 'Native laser registration and shared owner traces are bounded', '''
for i=1,100 do
 local e=prop();e.GetClass=dot.GetClass;e.GetOwner=dot.GetOwner;e.GetNWEntity=dot.GetNWEntity;e.GetNoDraw=dot.GetNoDraw;e.SetNoDraw=dot.SetNoDraw;e.IsDormant=dot.IsDormant;e.DrawModel=dot.DrawModel
 hook.Run('NetworkEntityCreated',e)
end
assert(SP.RPGAimRendering.count==64)
hook.Run('PreRender');assert(traces==1)
'''),
        ('R-T09', 'Guidance owner handoff hides the entry without duplicating the remote sprite', """
frame();dot.nativeOwner=prop()
hook.Run('PreRender');assert(dot:GetNoDraw() and SP.RPGAimRendering.paths[dot])
hook.Run('PostDrawTranslucentRenderables',false,false);assert(custom==2)
hook.Run('PostRender');assert(not dot:GetNoDraw())
dot.nativeOwner=owner;frame();assert(custom==3 and native==0)
"""),
        ('R-T10', 'New native dots are registered after construction; stale callbacks retire on cleanup', """
SP.CleanupRPGAimRendering();local callbacks={}
timer.Simple=function(_,fn) callbacks[#callbacks+1]=fn end
dot.class='C_BaseEntity';hook.Run('OnEntityCreated',dot)
dot.class='10C_LaserDot';callbacks[1]();assert(SP.RPGAimRendering.lasers[dot])
SP.CleanupRPGAimRendering();hook.Run('OnEntityCreated',dot)
SP.CleanupRPGAimRendering();callbacks[2]();assert(not SP.RPGAimRendering.lasers[dot])
"""),
        ('R-T11', 'PostRender restores visibility even after a failed sprite draw', """
hook.Run('PreRender');assert(dot:GetNoDraw())
render.DrawSprite=function() error('injected draw failure') end
assert(not pcall(hook.Run,'PostDrawTranslucentRenderables',false,false))
hook.Run('PostRender');assert(not dot:GetNoDraw())
"""),
        ('R-T12', 'A newly observed guidance dot keeps one aim point without any helper sprite', """
SP.CleanupRPGAimRendering();dot.nativeOwner=prop();dot.guidanceOwner=owner
hook.Run('NetworkEntityCreated',dot)
hook.Run('PreRender');assert(dot:GetNoDraw())
hook.Run('PostDrawTranslucentRenderables',false,false);assert(custom==1 and traces==1)
hook.Run('PostRender');assert(not dot:GetNoDraw())
local sprite=prop();sprite.GetClass=function() return 'env_sprite' end
hook.Run('EntityNetworkedVarChanged',sprite,'seamless_portals_rpg_owner',NULL,owner)
assert(not SP.RPGAimRendering.lasers[sprite])
dot.guidanceOwner=nil;dot.nativeOwner=owner;frame();assert(custom==2 and native==0)
"""),
    ]
    def chunk(path):
        return 'do\nlocal function module()\n' + normalize((root / path).read_text()) + '\nend\nmodule()\nend\n'

    sound_module = chunk('lua/seamless_portals/sound.lua')
    sound_base = (here / 'stubs.lua').read_text() + (here / 'custom_stubs.lua').read_text()
    sound_base += chunk('lua/seamless_portals/core.lua') + chunk('lua/seamless_portals/features.lua')
    sound_base += chunk('lua/seamless_portals/aperture.lua')
    sound_base += r'''
local SP=SeamlessPortals
local a,b=pair();local path={entry=a,exit=b,pos=Vector(200,0,4)}
net.Broadcast=function() net.Send('all') end
'''
    sound_fixture = r'''
SP.SoundPaths=function() return {path} end
local missile=prop(Vector(0,0,10))
function missile:GetClass() return 'rpg_missile' end
local event={Entity=missile,SoundName='weapons/rpg/rocket1.wav',Pos=missile:GetPos(),Channel=1,SeamlessRealm='server'}
'''
    server_cases = [
        ('R-S01', 'Missile removal stops relayed flight audio even after unlinking or disabling sound', """
hook.Run('EntityEmitSound',event);assert(#net.messages==1)
assert(SP.RPGSoundSources[missile]==missile:EntIndex())
a.exit=NULL;GetConVar('seamless_portals_soundrelay_server'):SetInt(0)
missile.valid=false;hook.Run('EntityRemoved',missile)
assert(#net.messages==2 and net.messages[2].name=='SEAMLESS_PORTALS_RPG_SOUND_STOP')
assert(net.messages[2].values[1]==missile:EntIndex() and net.messages[2].filter=='all')
hook.Run('EntityRemoved',missile);assert(#net.messages==2 and not next(SP.RPGSoundSources))
"""),
        ('R-S02', 'Flight-sound source tracking is bounded and map cleanup retires it', """
for i=1,65 do
 local e=prop();e.GetClass=missile.GetClass;event.Entity=e;TICK=TICK+1
 hook.Run('EntityEmitSound',event)
end
local count=0;for _ in pairs(SP.RPGSoundSources) do count=count+1 end
assert(count==64 and #net.messages==64)
hook.Run('PostCleanupMap');assert(not next(SP.RPGSoundSources) and #net.messages==128)
"""),
        ('R-S03', 'Hotload preserves ownership of flight audio already relayed', """
hook.Run('EntityEmitSound',event)
""" + sound_module + """
hook.Run('EntityRemoved',missile);assert(#net.messages==2 and not next(SP.RPGSoundSources))
"""),
        ('R-S04', 'Unrelated emitters do not acquire a missile lifetime', """
event.Entity=prop();hook.Run('EntityEmitSound',event)
assert(#net.messages==1 and not next(SP.RPGSoundSources))
event.Entity=missile;event.SoundName='ambient/explosions/explode_1.wav'
hook.Run('EntityEmitSound',event);hook.Run('EntityRemoved',missile)
assert(#net.messages==2 and not next(SP.RPGSoundSources))
"""),
    ]
    client_cases = [
        ('R-S05', 'Stopping one missile preserves other missiles and explosion tails', """
SP.PlayPortalSound(path,42,event);local first=CLIENT_EMITTERS[1]
SP.PlayPortalSound(path,43,event);local second=CLIENT_EMITTERS[2]
event.Channel=2;event.SoundName='ambient/explosions/explode_1.wav'
SP.PlayPortalSound(path,42,event);local explosion=CLIENT_EMITTERS[3]
SP.StopPortalRPGSound(42)
assert(first.stopped and not IsValid(first) and IsValid(second) and IsValid(explosion))
SP.StopPortalRPGSound(42);assert(IsValid(second) and IsValid(explosion))
"""),
        ('R-S06', 'A stop reaches every portal copy without resolving the original entity', """
SP.PlayPortalSound(path,42,event)
local c,d=pair();SP.PlayPortalSound({entry=c,exit=d,pos=path.pos},42,event)
assert(#CLIENT_EMITTERS==2)
Entity=function() error('source outside PVS must not be resolved') end
net.ReadUInt=function(bits) assert(bits==16);return 42 end
GetConVar('seamless_portals_soundrelay'):SetInt(0)
net.receivers.SEAMLESS_PORTALS_RPG_SOUND_STOP()
assert(not next(SP.SoundEmitters) and CLIENT_EMITTERS[1].stopped and CLIENT_EMITTERS[2].stopped)
"""),
        ('R-S07', 'A subsequent missile can reuse the index after its predecessor stops', """
for _,name in ipairs({'Missile.Ignite','Missile.Accelerate','weapons/rpg/rocket1.wav'}) do
 event.SoundName=name;SP.PlayPortalSound(path,42,event)
 local e=CLIENT_EMITTERS[#CLIENT_EMITTERS];assert(IsValid(e))
 SP.StopPortalRPGSound(42);assert(not IsValid(e) and not next(SP.SoundEmitters))
end
"""),
    ]
    results = []
    lua = Lua()
    batches = [(base + module, cases),
               (sound_base + 'SERVER=true;CLIENT=false;\n' + sound_module + sound_fixture, server_cases),
               (sound_base + 'SERVER=false;CLIENT=true;\n' + sound_module + sound_fixture, client_cases)]
    for prefix, batch in batches:
        for name, title, code in batch:
            try:
                assert lua.check(prefix + code + '\nreturn "passed"', True, name) == 'passed'
                status, observed = 'PASS', 'assertions passed'
            except Exception as exc:
                status, observed = 'FAIL', str(exc)
            results.append(dict(id=name, title=title, status=status, observed=observed))
            print(status, name, observed)
    report = dict(native_gmod_tested=False, tests=results,
                  passed=sum(x['status'] == 'PASS' for x in results),
                  failed=sum(x['status'] == 'FAIL' for x in results))
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(json.dumps(report, indent=2) + '\n')
    return bool(report['failed'])


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('source', type=Path)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    raise SystemExit(main(args.source.resolve(), args.output.resolve()))
