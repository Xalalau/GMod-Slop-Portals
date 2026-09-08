-- Explicit test doubles. These do not simulate native GMod rendering, networking or physics.
local vm, am = {}, {}
vm.__index = function(t,k) local i=({x=1,y=2,z=3})[k]; return i and rawget(t,i) or vm[k] end
vm.__newindex = function(t,k,v) rawset(t,({x=1,y=2,z=3})[k] or k,v) end
am.__index = am
function Vector(x, y, z)
    if type(x) == 'table' then return setmetatable({x[1], x[2], x[3]}, vm) end
    return setmetatable({x or 0, y or 0, z or 0}, vm)
end
function Angle(x, y, z)
    if type(x) == 'table' then return setmetatable({x[1], x[2], x[3]}, am) end
    return setmetatable({x or 0, y or 0, z or 0}, am)
end
function vm:Mul(v) for i = 1,3 do self[i] = self[i] * (type(v) == 'table' and v[i] or v) end return self end
function vm:Add(v) for i = 1,3 do self[i] = self[i] + v[i] end return self end
function vm:Sub(v) for i = 1,3 do self[i] = self[i] - v[i] end return self end
function vm:Dot(v) return self[1]*v[1] + self[2]*v[2] + self[3]*v[3] end
function vm:Cross(v) return Vector(self[2]*v[3]-self[3]*v[2], self[3]*v[1]-self[1]*v[3], self[1]*v[2]-self[2]*v[1]) end
function vm:LengthSqr() return self:Dot(self) end
function vm:Length() return math.sqrt(self:LengthSqr()) end
function vm:Distance(v) return (self-v):Length() end
function vm:DistToSqr(v) return (self-v):LengthSqr() end
function vm:IsZero() return self:LengthSqr() == 0 end
function vm:GetNormalized() local n = self:Length(); return n == 0 and Vector() or Vector(self):Mul(1/n) end
function vm:Set(v) for i = 1,3 do self[i] = v[i] end end
function vm:Negate() return self:Mul(-1) end
function vm:Angle() return {_forward = self:GetNormalized(), Forward = function(a) return Vector(a._forward) end} end
function am:Forward() return Vector(1,0,0) end
vm.__mul = function(a,b) return type(a) == 'number' and Vector(b):Mul(a) or Vector(a):Mul(b) end
vm.__div = function(a,b) return Vector(a):Mul(1/b) end
vm.__add = function(a,b) return Vector(a):Add(b) end
vm.__sub = function(a,b) return Vector(a):Sub(b) end
vm.__unm = function(a) return Vector(a):Mul(-1) end
vm.__eq = function(a,b) return a[1]==b[1] and a[2]==b[2] and a[3]==b[3] end
am.__eq = vm.__eq
function IsValid(e) return type(e) == 'table' and getmetatable(e) ~= vm and getmetatable(e) ~= am and e.valid ~= false end
function IsEntity(e) return type(e) == 'table' and e.__entity == true end
function isvector(e) return getmetatable(e) == vm end
function istable(e) return type(e) == 'table' and not IsEntity(e) and not isvector(e) and getmetatable(e) ~= am end
function isnumber(e) return type(e) == 'number' end
function isstring(e) return type(e) == 'string' end
function isfunction(e) return type(e) == 'function' end
function isbool(e) return type(e) == 'boolean' end
function AddCSLuaFile() end
function include() return function() end end
function SafeRemoveEntity(e) if IsValid(e) then e.valid = false end end
function ErrorNoHalt(s) LAST_ERROR = s end
function CurTime() return 1 end
function FrameTime() return 1/66 end
function FrameNumber() return 1 end
math.Clamp = function(x,a,b) return math.min(math.max(x,a),b) end
unpack = table.unpack
NULL = {valid = false, __entity = true}
vector_origin = Vector()
ENT, TOOL, SWEP = {}, {}, {}
CLIENT, SERVER = false, true
FCVAR_NONE, FCVAR_ARCHIVE, FCVAR_REPLICATED = 0,1,2
SOLID_VPHYSICS, MOVETYPE_NONE, MOVETYPE_VPHYSICS = 6,0,6
MASK_PLAYERSOLID = 1
hook = {values = {}}
function hook.Add(event, id, fn) hook.values[event] = hook.values[event] or {}; hook.values[event][id] = fn end
function hook.Remove(event,id) if hook.values[event] then hook.values[event][id] = nil end end
function hook.Run(event, ...) if hook.values[event] then for _, fn in pairs(hook.values[event]) do local v = fn(...); if v ~= nil then return v end end end end
function hook.GetTable() return hook.values end
concommand = {Add = function() end}
timer = {Simple = function(_,fn) fn() end, Remove = function() end, Create = function() end}
CVARS = {}
function CreateConVar(name, default)
    if CVARS[name] then return CVARS[name] end
    local cv = {value = tonumber(default) or default}
    function cv:GetBool() return tonumber(self.value) ~= 0 end
    function cv:GetInt() return math.floor(tonumber(self.value)) end
    function cv:GetFloat() return tonumber(self.value) end
    CVARS[name] = cv
    return cv
end
CreateClientConVar = CreateConVar
function GetConVar(name) return CVARS[name] end
bit = {bor = function(a,b) return a | b end}
util = {TraceLine = function() return {} end}
function table.Merge(a,b) for k,v in pairs(b) do a[k]=v end return a end
function table.RemoveByValue(a,v) for i=#a,1,-1 do if a[i]==v then table.remove(a,i) end end end
duplicator = {StoreEntityModifier = function(e,_,data) e.dupe=data end, RegisterEntityModifier = function() end}
SeamlessPortals = {Portals={}}
local next_entity = 0
function portal(size, sides)
    next_entity = next_entity + 1
    local e = {__entity=true, size=Vector(size or Vector(100,100,8)), sides=sides or 4,
        pos=Vector(), angle=Angle(), forward=Vector(1,0,0), right=Vector(0,-1,0), up=Vector(0,0,1), exit=NULL, id=next_entity}
    function e:GetClass() return 'seamless_portal' end
    function e:GetSize() return Vector(self.size) end
    function e:GetSides() return self.sides end
    function e:GetPos() return Vector(self.pos) end
    function e:GetAngles() return Angle(self.angle) end
    function e:GetForward() return Vector(self.forward) end
    function e:GetRight() return Vector(self.right) end
    function e:GetUp() return Vector(self.up) end
    function e:GetExitPortal() return self.exit end
    function e:SetExitPortal(v) self.exit=v; SeamlessPortals.LinkedRegistryDirty=true end
    function e:GetNWBool(key,default) if self.nw and self.nw[key] ~= nil then return self.nw[key] end return default end
    function e:SetNWBool(key,v) self.nw=self.nw or {}; self.nw[key]=v end
    function e:WorldToLocal(v) local d=v-self.pos;return Vector(d:Dot(self.forward),d:Dot(-self.right),d:Dot(self.up)) end
    function e:LocalToWorld(v) return self.pos+self.forward*v.x-self.right*v.y+self.up*v.z end
    function e:GetCreator() return NULL end
    function e:EntIndex() return self.id end
    return setmetatable(e,{__index=ENT})
end
function near(a,b,eps) assert(math.abs(a-b) < (eps or 1e-8), tostring(a)..' != '..tostring(b)) end
function nearvec(a,b,eps) for i=1,3 do near(a[i],b[i],eps) end end
