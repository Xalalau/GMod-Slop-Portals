-- Source entities are NEVER moved to relay audio. Server events are delivered
-- to the exit PAS, independently of whether the source entity is in the PVS.
local SP = SeamlessPortals
local server_enabled = CreateConVar("seamless_portals_soundrelay_server", "1", bit.bor(FCVAR_ARCHIVE,FCVAR_REPLICATED), "Relay spatial sounds through portals", 0, 1)
local busy, tick, used = false, -1, 0
local max_distance = CreateConVar("seamless_portals_sound_distance", "2048", bit.bor(FCVAR_ARCHIVE,FCVAR_REPLICATED), "Maximum source-to-aperture audio distance", 64, 8192)
-- Engine EntityEmitSound events may contain an entity but no explicit Pos.
function SP.NormalizeSoundEvent(event)
    if not istable(event) then return end
    local t = {} for k,v in pairs(event) do t[k]=v end
    if not SP.FiniteVector(t.Pos) then
        if not IsValid(t.Entity) then return end
        t.Pos = t.Entity.WorldSpaceCenter and t.Entity:WorldSpaceCenter() or t.Entity:GetPos()
    end
    if not SP.FiniteVector(t.Pos) then return end
    t.Pos = Vector(t.Pos.x,t.Pos.y,t.Pos.z)
    return t
end
local function permitted(t)
    if not t or busy or not server_enabled:GetBool() or not SP.HasTraversablePortals() then return false end
    if not isstring(t.SoundName) or #t.SoundName == 0 or #t.SoundName > 260
        or not SP.FiniteVector(t.Pos) or (t.SoundLevel or 75) <= 0 then return false end
    busy = true -- Guard third-party veto hooks that emit another sound.
    local ok, veto = SP.RunSafeHook("SeamlessPortalsAllowSoundRelay", t)
    busy = false
    return ok and veto ~= false -- ordinary spatial sounds no longer need an allowlist
end
function SP.SoundPaths(t)
    local paths = {}
    for _, entry in ipairs(SP.Portals) do
        local exit = SP.IsPortal(entry) and entry:GetExitPortal()
        if SP.IsPortal(exit) and SP.LinkAllows(entry,exit,"sound") then
            local d = t.Pos:DistToSqr(entry:GetPos())
            local radius = max_distance:GetFloat()
            if d <= radius*radius and (t.Pos-entry:GetPos()):Dot(entry:GetUp()) >= 0 then
                local raw = SP.RawTraceLine or SP.TraceLine or util.TraceLine
                local ray = raw({start=t.Pos,endpos=entry:GetPos()+entry:GetUp()*0.05,
                    filter={t.Entity,entry},mask=MASK_SOLID,SeamlessIgnore=true})
                if not ray.StartSolid and not ray.AllSolid and (not ray.Hit or (ray.Fraction or 0)>=0.999) then
                    -- Emit into the exit room, not behind a wall. A bounded path gain
                    -- accounts for the first leg; the engine attenuates the last leg.
                    paths[#paths+1] = {entry=entry,exit=exit,distance=d,
                        gain=1/(1+math.sqrt(d)/512),pos=exit:GetPos()+exit:GetUp()*4}
                end
            end
        end
    end
    table.sort(paths,function(a,b)
        if a.distance == b.distance then return a.entry:EntIndex()<b.entry:EntIndex() end
        return a.distance<b.distance
    end)
    while #paths>2 do table.remove(paths) end
    return paths
end
local message = "SEAMLESS_PORTALS_SPATIAL_SOUND_V2"
if SERVER then
    util.AddNetworkString(message)
    hook.Add("EntityEmitSound", "seamless_portals_detour_sound", function(event)
        local t=SP.NormalizeSoundEvent(event)
        if SP.IsNativeFireLoop and SP.IsNativeFireLoop(t) then return end
        if not permitted(t) then return end
        busy = true
        local ok, err = xpcall(function()
            local now = engine.TickCount()
            if tick ~= now then tick,used = now,0 end
            for _, path in ipairs(SP.SoundPaths(t)) do
                if used >= 64 then break end
                local recipients = RecipientFilter()
                -- The virtual source can be behind a solid wall. Recipient discovery
                -- must originate in the exit room, not inside that wall.
                recipients:AddPAS(path.exit:GetPos()+path.exit:GetUp()*4)
                net.Start(message)
                net.WriteEntity(path.entry) net.WriteEntity(path.exit)
                net.WriteVector(path.pos)
                net.WriteUInt(IsValid(t.Entity) and t.Entity:EntIndex() or 0,16)
                net.WriteString(t.SoundName)
                net.WriteInt(t.Channel or CHAN_AUTO,16)
                net.WriteFloat(math.Clamp((t.Volume or 1)*(path.gain or 1),0,1))
                net.WriteUInt(math.Clamp(t.SoundLevel or 75,0,511),9)
                net.WriteUInt(math.Clamp(t.Pitch or 100,0,255),8)
                net.WriteUInt(t.Flags or 0,16)
                net.WriteUInt(math.Clamp(t.DSP or 0,0,255),8)
                net.Send(recipients)
                used = used+1
            end
        end, debug.traceback)
        busy = false
        if not ok then ErrorNoHalt("[Seamless Portals] Sound relay: "..tostring(err).."\n") end
    end)
    return
