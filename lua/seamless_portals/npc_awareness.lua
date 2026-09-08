-- F10: Native NPC perception does not call a Lua util.TraceLine wrapper.
-- Represent a verified remote player by a non-solid attention target just IN
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
        if r.previous_state and npc:GetNPCState()==NPC_STATE_COMBAT and not IsValid(npc:GetEnemy()) then npc:SetNPCState(r.previous_state) end
    end
    if IsValid(r.proxy) then r.proxy:Remove() end
    records[npc]=nil SP.CountField("npc_attention_released")
end
local function allowed(npc)
    local disabled,ignore=GetConVar("ai_disabled"),GetConVar("ai_ignoreplayers")
    return enabled:GetBool() and IsValid(npc) and npc:Health()>0 and not npc:IsScripted()
        and npc:GetNPCState()~=NPC_STATE_SCRIPT and not (disabled and disabled:GetBool())
        and not (ignore and ignore:GetBool())
end
function SP.FindNPCTarget(npc,players)
    local source=npc:EyePos()
    local candidates={}
    for _,entry in ipairs(SP.Portals) do
        local exit=SP.IsPortal(entry) and entry:GetExitPortal()
        if SP.IsUsableLink(entry,exit) and SP.LinkAllows(entry,exit,"players") and SP.PlaneDistance(entry,source)>=0 then
            local first=source:Distance(entry:GetPos())
            if first<distance:GetFloat() then
                for _,ply in ipairs(players) do
                    if IsValid(ply) and ply:Alive() and not (FL_NOTARGET and ply:IsFlagSet(FL_NOTARGET))
                        and SP.PlaneDistance(exit,ply:WorldSpaceCenter())>=0 then
                        local path=first+ply:WorldSpaceCenter():Distance(exit:GetPos())
                        if path<distance:GetFloat() then candidates[#candidates+1]={entry=entry,exit=exit,player=ply,distance=path} end
                    end
                end
            end
        end
    end
    table.sort(candidates,function(a,b) return a.distance<b.distance end)
    for i=1,math.min(#candidates,8) do
        local c=candidates[i]
        local sight=SP.PortalSight(c.entry,c.exit,source,c.player:WorldSpaceCenter(),npc,c.player)
        if sight and npc:IsInViewCone(sight.virtual) then c.sight=sight return c end
    end
end
function SP.UpdateNPCAttention(npc,players)
    if not allowed(npc) then SP.ClearNPCAttention(npc) return end
    local c=SP.FindNPCTarget(npc,players)
    if not c then SP.ClearNPCAttention(npc) return end
    -- A look target does not change friendly disposition or fabricate hostility.
    npc:SetEyeTarget(c.sight.virtual)
    if npc:Disposition(c.player)~=D_HT or not armed_classes[npc:GetClass()]
        or not IsValid(npc:GetActiveWeapon()) or not SP.LinkAllows(c.entry,c.exit,"damage") then
        SP.ClearNPCAttention(npc) return
    end
    local r=records[npc]
    local current=npc:GetEnemy()
    if IsValid(current) and (not r or current~=r.proxy) and npc:Visible(current) then
        SP.ClearNPCAttention(npc) return -- never steal a visible native enemy
    end
    if not r then
        local count=0 for _ in pairs(records) do count=count+1 end
        if count>=32 then SP.CountField("npc_proxy_budget_rejected") return end
        local proxy=ents.Create("npc_bullseye") if not IsValid(proxy) then return end
        proxy.SEAMLESS_PORTALS_NPC_PROXY=true
        proxy:SetPos(c.sight.point+(npc:EyePos()-c.sight.point):GetNormalized()*2)
        proxy:SetKeyValue("health","1000000") proxy:Spawn()
        proxy:SetNoDraw(true) proxy:SetSolid(SOLID_NONE) proxy:SetSaveValue("m_takedamage",0)
        proxy:SetCollisionBounds(vector_origin,vector_origin)
        r={proxy=proxy,previous=current,previous_state=npc:GetNPCState()}
        records[npc]=r
        for _,other in ipairs(npcs) do if IsValid(other) and other~=npc then other:AddEntityRelationship(proxy,D_NU,99) end end
        npc:AddEntityRelationship(proxy,D_HT,99)
        npc:SetEnemy(proxy) npc:SetNPCState(NPC_STATE_COMBAT)
        SP.CountField("npc_attention_acquired")
    end
    r.entry,r.exit,r.player=c.entry,c.exit,c.player
    local attention=c.sight.point+(npc:EyePos()-c.sight.point):GetNormalized()*2
    r.proxy:SetPos(attention) npc:UpdateEnemyMemory(r.proxy,attention)
    if COND then npc:SetCondition(COND.SEE_ENEMY) npc:ClearCondition(COND.ENEMY_OCCLUDED) end
    -- Face naturally; do not restart a firing/reload animation every update.
    npc:SetIdealYaw((attention-npc:GetPos()):Angle().y)
    if not r.scheduled then npc:SetSchedule(SCHED_RANGE_ATTACK1) r.scheduled=true end
    r.expires=CurTime()+1
end
function SP.AdjustNPCPortalBullet(npc,data)
    local r=records[npc]
    if not r or not allowed(npc) or npc:GetEnemy()~=r.proxy or not IsValid(r.player) or not r.player:Alive()
        or not SP.LinkAllows(r.entry,r.exit,"damage") then return end
    -- Native weapon muzzle and EyePos differ; re-derive the target at the exact
    -- bullet Src, not by aiming at a near-plane dummy with parallax error.
    local path=SP.PortalSight(r.entry,r.exit,data.Src,r.player:WorldSpaceCenter(),npc,r.player)
    if not path then SP.ClearNPCAttention(npc) return end
    data.Dir=(path.virtual-data.Src):GetNormalized()
    SP.CountField("npc_portal_shots")
end
local next_update,cursor=0,0
hook.Add("Think","seamless_portals_npc_awareness",function()
    for npc,r in pairs(records) do
        if not allowed(npc) or not SP.IsUsableLink(r.entry,r.exit) or not IsValid(r.player)
            or not r.player:Alive() or CurTime()>(r.expires or 0) then SP.ClearNPCAttention(npc) end
    end
    if CurTime()<next_update then return end
    next_update=CurTime()+0.1
    if #npcs==0 then return end
    local players=player.GetAll()
    for i=1,math.min(#npcs,8) do
        cursor=cursor % #npcs+1
        local npc=npcs[cursor]
        if not IsValid(npc) then table.remove(npcs,cursor) cursor=cursor-1 if #npcs==0 then break end
        else SP.UpdateNPCAttention(npc,players) end
    end
end)
hook.Add("EntityTakeDamage","seamless_portals_attention_no_damage",function(ent)
    if ent.SEAMLESS_PORTALS_NPC_PROXY then return true end
end)
local function cleanup() for npc in pairs(records) do SP.ClearNPCAttention(npc) end end
hook.Add("PostCleanupMap","seamless_portals_npc_cleanup",cleanup)
hook.Add("ShutDown","seamless_portals_npc_cleanup",cleanup)
