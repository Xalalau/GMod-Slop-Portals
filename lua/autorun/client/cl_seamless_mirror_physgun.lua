-- F09: The world is mirrored before the viewmodel is drawn. Physgun native
-- sprites belong to the earlier world pass, so their screen position diverges.
-- Own only the local first-person effects in a mirrored MAIN view.
local SP=SeamlessPortals
local glow=Material("sprites/light_glow02_add")
local context
local function mirrored_view(ply,weapon)
    return not SP.Rendering and SP.ToggleMirror and SP.ToggleMirror()
        and IsValid(ply) and ply==LocalPlayer() and ply:Alive() and not ply:ShouldDrawLocalPlayer()
        and IsValid(weapon) and weapon:GetClass()=="weapon_physgun"
end
function SP.MirrorPhysgunContext(ply,weapon,enabled,target,bone,local_hit)
    if not mirrored_view(ply,weapon) then
        if IsValid(target) and (SP.IsPortal(target:GetNWEntity("seamless_portals_clip_entry"))
            or target:GetClass()=="seamless_portal_clone") then
            -- Keep the native beam; skip Sandbox's collection of held halos.
            return true
        end
        return
    end
    local hit
    if enabled and IsValid(target) and isvector(local_hit) then
        local matrix=target:GetBoneMatrix(target:TranslatePhysBoneToBone(bone or 0))
        if matrix then hit=LocalToWorld(local_hit,angle_zero,matrix:GetTranslation(),matrix:GetAngles())
        else hit=target:LocalToWorld(local_hit) end
    end
    local screen=hit and hit:ToScreen()
    context={weapon=weapon,frame=FrameNumber(),enabled=enabled,screen=screen}
    return false -- Hide both misplaced native sprites AND their native beam.
end
hook.Add("DrawPhysgunBeam","seamless_portals_mirror_physgun",SP.MirrorPhysgunContext)
function SP.DrawMirrorPhysgun(vm,ply,weapon)
    if not mirrored_view(ply,weapon) or not IsValid(vm) then return end
    local attachment=vm:LookupAttachment("muzzle")
    local muzzle=vm:GetAttachment(attachment and attachment>0 and attachment or 1)
    if not muzzle then return end
    local c=ply:GetWeaponColor()
    local color=Color(math.Clamp(c.x*255,0,255),math.Clamp(c.y*255,0,255),math.Clamp(c.z*255,0,255),210)
    -- This hook already uses the actual viewmodel FOV, including addon FOVs.
    -- Never flip the weapon, alter its transform, or guess a viewmodel FOV.
    render.SetMaterial(glow) render.DrawSprite(muzzle.Pos,7,7,color)
    local r=context
    local beams=GetConVar("physgun_drawbeams")
    if not r or r.frame~=FrameNumber() or r.weapon~=weapon or not r.enabled or not r.screen
        or not r.screen.visible or (beams and not beams:GetBool()) then return end
    local start=muzzle.Pos:ToScreen() -- evaluated IN viewmodel projection
    if not start.visible then return end
    local x,y=ScrW()-r.screen.x,r.screen.y -- target belongs to the flipped WORLD
    local dx,dy=x-start.x,y-start.y
    local length=math.sqrt(dx*dx+dy*dy)
    if length<1 then return end
    local nx,ny=-dy/length,dx/length
    cam.Start2D()
    local ok,err=xpcall(function()
        draw.NoTexture() surface.SetDrawColor(color)
        surface.DrawPoly({{x=start.x+nx,y=start.y+ny},{x=x+nx,y=y+ny},
            {x=x-nx,y=y-ny},{x=start.x-nx,y=start.y-ny}})
    end,debug.traceback)
    cam.End2D()
    if not ok then ErrorNoHalt("[Seamless Portals] Mirror physgun overlay: "..tostring(err).."\n") end
end
hook.Add("PostDrawViewModel","seamless_portals_mirror_physgun",SP.DrawMirrorPhysgun)
