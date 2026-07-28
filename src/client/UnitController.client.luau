local plr = game.Players.LocalPlayer
local mouse = plr:GetMouse()
local camera = workspace.CurrentCamera
local UIS = game:GetService("UserInputService")
local StarterPlayer = game:GetService("StarterPlayer")
local StarterPlayerScripts = StarterPlayer.StarterPlayerScripts
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Modules = StarterPlayerScripts.Client:WaitForChild("Modules")
local Remotes = ReplicatedStorage:WaitForChild("Remotes")

-- Ignore invisible walls for mouse raycasting.
mouse.TargetFilter = workspace:WaitForChild("Walls")

-- Load the gameplay modules.
local SelectionManager = require(Modules.SelectionManager)
local VisualManager = require(Modules.VisualManager)
local GuiManager = require(Modules.GuiManager)

-- Remote events used for unit actions.
local moveEvent = Remotes.MoveEvent
local removeSelectionEvent = Remotes.RemoveSelectionEvent
local interactEvent = Remotes.InteractEvent

local unitsFolder = workspace:WaitForChild("Units")

-- Drag and hover state variables.
local currentHoveredUnit = nil
local selectionBox = plr.PlayerGui:WaitForChild("ScreenGui").SelectionBox
local dragStart = nil
local isDragging = false
local DRAG_THRESHOLD = 20

--- ------------------------------------------
--- HELPER FUNCTIONS
--- ------------------------------------------

-- Update the selection box size and position on screen.
local function updateSelectionBox(from, to)
	local minX, minY = math.min(from.X, to.X), math.min(from.Y, to.Y)
	local maxX, maxY = math.max(from.X, to.X), math.max(from.Y, to.Y)
	selectionBox.Position = UDim2.fromOffset(minX, minY)
	selectionBox.Size = UDim2.fromOffset(maxX - minX, maxY - minY)
end

-- Find player-owned units inside the drag selection box.
local function getUnitsInBox(from, to)
	local minX, minY = math.min(from.X, to.X), math.min(from.Y, to.Y)
	local maxX, maxY = math.max(from.X, to.X), math.max(from.Y, to.Y)
	local result = {}

	for _, model in ipairs(unitsFolder:GetChildren()) do
		if model:FindFirstChild("Owner") and model.Owner.Value == plr and model.PrimaryPart then
			local screenPos, onScreen = camera:WorldToScreenPoint(model.PrimaryPart.Position)
			if
				onScreen
				and screenPos.X >= minX
				and screenPos.X <= maxX
				and screenPos.Y >= minY
				and screenPos.Y <= maxY
			then
				if model:FindFirstChild("Type") and model.Type.Value == "UNIT" then
					table.insert(result, model)
				end
			end
		end
	end
	return result
end

local function getCenterOfUnits(selectedUnits)
	local totalPosition = Vector3.new(0, 0, 0)
	local count = #selectedUnits

	if count == 0 then
		return nil
	end

	for _, unit in ipairs(selectedUnits) do
		totalPosition = totalPosition + unit.PrimaryPart.Position
	end

	-- Calculate the center point from the selected units.
	return totalPosition / count
end

--- ------------------------------------------
--- INPUT LOGIC
--- ------------------------------------------

-- Expand or shrink the selection box as the mouse moves.
local function handleDragMovement(input)
	if (input.Position - dragStart).Magnitude > DRAG_THRESHOLD then
		isDragging = true
		selectionBox.Visible = true
		updateSelectionBox(dragStart, input.Position)
	end
end

-- Manage hover effects when the cursor is over a unit.
local function handleUnitHover()
	local target = mouse.Target and mouse.Target:FindFirstAncestorOfClass("Model")
	local foundUnit = nil

	if target and target:FindFirstChild("Type") then
		foundUnit = target
	end

	if foundUnit ~= currentHoveredUnit then
		if currentHoveredUnit then
			SelectionManager.HoverEnd(currentHoveredUnit)
			GuiManager.HoverEnd()
		end

		currentHoveredUnit = foundUnit

		if currentHoveredUnit then
			SelectionManager.HoverStart(currentHoveredUnit)
			GuiManager.HoverStart(currentHoveredUnit)
		end
	end
end

-- Finish multi-unit selection after dragging.
local function finishBoxSelection(input)
	selectionBox.Visible = false
	SelectionManager.ClearAll()
	for _, u in ipairs(getUnitsInBox(dragStart, input.Position)) do
		SelectionManager.SelectUnit(u)
	end
