-- Bounded segmented traces. Never alter a caller's input or retained trace result.
local SP = SeamlessPortals
SP.TraceLine = SP.TraceLine or util.TraceLine
SP.RawTraceLine = SP.TraceLine
local function copy(t)
    local out = {}
    for k, v in pairs(t) do if k ~= "output" then out[k] = v end end
    return out
end
function SP.CanCrossTrace(tr, start, direction, feature)
    local entry = tr.Entity
    if not tr.Hit or tr.StartSolid or not SP.IsPortal(entry) then return false end
    local exit = entry:GetExitPortal()
    return SP.IsUsableLink(entry, exit) and (not feature or SP.LinkAllows(entry, exit, feature))
        and tr.HitNormal:Dot(entry:GetUp()) > 0.9 and direction:Dot(entry:GetUp()) < -1e-6
        and (start-entry:GetPos()):Dot(entry:GetUp()) >= -0.05
        and SP.InAperture(entry, tr.HitPos)
        and SP.InAperture(exit, (SP.TransformPortal(entry, exit, tr.HitPos)))
end
SeamlessPortals.TracePortalLine = function(data, trace_function)
    trace_function = trace_function or SP.TraceLine
    if data.SeamlessIgnore or not SP.FiniteVector(data.start) or not SP.FiniteVector(data.endpos) then
        return trace_function(data)
    end
    local work, segments = copy(data), {}
    work.output = nil
    local original_direction = data.endpos-data.start
    local original_length = original_direction:Length()
    local travelled, remaining_fraction, result = 0, 1, nil
    local max_hops = math.Clamp(math.floor(tonumber(data.SeamlessMaxHops) or 8), 0, 16)
    local first
    for hop = 0, max_hops do
        result = copy(trace_function(work))
        first = first or result
        segments[#segments+1] = copy(result)
        local segment_fraction = math.Clamp(result.Fraction or 1, 0, 1)
        travelled = travelled + remaining_fraction * segment_fraction
        remaining_fraction = remaining_fraction * (1-segment_fraction)
        local direction = (work.endpos-work.start):GetNormalized()
        if hop == max_hops or remaining_fraction <= 1e-8
            or not SP.CanCrossTrace(result, work.start, direction) then break end
        local entry, exit = result.Entity, result.Entity:GetExitPortal()
        local new_start = SP.TransformPortal(entry, exit, result.HitPos)
        local new_end = SP.TransformPortal(entry, exit, work.endpos)
        local length = (new_end-new_start):Length()
        local epsilon = math.min(0.05, length)
        if length <= 1e-6 then break end
        local epsilon_fraction = remaining_fraction * epsilon / length
        travelled, remaining_fraction = travelled+epsilon_fraction, remaining_fraction-epsilon_fraction
        work.start = new_start + (new_end-new_start):GetNormalized()*epsilon
        work.endpos = new_end
        work.filter = SP.ComposeTraceFilter(data.filter, data.whitelist, exit)
        work.whitelist = false
    end
    if #segments > 1 then
        result.SeamlessSegments = segments
        result.Fraction = math.Clamp(travelled, 0, 1)
        result.StartPos, result.Normal = Vector(data.start), original_direction:GetNormalized()
        result.StartSolid, result.AllSolid = first.StartSolid, first.AllSolid
        result.FractionLeftSolid = first.FractionLeftSolid
        result.SeamlessOriginalDistance = original_length
    else
        result.SeamlessSegments = nil
    end
    if data.output then
        -- Preserve ordinary output-table semantics while removing stale custom fields.
        data.output.SeamlessSegments, data.output.SeamlessOriginalDistance = nil, nil
        for k, v in pairs(result) do data.output[k] = v end
        return data.output
    end
    return result
end
local cv = CreateConVar("seamless_portals_global_trace", "1", bit.bor(FCVAR_ARCHIVE, FCVAR_REPLICATED), "Portal-aware global line traces while linked portals exist", 0, 1)
-- Reuse one wrapper identity on refresh. A third party wrapping us owns the outer
-- function; never stomp it or capture it and create an indirect recursion cycle.
SP.TraceOwnership = SP.TraceOwnership or {base = util.TraceLine, active = false}
local state = SP.TraceOwnership
if not state.wrapper then
    state.wrapper = function(data)
        if not state.active or state.busy or data.SeamlessIgnore then return state.base(data) end
        state.busy = true
        local ok, result = xpcall(function() return SP.TracePortalLine(data, state.base) end, debug.traceback)
        state.busy = false
        if not ok then error(result, 0) end
        return result
    end
end
-- Uninstall the old RC1 wrapper once; it otherwise remains in the chain on refresh.
if SP.GlobalTraceWrapper and util.TraceLine == SP.GlobalTraceWrapper and SP.GlobalTraceWrapper ~= state.wrapper then
    util.TraceLine = SP.TraceBeforeWrapper or SP.TraceLine
    state.base = util.TraceLine
end
SP.GlobalTraceWrapper = state.wrapper
function SP.UpdateTraceOwnership()
    state.active = cv:GetBool() and SP.HasTraversablePortals()
    if state.active and not state.installed then
        state.base, state.installed = util.TraceLine, true
        util.TraceLine = state.wrapper
    elseif not state.active and state.installed and util.TraceLine == state.wrapper then
        util.TraceLine, state.installed = state.base, false
    end
end
hook.Add("Think", "seamless_portals_trace_ownership", SP.UpdateTraceOwnership)
hook.Add("ShutDown", "seamless_portals_trace_ownership", function()
    state.active = false
    if util.TraceLine == state.wrapper then util.TraceLine = state.base end
end)
SP.UpdateTraceOwnership()
