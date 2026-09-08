-- Extra explicit doubles for full RC2 modules. They model API contracts, NOT
-- Source physics, native +use/physgun controllers, network or rendering.
local vector_meta=getmetatable(Vector())
function vector_meta:Normalize() local n=self:Length();if n>0 then self:Mul(1/n) end return n end
local angle_meta=getmetatable(Angle())
angle_meta.__index=function(t,k) local i=({p=1,y=2,r=3})[k];return i and rawget(t,i) or angle_meta[k] end
angle_meta.__newindex=function(t,k,v) rawset(t,({p=1,y=2,r=3})[k] or k,v) end
NOW,TICK,DT=10,660,1/66
function CurTime() return NOW end
function RealTime() return NOW end
engine={TickCount=function() return TICK end,TickInterval=function() return DT end}
MOVETYPE_WALK,MOVETYPE_NOCLIP,MASK_SOLID,CHAN_AUTO,SND_STOP,RENDERGROUP_OPAQUE=2,8,2,0,4,0
MOVETYPE_VPHYSICS=6
CONTENTS_SOLID,CONTENTS_MOVEABLE,CONTENTS_MONSTER,CONTENTS_WINDOW,CONTENTS_DEBRIS,CONTENTS_GRATE,CONTENTS_AUX=1,2,4,8,16,32,64
bit.bor=function(...) local n=0 for _,v in ipairs({...}) do n=n|v end return n end
bit.band=function(a,b) return a&b end
net={receivers={},messages={}}
function net.Receive(name,fn) net.receivers[name]=fn end
function net.Start(name) net.current={name=name,values={}} end
for _,name in ipairs({'WriteEntity','WriteVector','WriteUInt','WriteInt','WriteFloat','WriteString','WriteBool','WriteAngle'}) do
 net[name]=function(v) net.current.values[#net.current.values+1]=v end
end
function net.Send(filter) net.current.filter=filter;net.messages[#net.messages+1]=net.current;net.current=nil end
util.AddNetworkString=function() end
util.TraceHull=function(data) return {Hit=false,StartSolid=false,AllSolid=false} end
function RecipientFilter() return {AddPAS=function(self,v) self.pas=Vector(v) end} end
function SoundDuration() return 2 end
function MainEyePos() return Vector(200,0,20) end
function RunConsoleCommand(name,value) local cv=CVARS[name];if cv then cv.value=tonumber(value) or value end end
local portal_base=portal
local next_prop=1000
function portal(size,sides)
 local e=portal_base(size,sides)
 function e:WorldToLocalAngles(a) return Angle(a) end
 function e:LocalToWorldAngles(a) return Angle(a) end
 function e:IsPlayer() return false end
 function e:IsNPC() return false end
 function e:IsWorld() return false end
 function e:TriggerOutput(name,ent) self.outputs=self.outputs or {};table.insert(self.outputs,{name,ent}) end
 function e:GetParent() return NULL end
 return e
end
function physics(pos)
 local p={pos=Vector(pos),ang=Angle(),vel=Vector(1,2,3),angular=Vector(4,5,6),motion=true,motion_writes=0}
 function p:GetPos() return Vector(self.pos) end
 function p:GetAngles() return Angle(self.ang) end
 function p:GetVelocity() return Vector(self.vel) end
 function p:GetAngleVelocity() return Vector(self.angular) end
 function p:IsMotionEnabled() return self.motion end
 function p:SetPos(v) if self.fail_once then self.fail_once=false;error('injected write failure') end self.pos=Vector(v) end
 function p:SetAngles(v) self.ang=Angle(v) end
 function p:SetVelocity(v) self.vel=Vector(v) end
 function p:SetAngleVelocity(v) self.angular=Vector(v) end
 function p:EnableMotion(v) self.motion=v;self.motion_writes=self.motion_writes+1 end
 function p:Wake() self.woken=true end
 return p
end
function prop(pos,count)
 local e=portal();next_prop=next_prop+1;e.id=next_prop;e.pos=Vector(pos or Vector());e.holding=false;e.bodies={}
 for i=1,count or 1 do e.bodies[i]=physics(e.pos+Vector(i-1,0,0)) end
 e.lo,e.hi=Vector(-1,-1,-1),Vector(1,1,1)
 function e:GetClass() return 'prop_physics' end
 function e:IsVehicle() return false end
 function e:GetDriver() return NULL end
 function e:IsPlayerHolding() return self.holding end
 function e:GetPhysicsObjectCount() return #self.bodies end
 function e:GetPhysicsObjectNum(i) return self.bodies[i+1] or NULL end
 function e:GetPhysicsObject() return self.bodies[1] end
 function e:OBBMins() return Vector(self.lo) end
 function e:OBBMaxs() return Vector(self.hi) end
 function e:SetPos(v) self.pos=Vector(v) end
 function e:SetAngles(v) self.angle=Angle(v) end
 function e:SetNotSolid(v) self.notsolid=v end
 function e:SetNoDraw(v) self.nodraw=v end
 function e:DrawShadow() end
 function e:Remove() self.valid=false end
 function e:EmitSound(name) self.sound=name;self.emitted=(self.emitted or 0)+1;hook.Run('EntityEmitSound',{SoundName=name,Pos=self.pos,Entity=self}) end
 function e:StopSound() self.stopped=true end
 function e:PhysicsInit() error('native physics identity replaced') end
 function e:ForcePlayerDrop() error('native hold released') end
 return e
end
function player()
 local e=prop();e.lo,e.hi=Vector(-2,-2,0),Vector(2,2,8);e.nwent={}
 function e:IsPlayer() return true end
 function e:Alive() return true end
 function e:GetMoveType() return MOVETYPE_WALK end
 function e:InVehicle() return false end
 function e:GetRunSpeed() return 200 end
 function e:GetCurrentViewOffset() return Vector(0,0,6) end
 function e:Crouching() return false end
 function e:GetHull() return Vector(self.lo),Vector(self.hi) end
 function e:GetHullDuck() return self:GetHull() end
 function e:SetNWEntity(key,v) self.nwent[key]=v end
 function e:GetNWEntity(key) return self.nwent[key] or NULL end
 function e:GetInfoNum(_,default) return default end
 function e:GetVehicle() return NULL end
 function e:DropObject() error('player hold released') end
 return e
end
function move(pos,vel,side)
 return {pos=Vector(pos),vel=Vector(vel),side=side or 0,GetOrigin=function(t) return Vector(t.pos) end,
 GetVelocity=function(t) return Vector(t.vel) end,SetOrigin=function(t,v) t.pos=Vector(v) end,
 SetVelocity=function(t,v) t.vel=Vector(v) end,GetSideSpeed=function(t) return t.side end}
end
WORLD={__entity=true,IsWorld=function() return true end,GetClass=function() return "worldspawn" end}
game={GetWorld=function() return WORLD end,SinglePlayer=function() return false end}
constraint={
 GetAllConstrainedEntities=function(root) return root.group or {[root]=root} end,
 GetTable=function(ent) return ent.constraints or {} end,
 HasConstraints=function(ent) return ent.group~=nil end,
}
function pair(sides)
 local a,b=portal(nil,sides),portal(nil,sides);b.pos=Vector(200,0,0);a.exit=b;b.exit=a
 SeamlessPortals.Portals={a,b};SeamlessPortals.LinkedRegistryDirty=true
 return a,b
end
function DamageInfo()
 local d={Damage=20,DamageType=2,DamageCustom=0,DamageForce=Vector(0,0,-10),DamagePosition=Vector(),Inflictor=NULL,Attacker=NULL,AmmoType=1}
 for _,name in ipairs({'Damage','DamageType','DamageCustom','DamageForce','DamagePosition','Inflictor','Attacker','AmmoType'}) do
  d['Get'..name]=function(self) return self[name] end
  d['Set'..name]=function(self,v) self[name]=v end
 end
 return d
end
function ClientsideModel() local e=prop();CLIENT_EMITTERS=CLIENT_EMITTERS or {};table.insert(CLIENT_EMITTERS,e);return e end

-- Mutable ConVar setters are part of the engine API; CreateConVar is memoized.
local create_convar=CreateConVar
function CreateConVar(name,default,...)
 local cv=create_convar(name,default,...)
 function cv:SetInt(v) self.value=v end
 function cv:GetString() return tostring(self.value) end
 return cv
end
CreateClientConVar=CreateConVar

physenv={GetGravity=function() return Vector(0,0,-600) end}
local player_base=player
function player()
 local e=player_base()
 function e:GetModelScale() return 1 end
 function e:SetHull(a,b) self.lo=Vector(a);self.hi=Vector(b) end
 function e:SetHullDuck(a,b) self.dlo=Vector(a);self.dhi=Vector(b) end
 function e:GetHullDuck() return Vector(self.dlo or self.lo),Vector(self.dhi or self.hi) end
 function e:EyeAngles() return Angle() end
 function e:SetEyeAngles(a) self.eyeang=Angle(a) end
 function e:SetGroundEntity(v) self.ground=v end
 function e:SetNWInt(k,v) self.nwint=self.nwint or {};self.nwint[k]=v end
 function e:GetNWInt(k,d) return self.nwint and self.nwint[k] or d end
 function e:GetCurrentCommand() return {CommandNumber=function() return 7 end} end
 return e
end
