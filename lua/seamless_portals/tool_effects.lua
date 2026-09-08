-- Split Sandbox tool feedback at the same boundaries as its target trace.
local SP=SeamlessPortals
SP.ToolEffectOwnership=SP.ToolEffectOwnership or {base=util.Effect}
local state=SP.ToolEffectOwnership
function SP.ToolEffectSegments(data)
    local weapon=data:GetEntity()
    if not IsValid(weapon) or weapon:GetClass()~="gmod_tool" then return end
    local owner=weapon:GetOwner()
    if not IsValid(owner) then return end
    local start=owner:GetShootPos()
    local trace=SP.TracePortalLine({start=start,endpos=start+owner:GetAimVector()*56756,
        filter={owner,weapon},mask=MASK_SHOT})
    if trace.SeamlessSegments and trace.HitPos:DistToSqr(data:GetOrigin())<4 then return trace.SeamlessSegments end
end
function SP.EmitToolEffect(name,data,...)
    if string.lower(name)~="tooltracer" or not SP.HasTraversablePortals() then return state.base(name,data,...) end
    local segments=SP.ToolEffectSegments(data)
    if not segments then return state.base(name,data,...) end
    for i,segment in ipairs(segments) do
        local effect=EffectData()
        effect:SetOrigin(segment.HitPos)
        effect:SetStart(segment.StartPos)
        if i==1 then effect:SetEntity(data:GetEntity()) effect:SetAttachment(data:GetAttachment()) end
        state.base(name,effect,...)
    end
end
if not state.wrapper then
    state.wrapper=function(...) return SP.EmitToolEffect(...) end
    util.Effect=state.wrapper
end
hook.Add("ShutDown","seamless_portals_tool_effects",function()
    if util.Effect==state.wrapper then util.Effect=state.base end
end)
