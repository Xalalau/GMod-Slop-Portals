-- F09: The world is mirrored before the viewmodel is drawn. Physgun native
-- sprites belong to the earlier world pass, so their screen position diverges.
-- Own only the local first-person effects in a mirrored MAIN view.
local SP=SeamlessPortals
local glow=Material("sprites/light_glow02_add")
local beam=Material("sprites/physbeam")
local activeBeam=Material("sprites/physbeama")
local beamWidth=8
local context
local localMuzzle
function SP.CachePhysgunMuzzle()
    if SP.Rendering then return end
    localMuzzle=nil
    local ply=LocalPlayer()
    if not IsValid(ply) then return end
    local weapon=ply:GetActiveWeapon()
    if not IsValid(weapon) or weapon:GetClass()~="weapon_physgun" then return end
    local source=ply:ShouldDrawLocalPlayer() and weapon or ply:GetViewModel()
    local attachment=IsValid(source) and source:GetAttachment(source:LookupAttachment("muzzle"))
    if attachment then localMuzzle={frame=FrameNumber(),weapon=weapon,pos=Vector(attachment.Pos)} end
end
hook.Add("PreRender","seamless_portals_physgun_muzzle",SP.CachePhysgunMuzzle)
function SP.PhysgunMuzzle(ply,weapon)
    -- Portal views can draw the local avatar; retain the main view's muzzle.
    if ply==LocalPlayer() and localMuzzle and localMuzzle.frame==FrameNumber() and localMuzzle.weapon==weapon then
        return localMuzzle.pos
    end
    local attachment=weapon:GetAttachment(weapon:LookupAttachment("muzzle"))
    return attachment and attachment.Pos or ply:EyePos()
end
local function mirrored_view(ply,weapon)
    return not SP.Rendering and SP.ToggleMirror and SP.ToggleMirror()
        and IsValid(ply) and ply==LocalPlayer() and ply:Alive() and not ply:ShouldDrawLocalPlayer()
        and IsValid(weapon) and weapon:GetClass()=="weapon_physgun"
end
local aimCache=setmetatable({},{__mode="k"})
local function aiming_segments(ply)
    if not ply:KeyDown(IN_ATTACK) or SP.WantsPortalPhysgun(ply) or SP.GetHeldRecord(ply) or not SP.TracePortalLine then return end
    local cached=aimCache[ply]
    if cached and cached.frame==FrameNumber() then return cached.segments end
    local start=ply:EyePos()
    local native,carry=GetConVar("physgun_maxrange"),GetConVar("seamless_portals_carry_reach")
    local reach=math.Clamp(math.min(native and native:GetFloat() or 4096,carry and carry:GetFloat() or 4096),128,16384)
    local tr=SP.TracePortalLine({start=start,endpos=start+ply:GetAimVector()*reach,filter=ply,
        mask=MASK_SHOT,SeamlessMaxHops=1,SeamlessFeature="props"})
    local path=tr.SeamlessSegments
    local segments
    if path and #path==2 then
        local entry=path[1].Entity
        segments={{start=start,finish=path[1].HitPos},
            {start=SP.TransformPortal(entry,entry:GetExitPortal(),path[1].HitPos),finish=path[2].HitPos}}
        segments.entry=entry
    end
    aimCache[ply]={frame=FrameNumber(),segments=segments}
    return segments
end
local function held_segments(ply,target,bone,grab,entityFrame)
    local matrix=not entityFrame and target:GetBoneMatrix(target:TranslatePhysBoneToBone(bone))
    local hit=matrix and LocalToWorld(grab,angle_zero,matrix:GetTranslation(),matrix:GetAngles()) or target:LocalToWorld(grab)
    local start=ply:EyePos()
    local entry=target:GetNWEntity("seamless_portals_clip_entry")
    local exit=SP.IsPortal(entry) and entry:GetExitPortal()
    if SP.IsUsableLink(entry,exit) then
        local a,b=SP.PlaneDistance(entry,start),SP.PlaneDistance(entry,hit)
        if a>=0 and b<0 then
            local point=LerpVector(a/(a-b),start,hit)
            if SP.InAperture(entry,point) then
                return {{start=start,finish=point},
                    {start=SP.TransformPortal(entry,exit,point),finish=SP.TransformPortal(entry,exit,hit)},entry=entry}
            end
            return {{start=start,finish=point}}
        end
    end
    return {{start=start,finish=hit}}
