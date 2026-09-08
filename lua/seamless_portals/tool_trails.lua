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
        trail:SetVar("SEAMLESS_PORTALS_TRAIL_ENTITY",ent)
        local record=ent.SEAMLESS_PORTALS_CARRY
        if record and SP.ToolTrailCarryPosition then
            local position=SP.ToolTrailCarryPosition(ent,record)
            if position then
                trail:SetParent(NULL) trail:SetPos(position) ent:DeleteOnRemove(trail)
            end
        end
    end
    anchor:Remove()
    if not ok then error(trail,2) end
    return trail
end
if not factory.wrapper then
    factory.wrapper=function(...) return SP.CreateDetachableTrail(...) end
    util.SpriteTrail=factory.wrapper
end

function SP.ResetToolTrail(ent,sourcePos,destination)
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
    local carry=ent.SEAMLESS_PORTALS_TOOL_TRAIL_CARRY
    if carry and carry.trail~=visible then carry=nil end
    if not visible.SEAMLESS_PORTALS_DETACHABLE_TRAIL or (visible:GetParent()~=ent and not carry) then return false end
    if carry then sourcePos=carry.position end
    if not SP.FiniteVector(sourcePos) or (destination and not SP.FiniteVector(destination)) then return false end
    local trail=util.SpriteTrail(ent,0,data.Color,false,data.StartSize,data.EndSize,data.Length,
        1/((data.StartSize+data.EndSize)*0.5),data.Material..".vmt")
    if not SP.IsLiveEntity(trail) then return false end
    trail:SetNoDraw(visible:GetNoDraw())
    if destination then trail:SetParent(NULL) trail:SetPos(destination)
    else trail:SetParent(ent) trail:SetLocalPos(vector_origin) end
    ent.SEAMLESS_PORTALS_TOOL_TRAIL_CARRY=nil
    old.SEAMLESS_PORTALS_TRAIL_ENTITY=ent
    old.SEAMLESS_PORTALS_VISIBLE_TRAIL=trail
    old:DeleteOnRemove(trail)
    ent:DontDeleteOnRemove(old) ent:DeleteOnRemove(old)
    ent:DontDeleteOnRemove(trail) ent:DeleteOnRemove(trail)
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

-- Held objects can live behind the entrance while their visible origin is in
-- the exit room. Trails follow that origin, independently of the native handle.
function SP.ToolTrailCarryPosition(ent,record)
    if not SP.IsLiveEntity(ent) or not record or not SP.IsUsableLink(record.entry,record.exit) then return end
    local position=ent:GetPos()
    if SP.PlaneDistance(record.entry,position)<0 then
        return SP.TransformPortal(record.entry,record.exit,position),record.exit
    end
    return position,false
end
function SP.UpdateToolTrailCarry(ent,record,sourcePos)
    if not SP.IsLiveEntity(ent) then return end
    local owner=ent.SToolTrail
    if not SP.IsLiveEntity(owner) then ent.SEAMLESS_PORTALS_TOOL_TRAIL_CARRY=nil return end
    if owner:GetClass()~="env_spritetrail" or (owner:GetParent()~=ent and owner.SEAMLESS_PORTALS_TRAIL_ENTITY~=ent) then return end
    local active=SP.IsLiveEntity(owner.SEAMLESS_PORTALS_VISIBLE_TRAIL) and owner.SEAMLESS_PORTALS_VISIBLE_TRAIL or owner
    if not active.SEAMLESS_PORTALS_DETACHABLE_TRAIL then return end
    local position,space=SP.ToolTrailCarryPosition(ent,record)
    if not position then return end
    local state=ent.SEAMLESS_PORTALS_TOOL_TRAIL_CARRY
    if not state or state.trail~=active then
        local source=sourcePos or active:GetPos()
        state={trail=active,position=Vector(source),space=space and source:DistToSqr(position)<1 and space or false}
        ent.SEAMLESS_PORTALS_TOOL_TRAIL_CARRY=state
        owner.SEAMLESS_PORTALS_TRAIL_ENTITY=ent
        ent:DontDeleteOnRemove(owner) ent:DeleteOnRemove(owner)
        if active~=owner then ent:DontDeleteOnRemove(active) ent:DeleteOnRemove(active) end
        active:SetParent(NULL) active:SetPos(source)
    end
    if state.space~=space then
        if not SP.ResetToolTrail(ent,state.position,position) then return end
        active=owner.SEAMLESS_PORTALS_VISIBLE_TRAIL
        state.trail=active state.space=space
        ent.SEAMLESS_PORTALS_TOOL_TRAIL_CARRY=state
    end
    active:SetPos(position)
    state.position=Vector(position)
end
function SP.EndToolTrailCarry(ent)
    if not IsValid(ent) then return end
    local state=ent.SEAMLESS_PORTALS_TOOL_TRAIL_CARRY
    if not state then return end
    if SP.IsLiveEntity(state.trail) then
        if state.position:DistToSqr(ent:GetPos())>4 then
            if not SP.ResetToolTrail(ent,state.position) then return end
        else
            state.trail:SetParent(ent) state.trail:SetLocalPos(vector_origin)
        end
    end
    ent.SEAMLESS_PORTALS_TOOL_TRAIL_CARRY=nil
end
