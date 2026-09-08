-- Clip the native handle even before its independently-networked exit proxy is
-- available. Clip ownership is explicit and cannot erase a newer owner.
local SP=SeamlessPortals
SP.ClippedHandles=SP.ClippedHandles or setmetatable({},{__mode="k"})
local function update(ent,portal)
    if not IsValid(ent) then SP.ClippedHandles[ent]=nil return end
    if SP.IsPortal(portal) then
        SP.ClippedHandles[ent]=portal
        ent.SEAMLESS_PORTALS_CLIP_OWNER=SP
        local normal=portal:GetUp()
        ent:SetRenderClipPlaneEnabled(true)
        ent:SetRenderClipPlane(normal,normal:Dot(portal:GetPos()))
    else
        SP.ClippedHandles[ent]=nil
        if ent.SEAMLESS_PORTALS_CLIP_OWNER==SP then
            ent.SEAMLESS_PORTALS_CLIP_OWNER=nil
            ent:SetRenderClipPlaneEnabled(false)
        end
    end
end
hook.Add("EntityNetworkedVarChanged","seamless_portals_handle_clip",function(ent,key,_,value)
    if key=="seamless_portals_clip_entry" then update(ent,value) end
end)
hook.Add("NetworkEntityCreated","seamless_portals_handle_clip",function(ent)
    update(ent,ent:GetNWEntity("seamless_portals_clip_entry"))
end)
hook.Add("PreDrawOpaqueRenderables","seamless_portals_handle_clip",function(_,sky)
    if sky then return end
    for ent,portal in pairs(SP.ClippedHandles) do update(ent,portal) end
end)
hook.Add("ShutDown","seamless_portals_handle_clip",function()
    for ent in pairs(SP.ClippedHandles) do update(ent,NULL) end
end)
