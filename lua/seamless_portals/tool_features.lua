local SP=SeamlessPortals
SP.ToolFeatureDefaults={props=true,players=true,damage=true,sound=true,funnel=false}
if CLIENT then
    for name,default in pairs(SP.ToolFeatureDefaults) do
        CreateClientConVar("seamless_portals_feature_"..name,default and "1" or "0",true,true,"New portal behavior: "..name,0,1)
    end
    function SP.AddPhysgunHelp(panel)
        panel:Help("Physgun: hold Alt + Shift (Walk + Sprint) to grab a portal.")
    end
    function SP.AddFeatureControls(panel)
        SP.AddPhysgunHelp(panel)
        for _,item in ipairs({{"Players","players"},{"Props (including carried props)","props"},{"Hitscan damage","damage"},{"Spatial sound","sound"},{"Funneling assistance","funnel"}}) do
            panel:CheckBox(item[1],"seamless_portals_feature_"..item[2])
        end
    end
end
function SP.ApplyToolFeatures(portal,owner)
    if not SERVER or not SP.IsPortal(portal) or not IsValid(owner) then return false end
    for name,default in pairs(SP.ToolFeatureDefaults) do
        SP.SetFeature(portal,name,owner:GetInfoNum("seamless_portals_feature_"..name,default and 1 or 0)~=0)
    end
    return true
end
function SP.RawToolTrace(tool,incoming,button)
    if not incoming.SeamlessSegments then return incoming end
    local owner=tool:GetOwner()
    if not IsValid(owner) then return nil end
    local data=util.GetPlayerTrace(owner)
    data.mask=bit.bor(CONTENTS_SOLID,CONTENTS_MOVEABLE,CONTENTS_MONSTER,CONTENTS_WINDOW,CONTENTS_DEBRIS,CONTENTS_GRATE,CONTENTS_AUX)
    data.filter={owner,owner:GetVehicle()}
    local trace=SP.TraceLine(data)
    if not trace.Hit then return nil end
    -- Native Sandbox checked permission on the REMOTE trace. Recheck on the
    -- actual portal before changing it; never bypass protection via retargeting.
    local weapon=tool:GetWeapon()
    local mode=IsValid(weapon) and weapon:GetMode() or tool.Mode
    if not gamemode.Call("CanTool",owner,trace,mode,tool,button) then return nil end
    return trace
end
