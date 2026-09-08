-- Bounded Sandbox light transmission through one linked aperture.
if SERVER then AddCSLuaFile() end
local SP=SeamlessPortals
SP.ToolLightSources=SP.ToolLightSources or {}
local sources=SP.ToolLightSources
local function register(ent)
    if not IsValid(ent) or (ent:GetClass()~="gmod_light" and ent:GetClass()~="gmod_lamp") then return end
    for _,source in ipairs(sources) do if source==ent then return end end
    if #sources<128 then sources[#sources+1]=ent end
end
for _,class in ipairs({"gmod_light","gmod_lamp"}) do for _,ent in ipairs(ents.FindByClass(class)) do register(ent) end end
hook.Add("OnEntityCreated","seamless_portals_tool_lights",register)
hook.Add("EntityRemoved","seamless_portals_tool_lights",function(ent)
    for i=#sources,1,-1 do if sources[i]==ent then table.remove(sources,i) end end
end)
if SERVER then
    local next_update=0
    hook.Add("Think","seamless_portals_tool_lights",function()
        if CurTime()<next_update then return end
        next_update=CurTime()+0.25
        for _,source in ipairs(sources) do
            if IsValid(source) and source.GetFlashlightTexture then
                local texture=source:GetFlashlightTexture()
                if isstring(texture) and #texture<=256 and source:GetNWString("seamless_portals_lamp_texture")~=texture then
                    source:SetNWString("seamless_portals_lamp_texture",texture)
                end
            end
        end
    end)
    return
