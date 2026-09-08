-- F10: Native NPC perception does not call a Lua util.TraceLine wrapper.
-- Represent a verified remote actor by a non-solid attention target just IN
-- FRONT of the aperture. It is visible to native AI, rather than inside a wall.
-- At actual bullet emission, recompute aim in the shooter's unfolded frame.
if not SERVER then return end
local SP=SeamlessPortals
local enabled=CreateConVar("seamless_portals_npc_awareness","1",bit.bor(FCVAR_ARCHIVE,FCVAR_REPLICATED),"Native HL2 NPC portal attention and ranged targeting adapter",0,1)
local distance=CreateConVar("seamless_portals_npc_distance","2048",FCVAR_ARCHIVE,"Maximum portal-aware NPC sight path",128,8192)
SP.NPCAttention=SP.NPCAttention or setmetatable({},{__mode="k"})
SP.NPCCandidates=SP.NPCCandidates or {}
local records,npcs=SP.NPCAttention,SP.NPCCandidates
local known=setmetatable({},{__mode="k"})
local armed_classes={npc_combine_s=true,npc_metropolice=true,npc_citizen=true,npc_alyx=true,npc_barney=true}
local function register(ent)
    if IsValid(ent) and ent:IsNPC() and ent:GetClass()~="npc_bullseye" and not known[ent] then
        known[ent]=true npcs[#npcs+1]=ent
        for owner,r in pairs(records) do if ent~=owner and IsValid(r.proxy) then ent:AddEntityRelationship(r.proxy,D_NU,99) end end
    end
end
-- Delay NPC API mutations until entity initialization is complete.
hook.Add("OnEntityCreated","seamless_portals_npc_awareness",function(ent) timer.Simple(0,function() register(ent) end) end)
for _,ent in ipairs(ents.GetAll()) do register(ent) end
function SP.ClearNPCAttention(npc)
    local r=records[npc] if not r then return end
    if IsValid(npc) and IsValid(r.proxy) then
        if npc:GetEnemy()==r.proxy then npc:SetEnemy(IsValid(r.previous) and r.previous or NULL) end
        npc:ClearEnemyMemory(r.proxy)
        if r.hostile~=false and r.previous_state and npc:GetNPCState()==NPC_STATE_COMBAT and not IsValid(npc:GetEnemy()) then npc:SetNPCState(r.previous_state) end
    end
    if IsValid(r.proxy) then r.proxy:Remove() end
    records[npc]=nil SP.CountField("npc_attention_released")
end
local function alive(ent)
    if not SP.IsLiveEntity(ent) then return false end
    if ent:IsPlayer() then return ent:Alive() end
    if not ent:IsNPC() or ent:GetClass()=="npc_bullseye" then return false end
    -- Some native NPCs, including live Rollermines, have zero numeric health.
    local life=ent:GetInternalVariable("m_lifeState")
    return life==0 or (life==nil and ent:Health()>0)
end
local function target_allowed(ent)
    if not alive(ent) or (FL_NOTARGET and ent:IsFlagSet(FL_NOTARGET)) then return false end
    local ignore=GetConVar("ai_ignoreplayers")
    return not ent:IsPlayer() or not (ignore and ignore:GetBool())
end
local function allowed(npc)
    local disabled=GetConVar("ai_disabled")
    if not alive(npc) then return false end
    if npc:GetClass()=="npc_combine_camera" and (npc:GetInternalVariable("m_bEnabled")==false
        or bit.band(npc:GetSpawnFlags(),64)~=0) then return false end
    return enabled:GetBool() and not npc:IsScripted()
        and npc:GetNPCState()~=NPC_STATE_SCRIPT and not (disabled and disabled:GetBool())
end
function SP.FindNPCTarget(npc,actors)
    if not IsValid(npc) then return end
    local source=npc:EyePos()
    local candidates={}
    for _,entry in ipairs(SP.Portals) do
        local exit=SP.IsPortal(entry) and entry:GetExitPortal()
        if SP.IsUsableLink(entry,exit) and SP.LinkAllows(entry,exit,"players") and SP.PlaneDistance(entry,source)>=0 then
            local first=source:Distance(entry:GetPos())
            if first<distance:GetFloat() then
                for _,target in ipairs(actors) do
                    if target~=npc and target_allowed(target) and SP.PlaneDistance(exit,target:WorldSpaceCenter())>=0 then
                        local path=first+target:WorldSpaceCenter():Distance(exit:GetPos())
                        if path<distance:GetFloat() then
                            local relation=npc:Disposition(target)
                            local priority=relation==D_HT and 0 or relation==D_FR and 1 or relation==D_LI and 2 or 3
                            candidates[#candidates+1]={entry=entry,exit=exit,target=target,player=target,distance=path,priority=priority}
                        end
                    end
                end
            end
        end
    end
    table.sort(candidates,function(a,b)
        if a.priority~=b.priority then return a.priority<b.priority end
        return a.distance<b.distance
    end)
    for i=1,math.min(#candidates,8) do
        local c=candidates[i]
        local sight=SP.PortalSight(c.entry,c.exit,source,c.target:WorldSpaceCenter(),npc,c.target)
        if sight and npc:IsInViewCone(sight.virtual) then c.sight=sight return c end
    end
end
function SP.UpdateNPCAttention(npc,actors)
    if not allowed(npc) then SP.ClearNPCAttention(npc) return end
    local c=SP.FindNPCTarget(npc,actors)
    if not c then SP.ClearNPCAttention(npc) return end
    -- Preserve the real actor's relationship; allies never become attack targets.
    npc:SetEyeTarget(c.sight.virtual)
    local armed=armed_classes[npc:GetClass()] and IsValid(npc:GetActiveWeapon())
    local relation=npc:Disposition(c.target)
    local hostile=relation==D_HT
    if hostile and not SP.LinkAllows(c.entry,c.exit,"damage") then
        SP.ClearNPCAttention(npc) return
    end
    local r=records[npc]
    if r and (not IsValid(r.proxy) or r.hostile~=hostile) then SP.ClearNPCAttention(npc) r=nil end
    local current=npc:GetEnemy()
    if IsValid(current) and (not r or current~=r.proxy) and npc:Visible(current) then
        SP.ClearNPCAttention(npc) return -- never steal a visible native enemy
    end
    if not r then
        local count=0 for _ in pairs(records) do count=count+1 end
        if count>=32 and hostile then
            for owner,record in pairs(records) do
                if record.hostile==false then SP.ClearNPCAttention(owner) count=count-1 break end
            end
        end
        if count>=32 then SP.CountField("npc_proxy_budget_rejected") return end
        local proxy=ents.Create("npc_bullseye") if not IsValid(proxy) then return end
        proxy.SEAMLESS_PORTALS_NPC_PROXY=true
        proxy:SetPos(c.sight.point+(npc:EyePos()-c.sight.point):GetNormalized()*2)
        proxy:SetKeyValue("health","1000000") proxy:Spawn()
        proxy:SetNoDraw(true) proxy:SetSolid(SOLID_NONE) proxy:SetSaveValue("m_takedamage",0)
        proxy:SetCollisionBounds(vector_origin,vector_origin)
        r={proxy=proxy,previous=current,previous_state=npc:GetNPCState(),hostile=hostile}
        records[npc]=r
        for _,other in ipairs(npcs) do if IsValid(other) and other~=npc then other:AddEntityRelationship(proxy,D_NU,99) end end
        npc:AddEntityRelationship(proxy,relation,99)
        if hostile then
            npc:SetEnemy(proxy) npc:SetNPCState(NPC_STATE_COMBAT)
            if COND then npc:SetCondition(COND.NEW_ENEMY) end
        end
        SP.CountField("npc_attention_acquired")
    end
    r.entry,r.exit,r.target=c.entry,c.exit,c.target
    -- Legacy navigation consumers use this field only for an attack target.
    r.player=hostile and c.target or nil
    local attention=c.sight.point+(npc:EyePos()-c.sight.point):GetNormalized()*2
    r.proxy:SetPos(attention)
    -- Also renew interest after a wall camera dismisses a non-player stand-in.
    if npc:Disposition(r.proxy)~=relation then npc:AddEntityRelationship(r.proxy,relation,99) end
    if hostile then
        npc:UpdateEnemyMemory(r.proxy,attention)
        if COND then npc:SetCondition(COND.SEE_ENEMY) npc:ClearCondition(COND.ENEMY_OCCLUDED) end
    end
    -- Face naturally; do not restart a firing/reload animation every update.
    npc:SetIdealYaw((attention-npc:GetPos()):Angle().y)
    -- Scanners, guards and mines select their own native reaction to an enemy.
    if hostile and armed and not r.scheduled then npc:SetSchedule(SCHED_RANGE_ATTACK1) r.scheduled=true end
    r.expires=CurTime()+1
end
function SP.AdjustNPCPortalBullet(npc,data)
    local r=records[npc]
    local target=r and (r.target or r.player)
    if not r or r.hostile==false or not allowed(npc) or npc:GetEnemy()~=r.proxy or not target_allowed(target)
        or not SP.LinkAllows(r.entry,r.exit,"damage") then return end
    -- Native weapon muzzle and EyePos differ; re-derive the target at the exact
    -- bullet Src, not by aiming at a near-plane dummy with parallax error.
    local path=SP.PortalSight(r.entry,r.exit,data.Src,target:WorldSpaceCenter(),npc,target)
    -- FireBullets runs inside native attack code, which can still dereference
    -- GetEnemy() after this callback. Retire it from Think after the shot ends.
    if not path then r.expires=0 return end
    data.Dir=(path.virtual-data.Src):GetNormalized()
    SP.CountField("npc_portal_shots")
end
local next_update,cursor,target_cursor=0,0,0
hook.Add("Think","seamless_portals_npc_awareness",function()
    for npc,r in pairs(records) do
        if not allowed(npc) or not SP.IsUsableLink(r.entry,r.exit) or not IsValid(r.proxy)
            or not target_allowed(r.target or r.player) or CurTime()>(r.expires or 0) then SP.ClearNPCAttention(npc) end
    end
    if CurTime()<next_update then return end
    next_update=CurTime()+0.1
    if #npcs==0 then return end
    local players=player.GetAll()
    local actors={} local seen={}
    local function add(ent) if IsValid(ent) and not seen[ent] then actors[#actors+1]=ent seen[ent]=true end end
    for _,ply in ipairs(players) do add(ply) end
    -- Keep active targets stable while rotating a bounded slice of the registry.
    for _,r in pairs(records) do add(r.target or r.player) end
    for _=1,math.min(#npcs,64) do
        target_cursor=target_cursor % #npcs+1
        add(npcs[target_cursor])
    end
    for i=1,math.min(#npcs,8) do
        cursor=cursor % #npcs+1
        local npc=npcs[cursor]
        if not IsValid(npc) then table.remove(npcs,cursor) cursor=cursor-1 if #npcs==0 then break end
        else SP.UpdateNPCAttention(npc,actors) end
    end
end)
hook.Add("EntityTakeDamage","seamless_portals_attention_no_damage",function(ent)
    if ent.SEAMLESS_PORTALS_NPC_PROXY then return true end
end)
local function cleanup() for npc in pairs(records) do SP.ClearNPCAttention(npc) end end
hook.Add("PostCleanupMap","seamless_portals_npc_cleanup",cleanup)
hook.Add("ShutDown","seamless_portals_npc_cleanup",cleanup)