end
function SP.NativePhysgunSegments(ply)
    if not IsValid(ply) then return end
    local handle=ply:GetNWEntity("seamless_portals_native_physgun_handle")
    if not IsValid(handle) then return aiming_segments(ply) end
    local target=ply:GetNWEntity("seamless_portals_held")
    if not IsValid(target) then return end
    return held_segments(ply,target,ply:GetNWInt("seamless_portals_physgun_bone",0),
        ply:GetNWVector("seamless_portals_physgun_grab"),handle:GetNWBool("seamless_portals_physgun_entity_grab",false))
end
local ordinaryGrips=setmetatable({},{__mode="k"})
function SP.NativePhysgunExitSegments(ply)
    -- The engine already draws this hold through the portal view.
    if SP.Rendering or not IsValid(ply) or not ply:KeyDown(IN_ATTACK)
        or IsValid(ply:GetNWEntity("seamless_portals_native_physgun_handle")) then return end
    local grip=ordinaryGrips[ply]
    if not grip or FrameNumber()-grip.frame>1 or not IsValid(grip.target)
        or grip.target~=ply:GetNWEntity("seamless_portals_held") then return end
    local segments=held_segments(ply,grip.target,grip.bone,grip.grab)
    if #segments==2 then return segments end
end
function SP.CollectPhysgunHalo(ply,weapon,enabled,target,bone,local_hit)
    if SP.Rendering or not IsValid(target) then return end
    if IsValid(ply:GetNWEntity("seamless_portals_native_physgun_handle")) then
        target=ply:GetNWEntity("seamless_portals_held")
    end
    if not IsValid(target) or SP.IsPortal(target:GetNWEntity("seamless_portals_clip_entry"))
        or target:GetClass()=="seamless_portal_clone" then return end
    local gm=gmod.GetGamemode()
    if gm and gm.DrawPhysgunBeam then
        -- Keep the gamemode's halo collection when replacing only its beam.
        gm:DrawPhysgunBeam(ply,weapon,enabled,target,bone,local_hit)
    end
end
function SP.MirrorPhysgunContext(ply,weapon,enabled,target,bone,local_hit)
    local native=IsValid(ply) and IsValid(ply:GetNWEntity("seamless_portals_native_physgun_handle"))
    if IsValid(ply) then
        ordinaryGrips[ply]=enabled and not native and IsValid(target) and isvector(local_hit)
            and {target=target,bone=bone or 0,grab=Vector(local_hit),frame=FrameNumber()} or nil
    end
    local segments=enabled and (native or not IsValid(target)) and SP.NativePhysgunSegments(ply)
    if segments then
        SP.CollectPhysgunHalo(ply,weapon,enabled,target,bone,local_hit)
        if mirrored_view(ply,weapon) then
            context={weapon=weapon,frame=FrameNumber(),enabled=true,screen=segments and segments[1].finish:ToScreen()}
        end
        return false
    end
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
    SP.CollectPhysgunHalo(ply,weapon,enabled,target,bone,local_hit)
    context={weapon=weapon,frame=FrameNumber(),enabled=enabled,screen=screen}
    return false -- Hide both misplaced native sprites AND their native beam.
