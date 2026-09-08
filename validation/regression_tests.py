#!/usr/bin/env python3
"""Isolated candidate-source regression tests. Not native GLua or Garry's Mod integration."""
from pathlib import Path
import argparse
import hashlib
import importlib.util
import json
import subprocess
import sys
import tempfile
from lua_support import Lua, normalize


def main(root: Path, output: Path):
    root = root.resolve()
    lua = Lua()
    prelude = (Path(__file__).parent / 'stubs.lua').read_text()
    results = []
    def src(path, first=None, stop=None):
        text = (root / path).read_text()
        if first:
            text = text[text.index(first):]
        if stop:
            text = text[:text.index(stop)]
        return normalize(text) + '\n'
    core = src('lua/seamless_portals/core.lua') + src('lua/seamless_portals/features.lua') + src('lua/seamless_portals/aperture.lua') + src('lua/seamless_portals/tool_features.lua')
    def test(id, title, ids, code):
        try:
            observed = lua.check(prelude + core + code + '\nreturn "assertions passed"', True, id)
            assert observed == 'assertions passed', 'Assertions bypassed by early chunk return'
            status = 'PASS'
        except Exception as exc:
            observed, status = str(exc), 'FAIL'
        results.append(dict(id=id, title=title, proposals=ids, status=status, observed=observed, kind='candidate source + explicit Lua test doubles'))
    test('P01','Finite numbers reject NaN/infinity/non-numbers',['B01'],'''assert(SeamlessPortals.IsFinite(0)); for _,v in ipairs({math.huge,-math.huge,0/0,'4',false}) do assert(not SeamlessPortals.IsFinite(v)) end''')
    test('P02','Side counts enforce integral closed bounds',['B01'],'''for i=3,100 do assert(SeamlessPortals.ValidateSides(i)) end; for _,n in ipairs({-1,0,1,2,2.99,3.5,101,100000,math.huge}) do assert(not SeamlessPortals.ValidateSides(n)) end''')
    test('P03','Dimensions enforce all axes and type',['B01'],'''assert(SeamlessPortals.ValidateSize(Vector(1,1000,8))); assert(not SeamlessPortals.ValidateSize({100,100,8})); for axis=1,3 do for _,v in ipairs({0,-1,1001,math.huge,0/0}) do local s=Vector(100,100,8); s[axis]=v; assert(not SeamlessPortals.ValidateSize(s)) end end''')
    test('P04','Geometry identity includes either endpoint pose/shape/link',['B03'],'''local a,b,c=portal(),portal(),portal();a.exit=b; local first=SeamlessPortals.CaptureGeometry(a);assert(SeamlessPortals.SameGeometry(first,SeamlessPortals.CaptureGeometry(a)));b.angle[2]=90;assert(not SeamlessPortals.SameGeometry(first,SeamlessPortals.CaptureGeometry(a)));b.angle[2]=0;b.size[1]=200;assert(not SeamlessPortals.SameGeometry(first,SeamlessPortals.CaptureGeometry(a)));b.size[1]=100;a.exit=c;assert(not SeamlessPortals.SameGeometry(first,SeamlessPortals.CaptureGeometry(a)))''')
    test('P05','Polygon prop support and aperture bounds (C02 supersedes containment)',['B08'],'''local a,b=portal(),portal(); assert(SeamlessPortals.SupportsPropTraversal(a,b));assert(not SeamlessPortals.SupportsPropTraversal(a,a));b.sides=50; assert(SeamlessPortals.SupportsPropTraversal(a,b));local lo,hi=SeamlessPortals.GetApertureBounds(Vector(100,50,8),4);nearvec(lo,Vector(-50,-25,-8));nearvec(hi,Vector(50,25,0));assert(SeamlessPortals.GetApertureBounds(Vector(),4)==nil)''')
    test('P06','Callback trace filter preserved except exit',['B11'],'''local a,b=portal(),portal();local calls=0;local f=SeamlessPortals.ComposeTraceFilter(function(e) calls=calls+1;return e==a end,false,b);assert(f(a) and not f(b));assert(calls==1)''')
    test('P07','Entity, class and array blacklist filters preserved',['B11'],'''local a,b,c=portal(),portal(),portal();function c:GetClass() return 'prop_physics' end;assert(not SeamlessPortals.ComposeTraceFilter(a,false,b)(a));assert(SeamlessPortals.ComposeTraceFilter(a,false,b)(c));assert(not SeamlessPortals.ComposeTraceFilter('prop_physics',false,b)(c));local original={a,'prop_physics'};local f=SeamlessPortals.ComposeTraceFilter(original,false,b);assert(not f(a) and not f(b) and not f(c));assert(#original==2)''')
    test('P08','Whitelist excludes exit and retains allowed entities',['B11'],'''local a,b,c=portal(),portal(),portal();local f=SeamlessPortals.ComposeTraceFilter({a,b},true,b);assert(f(a) and not f(b) and not f(c));assert(SeamlessPortals.ComposeTraceFilter(nil,false,b)(c))''')
    test('P09','Aspect contract rejects incompatible links',['R08'],'''assert(SeamlessPortals.AspectCompatibleSize(Vector(100,50,8),Vector(200,100,16)));assert(not SeamlessPortals.AspectCompatibleSize(Vector(100,50,8),Vector(100,100,8)));assert(not SeamlessPortals.IsUsableLink(portal(),NULL))''')
    test('P10','Pair configuration rejects nil/non-tables without calls',['O03'],'''local a,b=portal(),portal();a.exit=b;b.exit=a;function a:Configure() error('unexpected mutation') end; b.Configure=a.Configure; assert(not SeamlessPortals.ConfigurePair(a,nil,b,nil)); assert(not SeamlessPortals.ConfigurePair(a,{},b,nil));assert(not SeamlessPortals.ConfigurePair(a,false,b,{}))''')
    config_setup='''local a,b=portal(),portal();a.exit=b;b.exit=a;for _,e in ipairs({a,b}) do function e:GetDisableBackface() return self.backface or false end; function e:Configure(size,sides,backface) self.size=Vector(size);self.sides=sides;self.backface=backface;return true end end;local ca={size=Vector(100,50,8),sides=4,disable_backface=true};local cb={size=Vector(200,100,8),sides=6,disable_backface=false};'''
    test('P11','Pair configuration commits matching aspect batch',['O03'],config_setup+'''assert(SeamlessPortals.ConfigurePair(a,ca,b,cb));nearvec(a.size,ca.size);nearvec(b.size,cb.size);assert(not a.SEAMLESS_PORTALS_CONFIGURING_PAIR and not b.SEAMLESS_PORTALS_CONFIGURING_PAIR)''')
    test('P12','Pair failure attempts rollback and clears transaction flags',['O03'],config_setup+'''local original=b.Configure;function b:Configure(size,sides,backface) if sides==6 then error('injected') end;return original(self,size,sides,backface) end;assert(not SeamlessPortals.ConfigurePair(a,ca,b,cb));nearvec(a.size,Vector(100,100,8));nearvec(b.size,Vector(100,100,8));assert(a.SEAMLESS_PORTALS_CONFIGURING_PAIR==nil and b.SEAMLESS_PORTALS_CONFIGURING_PAIR==nil);assert(LAST_ERROR)''')
    test('P13','Direction basis matches independent rotated reference; round trips',['O06','R08'],'''math.randomseed(41); for i=1,250 do local a,b=portal(),portal(Vector(200,200,8));for _,e in ipairs({a,b}) do local yaw=math.random()*math.pi*2;local tilt=math.random()*1.2;e.forward=Vector(math.cos(yaw)*math.cos(tilt),math.sin(yaw)*math.cos(tilt),math.sin(tilt));e.up=Vector(-math.cos(yaw)*math.sin(tilt),-math.sin(yaw)*math.sin(tilt),math.cos(tilt));e.right= -e.up:Cross(e.forward) end;local d=Vector(math.random()*10,math.random()*10,math.random()*10);local localx=d:Dot(a.forward);local localy=d:Dot(-a.right);local localz=d:Dot(a.up);local expected=b.forward*(localx*2)+(-b.right)*(-localy*2)+b.up*(-localz*2);local actual=SeamlessPortals.TransformDirection(a,b,d,true);nearvec(actual,expected);nearvec(SeamlessPortals.TransformDirection(b,a,actual,true),d);near(SeamlessPortals.TransformDirection(a,b,d,false):Length(),d:Length()) end''')
    test('P14','Mirror direction reflects only normal component',['O06'],'''local a=portal();local d=Vector(2,3,4);nearvec(SeamlessPortals.TransformDirection(a,a,d,true),Vector(2,3,-4));assert(SeamlessPortals.TransformDirection(a,NULL,d)==nil)''')
    test('P15','Linked count invalidates when links change',['O10'],'''local a,b=portal(),portal();SeamlessPortals.Portals={a,b};assert(not SeamlessPortals.HasTraversablePortals());a:SetExitPortal(b);assert(SeamlessPortals.HasTraversablePortals());a:SetExitPortal(NULL);assert(not SeamlessPortals.HasTraversablePortals())''')
    sv='lua/entities/seamless_portal/init.lua'
    link=src(sv,'local function set_dupe_link','function ENT:SetRemoveExit')
    test('P16','Relinking two pairs removes stale reciprocal links',['B06'],link+'''local a,b,c,d=portal(),portal(),portal(),portal();assert(a:LinkPortal(b));assert(c:LinkPortal(d));assert(a:LinkPortal(c));assert(a.exit==c and c.exit==a and not IsValid(b.exit) and not IsValid(d.exit));assert(b.dupe.exit_id==-1 and d.dupe.exit_id==-1)''')
    test('P17','Unlink stale inbound partner does not destroy unrelated pair',['B06','B07'],link+'''local a,b,c=portal(),portal(),portal();a:LinkPortal(c);b.exit=a;b:UnlinkPortal();assert(a.exit==c and c.exit==a and not IsValid(b.exit));assert(b.dupe.exit_id==-1)''')
    test('P18','Self-link and invalid link rejection preserve valid state',['B06','B31'],link+'''local a,b=portal(),portal();assert(a:LinkPortal(a));assert(a.exit==a);a:UnlinkPortal();assert(not IsValid(a.exit));a:LinkPortal(b);assert(not a:LinkPortal({GetClass=function() return 'prop_physics' end}));assert(a.exit==b and b.exit==a)''')
    hull=src('lua/autorun/sh_player_teleport.lua','local function get_hull(ply)','local function update_hull')
    player='''local ply={mins=Vector(-24,-24,0),maxs=Vector(24,24,96),dmins=Vector(-24,-24,0),dmaxs=Vector(24,24,48),scale=1}; function ply:GetHull() return Vector(self.mins),Vector(self.maxs) end;function ply:GetHullDuck() return Vector(self.dmins),Vector(self.dmaxs) end;function ply:SetHull(a,b) self.mins=Vector(a);self.maxs=Vector(b) end;function ply:SetHullDuck(a,b) self.dmins=Vector(a);self.dmaxs=Vector(b) end;function ply:GetModelScale() return self.scale end;'''
    test('P19','Floor standing/duck hulls remain ordered at multiple scales',['B04'],hull+player+'''for _,scale in ipairs({0.1,0.5,1,2,10}) do ply.scale=scale;invalidate_hull(ply);local a,b=get_hull(ply);clip_hull(ply,a,b,true);for j=1,3 do assert(ply.mins[j]<ply.maxs[j] and ply.dmins[j]<ply.dmaxs[j]) end;validate_hull(ply) end''')
    test('P20','Custom standing and crouched hull values restored exactly',['B05'],hull+player+'''invalidate_hull(ply);local a,b=get_hull(ply);clip_hull(ply,a,b,true);assert(validate_hull(ply));nearvec(ply.mins,Vector(-24,-24,0));nearvec(ply.maxs,Vector(24,24,96));nearvec(ply.dmaxs,Vector(24,24,48));assert(not validate_hull(ply))''')
    test('P21','External hull edits are not overwritten on release',['B05'],hull+player+'''invalidate_hull(ply);local a,b=get_hull(ply);clip_hull(ply,a,b,true);ply:SetHull(Vector(-8,-8,0),Vector(8,8,88));validate_hull(ply);nearvec(ply.maxs,Vector(8,8,88));nearvec(ply.dmaxs,Vector(24,24,48))''')
    trace=src('lua/seamless_portals/traces.lua')
    trace_setup='local a,b,target=portal(),portal(),portal();a.exit=b;SeamlessPortals.Portals={a,b};local count=0;local captured;local raw=function(data) count=count+1;local t=data.output or {};t.StartSolid=false;t.AllSolid=false;t.FractionLeftSolid=0;t.StartPos=Vector(data.start);t.Normal=Vector(0,0,-1);t.Hit=true;t.HitNormal=Vector(0,0,1);if count==1 then t.Entity=a;t.HitPos=Vector();t.Fraction=0.1 else captured=data;t.Entity=target;t.HitPos=Vector(0,0,-45);t.Fraction=0.5 end;return t end;util.TraceLine=raw;SeamlessPortals.TraceLine=raw;SeamlessPortals.TransformPortal=function(_,_,v) return Vector(v) end;'
    test('P22','Explicit trace preserves output identity and original filter',['B11','B12'],trace_setup+trace+'''local output={};local original=function(e) return e~=target end;local data={start=Vector(0,0,10),endpos=Vector(0,0,-90),output=output,filter=original};local result=SeamlessPortals.TracePortalLine(data);assert(result==output and output.Entity==target and data.filter==original);assert(not captured.filter(b) and not captured.filter(target));assert(captured.output==nil and captured.whitelist==false)''')
    test('P23','Segment metadata preserves local and accumulated fractions',['B13'],trace_setup+trace+'''local result=SeamlessPortals.TracePortalLine({start=Vector(0,0,10),endpos=Vector(0,0,-90)});near(result.Fraction,0.55025);near(result.SeamlessSegments[1].Fraction,0.1);near(result.SeamlessSegments[2].Fraction,0.5);nearvec(result.StartPos,Vector(0,0,10));assert(result.StartSolid==false and result.SeamlessSegments[1].Entity==a)''')
    test('P24','Dynamic default wrapper restores raw ownership when disabled',['O10','C03'],trace_setup+trace+'local data={start=Vector(0,0,10),endpos=Vector(0,0,-90)};assert(util.TraceLine(data).Entity==target and count==2);count=0;CVARS.seamless_portals_global_trace.value=0;SeamlessPortals.UpdateTraceOwnership();assert(util.TraceLine==raw and util.TraceLine(data).Entity==a and count==1)')
    bullet=src('lua/seamless_portals/traces.lua') + src('lua/seamless_portals/bullets.lua')
    bullet_setup='local a,b=portal(),portal();a.exit=b;b.pos=Vector(100,0,0);SeamlessPortals.Portals={a,b};local calls=0;local nextbullet;local shooter=portal();function shooter:FireBullets(d) calls=calls+1;nextbullet=d end;SeamlessPortals.TransformPortal=function(_,_,pos,ang) return Vector(100,0,0),ang end;local data={Src=Vector(0,0,10),Dir=Vector(0,0,-1),Distance=100,Damage=20};local damage={GetDamage=function() return 20 end,GetDamageType=function() return 2 end,GetDamageCustom=function() return 0 end,GetDamageForce=function() return Vector(0,0,-10) end,GetInflictor=function() return shooter end};local impact={Hit=true,StartSolid=false,StartPos=data.Src,HitPos=Vector(),HitNormal=Vector(0,0,1),Entity=a};'
    test('P25','Actual pellet impact continues with reduced range',['B14','B34','C04'],bullet_setup+bullet+"assert(hook.Run('EntityFireBullets',shooter,data)==true);near(data.Distance,100);local result=data.Callback(shooter,impact,damage);assert(result.damage==false and calls==1);near(nextbullet.Distance,89.95);nearvec(nextbullet.Src,Vector(100,0,0.05));assert(nextbullet.Num==1 and nextbullet.IgnoreEntity==nil)")
    test('P26','Spread/hull/multiple/ignored-target inputs retained before native pellet trace',['B15','C04'],bullet_setup+bullet+"for _,change in ipairs({{Num=2},{Spread=Vector(0.1,0,0)},{HullSize=1},{IgnoreEntity=b}}) do local d={Src=Vector(0,0,10),Dir=Vector(0,0,-1),Distance=100};for k,v in pairs(change) do d[k]=v end;assert(hook.Run('EntityFireBullets',shooter,d)==true);assert(d.Distance==100);nearvec(d.Src,Vector(0,0,10));for k,v in pairs(change) do assert(d[k]==v) end end;assert(calls==0)")
    test('P27','Exhausted pellet range terminates without second shot',['B14','C04'],bullet_setup+bullet+"data.Distance=10;assert(hook.Run('EntityFireBullets',shooter,data)==true);local ret=data.Callback(shooter,impact,damage);assert(ret.damage==false and calls==0 and data.Distance==10 and data.IgnoreEntity==nil)")
    render=src('lua/autorun/client/cl_render_core.lua','local function render_scene()','local get_flashlight')
    render_setup='''local clip_up,clip_pos=Vector(0,0,1),Vector();local renderview_table={};local cameras,planes=0,0;local clipping=false;local function push_cam() cameras=cameras+1 end;local function pop_cams() cameras=0 end;render={EnableClipping=function(v) local old=clipping;clipping=v;return old end,PushCustomClipPlane=function() planes=planes+1 end,PopCustomClipPlane=function() planes=planes-1 end};SeamlessPortals.Rendering=true;'''
    test('P28','RenderScene normal path calls renderer and balances resources',['R02'],render_setup+render+'''local calls=0;render.RenderView=function() calls=calls+1 end;render_scene();assert(calls==1 and cameras==0 and planes==0 and clipping==false and not SeamlessPortals.Rendering)''')
    test('P29','Render exception unwinds owned clip/camera state',['R02'],render_setup+render+'''render.RenderView=function() error('injected RenderView failure') end;local ok=pcall(render_scene);assert(not ok and cameras==0 and planes==0 and clipping==false and not SeamlessPortals.Rendering)''')
    cap=src('lua/autorun/client/cl_render_core.lua','\tlocal portal_render_max','    local target_depth')
    cap_setup='''local a,b=portal(),portal();a.SEAMLESS_PORTALS_RENDERED=true;b.SEAMLESS_PORTALS_RENDERED=true;SeamlessPortals.Portals={a,b};SeamlessPortals.Frame=0;local max_render={GetInt=function() return CAP end};local skip_frames={GetInt=function() return 0 end};local renderview_table={};function ScrW() return 1920 end;function ScrH() return 1080 end;local function pass()'''
    test('P30','Zero render cap resets all flags and skips work',['B17','B18'],cap_setup+cap+'''return 'work' end;CAP=0;assert(pass()==nil and not a.SEAMLESS_PORTALS_RENDERED and not b.SEAMLESS_PORTALS_RENDERED)''')
    test('P31','Refresh interval is bounded; viewport updates per pass',['B17','B19'],cap_setup+cap+'''return 'work' end;CAP=1;assert(pass()=='work');assert(SeamlessPortals.Frame==0 and renderview_table.w==1920 and renderview_table.h==1080);assert(not a.SEAMLESS_PORTALS_RENDERED and not b.SEAMLESS_PORTALS_RENDERED)''')
    mesh=src('lua/entities/seamless_portal_cutout.lua','function ENT:CreatePhysmesh()','local allowed_classes')
    mesh_setup='''local phys={EnableMotion=function() end,SetPos=function() end,SetAngles=function() end};local calls=0;local e=setmetatable({VERTICES={}}, {__index=ENT});function e:SetSolid() end;function e:SetMoveType() end;function e:EnableCustomCollisions() end;function e:GetPos() return Vector() end;function e:GetAngles() return Angle() end;function e:GetPhysicsObject() return phys end;function e:PhysicsFromMesh() calls=calls+1;return true end;'''
    test('P32','Mesh rejects NaN and collinear triangles before native call',['R10'],mesh+mesh_setup+'''e.VERTICES={Vector(0/0,0,0),Vector(1,0,0),Vector(0,1,0),Vector(),Vector(1,0,0),Vector(2,0,0)};assert(e:CreatePhysmesh()==false and calls==0)''')
    test('P33','Mesh retains valid triangles and requires native success',['R04','R10'],mesh+mesh_setup+'''e.VERTICES={Vector(),Vector(1,0,0),Vector(0,1,0)};assert(e:CreatePhysmesh()==true and calls==1);function e:PhysicsFromMesh() return false end;assert(e:CreatePhysmesh()==false)''')
    collision=src('lua/entities/seamless_portal_cutout.lua','local logic_collision_pair','function ENT:PhysicsCollide')
    collision_setup='''local world={GetPhysicsObject=function(self) return self end};game={GetWorld=function() return world end};local created=0;ents={Create=function() created=created+1;return {Spawn=function() end,SetPhysConstraintObjects=function() end,Activate=function() end,SetSaveValue=function() return true end,Input=function() end} end};SeamlessPortals.CollectTransportGroup=function(ent) if ent.constrained then return nil,\'fixture_unsupported_graph\' end return {ent} end;constraint={HasConstraints=function(e) return e.constrained==true end};local phys={RecheckCollisionFilter=function() end};local e={GetClass=function() return 'prop_physics' end,GetPhysicsObject=function() return phys end};local c=setmetatable({ENTITIES={},SEAMLESS_PORTALS_READY=true,GetPhysicsObject=function() return phys end},{__index=ENT});'''
    test('P34','Constrained entity admission is rejected without native work',['B09'],collision+collision_setup+'''e.constrained=true;assert(not c:AddEntity(e));assert(created==0 and e.SEAMLESS_PORTALS_CUTOUT==nil);e.constrained=false;assert(c:AddEntity(e));assert(e.SEAMLESS_PORTALS_CUTOUT==c and c.ENTITIES[e])''')
    test('P35','Removing foreign/deleted memberships does not alter owner',['B10'],collision+collision_setup+'''local other={};e.SEAMLESS_PORTALS_CUTOUT=other;c.ENTITIES[e]=true;c:RemoveEntity(e);assert(e.SEAMLESS_PORTALS_CUTOUT==other and c.ENTITIES[e]==nil and created==0);e.valid=false;c.ENTITIES[e]=true;c:RemoveEntity(e);assert(c.ENTITIES[e]==nil)''')
    test('P36','Native collision helper allocation failure fails closed',['R01','R04'],collision+collision_setup+'''ents.Create=function() return NULL end;assert(not c:AddEntity(e));assert(e.SEAMLESS_PORTALS_CUTOUT==nil and c.ENTITIES[e]==nil)''')
    test('P37','Cleanup invalidation lazily recreates collision helper',['R01'],collision+collision_setup+'''assert(c:AddEntity(e));assert(created==1);c:RemoveEntity(e);hook.Run('PostCleanupMap');assert(c:AddEntity(e));assert(created==2)''')
    scale=src('lua/entities/seamless_portal_clone.lua','    local function set_model_scale_checked','\n\t-- 2 way coupling')
    scale_setup='''local native=0;local phys={motion=false,mass=10,velocity=Vector(1,2,3),angular=Vector(4,5,6),material='metal'};function phys:GetMeshConvexes() return {{1,2,3}} end;function phys:GetVelocity() return Vector(self.velocity) end;function phys:GetAngleVelocity() return Vector(self.angular) end;function phys:IsMotionEnabled() return self.motion end;function phys:GetMaterial() return self.material end;function phys:GetMass() return self.mass end;function phys:GetDamping() return 0.2,0.3 end;function phys:SetMaterial(v) self.material=v end;function phys:SetDamping(a,b) self.damping={a,b} end;function phys:SetMass(v) self.mass=v end;function phys:EnableMotion(v) self.motion=v end;function phys:SetVelocity(v) self.velocity=Vector(v) end;function phys:SetAngleVelocity(v) self.angular=Vector(v) end;local e={scale=2};function e:GetPhysicsObject() return phys end;function e:GetModelScale() return self.scale end;function e:SetModelScale(v) self.scale=v end;function e:GetSolid() return 6 end;function e:PhysicsInit() native=native+1;return true end;function e:Activate() self.activations=(self.activations or 0)+1 end;'''
    test('P38','Scale changes preserve properties and use relative area mass',['B26','R04'],scale+scale_setup+'''assert(set_model_scale_checked(e,4)==phys);assert(e.scale==4 and native==1);near(phys.mass,40);assert(phys.motion==false and phys.material=='metal');nearvec(phys.velocity,Vector(1,2,3));assert(set_model_scale_checked(e,2)==phys);near(phys.mass,10);assert(set_model_scale_checked(e,2)==phys and native==2)''')
    test('P39','Scale failure restores visual scale; invalid old scale rejected',['R04'],scale+scale_setup+'''function e:PhysicsInit() native=native+1;return false end;assert(set_model_scale_checked(e,4)==nil and e.scale==2);e.scale=0;assert(set_model_scale_checked(e,4)==nil and native==1)''')
    test('P40','Excessive convex complexity rejected before scaling',['R04'],scale+scale_setup+'''function phys:GetMeshConvexes() local c={};for i=1,2000 do c[i]=1 end;return {c} end;assert(set_model_scale_checked(e,4)==nil and e.scale==2 and native==0)''')
    setup=src('lua/entities/seamless_portal/sh_init.lua','function ENT:SetupDataTables()','-- So the size is in source units')
    reconcile=src('lua/entities/seamless_portal/sh_init.lua','function ENT:ReconcileGeometry()','function ENT:GetRemoveExit()')
    entity_setup='''local e=setmetatable({vars={},callbacks={},builds=0,writes=0},{__index=ENT});function e:NetworkVar(kind,slot,name) self.vars[name]=kind=='Vector' and Vector() or kind=='Entity' and NULL or kind=='Bool' and false or 0;self['Get'..name]=function(ent) local v=ent.vars[name];return isvector(v) and Vector(v) or v end;self['Set'..name]=function(ent,v) local old=ent.vars[name];if ent.callbacks[name] then ent.callbacks[name](ent,name,old,v) end;ent.vars[name]=isvector(v) and Vector(v) or v;ent.writes=ent.writes+1 end end;function e:NetworkVarNotify(name,fn) self.callbacks[name]=fn end;function e:GetPhysicsObject() return {} end;function e:UpdatePhysmesh(size,sides) self.builds=self.builds+1;self.built_size=Vector(size);self.built_sides=sides;return true end;e:SetupDataTables();'''
    test('P43','Notify-before-assignment batches to one coherent rebuild',['B02','O03'],setup+reconcile+entity_setup+'''e:SetSize(Vector(100,100,8));e:SetSides(4);assert(e.builds==0);assert(e:ReconcileGeometry());assert(e.builds==1 and e.built_sides==4);e:SetSize(Vector(200,200,8));e:SetSides(50);assert(e.builds==1);e:ReconcileGeometry();assert(e.builds==2 and e.built_sides==50);nearvec(e.built_size,Vector(200,200,8));e:ReconcileGeometry();assert(e.builds==2)''')
    test('P44','Client reconciles missing initial/change notifications',['B02'],setup+reconcile+entity_setup+'''CLIENT=true;SERVER=false;e.vars.Size=Vector(100,100,8);e.vars.Sides=4;e.SEAMLESS_PORTALS_GEOMETRY_DIRTY=false;assert(e:ReconcileGeometry() and e.builds==1);e.vars.Sides=6;assert(e:ReconcileGeometry() and e.builds==2 and e.built_sides==6)''')
    test('P45','Invalid public setters leave native state and dirty flags unchanged',['B01'],setup+reconcile+entity_setup+'''e:SetSize(Vector(100,100,8));e:SetSides(4);e:ReconcileGeometry();local writes=e.writes;assert(not e:SetSides(100000) and not e:SetSize(Vector(0,10,8)));assert(e.writes==writes and e.builds==1 and e.SEAMLESS_PORTALS_GEOMETRY_DIRTY==false);assert(e:GetSides()==4);nearvec(e:GetSize(),Vector(100,100,8))''')
    surface = src('lua/entities/seamless_portal_cutout.lua', 'local function cut_concave', 'function ENT:CreatePhysmesh()')
    surface_setup = r'''
function Lerp(t,a,b) return a+(b-a)*math.Clamp(t,0,1) end
util.IntersectRayWithPlane=function(start,delta,point,normal)
 local denominator=delta:Dot(normal)
 if math.abs(denominator)<1e-8 then return end
 return start+delta*((point-start):Dot(normal)/denominator)
end
local function support_mesh(axis,sign,sides,gap,reverse,rear_wall)
 local p=portal(Vector(100,147.1,8),sides)
 local lo,hi=SeamlessPortals.GetApertureBounds(p:GetSize(),sides)
 local floor=(sign==1 and hi[axis] or lo[axis])+sign*gap
 local normal=Vector();normal[axis]=-sign
 -- Surface basis expressed directly in portal coordinates.
 function p:WorldToLocalAngles()
  return {Right=function() return axis==1 and Vector(0,sign,0) or Vector(-sign,0,0) end,
          Up=function() return Vector(0,0,1) end}
 end
 SeamlessPortals.TraceLine=function(data)
  assert(data.mask==MASK_SOLID_BRUSHONLY and data.filter(p)==false)
  if rear_wall and data.start.z < -rear_wall then
   return {Hit=true,StartSolid=true,AllSolid=true,Fraction=0,HitPos=data.start,HitNormal=Vector()}
  end
  local delta=data.endpos-data.start
  local fraction=delta[axis]~=0 and (floor-data.start[axis])/delta[axis] or -1
  local hit=fraction>=0 and fraction<=1
  return {Hit=hit,StartSolid=false,Fraction=hit and fraction or 1,
          HitPos=hit and data.start+delta*fraction or data.endpos,HitNormal=normal}
 end
 local c=setmetatable({VERTICES={}}, {__index=ENT})
 c:GeneratePhysmesh(p,reverse and portal() or nil)
 local area=0
 for i=1,#c.VERTICES,3 do
  local a,b,d=c.VERTICES[i],c.VERTICES[i+1],c.VERTICES[i+2]
  local target=floor*(reverse and axis==2 and -1 or 1)
  if math.abs(a[axis]-target)<1e-6 and math.abs(b[axis]-target)<1e-6 and math.abs(d[axis]-target)<1e-6 then
   area=area+(b-a):Cross(d-a):Length()/2
   for _,v in ipairs({a,b,d}) do assert(reverse and v.z<=1e-6 or not reverse and v.z>=-1e-6) end
  end
 end
 assert(area>1000,'Missing support beyond aperture border: '..axis..'/'..sign..'/'..sides)
end
'''
    test('P46','Cutout keeps floor and side support just outside the aperture',['F03'],surface+surface_setup+'''
for axis=1,2 do for _,sign in ipairs({-1,1}) do support_mesh(axis,sign,4,0.1,false) end end
''')
    test('P47','Rounded cutouts retain support beyond their polygon bounds',['F03'],surface+surface_setup+'''
for _,sides in ipairs({3,6,50,100}) do support_mesh(1,1,sides,16,false) end
''')
    test('P48','Exit support is transformed into the back half of the source cutout',['F03'],surface+surface_setup+'''
for axis=1,2 do for _,sign in ipairs({-1,1}) do support_mesh(axis,sign,4,0.1,true) end end
''')
    collision_cache = r'''
local pairs_state={}
local function pair_enabled(a,b)
 return not pairs_state[a] or pairs_state[a][b]~=false
end
ents.Create=function()
 created=created+1
 local helper={m_disabled=false,m_succeeded=false}
 function helper:Spawn() end
 function helper:SetPhysConstraintObjects(a,b) self.a,self.b=a,b end
 function helper:Apply(enabled)
  self.m_disabled,self.m_succeeded=not enabled,true
  pairs_state[self.a]=pairs_state[self.a] or {};pairs_state[self.a][self.b]=enabled
 end
 function helper:Activate() if self.m_disabled then self:Apply(false) end end
 function helper:Input(input)
  local enabled=input=='EnableCollisions'
  if self.m_succeeded and self.m_disabled==not enabled then return end
  self:Apply(enabled)
 end
 function helper:SetSaveValue(key,value) self[key]=value;return true end
 return helper
end
-- Distinct native bodies, including each cutout and the map.
local cutout_phys={RecheckCollisionFilter=function() end}
function c:GetPhysicsObject() return cutout_phys end
'''
    test('P49','Reentering a cutout restores its previously disabled collision pair',['F03'],collision+collision_setup+collision_cache+'''
assert(c:AddEntity(e));assert(pair_enabled(phys,cutout_phys) and not pair_enabled(phys,world))
c:RemoveEntity(e);assert(not pair_enabled(phys,cutout_phys) and pair_enabled(phys,world))
assert(c:AddEntity(e));assert(pair_enabled(phys,cutout_phys) and not pair_enabled(phys,world))
c:RemoveEntity(e);assert(pair_enabled(phys,world))
''')
    test('P50','Proxy reentry restores support after world collisions were enabled',['F03'],collision+collision_setup+collision_cache+'''
assert(c:AddProxy(e));c:RemoveProxy(e)
assert(pair_enabled(phys,world) and not pair_enabled(phys,cutout_phys))
assert(c:AddProxy(e));assert(pair_enabled(phys,cutout_phys) and not pair_enabled(phys,world))
c:RemoveProxy(e);assert(pair_enabled(phys,world) and e.SEAMLESS_PORTALS_PROXY_CUTOUT==nil)
''')
    coupling = src('lua/entities/seamless_portal_clone.lua', '    local function coupling_excess', '\n\tfunction ENT:Initialize()')
    coupling_setup = (Path(__file__).parent / 'custom_stubs.lua').read_text() + r'''
local a,b=pair()
local clone,child=prop(),prop()
local one,two=clone:GetPhysicsObject(),child:GetPhysicsObject()
local angle_meta=getmetatable(Angle())
function angle_meta:Normalize() for i=1,3 do self[i]=(self[i]+180)%360-180 end end
function WorldToLocal(pos,ang,origin,angles)
 return pos-origin,Angle(ang[1]-angles[1],ang[2]-angles[2],ang[3]-angles[3])
end
SeamlessPortals.TransformPortal=function(_,_,pos,ang) return Vector(pos),Angle(ang) end
SeamlessPortals.HasTrackedHold=function() return false end
function transform_portal_local(_,_,v) return Vector(v) end
SeamlessPortals.TransformDirection=transform_portal_local
for _,e in ipairs({clone,child}) do
 function e:GetModelScale() return 1 end
 function e:BoundingRadius() return self.radius or 24 end
end
function clone:GetPortal1() return a end
function clone:GetPortal2() return b end
clone.VerletWeld=ENT.VerletWeld
for _,p in ipairs({one,two}) do
 p.vel,p.angular=Vector(),Vector();p.masscenter=Vector();p.writes=0;p.contacts={{}}
 function p:IsAsleep() return self.asleep==true end
 function p:GetFrictionSnapshot() return self.contacts end
 function p:GetMassCenter() return Vector(self.masscenter) end
 function p:LocalToWorld(v) return self.pos+v end
 function p:LocalToWorldVector(v) return Vector(v) end
 function p:WorldToLocalVector(v) return Vector(v) end
 function p:SetVelocity(v) self.vel=Vector(v);self.writes=self.writes+1;self.asleep=false end
 function p:SetAngleVelocity(v) self.angular=Vector(v);self.writes=self.writes+1;self.asleep=false end
end
'''
    # Put the fixture after the source so it binds the actual entity method.
    def resting(code):
        return coupling + coupling_setup + code
    test('P51','Supported coherent props settle without controller writes or freezing',['F03'],resting('''
one.pos=Vector(0.1,0,0);one.ang=Angle(0,1,0)
one.vel=Vector(0.1,0,0);two.vel=Vector(0,0.1,0)
assert(clone:VerletWeld(clone,child));assert(one.writes==0 and two.writes==0)
assert(one.motion and two.motion and one.motion_writes==0 and two.motion_writes==0)
nearvec(one.vel,Vector(0.1,0,0));nearvec(two.vel,Vector(0,0.1,0))
'''))
    test('P52','Free bodies and a pushed remote body still exchange motion',['F03'],resting('''
one.contacts={};two.contacts={};one.vel=Vector(120,0,0)
assert(clone:VerletWeld(clone,child));nearvec(two.vel,Vector(60,0,0));nearvec(one.vel,two.vel)
one.contacts={{}};two.contacts={{}};one.asleep=true;two.asleep=true
one.vel=Vector(0,80,0);one.asleep=false;two.vel=Vector()
assert(clone:VerletWeld(clone,child));assert(two.vel.y>0 and not two.asleep)
'''))
    test('P53','Loss of support resumes coupling and preserves falling velocity',['F03'],resting('''
one.asleep=true;two.asleep=true
assert(clone:VerletWeld(clone,child));assert(one.writes==0 and two.writes==0)
one.asleep=false;one.contacts={};one.vel=Vector(0,0,-4)
assert(clone:VerletWeld(clone,child));assert(two.vel.z<0 and two.writes>0)
'''))
    test('P54','Position corrections use mass centers instead of offset model origins',['F03'],resting('''
one.contacts={};two.contacts={};one.pos=Vector(4,0,0);one.masscenter=Vector(-4,0,0)
one.vel=Vector(0,0,-20);two.vel=Vector(0,0,-20)
assert(clone:VerletWeld(clone,child));nearvec(one.vel,Vector(0,0,-20));nearvec(two.vel,one.vel)
'''))
    test('P55','Contact margin does not add torque to a coherently rotating body',['F03'],resting('''
one.ang=Angle(0,1,0);one.angular=Vector(0,0,30);two.angular=Vector(0,0,30)
assert(clone:VerletWeld(clone,child));nearvec(one.angular,Vector(0,0,30));nearvec(two.angular,one.angular)
'''))
    test('P56','Large pose errors and large prop surface offsets are corrected',['F03'],resting('''
one.pos=Vector(3,0,0);assert(clone:VerletWeld(clone,child));assert(one.vel.x<0 and two.vel.x>0)
one.pos=Vector();one.vel=Vector();two.vel=Vector();one.ang=Angle(0,2,0);child.radius=200
assert(clone:VerletWeld(clone,child));assert(one.angular.z<0 and two.angular.z>0)
'''))

    test('P57','Angular synchronization uses a common physical frame',['F03'],resting('''
local angle=math.pi/180
function one:LocalToWorldVector(v)
 return Vector(v.x*math.cos(angle)-v.y*math.sin(angle),v.x*math.sin(angle)+v.y*math.cos(angle),v.z)
end
function one:WorldToLocalVector(v)
 return Vector(v.x*math.cos(angle)+v.y*math.sin(angle),-v.x*math.sin(angle)+v.y*math.cos(angle),v.z)
end
one.ang=Angle(0,1,0);two.angular=Vector(30,0,0);one.angular=one:WorldToLocalVector(two.angular)
assert(clone:VerletWeld(clone,child));nearvec(two.angular,Vector(30,0,0))
nearvec(one:LocalToWorldVector(one.angular),two.angular)
'''))

    test('P58','The settling band stops corrections just outside the contact slop',['F03'],resting('''
one.pos=Vector(0.55,0,0);one.vel=Vector(0.1,0,0);two.vel=Vector(0.2,0,0)
assert(clone:VerletWeld(clone,child));assert(one.writes==0 and two.writes==0)
'''))
    test('P59','Sleeping bodies with a changed pose resume synchronization',['F03'],resting('''
one.asleep=true;two.asleep=true;one.pos=Vector(3,0,0)
assert(clone:VerletWeld(clone,child));assert(one.writes>0 and two.writes>0)
assert(not one.asleep and not two.asleep)
'''))

    test('P60','Floor support survives a mounting wall behind the aperture',['F03'],surface+surface_setup+'''
for _,wall in ipairs({0.1,1,2,4}) do
 for _,reverse in ipairs({false,true}) do support_mesh(1,1,4,0.1,reverse,wall) end
end
''')
    surface_probe = src('lua/entities/seamless_portal_cutout.lua', '\tlocal function trace_local_generate_quad', '\n    -- Sample the visible room.')
    probe_setup = '''
local size=Vector(100,100,8)
local portal=portal(size)
function portal:WorldToLocalAngles() return {Right=function() return Vector(0,1,0) end,Up=function() return Vector(0,0,1) end} end
local writes=0
local function generate_quad() writes=writes+1 end
local result={Hit=true,HitNormal=Vector(1,0,0),HitPos=Vector()}
SeamlessPortals.TraceLine=function() return result end
'''
    test('P61','Solid-origin and invalid-normal probes cannot create collision planes',['F03'],probe_setup+surface_probe+'''
result.StartSolid=true;trace_local_generate_quad(Vector(),Vector(100,0,0));assert(writes==0)
result.StartSolid=false;result.AllSolid=true;trace_local_generate_quad(Vector(),Vector(100,0,0));assert(writes==0)
result.AllSolid=false;result.HitNormal=Vector();trace_local_generate_quad(Vector(),Vector(100,0,0));assert(writes==0)
result.HitNormal=Vector(1,0,0);trace_local_generate_quad(Vector(),Vector(100,0,0));assert(writes==1)
''')

    # Test real Python build/check functions with temporary files and deterministic byte checks.
    try:
        release_path=root/'tools/build_release.py';spec=importlib.util.spec_from_file_location('release_candidate',release_path);module=importlib.util.module_from_spec(spec);spec.loader.exec_module(module)
        with tempfile.TemporaryDirectory() as tmp:
            a,b=Path(tmp)/'a.zip',Path(tmp)/'b.zip';module.build(root,a);module.build(root,b)
            assert a.read_bytes()==b.read_bytes()
            import zipfile
            with zipfile.ZipFile(a) as z:
                names=z.namelist();assert names==sorted(names);assert not any('/tests/' in n or '/.git/' in n or '/patch_proposals/' in n or '/tools/' in n for n in names)
                assert 'seamless/seamless_portals.fgd' in names
            try: module.build(root,root/'lua/should-not-exist.zip')
            except ValueError: pass
            else: raise AssertionError('Runtime-output path accepted')
        results.append(dict(id='P41',title='Release ZIP is deterministic and excludes metadata/tests/tooling',proposals=['O11'],status='PASS',observed='Identical archive bytes; output path guard; allowlist checked',kind='actual candidate Python code'))
    except Exception as exc:
        results.append(dict(id='P41',title='Release ZIP validation',proposals=['O11'],status='FAIL',observed=str(exc),kind='actual candidate Python code'))
    check=subprocess.run([sys.executable,str(root/'tools/check_source.py'),str(root)],capture_output=True,text=True)
    results.append(dict(id='P42',title='Candidate textual source regression gates',proposals=['O12'],status='PASS' if check.returncode==0 else 'FAIL',observed=(check.stdout+check.stderr).strip(),kind='textual gates, not a parser'))
    syntax=[]
    for path in sorted((root/'lua').rglob('*.lua')):
        try:lua.check(normalize(path.read_text(),True),False,str(path));status='PASS'
        except Exception as exc:status=str(exc)
        syntax.append(dict(file=path.relative_to(root).as_posix(),status=status))
    report={'native_gmod_tested':False,'executable_continue_translation':False,
        'limits':'Lua 5.4 operators normalized; engine APIs are explicit test doubles. Syntax-only continue stand-in is never executed. No rendering, physics, prediction, networking or performance claims.',
        'tests':results,'normalized_syntax':syntax,'passed':sum(r['status']=='PASS' for r in results),'failed':sum(r['status']!='PASS' for r in results)}
    output.parent.mkdir(parents=True,exist_ok=True);output.write_text(json.dumps(report,indent=2)+'\n')
    for r in results:
        print(f"{r['status']} {r['id']}: {r['title']}" + (f"\n{r['observed']}" if r['status']!='PASS' else ''))
    print(f"{report['passed']}/{len(results)} regression checks; {len(syntax)} normalized syntax checks (NOT native GLua)")
    return int(report['failed'] or any(r['status']!='PASS' for r in syntax))

if __name__=='__main__':
    parser=argparse.ArgumentParser(description=__doc__);parser.add_argument('source',type=Path);parser.add_argument('--output',type=Path,default=Path('regression_results.json'));args=parser.parse_args()
    try:raise SystemExit(main(args.source,args.output))
    except (OSError,RuntimeError,ValueError) as exc:parser.exit(1,f'Test setup failed: {exc}\n')
