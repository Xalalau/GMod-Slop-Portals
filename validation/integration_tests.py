#!/usr/bin/env python3
"""Release integration checks with explicit Lua API doubles; no native GMod execution."""
from pathlib import Path
import argparse
import ast
import importlib.util
import json
import tempfile
from unittest.mock import patch
from lua_support import Lua, normalize


def main(root: Path, output: Path) -> int:
    root = root.resolve()
    here = Path(__file__).resolve().parent
    lua = Lua()
    prelude = (here / 'stubs.lua').read_text(encoding='utf-8')
    syntax = ast.parse((here / 'regression_tests.py').read_text(encoding='utf-8'))
    results = []

    def fixture(name):
        for node in ast.walk(syntax):
            if isinstance(node, ast.Assign) and isinstance(node.value, ast.Constant):
                if any(isinstance(t, ast.Name) and t.id == name for t in node.targets):
                    return node.value.value
        raise ValueError('Missing existing fixture: ' + name)

    def src(path, start=None, end=None):
        text = (root / path).read_text(encoding='utf-8')
        if start is not None:
            text = text[text.index(start):]
        if end is not None:
            text = text[:text.index(end)]
        return normalize(text) + '\n'

    core = src('lua/seamless_portals/core.lua') + src('lua/seamless_portals/features.lua') + src('lua/seamless_portals/aperture.lua') + src('lua/seamless_portals/tool_features.lua')

    def test(identifier, title, code):
        try:
            observed = lua.check(prelude + core + code + '\nreturn "assertions passed"', True, identifier)
            assert observed == 'assertions passed', 'Assertions bypassed by early chunk return'
            status = 'PASS'
        except Exception as exc:
            status, observed = 'FAIL', str(exc)
        results.append({'id': identifier, 'title': title, 'status': status,
                        'kind': 'actual source excerpt, Lua 5.4 API doubles', 'observed': observed})

    test('I01', 'Reject still-valid entities marked for deletion', '''
local a = portal()
function a:IsMarkedForDeletion() return self.marked == true end
assert(SeamlessPortals.IsPortal(a))
a.marked = true
assert(IsValid(a) and not SeamlessPortals.IsLiveEntity(a) and not SeamlessPortals.IsPortal(a))
assert(not SeamlessPortals.IsLiveEntity(NULL))
''')
    test('I02', 'Disable links with failed geometry without removing their metadata', '''
local a,b = portal(),portal(); a.exit=b; b.exit=a
assert(SeamlessPortals.IsUsableLink(a,b))
b.SEAMLESS_PORTALS_GEOMETRY_FAILED=true
assert(not SeamlessPortals.IsUsableLink(a,b) and a.exit==b and b.exit==a)
b.SEAMLESS_PORTALS_GEOMETRY_FAILED=false
assert(SeamlessPortals.IsUsableLink(a,b))
''')
    shared = 'lua/entities/seamless_portal/sh_init.lua'
    setup = src(shared, 'function ENT:SetupDataTables()', '-- So the size is in source units')
    reconcile = src(shared, 'function ENT:ReconcileGeometry()', 'function ENT:GetRemoveExit()')
    test('I03', 'Geometry failure is recorded and a successful retry clears it', setup+reconcile+fixture('entity_setup')+'''
e:SetSize(Vector(100,100,8)); e:SetSides(4)
local build=e.UpdatePhysmesh
function e:UpdatePhysmesh() return false end
assert(not e:ReconcileGeometry() and e.SEAMLESS_PORTALS_GEOMETRY_FAILED)
e.UpdatePhysmesh=build
assert(e:ReconcileGeometry() and e.SEAMLESS_PORTALS_GEOMETRY_FAILED==false)
''')
    cutout = src('lua/entities/seamless_portal_cutout.lua', 'local logic_collision_pair', 'function ENT:PhysicsCollide')
    collision = fixture('collision_setup')
    deferred = '''
function SafeRemoveEntity(ent) if IsValid(ent) then ent.marked=true end end
local clone={}; e.SEAMLESS_PORTALS_CLONE=clone
'''
    test('I04', 'Deactivate releases membership before deferred deletion and is idempotent', cutout+collision+deferred+'''
assert(c:AddEntity(e)); c:Deactivate()
assert(not c.SEAMLESS_PORTALS_READY and c.SEAMLESS_PORTALS_DEACTIVATING)
assert(e.SEAMLESS_PORTALS_CUTOUT==nil and e.SEAMLESS_PORTALS_CLONE==nil)
assert(next(c.ENTITIES)==nil and IsValid(clone) and clone.marked)
local n=created; c:Deactivate(); assert(created==n)
''')
    test('I05', 'Retired or deletion-pending cutouts reject new admission', cutout+collision+'''
c:Deactivate(); assert(not c:AddEntity(e) and created==0)
c.SEAMLESS_PORTALS_DEACTIVATING=nil; c.SEAMLESS_PORTALS_READY=true
function c:IsMarkedForDeletion() return true end
assert(not c:AddEntity(e) and created==0)
''')
    test('I06', 'Failed world-collision restoration is retried after helper allocation recovers', cutout+collision+'''
assert(c:AddEntity(e)); local create=ents.Create
hook.Run('PostCleanupMap'); ents.Create=function() return NULL end
c:RemoveEntity(e); assert(restore_pending[e] and e.SEAMLESS_PORTALS_CUTOUT==nil)
ents.Create=create; hook.Run('Think')
assert(restore_pending[e]==nil and created==2)
''')
    test('I07', 'Recovery does not overwrite a newer cutout owner', cutout+collision+'''
assert(c:AddEntity(e)); local create=ents.Create
hook.Run('PostCleanupMap'); ents.Create=function() return NULL end
c:RemoveEntity(e); assert(restore_pending[e])
e.SEAMLESS_PORTALS_CUTOUT={}; ents.Create=create
local before=created; hook.Run('Think')
assert(restore_pending[e]==nil and created==before and e.SEAMLESS_PORTALS_CUTOUT~=nil)
''')
    test('I08', 'A deletion-pending collision helper is never reused', cutout+collision+'''
assert(c:AddEntity(e)); assert(created==1)
function logic_collision_pair:IsMarkedForDeletion() return true end
c:RemoveEntity(e); assert(created==2)
''')
    discard = src('lua/entities/seamless_portal/init.lua', 'function ENT:DiscardTraversalState()', 'function ENT:UnlinkPortal()')
    test('I09', 'Portal discard invokes synchronous deactivation before entity removal', discard+'''
local order={}; local c={Deactivate=function() order[#order+1]='deactivate' end}
local p=portal(); p.SEAMLESS_PORTALS_CUTOUT=c
function SafeRemoveEntity(ent) order[#order+1]='remove'; ent.marked=true end
p:DiscardTraversalState()
assert(order[1]=='deactivate' and order[2]=='remove' and p.SEAMLESS_PORTALS_CUTOUT==nil and c.marked)
''')
    update_cutout = src('lua/entities/seamless_portal/init.lua', 'function ENT:UpdateCutout(recursive)', '-- Prop and object teleporting')
    test('I10', 'Exit-cutout failure also retires the entry cutout', update_cutout+'''
local a,b=portal(),portal(); a.exit=b; b.exit=a
local old={SEAMLESS_PORTALS_READY=true,SEAMLESS_PORTALS_GEOMETRY=SeamlessPortals.CaptureGeometry(a)}
a.SEAMLESS_PORTALS_CUTOUT=old
function a:DiscardTraversalState() self.discarded=true; self.SEAMLESS_PORTALS_CUTOUT=nil end
function b:UpdateCutout(recursive) assert(recursive==true); return false end
assert(not a:UpdateCutout() and a.discarded and a.SEAMLESS_PORTALS_CUTOUT==nil)
''')
    test('I11', 'Directed link does not allocate an unrelated physics cutout', update_cutout+'''
local a,b,c=portal(),portal(),portal(); a.exit=b; b.exit=c
function a:DiscardTraversalState() self.discarded=true end
ents={Create=function() error('must not allocate') end}
assert(not a:UpdateCutout() and a.discarded)
assert(SeamlessPortals.IsUsableLink(a,b)) -- rendering/player/trace contract remains
''')
    hull = src('lua/autorun/sh_player_teleport.lua', 'local function get_hull(ply)', '-- TODO: extrude on sides')
    test('I12', 'Unlinking a portal restores an already-clipped custom player hull', 'local portal_trace_data={}\n'+hull+fixture('player')+'''
function ply:GetMoveType() return 2 end
local a=portal(); util.TraceHull=function() return {Hit=true,Entity=a} end
invalidate_hull(ply); local lo,hi=get_hull(ply); clip_hull(ply,lo,hi,true)
assert(ply.SEAMLESS_PORTALS_LAST_HULL)
assert(update_hull(ply,Vector()))
nearvec(ply.maxs,Vector(24,24,96)); nearvec(ply.dmaxs,Vector(24,24,48))
assert(ply.SEAMLESS_PORTALS_LAST_HULL==nil)
''')
    release_clip = src('lua/entities/seamless_portal_clone.lua', 'function ENT:ReleaseChildClip()', 'function ENT:Think()')
    test('I13', 'An old clone cannot clear the active clone clip plane', release_clip+'''
local child={SetRenderClipPlaneEnabled=function(self,on) self.clipped=on end,clipped=true}
local old=setmetatable({GetChild=function() return child end},{__index=ENT})
local new={}; child.SEAMLESS_PORTALS_CLIP_OWNER=new
old:ReleaseChildClip(); assert(child.clipped and child.SEAMLESS_PORTALS_CLIP_OWNER==new)
child.SEAMLESS_PORTALS_CLIP_OWNER=old; old:ReleaseChildClip()
assert(not child.clipped and child.SEAMLESS_PORTALS_CLIP_OWNER==nil)
''')
    test('I14', 'Changing a clone child releases only the previously-owned child', release_clip+'''
local old={SetRenderClipPlaneEnabled=function(self,on) self.clipped=on end,clipped=true}
local new={clipped=true}
local clone=setmetatable({GetChild=function() return new end,SEAMLESS_PORTALS_CLIPPED_CHILD=old},{__index=ENT})
old.SEAMLESS_PORTALS_CLIP_OWNER=clone; clone:ReleaseChildClip()
assert(not old.clipped and new.clipped and clone.SEAMLESS_PORTALS_CLIPPED_CHILD==nil)
''')
    clone_think = src('lua/entities/seamless_portal_clone.lua', 'function ENT:Think()', '\nif SERVER then')
    test('I15', 'Failed clone coupling releases its child instead of remaining active', clone_think+'''
local a,b=portal(),portal(); local child={}; local calls=0
child.SEAMLESS_PORTALS_CUTOUT={RemoveEntity=function(_,ent) assert(ent==child);calls=calls+1 end}
local clone=setmetatable({GetChild=function() return child end,GetPortal1=function() return a end,
GetPortal2=function() return b end,VerletWeld=function() return false end,
NextThink=function() error('must not schedule a failed clone') end},{__index=ENT})
clone:Think(); assert(calls==1)
''')
    scale = src('lua/entities/seamless_portal_clone.lua', '    local function set_model_scale_checked', '\n\t-- 2 way coupling')
    test('I16', 'Scaling activates collision then restores state on the newly-returned physics object', scale+fixture('scale_setup')+'''
local old=phys
function e:Activate()
 self.activations=(self.activations or 0)+1
 local replacement={}; for k,v in pairs(phys) do replacement[k]=v end
 phys=replacement
end
assert(set_model_scale_checked(e,4)==phys and phys~=old and e.activations==1)
near(phys.mass,40);near(old.mass,10);nearvec(phys.velocity,Vector(1,2,3))
assert(phys.motion==false and phys.material=='metal')
''')
    test('I17', 'Invalid physics after activation is rejected without property writes', scale+fixture('scale_setup')+'''
function e:Activate() phys.valid=false end
assert(set_model_scale_checked(e,4)==nil and e.scale==2)
near(phys.mass,10)
''')
    flashlight = 'function Matrix() return {} end\n'+src('lua/cl_portal_flashlight.lua', end='return UpdateLightNew')
    light_fixture = '''
local ply={FlashlightIsOn=function() return true end}; function LocalPlayer() return ply end
local light={pos=Vector(999,999,999),ang=Angle(10,20,30)}
function light:SetBrightness(v) self.brightness=v end
function light:SetPos(v) self.pos=Vector(v) end
function light:SetAngles(v) self.ang=Angle(v) end
function light:Remove() self.removed=true end
local input,angle=Vector(1,2,3),Angle(4,5,6)
SeamlessPortals.FlashlightContexts.portal={light=light,frame=FrameNumber(),input_pos=Vector(input),
input_ang=Angle(angle),base_pos=Vector(10,20,30),base_ang=Angle(0,90,0),distance=12}
'''
    test('I18', 'Same-frame flashlight reuse resets the source pose rather than compounding portal transforms', flashlight+light_fixture+'''
assert(UpdateLightNew(input,angle,'portal')==light)
nearvec(light.pos,Vector(10,20,30));assert(light.ang==Angle(0,90,0) and light.brightness==1)
light.pos=Vector(700,800,900)
UpdateLightNew(input,angle,'portal');nearvec(light.pos,Vector(10,20,30))
''')
    test('I19', 'An inactive player flashlight releases its cached native resource', flashlight+light_fixture+'''
function ply:FlashlightIsOn() return false end
assert(UpdateLightNew(input,angle,'portal')==nil and light.removed)
assert(SeamlessPortals.FlashlightContexts.portal==nil)
''')
    link_tool = src('lua/weapons/gmod_tool/stools/portal_creator_tool.lua', 'function TOOL:RightClick(trace)', '-- portal unlinking')
    test('I20', 'Tool link failure reports false and preserves link-selection stage', link_tool+'''
local a,b=portal(),portal(); function a:LinkPortal() return false end
local owner={GetInfoNum=function() return 0 end}
local tool=setmetatable({stage=2,GetOwner=function() return owner end,GetLinkTarget=function() return b end,
GetStage=function(self) return self.stage end,SetStage=function(self,v) self.stage=v end}, {__index=TOOL})
assert(tool:RightClick({Hit=true,Entity=a})==false and tool.stage==2)
''')

    spec = importlib.util.spec_from_file_location('integrated_builder', root/'tools/build_release.py')
    builder = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(builder)

    def python_test(identifier, title, action):
        try:
            action(); status, observed = 'PASS', 'assertions passed'
        except Exception as exc:
            status, observed = 'FAIL', str(exc)
        results.append(dict(id=identifier,title=title,status=status,observed=observed,kind='actual Python release builder'))

    def output_guard():
        for name in ['README.md','LICENSE','generated.zip','lua/generated.zip']:
            path=root/name
            before=path.read_bytes() if path.exists() else None
            try:
                builder.build(root,path)
            except ValueError:
                pass
            else:
                raise AssertionError('Accepted an output under the source: '+name)
            assert (path.read_bytes() if path.exists() else None)==before
    python_test('I21','Release builder cannot overwrite documentation or other addon source files',output_guard)

    def atomic_failure():
        with tempfile.TemporaryDirectory() as tmp:
            output=Path(tmp)/'existing.zip';output.write_bytes(b'previous release')
            with patch.object(builder.zipfile.ZipFile,'writestr',side_effect=OSError('injected write failure')):
                try:
                    builder.build(root,output)
                except OSError:
                    pass
                else:
                    raise AssertionError('Injected error did not propagate')
            assert output.read_bytes()==b'previous release'
            assert sorted(p.name for p in Path(tmp).iterdir())==['existing.zip']
    python_test('I22','Packaging failure preserves an existing output and removes temporary files',atomic_failure)

    def symlink_guard():
        with tempfile.TemporaryDirectory() as tmp:
            output=Path(tmp)/'misleading.zip';output.symlink_to(root/'LICENSE')
            before=(root/'LICENSE').read_bytes()
            try:
                builder.build(root,output)
            except ValueError:
                pass
            else:
                raise AssertionError('A symlink to addon input was accepted as output')
            assert (root/'LICENSE').read_bytes()==before
    python_test('I23','Output symlinks cannot bypass source-overwrite protection',symlink_guard)

    report={'native_gmod_tested':False,'tests':results,
            'passed':sum(t['status']=='PASS' for t in results),'failed':sum(t['status']!='PASS' for t in results),
            'limits':'Actual source excerpts with explicit Lua 5.4 doubles, not native physics/rendering/prediction. No executable continue translation.'}
    output.parent.mkdir(parents=True,exist_ok=True)
    output.write_text(json.dumps(report,indent=2)+'\n',encoding='utf-8')
    for result in results:
        print(f"{result['status']} {result['id']}: {result['title']}")
        if result['status']!='PASS':
            print(result['observed'])
    print(f"{report['passed']}/{len(results)} integration checks (not native GMod)")
    return int(report['failed']!=0)


if __name__=='__main__':
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('source',type=Path,nargs='?',default=Path(__file__).resolve().parents[1])
    parser.add_argument('--output',type=Path,default=Path('integration_results.json'))
    args=parser.parse_args()
    raise SystemExit(main(args.source,args.output))
