-- F01: Aperture-gated blast events. Native blast damage bypasses Lua's
-- util.BlastDamage, so damageable portals also act as non-destructible witnesses.
if not SERVER then return end
local SP = SeamlessPortals
local enabled=CreateConVar("seamless_portals_blasts","1",FCVAR_ARCHIVE,"Relay supported blast events through apertures",0,1)
local queue, native_events = {}, {}
local capture_depth=0
local function enqueue(event)
    if #queue>=128 then SP.CountField("blast_event_budget") return false end
    queue[#queue+1]=event
    return true
end
local applying, capture = nil, nil
local function number(ent,key)
    if not IsValid(ent) or not ent.GetInternalVariable then return end
    local value=ent:GetInternalVariable(key)
    if SP.IsFinite(value) and value>0 then return value end
end
function SP.NativeBlastProfile(info)
    local ent=info:GetInflictor()
    if not IsValid(ent) then return end
    local class=ent:GetClass()
    local damage,radius
    if class=="env_explosion" then
        damage=number(ent,"m_iMagnitude")
        radius=number(ent,"m_iRadiusOverride") or (damage and damage*2.5)
    elseif class=="prop_physics" or class=="prop_physics_multiplayer" then
        damage,radius=number(ent,"m_explodeDamage"),number(ent,"m_explodeRadius")
        if damage and not radius then radius=damage*2.5 end
    elseif class=="npc_grenade_frag" or class=="grenade_ar2" or class=="rpg_missile"
        or class=="grenade_helicopter" then
        damage=number(ent,"m_flDamage")
        radius=number(ent,"m_DmgRadius") or number(ent,"m_flDamageRadius")
        if class=="rpg_missile" then radius=radius or 200 end
    end
    if damage and radius then
        return {origin=Vector(ent:GetPos()),damage=damage,radius=radius,source=class}
    end
    -- An addon can expose its true blast radius. Never guess one from an already
    -- attenuated victim's damage and turn every DMG_BLAST event into an explosion.
    local ok,result=SP.RunSafeHook("SeamlessPortalsNativeBlastProfile",ent,info)
    if ok and istable(result) and SP.FiniteVector(result.origin)
        and SP.IsFinite(result.radius) and SP.IsFinite(result.damage) then return result end
end
local function usable()
    local damage=GetConVar("seamless_portals_damage")
    return enabled:GetBool() and (not damage or damage:GetBool()) and SP.HasTraversablePortals()
end
local function valid_event(event)
    return event and SP.FiniteVector(event.origin) and SP.IsFinite(event.radius)
        and event.radius>0 and event.radius<=16384 and SP.IsFinite(event.damage) and event.damage>0
end
function SP.NewBlastEvent(info,origin,radius,damage)
    local values=SP.SnapshotDamage(info)
    local event={info=values,origin=Vector(origin),radius=radius,
        damage=damage or values.Damage,direct=setmetatable({},{__mode="k"}),tick=engine.TickCount()}
    if not valid_event(event) then return end
    return event
end
function SP.ObserveNativeBlast(target,info,taken)
    if not usable() or not info:IsExplosionDamage() then return end
    if applying and target==applying.target and info:GetInflictor()==applying.inflictor then return end
    local event=capture
    if event and event.info.Inflictor~=info:GetInflictor() then event=nil end
    if not event then
        local profile=SP.NativeBlastProfile(info)
        if not profile then SP.CountField("blast_unknown_profile") return end
        local key=tostring(info:GetInflictor())..":"..engine.TickCount()..":"..tostring(profile.origin)
        event=native_events[key]
        if not event then
            event=SP.NewBlastEvent(info,profile.origin,profile.radius,profile.damage)
            if not event then return end
            event.native=true
            if not enqueue(event) then return end
            native_events[key]=event
        end
    end
    if taken and IsValid(target) and not SP.IsPortal(target) then
        event.direct[target]=math.max(event.direct[target] or 0,info:GetDamage())
    end
end
hook.Add("EntityTakeDamage","seamless_portals_native_blast_witness",function(target,info)
    SP.ObserveNativeBlast(target,info,false)
end)
hook.Add("PostEntityTakeDamage","seamless_portals_native_blast_direct",function(target,info,taken)
    SP.ObserveNativeBlast(target,info,taken)
end)
function SP.BlastPathDamage(event,path)
    if not valid_event(event) or not path or path.distance>=event.radius then return 0 end
    return event.damage*math.max(0,1-path.distance/event.radius)
end
function SP.RelayBlast(event)
    if not usable() or not valid_event(event) then return false end
    local targets, count = {},0
    for _,entry in ipairs(SP.Portals) do
        local exit=SP.IsPortal(entry) and entry:GetExitPortal()
        if SP.IsPortal(exit) and SP.LinkAllows(entry,exit,"damage") and SP.PlaneDistance(entry,event.origin)>=0 then
            local aperture=SP.ClosestAperturePoint(entry,event.origin)
            local entrance_distance=event.origin:Distance(aperture)
            if entrance_distance<event.radius then
                -- Broadphase only: actual distance and both obstructions are tested below.
                for _,ent in ipairs(ents.FindInSphere(exit:GetPos(),event.radius-entrance_distance+exit:BoundingRadius())) do
                    if IsValid(ent) and not ent:IsWorld() and not SP.IsPortal(ent)
                        and ent:GetClass()~="seamless_portal_cutout" and not ent.SEAMLESS_PORTALS_AI_PROXY then
                        count=count+1
                        if count>2048 then SP.CountField("blast_candidate_budget") break end
                        local virtual_source=SP.TransformPortal(entry,exit,event.origin)
                        local target=ent:NearestPoint(virtual_source)
                        local path=SP.PortalSight(entry,exit,event.origin,target,event.info.Inflictor,ent)
                        if path then
                            local amount=SP.BlastPathDamage(event,path)
                            local current=targets[ent]
                            if amount>0 and (not current or amount>current.amount) then
                                targets[ent]={amount=amount,point=target,path=path,virtual=virtual_source}
                            end
                        end
                    end
                end
            end
        end
        if count>2048 then break end
    end
    local previous=applying
    local ok,err=xpcall(function()
        local ordered={}
        for ent,hit in pairs(targets) do ordered[#ordered+1]={entity=ent,hit=hit} end
        table.sort(ordered,function(a,b) return a.entity:EntIndex()<b.entity:EntIndex() end)
        for _,item in ipairs(ordered) do
            local ent,hit=item.entity,item.hit
            -- Strongest-path policy: do not add the same explosion again through
            -- several portals or on top of an equal/stronger direct path.
            local amount=hit.amount-(event.direct[ent] or 0)
            if IsValid(ent) and amount>0 then
                local info=SP.CopyDamage(event.info)
                info:SetDamage(amount)
                info:SetDamagePosition(hit.point)
                info:SetReportedPosition(hit.virtual)
                local direction=(hit.point-hit.virtual):GetNormalized()
                local force=event.info.DamageForce:Length()
                if force<=0 then force=event.damage*300 end
                info:SetDamageForce(direction*force*(amount/event.damage))
                if not IsValid(info:GetAttacker()) then info:SetAttacker(game.GetWorld()) end
                if not IsValid(info:GetInflictor()) then info:SetInflictor(game.GetWorld()) end
                applying={target=ent,inflictor=info:GetInflictor()}
                ent:TakeDamageInfo(info)
                applying=previous
                SP.CountField("blast_targets_relayed")
            end
        end
    end,debug.traceback)
    applying=previous
    if not ok then ErrorNoHalt("[Seamless Portals] Blast relay: "..tostring(err).."\n") end
    return ok
end
function SP.FlushBlastEvents()
    -- Snapshot before callbacks; a secondary real barrel explosion may queue a
    -- different event. The applying guard only suppresses our synthetic damage.
    local pending=queue
    queue={}
    for i,event in ipairs(pending) do
        if i<=64 then SP.RelayBlast(event) else SP.CountField("blast_event_budget") end
    end
    for key,event in pairs(native_events) do
        if engine.TickCount()>event.tick+1 then native_events[key]=nil end
    end
end
hook.Add("Tick","seamless_portals_blast_queue",SP.FlushBlastEvents)
-- Lua blast entry points retain their original local damage and return value.
-- Native witnesses and Lua wrappers share one event to avoid double relays.
SP.BlastHooks=SP.BlastHooks or {}
function SP.InvokeBlast(name,owned,...)
    local args={...}
    if capture_depth>=8 or not usable() then return owned.base(unpack(args)) end
    local info,origin,radius
    if name=="BlastDamageInfo" then info,origin,radius=args[1],args[2],args[3]
    else
        info=DamageInfo() info:SetInflictor(IsValid(args[1]) and args[1] or game.GetWorld())
        info:SetAttacker(IsValid(args[2]) and args[2] or game.GetWorld())
        info:SetDamage(args[5]) info:SetDamageType(DMG_BLAST)
        origin,radius=args[3],args[4]
    end
    if not SP.FiniteVector(origin) then return owned.base(unpack(args)) end
    local event=SP.NewBlastEvent(info,origin,radius)
    if not event then return owned.base(unpack(args)) end
    local previous=capture
    capture=event
    capture_depth=capture_depth+1
    local result
    local ok,err=xpcall(function() result=owned.base(unpack(args)) end,debug.traceback)
    capture=previous
    capture_depth=capture_depth-1
    if not ok then error(err,0) end
    enqueue(event)
    return result
end
for _,name in ipairs({"BlastDamage","BlastDamageInfo"}) do
    local owned=SP.BlastHooks[name]
    if not owned then
        owned={base=util[name]}
        owned.wrapper=function(...) return SP.InvokeBlast(name,owned,...) end
        SP.BlastHooks[name]=owned
        util[name]=owned.wrapper
    end
end
hook.Add("PostCleanupMap","seamless_portals_blast_reset",function() queue={} native_events={} capture=nil applying=nil capture_depth=0 end)
hook.Add("ShutDown","seamless_portals_blast_reset",function()
    for name,owned in pairs(SP.BlastHooks) do if util[name]==owned.wrapper then util[name]=owned.base end end
end)