end
hook.Add("DrawPhysgunBeam","seamless_portals_mirror_physgun",SP.MirrorPhysgunContext)
function SP.BuildPhysgunBeamPaths(start,finish,control,entry,exit)
    local sections={{}}
    local previous,distance
    local crossed=false
    for i=0,16 do
        local t=i/16
        local point=start*((1-t)^2)+control*(2*t*(1-t))+finish*(t*t)
        local depth=entry and SP.PlaneDistance(entry,point)
        if previous and not crossed and depth and distance>=0 and depth<0 then
            local f=distance/(distance-depth)
            local cut=LerpVector(f,previous.pos,point)
            local cutT=previous.t+(t-previous.t)*f
            sections[1][#sections[1]+1]={pos=cut,t=cutT}
            sections[2]={{pos=SP.TransformPortal(entry,exit,cut),t=cutT}}
            crossed=true
        end
        local section=sections[#sections]
        section[#section+1]={pos=crossed and SP.TransformPortal(entry,exit,point) or point,t=t}
        previous,distance={pos=point,t=t},depth
    end
    return sections
end
local beamAnimation=setmetatable({},{__mode="k"})
local function beam_layers(ply,holding)
    local animation=beamAnimation[ply]
    if not animation or animation.frame~=FrameNumber() then
        animation={frame=FrameNumber(),widths={2,math.Rand(2,5),math.Rand(2,6)}}
        beamAnimation[ply]=animation
    end
    local scroll=CurTime()*(holding and 10 or -2)
    return animation.widths,{scroll,scroll*1.1,-scroll*0.9}
end
local function draw_beam_path(path,color,width,scroll,length,reverse)
    if #path<2 then return end
    render.StartBeam(#path)
    for index=1,#path do
        local point=path[reverse and #path-index+1 or index]
        local fade=math.min(1,point.t*16,(1-point.t)*16)
        local uv=scroll%1-(reverse and 1-point.t or point.t)*length/50
        render.AddBeam(point.pos,width,uv,Color(color.r*fade,color.g*fade,color.b*fade,255))
    end
    render.EndBeam()
end
hook.Add("PostDrawTranslucentRenderables","seamless_portals_native_physgun",function(depth,skybox)
    local beams=GetConVar("physgun_drawbeams")
    if depth or skybox or (beams and not beams:GetBool()) then return end
    for _,ply in ipairs(player.GetAll()) do
        local weapon=ply:GetActiveWeapon()
        local segments=IsValid(weapon) and weapon:GetClass()=="weapon_physgun" and SP.NativePhysgunSegments(ply)
        local exitOnly
        if not segments and IsValid(weapon) and weapon:GetClass()=="weapon_physgun" then
            segments=SP.NativePhysgunExitSegments(ply)
            exitOnly=true
        end
        if segments then
            local c=ply:GetWeaponColor():GetNormalized()
            local color=Color(c.x*255,c.y*255,c.z*255,255)
            local start=SP.PhysgunMuzzle(ply,weapon)
            local entry=segments.entry
            local exit=SP.IsPortal(entry) and entry:GetExitPortal()
            local finish=segments[#segments].finish
            if SP.IsUsableLink(entry,exit) then finish=SP.TransformPortal(exit,entry,finish) else entry=nil end
            local holding=IsValid(ply:GetNWEntity("seamless_portals_held"))
            local length=start:Distance(finish)
            local control=holding and ply:EyePos()+ply:GetAimVector()*(length*0.6) or finish
            local paths=SP.BuildPhysgunBeamPaths(start,finish,control,entry,exit)
            local widths,scrolls=beam_layers(ply,holding)
            render.SetMaterial(holding and activeBeam or beam)
            for i,path in ipairs(paths) do
                if i~=1 or (not exitOnly and not mirrored_view(ply,weapon)) then
                    for pass=1,3 do draw_beam_path(path,color,widths[pass],scrolls[pass],length,pass>1) end
                end
            end
            render.SetMaterial(glow)
            render.DrawSprite(segments[#segments].finish,6,6,color)
        end
    end
end)
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
    local nx,ny=-dy/length*beamWidth*0.5,dx/length*beamWidth*0.5
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
