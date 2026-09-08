TOOL.Category = "Seamless Portals"
TOOL.Name = "#Tool.portal_resizer_tool.name"

if CLIENT then
	language.Add("Tool.portal_resizer_tool.name", "Portal Resizer")
	language.Add("Tool.portal_resizer_tool.desc", "Sets the size of portals")

	TOOL.ConvarX = SeamlessPortals.ClientConVars.size_x
	TOOL.ConvarY = SeamlessPortals.ClientConVars.size_y
	TOOL.ConvarZ = SeamlessPortals.ClientConVars.size_z
	TOOL.ConvarSides = SeamlessPortals.ClientConVars.sides
	TOOL.ConvarB = SeamlessPortals.ClientConVars.backface

	TOOL.Information = {
		{name = "left"},
		{name = "right"},
	}

	language.Add("Tool.portal_resizer_tool.left", "Left Click: Set the size of a portal" )
	language.Add("Tool.portal_resizer_tool.right", "Right Click: Copy portal size, sides and backface")

	function TOOL.BuildCPanel(panel)
		panel:AddControl("label", {
			text = "Sets the size of portals",
		})
		panel:NumSlider("Portal Size X", "seamless_portals_size_x", 1, 1000, 1)
		panel:NumSlider("Portal Size Y", "seamless_portals_size_y", 1, 1000, 1)
		panel:NumSlider("Portal Size Z", "seamless_portals_size_z", 1, 100, 1)
		panel:NumSlider("Portal Sides", "seamless_portals_sides", 3, 100, 0)
		panel:CheckBox("Has Backface (Invisible until linked!)", "seamless_portals_backface")
	end

	local COLOR_GREEN = Color(0, 255, 0, 50)
	function TOOL:DrawHUD()
		local traceTable = util.GetPlayerTrace(self:GetOwner())
		local trace = SeamlessPortals.TraceLine(traceTable)

		if !IsValid(trace.Entity) or trace.Entity:GetClass() != "seamless_portal" then return end	-- dont draw the world or else u crash lol

		local mins, maxs = trace.Entity:OBBMins(), trace.Entity:OBBMaxs()
		mins[3] = mins[3]
		maxs[3] = 0

		cam.Start3D()
			render.SetColorMaterial()
			render.DrawBox(trace.Entity:GetPos(), trace.Entity:GetAngles(), mins, maxs, COLOR_GREEN)
		cam.End3D()
	end
end

function TOOL:LeftClick(trace)
    trace=SeamlessPortals.RawToolTrace(self,trace,1)
    if not trace then return false end
	if not trace then return false end

	if !IsValid(trace.Entity) or trace.Entity:GetClass() != "seamless_portal" then return false end
	if CPPI and SERVER then if !trace.Entity:CPPICanTool(self:GetOwner(), "portal_resizer_tool") then return false end end
		if CLIENT then return true end
	local sizex = self:GetOwner():GetInfoNum("seamless_portals_size_x", 1)
	local sizey = self:GetOwner():GetInfoNum("seamless_portals_size_y", 1)
	local sizez = self:GetOwner():GetInfoNum("seamless_portals_size_z", 1)
	local size = Vector(sizex, sizey, sizez)
	local sides = self:GetOwner():GetInfoNum("seamless_portals_sides", 4)
	if not SeamlessPortals.ValidateSize(size) or not SeamlessPortals.ValidateSides(sides) then return false end
	return trace.Entity:Configure(size, sides, self:GetOwner():GetInfoNum("seamless_portals_backface", 1) == 0)
end


if SERVER then
    util.AddNetworkString("SEAMLESS_PORTALS_COPY_CONFIGURATION")
else
    net.Receive("SEAMLESS_PORTALS_COPY_CONFIGURATION", function()
        local size = net.ReadVector()
        local sides, backface = net.ReadUInt(7), net.ReadBool()
        if not SeamlessPortals.ValidateSize(size) or not SeamlessPortals.ValidateSides(sides) then return end
        RunConsoleCommand("seamless_portals_size_x", tostring(size[1]))
        RunConsoleCommand("seamless_portals_size_y", tostring(size[2]))
        RunConsoleCommand("seamless_portals_size_z", tostring(size[3]))
        RunConsoleCommand("seamless_portals_sides", tostring(sides))
        RunConsoleCommand("seamless_portals_backface", backface and "1" or "0")
    end)
end

function TOOL:RightClick()
    if CLIENT then return true end
    local owner = self:GetOwner()
    local trace = SeamlessPortals.TraceLine(util.GetPlayerTrace(owner))
    if not SeamlessPortals.IsPortal(trace.Entity) then return false end
    net.Start("SEAMLESS_PORTALS_COPY_CONFIGURATION")
    net.WriteVector(trace.Entity:GetSize())
    net.WriteUInt(trace.Entity:GetSides(), 7)
    net.WriteBool(not trace.Entity:GetDisableBackface())
    net.Send(owner)

	return true
end
