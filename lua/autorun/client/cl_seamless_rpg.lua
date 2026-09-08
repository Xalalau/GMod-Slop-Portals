-- The native RPG dot predicts its own straight trace and ignores its server position.
local SP=SeamlessPortals
SP.RPGRenderOwnership=SP.RPGRenderOwnership or {}
local state=SP.RPGRenderOwnership
state.lasers=state.lasers or setmetatable({},{__mode="k"})
local function adapt_laser(ent)
    if not IsValid(ent) or ent:GetClass()~="env_laserdot" or state.lasers[ent] then return end
    local base=ent.RenderOverride
    local wrapper=function(self,...)
        if self:GetNWBool("seamless_portals_rpg_hidden",false) then return end
        if base then return base(self,...) end
        return self:DrawModel(...)
    end
    state.lasers[ent]={base=base,wrapper=wrapper}
    ent.RenderOverride=wrapper
end
hook.Add("OnEntityCreated","seamless_portals_rpg_render",adapt_laser)
for _,ent in ipairs(ents.FindByClass("env_laserdot")) do adapt_laser(ent) end

hook.Add("ShutDown","seamless_portals_rpg_render",function()
    for ent,record in pairs(state.lasers) do
        if IsValid(ent) and ent.RenderOverride==record.wrapper then ent.RenderOverride=record.base end
    end
end)
