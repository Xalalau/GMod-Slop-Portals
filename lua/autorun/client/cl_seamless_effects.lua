-- Adapt Sandbox effects that start a fresh camera inside a portal view.
local SP=SeamlessPortals
SP.ClientEffectAdapters=SP.ClientEffectAdapters or {}
local state=SP.ClientEffectAdapters
local refract=Material("models/spawn_effect")
function SP.DrawPortalSpawnOverlay(effect,ent,flags)
    local previous=effect:StartClip(ent,1.2)
    local ok,err=xpcall(function()
        refract:SetFloat("$refractamount",math.Clamp((effect.LifeTime-CurTime())/effect.Time,0,1)*0.1)
        render.UpdateRefractTexture()
        render.MaterialOverride(refract)
        ent:DrawModel(flags)
    end,debug.traceback)
    render.MaterialOverride()
    render.PopCustomClipPlane()
    render.EnableClipping(previous)
    if not ok then ErrorNoHalt("[Seamless Portals] Spawn overlay: "..tostring(err).."\n") end
end
function SP.InstallPortalEffectAdapters()
    for _,effect in ipairs(effects.GetList()) do
        if effect.RenderOverlay and effect.RenderParent and effect.StartClip and not state[effect] then
            local base=effect.RenderOverlay
            local wrapper=function(self,ent,flags)
                if SP.Rendering then return SP.DrawPortalSpawnOverlay(self,ent,flags) end
                return base(self,ent,flags)
            end
            state[effect]={base=base,wrapper=wrapper}
            effect.RenderOverlay=wrapper
        end
    end
end
if not state.halo then
    state.halo={base=halo.Render}
    state.halo.wrapper=function(entry)
        if not SP.Rendering or not SP.PortalVirtualEye then return state.halo.base(entry) end
        -- Native halo.Render calls Start3D() with the PVS camera, which is near
        -- the aperture. Its model pass must use the same virtual eye as the scene.
        local base=cam.Start3D
        local wrapper=function(pos,ang,fov,...)
            return base(pos or SP.PortalVirtualEye,ang or SP.PortalVirtualAngles,fov or SP.PortalViewFOV,...)
        end
        cam.Start3D=wrapper
        local ok,err=xpcall(function() state.halo.base(entry) end,debug.traceback)
        if cam.Start3D==wrapper then cam.Start3D=base end
        if not ok then error(err,0) end
    end
    halo.Render=state.halo.wrapper
end
function SP.PortalViewPoint(point,target)
    local eye=EyePos()
    local candidates={}
    for _,portal in ipairs(SP.Portals) do
        if SP.IsPortal(portal) and SP.IsUsableLink(portal,portal:GetExitPortal()) and SP.PlaneDistance(portal,eye)>0 then
            candidates[#candidates+1]=portal
        end
    end
    table.sort(candidates,function(a,b) return a:GetPos():DistToSqr(eye)<b:GetPos():DistToSqr(eye) end)
    for i=1,math.min(#candidates,8) do
        local portal=candidates[i]
        local path=SP.PortalSight(portal,portal:GetExitPortal(),eye,point,LocalPlayer(),target)
        if path and path.virtual:ToScreen().visible then return path.virtual,path end
    end
end
local face_texture=surface.GetTextureID("gui/faceposer_indicator")
function SP.DrawPortalFaceMarker(tool)
    local ent=tool:FacePoserEntity()
    if not IsValid(ent) or ent:IsWorld() or ent:GetFlexNum()==0 then return false end
    local pos=ent:GetPos()
    local attachment=ent:GetAttachment(ent:LookupAttachment("eyes"))
    if attachment then pos=attachment.Pos
    else
        for i=0,ent:GetBoneCount()-1 do
            if string.find(string.lower(ent:GetBoneName(i) or ""),"head",1,true) then pos=ent:GetBonePosition(i) break end
        end
    end
    local virtual=SP.PortalViewPoint(pos,ent)
    if not virtual then return false end
    local screen=virtual:ToScreen()
    local side=(virtual+EyeAngles():Right()*20):ToScreen()
    local size=math.abs(side.x-screen.x)
    surface.SetDrawColor(255,255,255,255) surface.SetTexture(face_texture)
    surface.DrawTexturedRect(screen.x-size,screen.y-size,size*2,size*2)
    return true
end
local function adapt_tool(tool)
    if not tool or state[tool] or not tool.DrawHUD then return end
    local base=tool.DrawHUD
    local wrapper=function(self,...)
        local enabled=GetConVar("gmod_drawtooleffects")
        if (not enabled or enabled:GetBool()) and SP.HasTraversablePortals() and SP.DrawPortalFaceMarker(self) then return end
        return base(self,...)
    end
    state[tool]={base=base,wrapper=wrapper,method="DrawHUD"}
    tool.DrawHUD=wrapper
end
hook.Add("PreRegisterTOOL","seamless_portals_face_marker",function(tool,name) if name=="faceposer" then adapt_tool(tool) end end)
hook.Add("Think","seamless_portals_effect_adapters",function()
    local ply=LocalPlayer()
    local weapon=IsValid(ply) and ply:GetActiveWeapon()
    if IsValid(weapon) and weapon:GetClass()=="gmod_tool" then adapt_tool(weapon:GetToolObject("faceposer")) end
end)
hook.Add("InitPostEntity","seamless_portals_effect_adapters",SP.InstallPortalEffectAdapters)
hook.Add("OnReloaded","seamless_portals_effect_adapters",SP.InstallPortalEffectAdapters)
SP.InstallPortalEffectAdapters()
hook.Add("ShutDown","seamless_portals_effect_adapters",function()
    for owner,record in pairs(state) do
        if istable(owner) then
            local method=record.method or "RenderOverlay"
            if owner[method]==record.wrapper then owner[method]=record.base end
        end
    end
    if halo.Render==state.halo.wrapper then halo.Render=state.halo.base end
end)
