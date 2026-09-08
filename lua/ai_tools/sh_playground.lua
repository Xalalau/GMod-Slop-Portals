-- AI agents may run any tests they need in this file and may use it temporarily.
-- BEGIN SEAMLESS_PORTALS_AI_PROP_REST
do
local function probe()
local SP,AI=SeamlessPortals,SeamlessPortals.AI
local runID,phase='prop_wall_20260908_095837','surface_only'
if game.GetMap()~='gm_construct' or (SERVER and game.IsDedicated()) then return end
if AI[runID..phase] then return end
AI[runID..phase]=true
if AI.PropRestCleanup then AI.PropRestCleanup() end
local realm=SERVER and 'server' or 'client'
local dir='seamless_tests/'..runID
local ec=AI.ErrorCapture;local old=ec.logPath
ec.logPath=dir..'/'..phase..'_errors_'..realm..'.json';ec.Reset();ec.Install()
local report={convars={sv_gravity=GetConVar("sv_gravity"):GetFloat(),phys_timescale=GetConVar("phys_timescale"):GetFloat()},helpers_ready=AI.LoadedAt~=nil and AI.Realm==realm,run_id=runID,phase=phase,executed_at=os.date('!%Y-%m-%dT%H:%M:%SZ'),map=game.GetMap(),singleplayer=game.SinglePlayer(),cases={}}
local id='SEAMLESS_PORTALS_AI_PropRest_'..runID
local entities={}
local function clear()
 for _,e in ipairs(entities) do if IsValid(e) then e:Remove() end end
 entities={}
end
local function finish()
 timer.Remove(id);clear()
 ec.Flush(true);report.errors=ec.errors;ec.Cleanup();ec.logPath=old
 report.finished=os.date('!%Y-%m-%dT%H:%M:%SZ')
 file.Write(dir..'/'..phase..'_'..realm..'.json',util.TableToJSON(report,true))
 AI.PropRestCleanup=nil
end
AI.PropRestCleanup=finish
if CLIENT then
 local ok,err=pcall(include,'seamless_portals/tests/smoke.lua');report.smoke={ok=ok,error=err}
 timer.Create(id,16,1,finish);return
