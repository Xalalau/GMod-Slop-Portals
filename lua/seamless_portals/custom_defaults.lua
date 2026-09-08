-- One-time migration from RC1 opt-outs. Subsequent user configuration is kept.
local function apply()
    if SERVER then
        for _,name in ipairs({"seamless_portals_global_trace","seamless_portals_damage","seamless_portals_soundrelay_server"}) do
            local c=GetConVar(name) if c then c:SetInt(1) end
        end
    else
        for _,name in ipairs({"seamless_portals_soundrelay","seamless_portals_skyfallback"}) do
            local c=GetConVar(name) if c then c:SetInt(1) end
        end
    end
end
local marker
if SERVER then
    marker=CreateConVar("seamless_portals_custom_profile_server","0",FCVAR_ARCHIVE,"Custom defaults migration version",0,2)
else
    marker=CreateClientConVar("seamless_portals_custom_profile_client","0",true,false,"Custom defaults migration version",0,2)
end
timer.Simple(0,function()
    if marker:GetInt()<2 then apply() marker:SetInt(2) end
end)
concommand.Add(SERVER and "seamless_portals_apply_custom_defaults" or "seamless_portals_apply_custom_client_defaults",function(ply)
    if SERVER and IsValid(ply) and not ply:IsSuperAdmin() then return end
    apply() marker:SetInt(2)
end)
