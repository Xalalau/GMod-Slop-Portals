#!/usr/bin/env python3
"""Context-menu range regressions with API doubles, not native network acceptance."""
import argparse
import json
from pathlib import Path

from lua_support import Lua, normalize


def main(root, output):
    here = Path(__file__).resolve().parent
    base = (here / "stubs.lua").read_text() + (here / "custom_stubs.lua").read_text()
    for name in ("core", "aperture", "crossing"):
        base += "\ndo\n" + normalize((root / f"lua/seamless_portals/{name}.lua").read_text()) + "\nend\n"
    transform = (root / "lua/entities/seamless_portal/sh_init.lua").read_text()
    transform = transform[transform.index("SeamlessPortals.TransformPortal = function"):]
    base += "\ndo\n" + normalize(transform[:transform.index("-- Only render the portals")]) + "\nend\n"
    base += """
local SP=SeamlessPortals
local a,b=pair();b.pos=Vector(4000,0,0)
local p,e=player(),prop(Vector(4000,0,160))
function p:GetShootPos() return Vector(0,0,160) end
function e:OBBCenter() return (self.lo+self.hi)/2 end
function e:GetSolid() return self.solid or SOLID_VPHYSICS end
function e:GetSolidFlags() return self.solidflags or 0 end
SOLID_NONE,FSOLID_USE_TRIGGER_BOUNDS,FSOLID_CUSTOMRAYTEST=0,128,1
CreateConVar('seamless_portals_global_trace','1')
-- Native properties.CanBeTargeted contract, including its OBB range allowance.
properties={CanBeTargeted=function(ent,ply)
 if not IsValid(ent) or ent:IsPlayer() then return false end
 if IsValid(ply) then
  local mins,maxs=ent:OBBMins(),ent:OBBMaxs()
  local allowance=math.max(math.abs(mins.x)+maxs.x,math.abs(mins.y)+maxs.y,math.abs(mins.z)+maxs.z)
  if ent:LocalToWorld(ent:OBBCenter()):Distance(ply:GetShootPos())>1024+allowance then return false end
 end
 return not (ent:GetPhysicsObjectCount()<1 and ent:GetSolid()==SOLID_NONE
  and bit.band(ent:GetSolidFlags(),FSOLID_USE_TRIGGER_BOUNDS)==0
  and bit.band(ent:GetSolidFlags(),FSOLID_CUSTOMRAYTEST)==0)
end}
local native=properties.CanBeTargeted
local traces=0
SP.RawTraceLine=function(data)
 traces=traces+1
 assert(data.SeamlessIgnore and data.mask==MASK_SOLID)
 return {Hit=false,Fraction=1}
end
"""
    module = "\ndo\n" + normalize((root / "lua/seamless_portals/properties.lua").read_text()) + "\nend\n"
    cases = [
        ("portal-range", "A nearby portal path admits a prop rejected by world distance", """
assert(not native(e,p) and native(e))
assert(properties.CanBeTargeted(e,p) and traces==2)
"""),
        ("ordinary-targets", "Ordinary targets retain the native result without visibility scans", """
e:SetPos(Vector(100,0,160))
assert(properties.CanBeTargeted(e,p) and traces==0)
GetConVar('seamless_portals_global_trace'):SetInt(0)
assert(properties.CanBeTargeted(e,p) and properties.CanBeTargeted(e) and traces==0)
assert(not properties.CanBeTargeted(p,p) and not properties.CanBeTargeted(NULL,p))
"""),
        ("target-structure", "Portal range never admits players or entities without native target geometry", """
e.bodies={};e.solid=SOLID_NONE
assert(not properties.CanBeTargeted(e,p) and traces==0)
e.solidflags=FSOLID_CUSTOMRAYTEST
assert(properties.CanBeTargeted(e,p))
e.valid=false;assert(not properties.CanBeTargeted(e,p))
e.valid=true
function e:IsMarkedForDeletion() return true end
assert(not properties.CanBeTargeted(e,p))
"""),
        ("portal-occlusion", "Walls and start-solid hits on either physical segment reject remote actions", """
for _,blocked in ipairs({1,2}) do
 for _,solid in ipairs({false,true}) do
  traces=0
  SP.RawTraceLine=function(data)
   traces=traces+1
   assert(data.SeamlessIgnore)
   return {Hit=traces==blocked,Fraction=traces==blocked and .5 or 1,StartSolid=solid and traces==blocked}
  end
  assert(not properties.CanBeTargeted(e,p))
 end
end
"""),
        ("portal-admission", "Range, aperture edges, backfaces and disabled or removed links remain blocked", """
e:SetPos(Vector(4000,0,1000));assert(not properties.CanBeTargeted(e,p))
e:SetPos(Vector(4200,0,160));assert(not properties.CanBeTargeted(e,p))
e:SetPos(Vector(4000,0,-160));assert(not properties.CanBeTargeted(e,p))
e:SetPos(Vector(4000,0,160))
GetConVar('seamless_portals_global_trace'):SetInt(0);assert(not properties.CanBeTargeted(e,p))
GetConVar('seamless_portals_global_trace'):SetInt(1)
b.valid=false;assert(not properties.CanBeTargeted(e,p));b.valid=true
a:SetExitPortal(NULL);assert(not properties.CanBeTargeted(e,p))
a:SetExitPortal(b);assert(properties.CanBeTargeted(e,p))
"""),
        ("bounded-requests", "Remote requests share a per-player per-tick visibility budget", """
for i=1,16 do assert(properties.CanBeTargeted(e,p)) end
assert(traces==32)
for i=1,100 do assert(not properties.CanBeTargeted(e,p)) end
assert(traces==32)
TICK=TICK+1
assert(properties.CanBeTargeted(e,p) and traces==34)
"""),
        ("property-permission", "A property still applies its permission filter to the actual player and target", """
local permitted=false
hook.Add('CanProperty','test',function(ply,name,ent)
 assert(ply==p and name=='ignite' and ent==e)
 return permitted
end)
local function receive()
 if not properties.CanBeTargeted(e,p) then return end
 if not hook.Run('CanProperty',p,'ignite',e) then return end
 e.ignited=true
end
receive();assert(not e.ignited)
permitted=true;receive();assert(e.ignited)
"""),
        ("reload-ownership", "Refresh keeps one wrapper and shutdown preserves a later addon's wrapper", """
local owned=properties.CanBeTargeted
""" + module + """
assert(properties.CanBeTargeted==owned)
local calls=0
local outer=function(ent,ply)
 calls=calls+1
 if ent==e then return false end
 return owned(ent,ply)
end
properties.CanBeTargeted=outer
""" + module + """
assert(properties.CanBeTargeted==outer and not properties.CanBeTargeted(e,p) and calls==1)
hook.Run('ShutDown');assert(properties.CanBeTargeted==outer)
properties.CanBeTargeted=owned
hook.Run('ShutDown');assert(properties.CanBeTargeted==native)
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
        print(status, name, title)
        if status == "FAIL":
            print(observed)
    report = dict(native_gmod_tested=False, tests=results,
                  passed=sum(row["status"] == "PASS" for row in results),
                  failed=sum(row["status"] == "FAIL" for row in results))
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(json.dumps(report, indent=2) + "\n")
    return int(bool(report["failed"]))


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("source", type=Path)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    raise SystemExit(main(args.source, args.output))