end
local enabled = CreateClientConVar("seamless_portals_soundrelay","1",true,false,"Hear sounds through linked portals",0,1)
-- A separate invisible client emitter gives each source/path/channel ownership.
-- Unknown looping WAVs are bounded to 30 s; explicit stop flags/portal removal
-- stop sooner. Native StopSound without an emit hook cannot be inferred here.
SP.SoundEmitters = SP.SoundEmitters or {}
local emitters, recent = SP.SoundEmitters, {}
local serial = 0
local function remove_emitter(key, record)
    if IsValid(record.entity) then record.entity:StopSound(record.name) record.entity:Remove() end
    emitters[key] = nil
end
function SP.PlayPortalSound(path, source, t)
    if not enabled:GetBool() or not server_enabled:GetBool()
        or not SP.LinkAllows(path.entry,path.exit,"sound") then return end
    if (MainEyePos()-path.exit:GetPos()):Dot(path.exit:GetUp()) < 0 then return end
    local channel = path.entry:EntIndex()..":"..source..":"..(t.Channel or CHAN_AUTO)
    local base = channel..":"..t.SoundName
    if bit.band(t.Flags or 0,SND_STOP or 4) ~= 0 then
        for key, record in pairs(emitters) do if record.base == base then remove_emitter(key,record) end end
        return
    end
    local now = RealTime()
    -- Coalesce only server/client duplicates, never two events in the same realm.
    local previous = recent[base]
    if previous and previous.realm ~= t.SeamlessRealm and now-previous.time < 0.075 then return end
    recent[base] = {time=now,realm=t.SeamlessRealm}
    local key = base
    if (t.Channel or CHAN_AUTO) == CHAN_AUTO then serial=serial+1 key=base..":"..serial end
    local record = emitters[key]
    if (t.Channel or CHAN_AUTO) ~= CHAN_AUTO then
        for other_key, other in pairs(emitters) do
            if other.channel == channel and other_key ~= key then remove_emitter(other_key,other) end
        end
    end
    if not record then
        local count = 0 for _ in pairs(emitters) do count=count+1 end
        if count >= 64 then return end
        local entity = ClientsideModel("models/props_junk/PopCan01a.mdl",RENDERGROUP_OPAQUE)
        if not IsValid(entity) then return end
        entity:SetNoDraw(true) entity:DrawShadow(false)
        record = {entity=entity,base=base,channel=channel,name=t.SoundName,entry=path.entry,exit=path.exit,expires=now+30}
        emitters[key] = record
    end
    record.entity:SetPos(path.pos)
    local duration = SoundDuration(t.SoundName)
    if not SP.IsFinite(duration) or duration <= 0 then duration=30 end
    record.expires = now+math.Clamp(duration+0.25,0.25,30)
    busy = true
    local ok, err = xpcall(function()
        if string.sub(t.SoundName,1,1)=="!" and EmitSentence then
            EmitSentence(string.sub(t.SoundName,2),path.pos,record.entity:EntIndex(),t.Channel or CHAN_AUTO,
                t.Volume or 1,t.SoundLevel or 75,t.Flags or 0,t.Pitch or 100,t.DSP or 0)
        else
            record.entity:EmitSound(t.SoundName,t.SoundLevel or 75,t.Pitch or 100,t.Volume or 1,
                t.Channel or CHAN_AUTO,t.Flags or 0,t.DSP or 0)
        end
    end,debug.traceback)
    busy = false
    if not ok then remove_emitter(key,record) ErrorNoHalt("[Seamless Portals] Audio emitter: "..tostring(err).."\n") end
end
net.Receive(message,function()
    local path={entry=net.ReadEntity(),exit=net.ReadEntity(),pos=net.ReadVector()}
    local source=net.ReadUInt(16)
    local t={SoundName=net.ReadString(),Channel=net.ReadInt(16),Volume=net.ReadFloat(),SoundLevel=net.ReadUInt(9),
        Pitch=net.ReadUInt(8),Flags=net.ReadUInt(16),DSP=net.ReadUInt(8),SeamlessRealm="server"}
    SP.PlayPortalSound(path,source,t)
end)
hook.Add("EntityEmitSound","seamless_portals_detour_sound",function(event)
    local t=SP.NormalizeSoundEvent(event)
    if SP.IsNativeFireLoop and SP.IsNativeFireLoop(t) then return end
    if not enabled:GetBool() or not permitted(t) then return end
    local copy = {} for k,v in pairs(t) do copy[k]=v end copy.SeamlessRealm="client"
    for _, path in ipairs(SP.SoundPaths(t)) do
        copy.Volume=(t.Volume or 1)*(path.gain or 1)
        SP.PlayPortalSound(path,IsValid(t.Entity) and t.Entity:EntIndex() or 0,copy)
    end
end)
hook.Add("Think","seamless_portals_sound_cleanup",function()
    local now=RealTime()
    for key,record in pairs(emitters) do
        if now>=(record.expires or 0) or not enabled:GetBool() or not server_enabled:GetBool() or not SP.LinkAllows(record.entry,record.exit,"sound") then
            remove_emitter(key,record)
        end
    end
    for key,item in pairs(recent) do if now-item.time>0.1 then recent[key]=nil end end
end)
hook.Add("ShutDown","seamless_portals_sound_cleanup",function()
    for key,record in pairs(emitters) do remove_emitter(key,record) end
end)
