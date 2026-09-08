-- F05: Each tracer ends at its aperture. Only the initial leg uses a muzzle.
-- Short moving streaks use fixed shot coordinates; damage keeps its own trace.
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
local tick,used,bytes=-1,0,0
function SP.SendBulletVisual(context,result)
    if not SERVER or not context or not context.draw or #context.segments==0 or (istable(result) and result.effects==false) then return end
    local now=engine.TickCount() if tick~=now then tick,used,bytes=now,0,0 end
    local cost=64+#context.name+#context.segments*44
    if used>=128 or bytes+cost>16384 then SP.CountField("tracer_budget_rejected") return end
    used=used+1 bytes=bytes+cost
    local recipients=RecipientFilter()
    if IsValid(context.shooter) and context.shooter:IsPlayer() then recipients:AddPlayer(context.shooter) end
    for _,segment in ipairs(context.segments) do recipients:AddPVS(segment.start) recipients:AddPVS(segment.finish) end
    net.Start(message) net.WriteString(context.name) net.WriteUInt(#context.segments,4)
    for _,segment in ipairs(context.segments) do net.WriteVector(segment.start) net.WriteVector(segment.finish) end
    -- Append an optional extension: old receivers still read the legacy prefix.
    -- WriteVector truncates coordinates outside +/-16384, including long misses.
    local weapon=IsValid(context.shooter) and context.shooter.GetActiveWeapon and context.shooter:GetActiveWeapon()
    net.WriteEntity(IsValid(weapon) and weapon or NULL)
    for _,segment in ipairs(context.segments) do
        for _,point in ipairs({segment.start,segment.finish}) do
            net.WriteFloat(point.x) net.WriteFloat(point.y) net.WriteFloat(point.z)
        end
    end
    net.Send(recipients) SP.CountField("tracer_paths")
end
if SERVER then util.AddNetworkString(message) return end
SP.TracerSegments={}
local segments=SP.TracerSegments
local material=Material("effects/spark")
local main_view
local muzzle_cache=setmetatable({},{__mode="k"})
local speeds={ar2tracer=8000,airboatguntracer=10000,airboatgunheavytracer=8000,helicoptertracer=8000}
hook.Add("RenderScene","seamless_portals_tracer_view",function(origin,angles,fov)
    if not SP.Rendering then main_view={origin=Vector(origin),angles=Angle(angles),fov=fov} end
end)
hook.Add("PostDrawViewModel","seamless_portals_tracer_muzzle",function(vm,owner,weapon)
    if SP.Rendering or not main_view or owner~=LocalPlayer() or not IsValid(vm) or not IsValid(weapon) then return end
    local id=vm:LookupAttachment("muzzle")
    local attachment=vm:GetAttachment(id>0 and id or 1)
    if not attachment then return end
    -- Viewmodel bones are only reliable during its draw, and use a different FOV.
    local screen=attachment.Pos:ToScreen()
    if not screen.visible then return end
    local view=main_view
    local forward,right,up=view.angles:Forward(),view.angles:Right(),view.angles:Up()
    local depth=(attachment.Pos-view.origin):Dot(forward)
    if depth<0.1 or depth>128 then return end
    local center=view.origin+forward*depth
    cam.Start3D(view.origin,view.angles,view.fov)
    local c,r,u=center:ToScreen(),(center+right):ToScreen(),(center+up):ToScreen()
    cam.End3D()
    if math.abs(r.x-c.x)<0.001 or math.abs(u.y-c.y)<0.001 then return end
    local x=SP.ToggleMirror and SP.ToggleMirror() and ScrW()-screen.x or screen.x
    local point=center+right*((x-c.x)/(r.x-c.x))+up*((screen.y-c.y)/(u.y-c.y))
    muzzle_cache[weapon]={offset=WorldToLocal(point,angle_zero,owner:GetShootPos(),owner:EyeAngles()),time=CurTime()}
end)
function SP.BulletMuzzlePoint(start,weapon)
    if not IsValid(weapon) then return start end
    local owner=weapon:GetOwner()
    if IsValid(owner) and owner==LocalPlayer() and not owner:ShouldDrawLocalPlayer() then
        local cached=muzzle_cache[weapon]
        if cached and CurTime()-cached.time<0.25 then
            return LocalToWorld(cached.offset,angle_zero,owner:GetShootPos(),owner:EyeAngles())
        end
        return start
    end
    local id=weapon:LookupAttachment("muzzle")
    local attachment=weapon:GetAttachment(id>0 and id or 1)
    if attachment and SP.FiniteVector(attachment.Pos) and attachment.Pos:DistToSqr(start)<16384 then return attachment.Pos end
    return start
end
function SP.EmitBulletVisual(name,path,weapon)
    local kind=string.lower(name)
    local pulse=string.find(kind,"ar2",1,true) or string.find(kind,"airboat",1,true)
    for i,segment in ipairs(path) do
        if #segments>=512 then return end
        if SP.FiniteVector(segment.start) and SP.FiniteVector(segment.finish) then
            local start=segment.start
            if i==1 then start=SP.BulletMuzzlePoint(start,weapon) end
            local delta=segment.finish-start
            local length=delta:Length()
            if length>0.01 then
                local speed=speeds[kind] or 5000
                segments[#segments+1]={start=Vector(start),finish=Vector(segment.finish),
                    direction=delta/length,length=length,speed=speed,created=CurTime(),
                    width=pulse and 1.5 or 1,color=pulse and Color(160,210,255) or Color(255,220,150)}
            end
        end
    end
end
function SP.SampleBulletTracer(segment,age)
    -- Clip both ends to this leg, including very short muzzle-to-portal paths.
    local head=math.min(segment.length,math.max(age,0)*segment.speed+96)
    local tail=math.max(0,math.max(age,0)*segment.speed)
    if tail>=head then return end
    return segment.start+segment.direction*tail,segment.start+segment.direction*head
end
hook.Add("PostDrawTranslucentRenderables","seamless_portals_segmented_tracers",function(depth,sky)
    if depth or sky then return end
    render.SetMaterial(material)
    local now=CurTime()
    for _,segment in ipairs(segments) do
        -- A sub-frame leg must get one visible frame even at a low frame rate.
        segment.born=segment.born or now
        local start,finish=SP.SampleBulletTracer(segment,now-segment.born)
        if start and finish then render.DrawBeam(start,finish,segment.width,0,1,segment.color) end
    end
end)
hook.Add("Think","seamless_portals_tracer_expiry",function()
    local now=CurTime()
    for i=#segments,1,-1 do
        local segment=segments[i]
        if now-(segment.born or segment.created)>math.max(0.1,segment.length/segment.speed) then table.remove(segments,i) end
    end
end)
net.Receive(message,function()
    local name,count=net.ReadString(),net.ReadUInt(4)
    if count>9 or #name>128 then return end
    local path={}
    for i=1,count do path[i]={start=net.ReadVector(),finish=net.ReadVector()} end
    local weapon
    local _,remaining=net.BytesLeft()
    if remaining and remaining>=(rawget(_G,"MAX_EDICT_BITS") or 13)+count*192 then
        weapon=net.ReadEntity()
        for _,segment in ipairs(path) do
            segment.start=Vector(net.ReadFloat(),net.ReadFloat(),net.ReadFloat())
            segment.finish=Vector(net.ReadFloat(),net.ReadFloat(),net.ReadFloat())
        end
    end
    SP.EmitBulletVisual(name,path,weapon)
end)