end
local maximum=CreateClientConVar("seamless_portals_tool_lights","4",true,false,"Maximum transmitted Sandbox lights and lamps",0,4)
local raw_trace=SP.RawTraceLine or SP.TraceLine or util.TraceLine
local function clip(vertices,plane)
    local result={}
    for i,p in ipairs(vertices) do
        local q=vertices[i%#vertices+1]
        local a,b=plane(p),plane(q)
        if a>=0 then result[#result+1]=p end
        if (a<0 and b>0) or (a>0 and b<0) then result[#result+1]=p+(q-p)*(a/(a-b)) end
    end
    return result
end
function SP.ToolLightMask(vertices,tangent)
    local planes={function(p) return p.x-0.01 end,
        function(p) return p.x*tangent-p.y end,function(p) return p.x*tangent+p.y end,
        function(p) return p.x*tangent-p.z end,function(p) return p.x*tangent+p.z end}
    for _,plane in ipairs(planes) do vertices=clip(vertices,plane) if #vertices<3 then return end end
    local polygon={}
    for _,p in ipairs(vertices) do
        local u,v=0.5+p.y/(2*p.x*tangent),0.5-p.z/(2*p.x*tangent)
        polygon[#polygon+1]={x=u*256,y=v*256,u=u,v=v}
    end
    local area=0
    for i,p in ipairs(polygon) do local q=polygon[i%#polygon+1] area=area+p.x*q.y-q.x*p.y end
    if math.abs(area)<0.1 then return end
    if area<0 then local reversed={} for i=#polygon,1,-1 do reversed[#reversed+1]=polygon[i] end polygon=reversed end
    return polygon
end
function SP.ToolLightRelay(source,entry)
    if not IsValid(source) or source:IsDormant() or not source.GetOn or not source:GetOn() or not SP.IsPortal(entry) then return end
    local exit=entry:GetExitPortal()
    if not SP.IsUsableLink(entry,exit) then return end
    local lamp=source:GetClass()=="gmod_lamp"
    local position,angles=source:GetPos(),nil
    local range=lamp and source:GetDistance() or source:GetLightSize()
    local brightness=source:GetBrightness()
    if not SP.IsFinite(range) or not SP.IsFinite(brightness) then return end
    range=math.Clamp(range,0,8192)
    if lamp then
        if not SP.IsFinite(source:GetLightFOV()) then return end
        local info=source:GetLightInfo()
        position=source:LocalToWorld(info.Offset-Vector(5,0,0))
        angles=source:LocalToWorldAngles(info.Angle)
        brightness=math.Clamp(brightness,0,8)
    else brightness=2^math.Clamp(brightness,0,6) end
    if range<=1 or brightness<=0 or SP.PlaneDistance(entry,position)<=0.5 then return end
    local closest=SP.ClosestAperturePoint(entry,position)
    if closest:DistToSqr(position)>=range*range then return end
    angles=angles or (entry:GetPos()-position):Angle()
    local mapped,mapped_angles=SP.TransformPortal(entry,exit,position,angles)
    local forward,right,up=mapped_angles:Forward(),mapped_angles:Right(),mapped_angles:Up()
    local vertices,near,tangent={},0,0
    for _,p in ipairs(SP.ApertureVertices(exit)) do
        local delta=exit:LocalToWorld(p)-mapped
        local v=Vector(delta:Dot(forward),delta:Dot(right),delta:Dot(up))
        vertices[#vertices+1]=v
        near=math.max(near,v.x)
        if v.x>0 then tangent=math.max(tangent,math.abs(v.y/v.x),math.abs(v.z/v.x)) else tangent=100 end
    end
    local fov=lamp and math.Clamp(source:GetLightFOV(),10,170) or math.Clamp(math.deg(math.atan(tangent))*2+1,1,175)
    local polygon=SP.ToolLightMask(vertices,math.tan(math.rad(fov/2)))
    if not polygon then return end
    local scale=exit:GetSize().x/entry:GetSize().x
    if near+1>=range*scale then return end
    local noworld=not lamp and source:GetLightWorld()
    local nomodel=not lamp and source:GetLightModels()
    if noworld and nomodel then return end
    return {source=source,entry=entry,exit=exit,position=mapped,angles=mapped_angles,
        source_position=position,closest=closest,polygon=polygon,fov=fov,near=near+0.25,
        far=range*scale,brightness=brightness,color=source:GetColor(),shadows=lamp,
        world=not noworld,nomodel=nomodel,
        texture=lamp and source:GetNWString("seamless_portals_lamp_texture","effects/flashlight001") or "vgui/white"}
end
SP.ToolLightSlots=SP.ToolLightSlots or {}
local slots=SP.ToolLightSlots
local function release(slot)
    if IsValid(slot.light) then slot.light:Remove() end
    slot.light=nil slot.source=nil slot.entry=nil
end
function SP.ClearToolLights()
    for _,slot in ipairs(slots) do release(slot) end
end
local function draw_mask(slot,relay)
    if not slot.rt then
        slot.rt=GetRenderTarget("seamless_portals_tool_light_mask_"..slot.id,256,256)
        slot.material=CreateMaterial("seamless_portals_tool_light_source_"..slot.id,"UnlitGeneric",{
            ["$basetexture"]="vgui/white",["$vertexcolor"]="1",["$vertexalpha"]="1"})
    end
    slot.material:SetTexture("$basetexture",relay.texture)
    render.PushRenderTarget(slot.rt)
    render.Clear(0,0,0,255,true,true)
    cam.Start2D()
    local clipping=DisableClipping(true)
    local ok,err=xpcall(function()
        surface.SetMaterial(slot.material) surface.SetDrawColor(255,255,255,255)
        surface.DrawPoly(relay.polygon)
    end,debug.traceback)
    DisableClipping(clipping)
    cam.End2D()
    render.PopRenderTarget()
    if not ok then ErrorNoHalt("[Seamless Portals] Tool light mask: "..tostring(err).."\n") end
    return ok
end
local candidates,next_search,cursor={},0,0
local function select_candidates()
    -- Refresh at most eight sources and 64 endpoints per source in one frame.
    for _=1,math.min(8,#sources) do
        cursor=cursor%#sources+1
        local source=sources[cursor]
        local rows={}
        if IsValid(source) then
            for i=1,math.min(64,#SP.Portals) do
                local relay=SP.ToolLightRelay(source,SP.Portals[i])
                if relay then rows[#rows+1]=relay end
            end
        end
        candidates[source]=rows
    end
    local all={}
    local eye=LocalPlayer():EyePos()
    for source,rows in pairs(candidates) do
        if not IsValid(source) then candidates[source]=nil
        else for _,relay in ipairs(rows) do
            if SP.IsPortal(relay.entry) and SP.IsPortal(relay.exit) and source:GetOn()
                and relay.entry:GetExitPortal()==relay.exit then
                relay.distance=relay.exit:GetPos():DistToSqr(eye)
                all[#all+1]=relay
            end
        end end
    end
    table.sort(all,function(a,b) return a.distance<b.distance end)
    local used=0
    for _,relay in ipairs(all) do
        if used>=maximum:GetInt() then break end
        local source,entry=relay.source,relay.entry
        local trace=raw_trace({start=relay.source_position,endpos=relay.closest+entry:GetUp()*0.5,
            filter={source,entry,source:GetParent()},mask=MASK_OPAQUE,SeamlessIgnore=true})
        if not trace.StartSolid and (not trace.Hit or trace.Fraction>0.999) then
            used=used+1
            slots[used]=slots[used] or {id=used}
            slots[used].source,slots[used].entry=source,entry
        end
    end
    for i=used+1,#slots do release(slots[i]) end
end
hook.Add("PreRender","seamless_portals_tool_lights",function()
    if SP.Rendering or not IsValid(LocalPlayer()) then return end
    if maximum:GetInt()<=0 or not SP.HasTraversablePortals() then SP.ClearToolLights() return end
    if CurTime()>=next_search then next_search=CurTime()+0.1 select_candidates() end
    for _,slot in ipairs(slots) do
        local relay=SP.ToolLightRelay(slot.source,slot.entry)
        if not relay then release(slot)
        elseif draw_mask(slot,relay) then
            if not IsValid(slot.light) then slot.light=ProjectedTexture() end
            local light=slot.light
            if IsValid(light) then
                light:SetPos(relay.position) light:SetAngles(relay.angles) light:SetFOV(relay.fov)
                light:SetNearZ(relay.near) light:SetFarZ(relay.far)
                light:SetColor(relay.color) light:SetBrightness(relay.brightness)
                light:SetConstantAttenuation(0) light:SetLinearAttenuation(100) light:SetQuadraticAttenuation(0)
                light:SetEnableShadows(relay.shadows) light:SetLightWorld(relay.world)
                light:SetTargetEntity(relay.nomodel and game.GetWorld() or NULL)
                light:SetTexture(slot.rt) light:SetNoCull(true) light:Update()
            end
        end
    end
end)
hook.Add("PostCleanupMap","seamless_portals_tool_lights",SP.ClearToolLights)
hook.Add("ShutDown","seamless_portals_tool_lights",SP.ClearToolLights)