end

-- Handle single-click selection and move orders on empty ground.
local function handleSingleClickOrMove(isShift)
	local target = mouse.Target and mouse.Target:FindFirstAncestorOfClass("Model")

	-- Select or deselect the clicked owned unit.
	if target and target:FindFirstChild("Owner") and target.Owner.Value == plr then
		if not isShift then
			SelectionManager.ClearAll()
		end
		SelectionManager.SelectUnit(target)

		-- Move the selected units to the clicked position.
	elseif mouse.Hit and #SelectionManager.SelectedUnits > 0 then
		local pos = mouse.Hit.Position

		VisualManager.ClickEffect()

		local currentCenter = getCenterOfUnits(SelectionManager.SelectedUnits)

		for _, unit in ipairs(SelectionManager.SelectedUnits) do
			if unit.PrimaryPart and unit:FindFirstChild("Type") and unit.Type.Value == "UNIT" then
				local finalUnitTarget = pos

				if currentCenter then
					-- Calculate the unit's original offset from the group center.
					local offset = unit.PrimaryPart.Position - currentCenter
					if offset.Magnitude > 5 then
						offset = offset.Unit * 2
					end
					local targetOffset = Vector3.new(offset.X, 0, offset.Z)

					-- Set the new target as the clicked point plus the unit's original offset.
					finalUnitTarget = pos + targetOffset
				end

				if isShift then
					VisualManager.AddWaypoint(unit, finalUnitTarget)
					moveEvent:FireServer(unit, { finalUnitTarget }, false)
				else
					VisualManager.ClearBeams(unit)
					VisualManager.AddWaypoint(unit, finalUnitTarget)
					moveEvent:FireServer(unit, { finalUnitTarget }, true)
				end
			end
		end
	end
end

-- Send an interaction command to all selected units.
local function handleUnitInteraction()
	for _, unit in ipairs(SelectionManager.SelectedUnits) do
		interactEvent:FireServer(unit)
	end
end

-- Toggle the spawn menu with a right-click on a building.
local function handleRightClick()
	local target = mouse.Target and mouse.Target:FindFirstAncestorOfClass("Model")

	if
		target
		and target:FindFirstChild("Owner")
		and target.Owner.Value == plr
		and target:FindFirstChild("Type")
		and target:FindFirstChild("Type").Value == "BUILDING"
	then
		local isOpen = GuiManager.IsSpawnGuiOpen(target)
		if isOpen then
			GuiManager.CloseSpawnGui(target)
		else
			GuiManager.OpenSpawnGui(target)
		end
	end
end

--- ------------------------------------------
--- EVENT LISTENERS
--- ------------------------------------------

-- Handle unit removal requests from the server.
removeSelectionEvent.OnClientEvent:Connect(function(unit)
	if not unit then
		return
	end
	local idx = table.find(SelectionManager.SelectedUnits, unit)
	if not idx then
		return
	end
	SelectionManager.DeselectUnit(unit)
end)

-- Handle input start events such as clicks and key presses.
UIS.InputBegan:Connect(function(input, gameProcessed)
	if gameProcessed then
		return
	end

	if input.KeyCode == Enum.KeyCode.E then
		SelectionManager.ClearAll()
		GuiManager.CloseAllSpawnGuis()
	elseif input.UserInputType == Enum.UserInputType.MouseButton1 then
		dragStart = input.Position
	end
end)

-- Handle mouse movement and hover updates.
UIS.InputChanged:Connect(function(input)
	if input.UserInputType == Enum.UserInputType.MouseMovement then
		if dragStart then
			handleDragMovement(input)
		end
		handleUnitHover()
	end
end)

-- Handle input release events.
UIS.InputEnded:Connect(function(input, gameProcessed)
	if gameProcessed then
		return
	end

	if input.UserInputType == Enum.UserInputType.MouseButton1 then
		if isDragging then
			finishBoxSelection(input)
		else
			local isShiftPressed = UIS:IsKeyDown(Enum.KeyCode.LeftShift) or UIS:IsKeyDown(Enum.KeyCode.RightShift)
			handleSingleClickOrMove(isShiftPressed)
		end
		dragStart, isDragging = nil, false
	elseif input.KeyCode == Enum.KeyCode.Q then
		handleUnitInteraction()
	elseif input.UserInputType == Enum.UserInputType.MouseButton2 then
		handleRightClick()
	end
end)