end
local originalENT=ENT
local reloaded,err=pcall(function()
 ENT={};include('entities/seamless_portal_cutout.lua');scripted_ents.Register(ENT,'seamless_portal_cutout')
 ENT={};include('entities/seamless_portal_clone.lua');scripted_ents.Register(ENT,'seamless_portal_clone')
end)
ENT=originalENT;report.reload={ok=reloaded,error=err}
local smokeok,smokeerr=pcall(include,'seamless_portals/tests/smoke.lua');report.smoke={ok=smokeok,error=smokeerr}
local function add(e) entities[#entities+1]=e;return e end
local function portal(pos,ang)
 local e=add(ents.Create('seamless_portal'));e:SetPos(pos);e:SetAngles(ang);e:Spawn();e:Configure(Vector(100,147.1,8),4,false);return e
end
local function makeProp(model,pos,ang)
 local e=add(ents.Create('prop_physics'));e:SetModel(model);e:SetPos(pos);e:SetAngles(ang);e:Spawn();e:Activate()
 local probe=pos+Vector(pos.x>0 and -32 or 32,0,0)
 local ground=SP.RawTraceLine({start=probe,endpos=probe-Vector(0,0,256),mask=MASK_SOLID_BRUSHONLY,filter=function() return false end})
 local minimum=e:WorldSpaceAABB();e:SetPos(pos+Vector(0,0,ground.HitPos.z-minimum.z+24));e:GetPhysicsObject():Wake()
 return e
end
local cases={{name='near_crate',gap=2,model='models/props_junk/wood_crate001a.mdl',angle=Angle(7,20,5)}}
local index,began,row,a,b,prop,body,control,verts,supports
local function setup()
 clear();index=(index or 0)+1
 local case=cases[index];if not case then finish();return false end
 local source=Vector(1024-case.gap,-430,-93.86875);local dest=Vector(-1024+case.gap,-430,-93.86875)
 a=portal(source,Angle(90,180,0));b=portal(dest,Angle(90,0,0));a:SetExitPortal(b);b:SetExitPortal(a);a:UpdateCutout()
 local generate=CompileString([==[
local ENT={}
ENT.Type = "anim"
ENT.Base = "base_anim"

ENT.Category          = "Seamless Portals"
ENT.PrintName         = "Cutout"
ENT.Author            = "Meetric"
ENT.Purpose           = ""
ENT.Instructions      = ""
ENT.DisableDuplicator = true
ENT.ENTITIES          = {}
ENT.VERTICES          = {}

SeamlessPortals.CutoutMeshRevision = 2

-- SERVER only entity
-- physically cuts a hole in the world,
-- code reused from Earthbending

-- tris are in the format {pos1, pos2, pos3, ...}
-- code based on Glass: Rewrite
local function cut_concave(tris, plane_pos, plane_dir)
	plane_dir = plane_dir:GetNormalized()

	local split_tris = {}
	local intersect = util.IntersectRayWithPlane

	local function inside(p)
		return (p - plane_pos):Dot(plane_dir) >= 0
	end

	-- sutherland-hodgman
	local function clip(poly)
		local result = {}

		for i = 1, #poly do
			local a = poly[i] -- current
			local b = poly[i % #poly + 1] -- previous
			local a_in = inside(a)
			local b_in = inside(b)

			if a_in and b_in then
				result[#result + 1] = b
			elseif a_in then
				result[#result + 1] = intersect(a, b - a, plane_pos, plane_dir) or b
			elseif b_in then
				result[#result + 1] = intersect(a, b - a, plane_pos, plane_dir) or b
				result[#result + 1] = b
			end
		end

		return result
	end

	for i = 1, #tris, 3 do
		local poly = clip({
			tris[i    ],
			tris[i + 1],
			tris[i + 2]
		})

		for j = 2, #poly - 1 do
			split_tris[#split_tris + 1] = poly[1    ]
			split_tris[#split_tris + 1] = poly[j    ]
			split_tris[#split_tris + 1] = poly[j + 1]
		end
	end

	return split_tris
end

-- __eq vector comparisons are too precise
local function vector_equal(v0, v1)
    return (v0 - v1):LengthSqr() < 1e-3
end

local function trace_local(self, start_pos, end_pos)
	local tr_table = {
        start = self:LocalToWorld(start_pos),
        endpos = self:LocalToWorld(end_pos),
        mask = MASK_SOLID_BRUSHONLY,
        filter = function() return false end, -- exclude entities; world is traced separately
    }

    local tr = SeamlessPortals.TraceLine(tr_table)

	if tr.Fraction == 1 and tr.StartSolid then
		return start_pos
	end

    return self:WorldToLocal(tr.HitPos)
end

function ENT:SetPortal(portal)
	self.SEAMLESS_PORTALS_CUTOUT_PORTAL = portal
end

function ENT:GetPortal()
	return self.SEAMLESS_PORTALS_CUTOUT_PORTAL
end

function ENT:Initialize()
	self.ENTITIES, self.VERTICES, self.PROXIES = {}, {}, {}
	self.SEAMLESS_PORTALS_READY = false
    self:SetCollisionGroup(COLLISION_GROUP_PASSABLE_DOOR) -- props only
    self:SetTrigger(true)
end

-- approximates the world surface with a hole cut into it
function ENT:GeneratePhysmesh(portal, exit_portal)
	local size = portal:GetSize()
	local offset = size / 2
	local aperture_min, aperture_max = SeamlessPortals.GetApertureBounds(size, portal:GetSides())

	if exit_portal then self.VERTICES = {} end
	local vertices = {}

	local function pos_local(x, y, z)
		-- These surface probes extend past the aperture. GMod Lerp clamps to
		-- [0, 1], which misses floors even slightly below the portal's bottom.
		return Vector(aperture_min.x + x * (aperture_max.x - aperture_min.x),
			aperture_min.y + y * (aperture_max.y - aperture_min.y), z - size[3])
	end

	local inset = -2
	local pos00 = pos_local(0, 0, inset)
	local pos10 = pos_local(1, 0, inset)
	local pos01 = pos_local(0, 1, inset)
	local pos11 = pos_local(1, 1, inset)

	local function generate_tri(pos0, pos1, pos2)
		-- check for degen triangles
		if vector_equal(pos0, pos1) or vector_equal(pos0, pos2) or vector_equal(pos1, pos2) then return end

		local len = #vertices
		vertices[len + 1] = pos0
		vertices[len + 2] = pos1
		vertices[len + 3] = pos2
	end

	local function generate_quad(pos0, pos1, pos2, pos3)
		-- check for degen triangles
		if vector_equal(pos0, pos1) or vector_equal(pos0, pos3) or vector_equal(pos1, pos3) then return end
		if vector_equal(pos3, pos2) or vector_equal(pos3, pos0) or vector_equal(pos2, pos0) then return end

		local len = #vertices
		vertices[len + 1] = pos0
		vertices[len + 2] = pos1
		vertices[len + 3] = pos3
		vertices[len + 4] = pos3
		vertices[len + 5] = pos2
		vertices[len + 6] = pos0
	end

	local function trace_local_generate_quad(start_pos, end_pos)
		local tr = SeamlessPortals.TraceLine({
			start = portal:LocalToWorld(start_pos),
			endpos = portal:LocalToWorld(end_pos),
			mask = MASK_SOLID_BRUSHONLY,
        filter = function() return false end, -- exclude entities; world is traced separately
		})

		-- A trace born inside the mounting wall has no usable surface normal.
        if not tr.Hit or tr.StartSolid or tr.AllSolid or tr.HitNormal:LengthSqr() < 0.5 then return nil end

		tr.HitAngle = portal:WorldToLocalAngles(tr.HitNormal:Angle())
		tr.HitPos = portal:WorldToLocal(tr.HitPos)

		local right = tr.HitAngle:Right() * math.max(size[1], size[2]) * 1.5
		local front = tr.HitAngle:Up() * math.max(size[1], size[2]) * 1.5
		generate_quad(tr.HitPos - front + right, tr.HitPos + front + right, tr.HitPos - front - right, tr.HitPos + front - right)
	end

    -- Sample the visible room. The decorative slab extends behind z=0 and
    -- may already be inside the wall that this opening is meant to remove.
    local surface_z = size.z + 0.5
    local surface_start = pos_local(0.5, 0.5, surface_z)
    trace_local_generate_quad(surface_start, pos_local(2.5, 0.5, surface_z))
    trace_local_generate_quad(surface_start, pos_local(-1.5, 0.5, surface_z))
    trace_local_generate_quad(surface_start, pos_local(0.5, 2.5, surface_z))
    trace_local_generate_quad(surface_start, pos_local(0.5, -1.5, surface_z))
    trace_local_generate_quad(surface_start, pos_local(0.5, 0.5, offset[1] * 3))


	if #vertices <= 0 then return end

	vertices = cut_concave(vertices, vector_origin, Vector(0, 0, 1))

	if exit_portal then -- invert cut
		local ratio = exit_portal:GetSize()[1] / portal:GetSize()[1]
		local negated_verts = {}
		for _, v in ipairs(vertices) do
			if !negated_verts[v] then
				v[2] = -v[2]
				v[3] = -v[3]
				v:Mul(ratio)
				negated_verts[v] = true
			end
		end
	end

	--[[
	for i = 1, #vertices, 3 do
		debugoverlay.Triangle(
			self:LocalToWorld(vertices[i]), self:LocalToWorld(vertices[i + 1]), self:LocalToWorld(vertices[i + 2]),
			0.5, Color(255, 255, 255, 5), false
		)
	end]]

    for _, v in ipairs(vertices) do
    	table.insert(self.VERTICES, v)
    end
end


return ENT.GeneratePhysmesh
]==],'prop_wall_surface_fixture',false)()
 for _,p in ipairs({a,b}) do
  local c=p.SEAMLESS_PORTALS_CUTOUT;c.VERTICES={}
  generate(c,p:GetExitPortal(),p);generate(c,p)
  assert(c:CreatePhysmesh())
 end
 row={name=case.name,gap=case.gap,samples={},entry=tostring(source),exit=tostring(dest)};report.cases[#report.cases+1]=row
 supports={}
 if case.name=='remove_support' then
  for _,pos in ipairs({source,dest}) do
   local e=makeProp('models/props_junk/wood_crate001a.mdl',pos,Angle())
   e:SetPos(e:GetPos()-Vector(0,0,24));e:GetPhysicsObject():EnableMotion(false);supports[#supports+1]=e
  end
 end
 prop=makeProp(case.model,source,case.angle)
 if case.name=='remove_support' then prop:SetPos(prop:GetPos()+Vector(0,0,19)) end
 control=makeProp(case.model,source-Vector(100,0,0),case.angle)
 body=prop:GetPhysicsObject();verts={}
 for _,poly in ipairs(body:GetMeshConvexes() or {}) do for _,v in ipairs(poly) do verts[#verts+1]=v.pos end end
 a.SEAMLESS_PORTALS_CUTOUT:AddEntity(prop)
 began=CurTime();return true
end
if not setup() then return end
timer.Create(id,.05,0,function()
 local t=CurTime()-began
 if IsValid(prop) then
  local cp=control:GetPhysicsObject();local clone=prop.SEAMLESS_PORTALS_CLONE
  local s={mass=body:GetMass(),transfer=prop.SEAMLESS_PORTALS_LAST_TRANSFER,interfered=prop:IsPlayerHolding() or SP.HasTrackedHold(prop),motion=body:IsMotionEnabled(),time=t,pos=tostring(prop:GetPos()),angle=tostring(prop:GetAngles()),speed=body:GetVelocity():Length(),angular=body:GetAngleVelocity():Length(),asleep=body:IsAsleep(),control_speed=cp:GetVelocity():Length(),control_angular=cp:GetAngleVelocity():Length(),control_asleep=cp:IsAsleep(),clone=IsValid(clone),same_body=body==prop:GetPhysicsObject(),owner=tostring(prop.SEAMLESS_PORTALS_CUTOUT)}
  if IsValid(clone) then
   local pb=clone:GetPhysicsObject();local pos,ang=SP.TransformPortal(clone:GetPortal2(),clone:GetPortal1(),pb:GetPos(),pb:GetAngles())
   local delta=prop:WorldToLocalAngles(ang)
   s.delta=(body:GetPos()-pos):Length();s.angle_error=tostring(delta);s.clone_speed=pb:GetVelocity():Length();s.clone_angular=pb:GetAngleVelocity():Length();s.clone_asleep=pb:IsAsleep()
  end
  local probe=prop:GetPos()+Vector(prop:GetPos().x>0 and -32 or 32,0,0)
  local ground=SP.RawTraceLine({start=probe+Vector(0,0,64),endpos=probe-Vector(0,0,128),mask=MASK_SOLID_BRUSHONLY,filter=function() return false end})
  local clearance=math.huge
  if ground.Hit and not ground.StartSolid then for _,v in ipairs(verts) do clearance=math.min(clearance,(prop:LocalToWorld(v)-ground.HitPos):Dot(ground.HitNormal)) end end
  s.contacts={}
  for i,contact in ipairs(body:GetFrictionSnapshot()) do if i>16 then break end
   s.contacts[#s.contacts+1]={entity=tostring(contact.Other:GetEntity()),normal=tostring(contact.Normal),point=tostring(contact.ContactPoint)}
  end
  s.clearance=SP.IsFinite(clearance) and clearance or nil;row.samples[#row.samples+1]=s
  if t>6 and not row.action then
   if row.name=='source_push' or row.name=='remote_push' then
    local target=row.name=='remote_push' and IsValid(clone) and clone:GetPhysicsObject() or body
    row.action={time=t,before=s,target_is_clone=target~=body}
    target:Wake();target:SetVelocity(Vector(0,30,40))
   elseif row.name=='remove_support' then
    row.action={time=t,before=s}
    for _,e in ipairs(supports) do if IsValid(e) then e:Remove() end end
   end
  end
 end
 if t>12 then setup() end
end)
end
probe()
end
-- END SEAMLESS_PORTALS_AI_PROP_REST

-- BEGIN SEAMLESS_PORTALS_AI_GRAVITY_LIVE
do
local function probe()
local SP,AI=SeamlessPortals,SeamlessPortals.AI
local runID='gravity_live_20260908_093827'
if AI[runID..'_watch4'] then return end
AI[runID..'_watch4']=true
if AI.GravityLiveCleanup then AI.GravityLiveCleanup() end
local realm=SERVER and (game.IsDedicated() and 'dedicated' or 'server') or 'client'
local dir='seamless_tests/'..runID
local report={run_id=runID,executed_at=os.date('!%Y-%m-%dT%H:%M:%SZ'),map=game.GetMap(),realm=realm,samples={},commands={},renders={},calls=0}
local ec=AI.ErrorCapture
local oldPath,oldErrors,oldDirty=ec.logPath,ec.errors,ec.dirty
local installed=hook.GetTable().OnLuaError and hook.GetTable().OnLuaError[ec.hookName]~=nil
ec.logPath=dir..'/watch4_errors_'..realm..'.json';ec.Reset();ec.Install()
include('seamless_portals/gravitygun.lua')
if SERVER then include('seamless_portals/remote_pickup.lua') end
include('seamless_portals/tests/smoke.lua')
local id='SEAMLESS_PORTALS_AI_GravityLive_'..runID
local started=CurTime()
local function traceRow(p,ent)
 local eye=p:GetShootPos();local aim=p:EyeAngles();aim.p=math.Clamp(math.NormalizeAngle(aim.p),-75,75)
 local direction=aim:Forward();local phys=ent:GetPhysicsObject()
 local row={time=CurTime()-started,tick=engine.TickCount(),eye=tostring(eye),player=tostring(p:GetPos()),angles=tostring(p:EyeAngles()),offset=tostring(p:GetCurrentViewOffset()),hull=tostring(p:OBBMaxs()),saved=tostring(p.SEAMLESS_PORTALS_HULL_MAXS),pos=tostring(ent:GetPos()),center=tostring(ent:WorldSpaceCenter()),distance=ent:WorldSpaceCenter():Distance(eye),model=ent:GetModel(),block=p.SEAMLESS_PORTALS_TRANSPORT_BLOCKED,ent_block=ent.SEAMLESS_PORTALS_TRANSPORT_BLOCKED,physical=IsValid(phys),carry=SP.Holds[p] and tostring(SP.Holds[p].entry)}
 if IsValid(phys) then
  row.motion=phys:IsMotionEnabled();row.phys_pos=tostring(phys:GetPos())
  local mesh=phys:GetMesh();row.mesh=mesh and #mesh
  if mesh then
   local localDir=ent:WorldToLocal(ent:GetPos()+direction);local minimum=math.huge
   for _,v in ipairs(mesh) do minimum=math.min(minimum,v.pos:Dot(localDir)) end
   local radius=p:OBBMaxs():Length2D()+math.abs(minimum)
   local saved=p.SEAMLESS_PORTALS_HULL_MAXS
   row.radius=radius;row.desired=24+(saved and saved:Length2D() or p:OBBMaxs():Length2D())+math.abs(minimum)
   local tr=SP.RawTraceLine({start=eye,endpos=eye+direction*(24+radius*2),mask=MASK_SOLID_BRUSHONLY,filter={p,ent}})
   row.brush={fraction=tr.Fraction,startsolid=tr.StartSolid,hit=tostring(tr.HitPos),entity=tostring(tr.Entity)}
   local crossing=SP.FirstCrossing(eye,direction*row.desired,'props')
   if crossing then
    row.entry=tostring(crossing.entry);row.entry_pos=tostring(crossing.entry:GetPos());row.entry_angle=tostring(crossing.entry:GetAngles());row.depth=SP.PlaneDistance(crossing.entry,eye)
    local front=SP.RawTraceLine({start=eye,endpos=crossing.point,mask=MASK_SOLID_BRUSHONLY,filter={p,ent}})
    row.front={fraction=front.Fraction,startsolid=front.StartSolid,allsolid=front.AllSolid,distance=front.HitPos:Distance(crossing.point)}
   end
  end
 end
 local clone=ent.SEAMLESS_PORTALS_CLONE
 if IsValid(clone) then row.clone=tostring(clone:GetPos()) end
 return row
end
local original=hook.GetTable().StartCommand.seamless_portals_gravitygun_grip
local wrapper
wrapper=function(p,cmd)
 local record=SP.GetHeldRecord(p)
 local weapon=IsValid(p) and p:GetActiveWeapon()
 local should=p:IsBot()==false and record and IsValid(record.entity) and IsValid(weapon) and weapon:GetClass()=='weapon_physcannon'
 local row=should and traceRow(p,record.entity)
 original(p,cmd)
 report.calls=report.calls+1
 if row and #report.commands<20000 then
  local pending=SP.GravityGripOffsets[p];row.applied=pending and tostring(pending.applied-pending.original);row.native_hull=pending and pending.hulls and tostring(p:OBBMaxs());row.native_angles=tostring(p:EyeAngles())
  report.commands[#report.commands+1]=row
 end
end
hook.Add('StartCommand','seamless_portals_gravitygun_grip',wrapper)
local function write()
 report.errors=ec.errors;report.updated=os.date('!%Y-%m-%dT%H:%M:%SZ')
 file.Write(dir..'/watch4_'..realm..'.json',util.TableToJSON(report,true))
end
local function finish()
 timer.Remove(id);hook.Remove('PostDrawOpaqueRenderables',id)
 if hook.GetTable().StartCommand.seamless_portals_gravitygun_grip==wrapper then hook.Add('StartCommand','seamless_portals_gravitygun_grip',original) end
 ec.Flush(true);report.finished=true;write()
 if not installed then ec.Cleanup() end
 ec.logPath=oldPath;ec.errors=oldErrors;ec.dirty=oldDirty
 AI.GravityLiveCleanup=nil
end
AI.GravityLiveCleanup=finish
if CLIENT then
 local last=0
 hook.Add('PostDrawOpaqueRenderables',id,function(_,sky)
  if sky or SP.Rendering or RealTime()-last<.1 then return end
  local p=LocalPlayer();if not IsValid(p) then return end
  local r=SP.GetHeldRecord(p);local ent=r and r.entity
  if not IsValid(ent) then return end
  last=RealTime()
  report.renders[#report.renders+1]={time=CurTime()-started,eye=tostring(EyePos()),distance=ent:WorldSpaceCenter():Distance(EyePos()),position=tostring(ent:GetPos()),origin=tostring(ent:GetRenderOrigin()),eye_player=tostring(p:EyePos())}
 end)
end
timer.Create(id,.1,0,function()
 for _,p in ipairs(player.GetHumans()) do
  local record=SP.GetHeldRecord(p);local ent=record and record.entity
  if IsValid(ent) then report.samples[#report.samples+1]=traceRow(p,ent) end
 end
 if CurTime()-started>300 then finish() elseif math.floor((CurTime()-started)*10)%10==0 then write() end
end)
write()
end
probe()
end
-- END SEAMLESS_PORTALS_AI_GRAVITY_LIVE



-- BEGIN SEAMLESS_PORTALS_AI_GRAVITY_ANGLES
do
local function probe()
local SP,AI=SeamlessPortals,SeamlessPortals.AI
local run='gravity_live_20260908_093827'
if not SERVER or AI[run..'_angles'] then return end
AI[run..'_angles']=true
local realm=game.IsDedicated() and 'dedicated' or 'server'
local p=player.GetHumans()[1];if not IsValid(p) then return end
local original,absolute,localAngles=Angle(p:EyeAngles()),Angle(p:GetAngles()),Angle(p:GetLocalAngles())
local report={}
local function row(name) report[name]={eye=tostring(p:EyeAngles()),absolute=tostring(p:GetAngles()),localAngles=tostring(p:GetLocalAngles()),axis=tostring(p:LocalToWorld(Vector(1,0,0))-p:GetPos())} end
row('before');p:SetEyeAngles(Angle(-75,original.y,original.r));row('eye_changed');p:SetAngles(absolute);row('body_restored');p:SetLocalAngles(localAngles);row('local_restored');p:SetEyeAngles(original);row('after')
file.Write('seamless_tests/'..run..'/angles_'..realm..'.json',util.TableToJSON(report,true))
end
probe()
end
-- END SEAMLESS_PORTALS_AI_GRAVITY_ANGLES



-- BEGIN SEAMLESS_PORTALS_AI_GRAVITY_TRACEPROBE
do
local function probe()
local SP,AI=SeamlessPortals,SeamlessPortals.AI
local run='gravity_live_20260908_093827'
if not SERVER or AI[run..'_trace3'] then return end
AI[run..'_trace3']=true
local realm=game.IsDedicated() and 'dedicated' or 'server'
local pos=game.IsDedicated() and Vector(6144,4096,-12000) or Vector(0,0,800)
local e=ents.Create('func_brush');e:SetModel('*0');e:SetPos(pos);e:Spawn();e:PhysicsInitBox(Vector(-4,-4,-4),Vector(4,4,4));e:SetSolid(SOLID_VPHYSICS);e:SetNoDraw(true);e:EnableCustomCollisions(true);e:SetCollisionBounds(Vector(-4,-4,-4),Vector(4,4,4))
local body=e:GetPhysicsObject();body:EnableMotion(false)
local report={traces={},calls={}}
e.TestCollision=function(self,start,delta,isbox,extents,mask)
 report.calls[#report.calls+1]={mask=mask,box=isbox};return {HitPos=start+delta*.01,Normal=Vector(-1,0,0),Fraction=.01}
end
local function trace(label)
 local tr=SP.RawTraceLine({start=pos-Vector(8,0,0),endpos=pos+Vector(64,0,0),mask=MASK_SOLID_BRUSHONLY})
 report.traces[#report.traces+1]={label=label,hit=tr.Hit,entity=tostring(tr.Entity),fraction=tr.Fraction,startsolid=tr.StartSolid,contents=body:GetContents()}
end
timer.Simple(.1,function()
trace('default');body:SetContents(CONTENTS_SOLID);trace('solid');body:EnableCollisions(false);trace('no_physics');e:SetNotSolid(true);trace('not_solid');e:Remove()
file.Write('seamless_tests/'..run..'/trace3_'..realm..'.json',util.TableToJSON(report,true))
end)
end
probe()
end
-- END SEAMLESS_PORTALS_AI_GRAVITY_TRACEPROBE



-- BEGIN SEAMLESS_PORTALS_AI_GRAVITY_BLOCKS
do
local function probe()
local SP,AI=SeamlessPortals,SeamlessPortals.AI
local run='gravity_live_20260908_093827'
if not SERVER or AI[run..'_blocks'] then return end
AI[run..'_blocks']=true
local realm=game.IsDedicated() and 'dedicated' or 'server'
local report={run_id=run,events={}}
local original=SP.PlanTransport
local wrapper
wrapper=function(root,entry,exit,holder,...)
 local r=IsValid(holder) and SP.GetHeldRecord(holder)
 if not r or r.kind~='gravgun' or holder:IsBot() then return original(root,entry,exit,holder,...) end
 local trace=util.TraceHull;local rows={};local raw
 raw=function(data,...)
  local tr=trace(data,...)
  rows[#rows+1]={start=tostring(data.start),mins=tostring(data.mins),maxs=tostring(data.maxs),mask=data.mask,entity=tostring(tr.Entity),hit=tr.Hit,startsolid=tr.StartSolid,allsolid=tr.AllSolid,pos=tostring(tr.HitPos),normal=tostring(tr.HitNormal)}
  return tr
 end
 util.TraceHull=raw
 local args={...};local ok,plan,reason=xpcall(function() return original(root,entry,exit,holder,unpack(args)) end,debug.traceback)
 if util.TraceHull==raw then util.TraceHull=trace end
 if not ok then error(plan) end
 if #report.events<600 then report.events[#report.events+1]={time=CurTime(),reason=reason,traces=rows,player=tostring(holder:GetPos()),root=tostring(root:GetPos())} end
 file.Write('seamless_tests/'..run..'/blocks_'..realm..'.json',util.TableToJSON(report,true))
 return plan,reason
end
SP.PlanTransport=wrapper
AI.GravityBlocksCleanup=function() if SP.PlanTransport==wrapper then SP.PlanTransport=original end AI.GravityBlocksCleanup=nil end
end
probe()
end
-- END SEAMLESS_PORTALS_AI_GRAVITY_BLOCKS





-- BEGIN SEAMLESS_PORTALS_AI_GRAVITY_WALLPAIR
do
local function probe()
local SP,AI=SeamlessPortals,SeamlessPortals.AI
local runID='gravity_live_20260908_093827'
local realm=SERVER and (game.IsDedicated() and 'dedicated' or 'server') or 'client'
if AI[runID..'_firm3'] then return end
AI[runID..'_firm3']=true
local ec=AI.ErrorCapture
local oldPath,oldErrors,oldDirty=ec.logPath,ec.errors,ec.dirty
local installed=hook.GetTable().OnLuaError and hook.GetTable().OnLuaError[ec.hookName]~=nil
local dir='seamless_tests/'..runID
local report={run_id=runID,executed_at=os.date('!%Y-%m-%dT%H:%M:%SZ'),realm=realm,map=game.GetMap(),events={},samples={},sounds={}}
ec.logPath=dir..'/firm3_errors_'..realm..'.json';ec.Reset();ec.Install()
file.Write(dir..'/firm3_started_'..realm..'.json',util.TableToJSON(report,true))
local function save()
 ec.Flush(true);report.errors=ec.errors
 file.Write(dir..'/firm3_'..realm..'.json',util.TableToJSON(report,true))
 if not installed then ec.Cleanup() end
 ec.logPath=oldPath;ec.errors=oldErrors;ec.dirty=oldDirty
end
if SERVER then AddCSLuaFile('seamless_portals/gravitygun.lua') end




if SERVER then include('seamless_portals/held_proxy.lua');include('seamless_portals/remote_pickup.lua') end
if not SERVER or not game.IsDedicated() then include('seamless_portals/tests/smoke.lua');report.smoke=true;save();return end
local p=player.CreateNextBot('Gravity gun portal test')
if not IsValid(p) then report.error='bot_creation_failed';save();return end
local id='SEAMLESS_PORTALS_AI_Gravitygun_'..runID
local ground=SP.RawTraceLine({start=Vector(6144,4096,-11000),endpos=Vector(6144,4096,-15000)})
local wall=SP.RawTraceLine({start=Vector(2048,0,-12680),endpos=Vector(0,0,-12680),mask=MASK_SOLID_BRUSHONLY})
report.wall={hit=wall.Hit,pos=wall.HitPos,normal=wall.HitNormal}
if not wall.Hit then p:Kick('No fixture wall');save();return end
local origin=wall.HitPos+wall.HitNormal*35-Vector(0,0,64)
local look=(-wall.HitNormal):Angle();look.p=-11.5
p:SetPos(origin);p:SetEyeAngles(look);p:SetMoveType(MOVETYPE_NOCLIP);p:AddFlags(FL_NOTARGET)
p:Give('weapon_physcannon');p:SelectWeapon('weapon_physcannon')
local eye=p:EyePos()
local function portal(pos,ang)
 local e=ents.Create('seamless_portal');e:SetPos(pos);e:SetAngles(ang);e:Spawn();e:Configure(Vector(100,147.1,8),4,false);return e
end
local a=portal(wall.HitPos+wall.HitNormal*9,wall.HitNormal:Angle()+Angle(90,0,0))
local exitWall=SP.RawTraceLine({start=Vector(400,2048,-12680),endpos=Vector(400,0,-12680),mask=MASK_SOLID_BRUSHONLY})
local b=portal(exitWall.HitPos+exitWall.HitNormal*9,exitWall.HitNormal:Angle()+Angle(90,0,0))
a:SetExitPortal(b);b:SetExitPortal(a)
local target=ents.Create('prop_physics');target:SetModel('models/props_junk/metalbucket01a.mdl');target:SetPos(SP.TransformPortal(a,b,eye+p:GetAimVector()*110));target:Spawn();target:SetHealth(10000)
local phys=target:GetPhysicsObject();phys:EnableGravity(false);report.original_mass=phys:GetMass()
report.brush_traces={}
local nativeTest=a.TestCollision
a.TestCollision=function(self,start,delta,isbox,extents,mask)
 if not isbox and mask==MASK_SOLID_BRUSHONLY and #report.brush_traces<1024 then report.brush_traces[#report.brush_traces+1]={tick=engine.TickCount(),start=start,delta=delta,holding=target:IsPlayerHolding()} end
 return nativeTest(self,start,delta,isbox,extents,mask)
end
local started=CurTime();local phase='grab'
local previousOffset
local function restore(ply)
 if ply==p and previousOffset then ply:SetCurrentViewOffset(previousOffset);previousOffset=nil end
end
hook.Add('SetupMove',id,restore)
local mesh=phys:GetMesh();local lo,hi=phys:GetAABB()
report.geometry={aabb_min=tostring(lo),aabb_max=tostring(hi),obb_min=tostring(target:OBBMins()),obb_max=tostring(target:OBBMaxs()),vertices=mesh and #mesh}
local function offset()
 restore(p)
 if not target:IsPlayerHolding() then return end
 local direction=p:GetAimVector()
 local minimum=math.huge
 for _,v in ipairs(mesh or {}) do local q=Vector(v.pos);q:Rotate(target:GetAngles());minimum=math.min(minimum,q:Dot(direction)) end
 local radius=p:OBBMaxs():Length2D()+math.abs(minimum)
 local desired=24+math.sqrt(16*16*2)+math.abs(minimum)
 local function hit(shift)
  local start=p:GetShootPos()+direction*shift
  local tr=SP.RawTraceLine({start=start,endpos=start+direction*(24+radius*2),filter={p,target},mask=MASK_SOLID_BRUSHONLY})
  return tr.Fraction<.5
 end
 local shift=desired-(24+radius)
 if hit(shift) then shift=desired-radius*.5 end
 report.last_target={radius=radius,desired=desired,shift=shift,short=hit(shift)}
 if false and phase~='grab' then previousOffset=p:GetCurrentViewOffset();p:SetCurrentViewOffset(previousOffset+direction*shift) end
end

for _,event in ipairs({'GravGunPunt','GravGunPickupAllowed','GravGunOnPickedUp','GravGunOnDropped'}) do
 hook.Add(event,id,function(ply,e)
  if ply~=p then return end
  if event~='GravGunPickupAllowed' or #report.events<60 then report.events[#report.events+1]={phase=phase,event=event,entity=tostring(e),time=CurTime()-started} end
  if event=='GravGunOnPickedUp' then phase='held' end
 end)
end
hook.Add('EntityTakeDamage',id,function(e,info)
 if e==a or e==target then report.events[#report.events+1]={phase=phase,event='damage',entity=tostring(e),damage=info:GetDamage(),kind=info:GetDamageType()} end
end)
hook.Add('EntityEmitSound',id,function(t)
 if t.Entity==p or t.Entity==p:GetActiveWeapon() then report.sounds[#report.sounds+1]={phase=phase,name=t.SoundName,original=t.OriginalSoundName} end
end)
hook.Add('StartCommand',id,function(ply,cmd)
 if ply~=p then return end
 cmd:ClearButtons();cmd:ClearMovement();cmd:SetViewAngles(ply:EyeAngles());offset()
 if phase=='cross' then cmd:SetForwardMove(3) end
 local elapsed=CurTime()-started
 if phase=='after' and elapsed>4 and elapsed<6 then
  report.base_angle=report.base_angle or Angle(p:EyeAngles());local look=Angle(report.base_angle);look.y=look.y+math.sin((elapsed-4)*8)*35;p:SetEyeAngles(look);cmd:SetViewAngles(look)
 elseif phase=='after' and elapsed>=6 and report.base_angle then p:SetEyeAngles(report.base_angle);cmd:SetViewAngles(report.base_angle) end
 if phase=='after' and elapsed>7 and elapsed<7.1 then cmd:SetButtons(IN_ATTACK) end
 if elapsed>.7 and elapsed<1.1 then cmd:SetButtons(IN_ATTACK2)
 elseif phase=='pull' then cmd:SetButtons(IN_ATTACK2) end
end)
local function finish()
 timer.Remove(id);restore(p);hook.Remove('SetupMove',id)
 for _,name in ipairs({'StartCommand','EntityTakeDamage','EntityEmitSound','GravGunPunt','GravGunPickupAllowed','GravGunOnPickedUp','GravGunOnDropped'}) do hook.Remove(name,id) end
 report.final_mass=phys:GetMass();for _,e in ipairs({target,a,b}) do if IsValid(e) then e:Remove() end end
 if IsValid(p) then p:Kick('Gravity gun test complete') end
 report.audit=SP.CarryAudit[p];report.finished=os.date('!%Y-%m-%dT%H:%M:%SZ');save();AI.GravitygunProbeCleanup=nil
end
AI.GravitygunProbeCleanup=finish
timer.Create(id,engine.TickInterval(),0,function()
 if not IsValid(p) or not IsValid(target) then finish();return end
 local weapon=p:GetActiveWeapon();local vm=p:GetViewModel()
 local tr=SP.RawTraceLine({start=p:EyePos(),endpos=p:EyePos()+p:GetAimVector()*120,filter={p,target},mask=MASK_SOLID_BRUSHONLY})
 report.last_brush=tostring(tr.Entity)..' '..tostring(tr.Fraction)
 
 local elapsed=CurTime()-started
 if phase=='held' and elapsed>3 then phase='cross' end
 if phase=='cross' and p:GetPos():DistToSqr(origin)>1000^2 then phase='after' end
 local actual=SP.GetHeldRecord(p)
 if actual and actual.nativePickup and elapsed>3.5 then local h=actual.controllerEntity:GetPhysicsObject();h:SetMass(16) end
 report.samples[#report.samples+1]={body_angle=tostring(target:GetAngles()),handle_pos=actual and IsValid(actual.controllerEntity) and tostring(actual.controllerEntity:GetPos()),mass=phys:GetMass(),angular=tostring(phys:GetAngleVelocity()),controller=actual and tostring(actual.controllerEntity),native=actual and actual.nativePickup and actual.nativePickup.confirmed,kind=actual and actual.kind,entry_depth=SP.PlaneDistance(a,target:WorldSpaceCenter()),proxy=IsValid(target.SEAMLESS_PORTALS_CLONE) and tostring(target.SEAMLESS_PORTALS_CLONE:GetPos()),phase=phase,time=CurTime()-started,target=report.last_target,eye=tostring(p:EyePos()),distance=target:WorldSpaceCenter():Distance(p:EyePos()),brush=report.last_brush,velocity=tostring(phys:GetVelocity()),position=tostring(target:GetPos()),player=tostring(p:GetPos()),angle=tostring(p:EyeAngles()),same_body=target:GetPhysicsObject()==phys,blocked=p.SEAMLESS_PORTALS_TRANSPORT_BLOCKED,carry=SP.Holds[p] and tostring(SP.Holds[p].entry),held=actual and actual.entity==target or false,activity=IsValid(vm) and vm:GetSequenceActivity(vm:GetSequence()),nextprimary=IsValid(weapon) and weapon:GetNextPrimaryFire(),nextsecondary=IsValid(weapon) and weapon:GetNextSecondaryFire()}
 if CurTime()-started>1.5 and phase=='punt' then
 phase='pull';target:SetPos(b:GetPos()+Vector(120,0,0));phys:SetPos(target:GetPos(),true);phys:SetVelocity(vector_origin);phys:SetAngleVelocity(vector_origin)
 end
 if CurTime()-started>9 then finish() end
end)
end
probe()
end
-- END SEAMLESS_PORTALS_AI_GRAVITY_WALLPAIR












































-- BEGIN SEAMLESS_PORTALS_AI_GRAVITY_GEOMETRY
do
local function probe()
local SP,AI=SeamlessPortals,SeamlessPortals.AI
local run='gravity_live_20260908_093827'
if not SERVER or AI[run..'_geometry'] then return end
AI[run..'_geometry']=true
local realm=game.IsDedicated() and 'dedicated' or 'server'
local out={portals={},players={}}
for _,p in ipairs(player.GetHumans()) do out.players[#out.players+1]={pos=p:GetPos(),eye=p:EyePos(),angle=p:EyeAngles(),weapon=tostring(p:GetActiveWeapon())} end
for _,e in ipairs(SP.Portals) do
 if SP.IsPortal(e) then
 local t={id=e:EntIndex(),pos=e:GetPos(),angle=e:GetAngles(),size=e:GetSize(),normal=e:GetUp(),traces={},exit=tostring(e:GetExitPortal())};out.portals[#out.portals+1]=t
 for d=0,100,5 do
 local start=e:GetPos()+e:GetUp()*d
 local a=SP.RawTraceLine({start=start,endpos=start-e:GetUp()*90,filter=e,mask=MASK_SOLID_BRUSHONLY})
 local shifted=start-e:GetUp()*39.5
 local b=SP.RawTraceLine({start=shifted,endpos=shifted-e:GetUp()*90,filter=e,mask=MASK_SOLID_BRUSHONLY})
 t.traces[#t.traces+1]={depth=d,hit=a.Hit,fraction=a.Fraction,solid=a.StartSolid,shifted_hit=b.Hit,shifted_fraction=b.Fraction,shifted_solid=b.StartSolid}
 end
 end
end
file.Write('seamless_tests/'..run..'/geometry_'..realm..'.json',util.TableToJSON(out,true))
end
probe()
end
-- END SEAMLESS_PORTALS_AI_GRAVITY_GEOMETRY






