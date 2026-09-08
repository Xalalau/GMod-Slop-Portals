-- F05: Tracers are a list of world-space segments, never one engine muzzle
-- attachment spanning two disconnected coordinate frames. Damage is separate.
local SP=SeamlessPortals
local message="SEAMLESS_PORTALS_TRACERS_V3"
local shot_counts=setmetatable({},{__mode="k"})
function SP.NewBulletVisual(shooter,data)
    local interval=math.floor(tonumber(data.SeamlessTracerInterval or data.Tracer or 1) or 1)
    shot_counts[shooter]=(shot_counts[shooter] or 0)+1
    return {segments={},draw=interval>0 and (shot_counts[shooter]-1)%math.max(interval,1)==0,
        shooter=shooter,name=isstring(data.TracerName) and string.sub(data.TracerName,1,128) or "Tracer"}
end
function SP.AddBulletVisual(context,start,finish)
    if not context or #context.segments>=9 or not SP.FiniteVector(start) or not SP.FiniteVector(finish) then return end
    context.segments[#context.segments+1]={start=Vector(start.x,start.y,start.z),finish=Vector(finish.x,finish.y,finish.z)}
end
local tick,used=-1,0
function SP.SendBulletVisual(context,result)
    if not SERVER or not context or not context.draw or #context.segments==0 or (istable(result) and result.effects==false) then return end
    local now=engine.TickCount() if tick~=now then tick,used=now,0 end
    if used>=128 then SP.CountField("tracer_budget_rejected") return end
    used=used+1
    local recipients=RecipientFilter()
    if IsValid(context.shooter) and context.shooter:IsPlayer() then recipients:AddPlayer(context.shooter) end
    for _,segment in ipairs(context.segments) do recipients:AddPVS(segment.start) recipients:AddPVS(segment.finish) end
    net.Start(message) net.WriteString(context.name) net.WriteUInt(#context.segments,4)
    for _,segment in ipairs(context.segments) do net.WriteVector(segment.start) net.WriteVector(segment.finish) end
    net.Send(recipients) SP.CountField("tracer_paths")
end
if SERVER then util.AddNetworkString(message) return end
SP.TracerSegments=SP.TracerSegments or {}
local segments=SP.TracerSegments
local tracer_material=Material("effects/laser1")
net.Receive(message,function()
    local name,count=net.ReadString(),net.ReadUInt(4)
    if count>9 then return end
    for i=1,count do
        local start,finish=net.ReadVector(),net.ReadVector()
        if SP.FiniteVector(start) and SP.FiniteVector(finish) and #segments<512 then
            local pulse=string.find(string.lower(name),"ar2",1,true) or string.find(string.lower(name),"airboat",1,true)
            segments[#segments+1]={start=start,finish=finish,expires=RealTime()+0.055,
                width=pulse and 1.5 or 0.7,color=pulse and Color(160,210,255) or Color(255,220,150)}
        end
    end
end)
hook.Add("PostDrawTranslucentRenderables","seamless_portals_segmented_tracers",function(depth,sky)
    if depth or sky then return end
    render.SetMaterial(tracer_material)
    for _,s in ipairs(segments) do
        if RealTime()<s.expires then render.DrawBeam(s.start,s.finish,s.width,0,1,s.color) end
    end
end)
hook.Add("Think","seamless_portals_tracer_expiry",function()
    for i=#segments,1,-1 do if RealTime()>=segments[i].expires then table.remove(segments,i) end end
end)
