TOOL.Category="Seamless Portals"
TOOL.Name="Portal Behavior"
TOOL.Information={{name="left"},{name="right"},{name="reload"}}
if CLIENT then
    language.Add("Tool.portal_behavior_tool.name","Portal Behavior")
    language.Add("Tool.portal_behavior_tool.desc","Configure passage, damage, sound and funneling without resizing a portal")
    language.Add("Tool.portal_behavior_tool.left","Apply behavior settings")
    language.Add("Tool.portal_behavior_tool.right","Copy this portal's behavior")
    language.Add("Tool.portal_behavior_tool.reload","Restore custom defaults on this portal")
    function TOOL.BuildCPanel(panel) SeamlessPortals.AddFeatureControls(panel) end
end
function TOOL:LeftClick(trace)
    trace=SeamlessPortals.RawToolTrace(self,trace,1)
    if not trace or not SeamlessPortals.IsPortal(trace.Entity) then return false end
    if SERVER then SeamlessPortals.ApplyToolFeatures(trace.Entity,self:GetOwner()) end
    return true
end
function TOOL:RightClick(trace)
    trace=SeamlessPortals.RawToolTrace(self,trace,2)
    if not trace or not SeamlessPortals.IsPortal(trace.Entity) then return false end
    if CLIENT then
        for name in pairs(SeamlessPortals.ToolFeatureDefaults) do
            RunConsoleCommand("seamless_portals_feature_"..name,SeamlessPortals.FeatureEnabled(trace.Entity,name) and "1" or "0")
        end
    end
    return true
end
function TOOL:Reload(trace)
    trace=SeamlessPortals.RawToolTrace(self,trace,3)
    if not trace or not SeamlessPortals.IsPortal(trace.Entity) then return false end
    if SERVER then
        for name,value in pairs(SeamlessPortals.ToolFeatureDefaults) do SeamlessPortals.SetFeature(trace.Entity,name,value) end
    end
    return true
end
