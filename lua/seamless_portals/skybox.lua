-- Six-face fallback adapted from Xalalau's mee-portals behavior. The newer
-- two-target renderer is retained; no global halo.Add replacement is installed.
if not CLIENT then return end
local SP=SeamlessPortals
local enabled=CreateClientConVar("seamless_portals_skyfallback","1",true,false,"Draw a missing 2D sky inside portal views",0,1)
local name,materials=nil,{}
local suffixes={"bk","dn","ft","lf","rt","up"}
local offsets={Vector(0,1,0),Vector(0,0,-1),Vector(0,-1,0),Vector(-1,0,0),Vector(1,0,0),Vector(0,0,1)}
local normals={Vector(0,-1,0),Vector(0,0,1),Vector(0,1,0),Vector(1,0,0),Vector(-1,0,0),Vector(0,0,-1)}
function SP.DrawFallbackSky(position)
    local cv=GetConVar("sv_skyname")
    if not cv then return end
    local current=cv:GetString()
    if current~=name then
        name,materials=current,{}
        for i,suffix in ipairs(suffixes) do materials[i]=Material("skybox/"..name..suffix) end
    end
    local old_clip=render.EnableClipping(false)
    local ok,err=xpcall(function()
        -- Disable depth WRITES only. Existing world depth must still occlude sky.
        render.OverrideDepthEnable(true,false)
        for i,material in ipairs(materials) do
            if not material:IsError() then
                render.SetMaterial(material)
                render.DrawQuadEasy(position+offsets[i]*16000,normals[i],32000,32000,color_white,(i==2 or i==6) and 180 or 0)
            end
        end
    end,debug.traceback)
    render.OverrideDepthEnable(false,false)
    render.EnableClipping(old_clip)
    if not ok then ErrorNoHalt("[Seamless Portals] Sky fallback: "..tostring(err).."\n") end
end
hook.Add("PostDrawTranslucentRenderables","seamless_portals_sky_fallback",function(depth,skybox)
    if depth or skybox or not enabled:GetBool() or not SP.Rendering or SP.PortalSkySeen
        or not SP.FiniteVector(SP.PortalVirtualEye) then return end
    if util.IsSkyboxVisibleFromPoint(SP.PortalVirtualEye) then return end
    SP.DrawFallbackSky(SP.PortalVirtualEye)
    SP.PortalSkySeen=true
end)
