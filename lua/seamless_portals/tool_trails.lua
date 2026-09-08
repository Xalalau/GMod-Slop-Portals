-- Let Sandbox Trail Tool history expire at the entrance after a transfer.
if not SERVER then return end
local SP=SeamlessPortals

-- Attachment zero follows the entity origin. Use normal parenting so it can
-- later be detached; native SpriteTrail attachment handles cannot be cleared.
SP.ToolTrailFactory=SP.ToolTrailFactory or {base=util.SpriteTrail}
local factory=SP.ToolTrailFactory
function SP.CreateDetachableTrail(ent,attachment,...)
    if attachment~=0 or not SP.IsLiveEntity(ent) then return factory.base(ent,attachment,...) end
    local anchor=ents.Create("info_target")
    if not SP.IsLiveEntity(anchor) then return factory.base(ent,attachment,...) end
    anchor:SetPos(ent:GetPos()) anchor:Spawn()
    local ok,trail=pcall(factory.base,anchor,attachment,...)
    if ok and SP.IsLiveEntity(trail) then
        anchor:DontDeleteOnRemove(trail)
        trail:SetParent(ent) trail:SetLocalPos(vector_origin)
        trail:SetVar("SEAMLESS_PORTALS_DETACHABLE_TRAIL",true)
    end
    anchor:Remove()
    if not ok then error(trail,2) end
    return trail
end
if not factory.wrapper then
    factory.wrapper=function(...) return SP.CreateDetachableTrail(...) end
    util.SpriteTrail=factory.wrapper
end

function SP.ResetToolTrail(ent,sourcePos)
    if not SP.IsLiveEntity(ent) then return false end
    local old=ent.SToolTrail
    local data=ent.EntityMods and ent.EntityMods.trail
    if not SP.IsLiveEntity(old) or old:GetClass()~="env_spritetrail"
        or (old:GetParent()~=ent and old.SEAMLESS_PORTALS_TRAIL_ENTITY~=ent)
        or not istable(data) or not IsColor(data.Color) or not isstring(data.Material)
        or data.Material=="" or not SP.IsFinite(data.Length) or data.Length<0
        or not SP.IsFinite(data.StartSize) or data.StartSize<0
        or not SP.IsFinite(data.EndSize) or data.EndSize<0
        or data.StartSize+data.EndSize<=0 then return false end
    local previous=old.SEAMLESS_PORTALS_VISIBLE_TRAIL
    local visible=SP.IsLiveEntity(previous) and previous or old
    if not visible.SEAMLESS_PORTALS_DETACHABLE_TRAIL or visible:GetParent()~=ent then return false end
    if not SP.FiniteVector(sourcePos) then return false end
    local trail=util.SpriteTrail(ent,0,data.Color,false,data.StartSize,data.EndSize,data.Length,
        1/((data.StartSize+data.EndSize)*0.5),data.Material..".vmt")
    if not SP.IsLiveEntity(trail) then return false end
    trail:SetNoDraw(visible:GetNoDraw())
    old.SEAMLESS_PORTALS_TRAIL_ENTITY=ent
    old.SEAMLESS_PORTALS_VISIBLE_TRAIL=trail
    old:DeleteOnRemove(trail)
    ent:DeleteOnRemove(old) ent:DeleteOnRemove(trail)
    visible:SetParent(NULL) visible:SetPos(sourcePos)
    -- Keep all old points alive for their native lifetime. The original handle
    -- remains as the tool's undo/cleanup owner after its visible history expires.
    timer.Simple(data.Length+0.1,function()
        if not IsValid(visible) then return end
        if visible==old then
            visible:SetNoDraw(true)
            if SP.IsLiveEntity(ent) then visible:SetParent(ent) visible:SetLocalPos(vector_origin) end
        else
            if IsValid(old) then old:DontDeleteOnRemove(visible) end
            if IsValid(ent) then ent:DontDeleteOnRemove(visible) end
            visible:Remove()
        end
    end)
    return true
end
