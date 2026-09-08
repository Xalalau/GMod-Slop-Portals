-- F04: Explicit lifetime protocol for native burning audio and addon loop adapters.
-- A native CSoundPatch need not emit an event when it changes/stops. Do not
-- pretend that replaying a WAV once implements that lifecycle.
local SP=SeamlessPortals
local message="SEAMLESS_PORTALS_LOOP_V3"
local enabled=CreateConVar("seamless_portals_native_fire_sound","1",bit.bor(FCVAR_ARCHIVE,FCVAR_REPLICATED),"Relay native burning-object loops",0,1)
local fire_wave="ambient/fire/fire_small_loop1.wav"
function SP.IsNativeFireLoop(t)
    if not t or not enabled:GetBool() or not IsValid(t.Entity) or not t.Entity:IsOnFire() then return false end
    local n=string.lower(t.SoundName or "")
    return n==fire_wave or n=="general.burningobject" or n=="ambient/fire/fire_med_loop1.wav"
end
if SERVER then
    util.AddNetworkString(message)
    SP.NativeFireCandidates=SP.NativeFireCandidates or setmetatable({},{__mode="k"})
    local candidates=SP.NativeFireCandidates
    local function register(ent)
        -- Registration only; entity construction is not finished in this hook.
        if IsValid(ent) then candidates[ent]=true end
    end
    hook.Add("OnEntityCreated","seamless_portals_fire_candidates",register)
    for _,ent in ipairs(ents.GetAll()) do register(ent) end
    local next_scan=0
    -- Addons can call this repeatedly (at least every 0.5 s) for their own
    -- persistent loops. Stop is explicit; an expiring lease covers lost PAS.
    function SP.RelayLoop(source,key,wave,volume,pitch,level,stop)
        if not IsValid(source) or not isstring(key) or #key>64 or not isstring(wave) or #wave>260 then return end
        local t=SP.NormalizeSoundEvent({Entity=source,SoundName=wave,SoundLevel=level or 75})
        if not t then return end
        local relay=GetConVar("seamless_portals_soundrelay_server")
        if not relay or not relay:GetBool() then return end
        for _,path in ipairs(SP.SoundPaths(t)) do
            local recipients=RecipientFilter() recipients:AddPAS(path.pos)
            net.Start(message)
            net.WriteEntity(path.entry) net.WriteEntity(path.exit)
            net.WriteUInt(source:EntIndex(),16) net.WriteString(key) net.WriteString(wave)
            net.WriteVector(path.pos) net.WriteBool(stop==true)
            net.WriteFloat(math.Clamp((volume or 1)*(path.gain or 1),0,1))
            net.WriteUInt(math.Clamp(pitch or 100,0,255),8)
            net.WriteUInt(math.Clamp(level or 75,0,511),9)
            net.Send(recipients)
            SP.CountField("loop_updates")
        end
    end
    local burning=setmetatable({},{__mode="k"})
    hook.Add("Think","seamless_portals_native_fire_loop",function()
        if CurTime()<next_scan then return end
        next_scan=CurTime()+0.25
        local budget=0
        for ent in pairs(candidates) do
            if not IsValid(ent) then candidates[ent]=nil burning[ent]=nil
            else
                local on=enabled:GetBool() and ent:IsOnFire()
                if on then
                    if budget<64 then SP.RelayLoop(ent,"native_fire",fire_wave,0.8,100,75,false) budget=budget+1 end
                    burning[ent]=true
                elseif burning[ent] then
                    SP.RelayLoop(ent,"native_fire",fire_wave,0,100,75,true) burning[ent]=nil
                end
            end
        end
    end)
    hook.Add("PostCleanupMap","seamless_portals_fire_reset",function()
        for ent in pairs(candidates) do candidates[ent]=nil end
        for ent in pairs(burning) do burning[ent]=nil end
        for _,ent in ipairs(ents.GetAll()) do register(ent) end
    end)
    return
end
SP.LoopEmitters=SP.LoopEmitters or {}
local records=SP.LoopEmitters
local function destroy(key,r)
    if r.patch then r.patch:Stop() end
    if IsValid(r.entity) then r.entity:Remove() end
    records[key]=nil
end
function SP.ReceiveLoop(path,source,key,wave,stop,volume,pitch,level)
    key=path.entry:EntIndex()..":"..source..":"..key
    local r=records[key]
    local local_on=GetConVar("seamless_portals_soundrelay")
    local server_on=GetConVar("seamless_portals_soundrelay_server")
    if stop or not local_on or not local_on:GetBool() or not server_on or not server_on:GetBool()
        or not SP.LinkAllows(path.entry,path.exit,"sound") then
        if r then destroy(key,r) end return
    end
    if not SP.FiniteVector(path.pos) or not isstring(wave) or #wave>260 then return end
    if r and r.wave~=wave then destroy(key,r) r=nil end
    if not r then
        local count=0 for _ in pairs(records) do count=count+1 end
        if count>=64 then SP.CountField("loop_budget_rejected") return end
        local ent=ClientsideModel("models/props_junk/PopCan01a.mdl",RENDERGROUP_OPAQUE)
        if not IsValid(ent) then return end
        ent:SetNoDraw(true) ent:DrawShadow(false) ent:SetPos(path.pos)
        local patch=CreateSound(ent,wave)
        if not patch then ent:Remove() return end
        patch:SetSoundLevel(level) patch:PlayEx(volume,pitch)
        r={entity=ent,patch=patch,wave=wave,entry=path.entry,exit=path.exit}
        records[key]=r
    else
        r.entity:SetPos(path.pos) r.patch:ChangeVolume(volume,0.15) r.patch:ChangePitch(pitch,0.15)
    end
    r.expires=RealTime()+1.1
end
net.Receive(message,function()
    local path={entry=net.ReadEntity(),exit=net.ReadEntity()}
    local source,key,wave=net.ReadUInt(16),net.ReadString(),net.ReadString()
    path.pos=net.ReadVector()
    local stop,volume,pitch,level=net.ReadBool(),net.ReadFloat(),net.ReadUInt(8),net.ReadUInt(9)
    if not SP.IsPortal(path.entry) or not SP.IsPortal(path.exit) then return end
    SP.ReceiveLoop(path,source,key,wave,stop,volume,pitch,level)
end)
hook.Add("Think","seamless_portals_loop_cleanup",function()
    local server_on=GetConVar("seamless_portals_soundrelay_server")
    local local_on=GetConVar("seamless_portals_soundrelay")
    for key,r in pairs(records) do
        if RealTime()>=r.expires or not IsValid(r.entity) or not server_on:GetBool() or not local_on:GetBool()
            or not SP.LinkAllows(r.entry,r.exit,"sound") or SP.PlaneDistance(r.exit,MainEyePos())<0 then destroy(key,r) end
    end
end)
hook.Add("ShutDown","seamless_portals_loop_cleanup",function() for key,r in pairs(records) do destroy(key,r) end end)
