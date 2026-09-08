-- Split Sandbox tool feedback at the same boundaries as its target trace.
local SP=SeamlessPortals
SP.ToolEffectOwnership=SP.ToolEffectOwnership or {base=util.Effect}
local state=SP.ToolEffectOwnership
state.camera_traces=state.camera_traces or setmetatable({},{__mode="k"})
state.clicks=state.clicks or setmetatable({},{__mode="k"})
function SP.RememberToolClick(weapon,trace)
    state.clicks[weapon]=nil
    if trace and trace.SeamlessSegments then
        local segments={}
        for _,segment in ipairs(trace.SeamlessSegments) do
            segments[#segments+1]={StartPos=Vector(segment.StartPos),HitPos=Vector(segment.HitPos)}
        end
        state.clicks[weapon]={tick=engine.TickCount(),hit=Vector(trace.HitPos),segments=segments}
    end
    return trace
end
function SP.CameraEffectFilter(owner,start,original,whitelist)
    local allowed=SP.ComposeTraceFilter(original,whitelist,owner)
    return function(ent)
        if ent:GetClass()=="gmod_cameraprop" and ent.GetPlayer and ent:GetPlayer()==owner
            and ent:GetPos():DistToSqr(start)<4096 then return false end
        return allowed(ent)
    end
end
function SP.CameraToolTrace(weapon,base,...)
    if not SP.HasTraversablePortals() then return SP.RememberToolClick(weapon,base(weapon,...)) end
    local owner=weapon:GetOwner()
    if not IsValid(owner) then return SP.RememberToolClick(weapon,base(weapon,...)) end
    local start=owner:GetShootPos()
    local camera=weapon:GetMode()=="camera"
    local line,hull,active=util.TraceLine,util.TraceHull,true
    local line_result
    local function filtered(data)
        if not camera then return data end
        local work={}
        for key,value in pairs(data) do work[key]=value end
        work.filter=SP.CameraEffectFilter(owner,start,data.filter,data.whitelist)
        work.whitelist=false
        return work
    end
    local line_wrapper=function(data)
        if not active then return line(data) end
        line_result=line(filtered(data))
        return line_result
    end
    local hull_wrapper=function(data)
        if not active then return hull(data) end
        -- Sandbox retries world hits with a zero-size hull. Keep that retry on
        -- the portal path, or it replaces the remote map hit with the entrance.
        if line_result and line_result.SeamlessSegments then
            return SP.TracePortalLine(filtered(data),hull)
        end
        return hull(filtered(data))
    end
    util.TraceLine,util.TraceHull=line_wrapper,hull_wrapper
    local args={...}
    local ok,result=xpcall(function() return base(weapon,unpack(args)) end,debug.traceback)
    active=false
    if util.TraceLine==line_wrapper then util.TraceLine=line end
    if util.TraceHull==hull_wrapper then util.TraceHull=hull end
    if not ok then error(result,0) end
    return SP.RememberToolClick(weapon,result)
end
function SP.AdaptCameraToolTrace(weapon)
    if not IsValid(weapon) or weapon:GetClass()~="gmod_tool" or not isfunction(weapon.DoToolTrace)
        or state.camera_traces[weapon] then return end
    local record={base=weapon.DoToolTrace}
    record.wrapper=function(self,...) return SP.CameraToolTrace(self,record.base,...) end
    state.camera_traces[weapon]=record
    weapon.DoToolTrace=record.wrapper
end
hook.Add("Think","seamless_portals_camera_trace",function()
    for _,owner in ipairs(player.GetAll()) do SP.AdaptCameraToolTrace(owner:GetActiveWeapon()) end
end)
function SP.ToolEffectSegments(data)
    local weapon=data:GetEntity()
    if not IsValid(weapon) or weapon:GetClass()~="gmod_tool" then return end
    -- Tools may remove or replace the target before they emit their feedback.
    local click=state.clicks[weapon]
    if click and click.tick==engine.TickCount() and click.hit:DistToSqr(data:GetOrigin())<4 then return click.segments end
    local owner=weapon:GetOwner()
    if not IsValid(owner) then return end
    local start=owner:GetShootPos()
    local filter
    if weapon.GetMode and weapon:GetMode()=="camera" then
        -- Camera is created at the eye before DoShootEffect retraces the click.
        -- Exclude that new camera, which can otherwise enclose the ray origin.
        filter=SP.CameraEffectFilter(owner,start,{owner,weapon,owner:GetVehicle()})
    else filter={owner,weapon} end
    local trace=SP.TracePortalLine({start=start,endpos=start+owner:GetAimVector()*56756,
        filter=filter,mask=MASK_SHOT})
    if trace.SeamlessSegments and trace.HitPos:DistToSqr(data:GetOrigin())<4 then return trace.SeamlessSegments end
end
function SP.EmitToolEffect(name,data,...)
    if string.lower(name)~="tooltracer" or not SP.HasTraversablePortals() then return state.base(name,data,...) end
    local segments=SP.ToolEffectSegments(data)
    if not segments then return state.base(name,data,...) end
    local weapon,attachment=data:GetEntity(),data:GetAttachment()
    local origin,start=data:GetOrigin(),data:GetStart()
    for i,segment in ipairs(segments) do
        local effect=EffectData()
        effect:SetOrigin(segment.HitPos)
        effect:SetStart(segment.StartPos)
        -- EffectData can retain native fields from the preceding allocation.
        effect:SetEntity(NULL) effect:SetAttachment(0)
        if i==1 then effect:SetEntity(weapon) effect:SetAttachment(attachment) end
        state.base(name,effect,...)
    end
    data:SetEntity(weapon) data:SetAttachment(attachment)
    data:SetOrigin(origin) data:SetStart(start)
end
if not state.wrapper then
    state.wrapper=function(...) return SP.EmitToolEffect(...) end
    util.Effect=state.wrapper
end
hook.Add("ShutDown","seamless_portals_tool_effects",function()
    if util.Effect==state.wrapper then util.Effect=state.base end
    for weapon,record in pairs(state.camera_traces) do
        if IsValid(weapon) and weapon.DoToolTrace==record.wrapper then weapon.DoToolTrace=record.base end
    end
end)
