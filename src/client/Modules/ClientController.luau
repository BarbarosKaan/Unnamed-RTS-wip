local ClientController = {}

local Players = game:GetService("Players")
local StarterPlayer = game:GetService("StarterPlayer")
local StarterPlayerScripts = StarterPlayer.StarterPlayerScripts
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Modules = StarterPlayerScripts.Client:WaitForChild("Modules")
local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local plr = Players.LocalPlayer
local mouse = plr:GetMouse()
local camera = workspace.CurrentCamera

mouse.TargetFilter = workspace:WaitForChild("Walls")

local loadedModules = {}
local initializedModules = {}
local hasStarted = false
local placementStarted = false
local unitStarted = false

local function loadModules()
	if next(loadedModules) ~= nil then
		return loadedModules
	end

	for _, child in ipairs(Modules:GetChildren()) do
		if child:IsA("ModuleScript") and child ~= script then
			loadedModules[child.Name] = require(child)
		end
	end

	return loadedModules
end

local function initModules()
	local modules = loadModules()
	for moduleName, module in pairs(modules) do
		if type(module.Init) == "function" and not initializedModules[moduleName] then
			module.Init(modules)
			initializedModules[moduleName] = true
		end
	end
end

function ClientController.Init()
	initModules()
end

function ClientController.StartPlacementSystem()
	if placementStarted then
		return
	end

	placementStarted = true
	local modules = loadModules()
	local PlacementManager = modules.PlacementManager
	local GuiManager = modules.GuiManager

	local gamegui = plr:WaitForChild("PlayerGui"):WaitForChild("GameGui")
	local farmZones = workspace:WaitForChild("FarmZones")
	local rigZones = workspace:WaitForChild("RigZones")
	local buildingsFrame = gamegui:WaitForChild("Buildings")
	local buildingButtonsFrame = buildingsFrame:WaitForChild("Buttons")
	local buildingButtons = GuiManager.SetupBuildingButtons(buildingButtonsFrame)
	buildingsFrame.Visible = true

	local function onBuildingStart(name)
		if name == "Farm" then
			for _, zone in pairs(farmZones:GetChildren()) do
				TweenService:Create(zone, TweenInfo.new(0.5, Enum.EasingStyle.Linear), { Transparency = 0.7 }):Play()
			end
		elseif name == "Oil Rig" then
			for _, zone in pairs(rigZones:GetChildren()) do
				TweenService:Create(zone, TweenInfo.new(0.5, Enum.EasingStyle.Linear), { Transparency = 0.7 }):Play()
			end
		end
	end

	local function onBuildingEnd()
		for _, zone in pairs(farmZones:GetChildren()) do
			TweenService:Create(zone, TweenInfo.new(0.5, Enum.EasingStyle.Linear), { Transparency = 1 }):Play()
		end
		for _, zone in pairs(rigZones:GetChildren()) do
			TweenService:Create(zone, TweenInfo.new(0.5, Enum.EasingStyle.Linear), { Transparency = 1 }):Play()
		end
	end

	for _, button in ipairs(buildingButtons) do
		if button:IsA("TextButton") then
			button.MouseButton1Click:Connect(function()
				if PlacementManager.IsPlacing() then
					PlacementManager.Cancel()
					onBuildingEnd()
				end
				PlacementManager.Start(button.Text)
				onBuildingStart(button.Text)
			end)
		end
	end

	UserInputService.InputBegan:Connect(function(input, gameProcessed)
		if gameProcessed then
			return
		end
		if not PlacementManager.IsPlacing() then
			return
		end

		if input.KeyCode == Enum.KeyCode.E then
			PlacementManager.Cancel()
			onBuildingEnd()
		elseif input.UserInputType == Enum.UserInputType.MouseButton1 then
			local success = PlacementManager.Place()
			if success then
				onBuildingEnd()
			end
		elseif input.KeyCode == Enum.KeyCode.R then
			PlacementManager.Rotate()
		end
	end)
end

function ClientController.StartUnitSystem()
	if unitStarted then
		return
	end

	unitStarted = true
	local modules = loadModules()
	local SelectionManager = modules.SelectionManager
	local VisualManager = modules.VisualManager
	local GuiManager = modules.GuiManager
	local moveEvent = Remotes.MoveEvent
	local removeSelectionEvent = Remotes.RemoveSelectionEvent
	local interactEvent = Remotes.InteractEvent

	local unitsFolder = workspace:WaitForChild("Units")
	local currentHoveredUnit = nil
	local selectionBox = plr.PlayerGui:WaitForChild("GameGui"):WaitForChild("SelectionBox")
	local dragStart = nil
	local isDragging = false
	local DRAG_THRESHOLD = 20

	local function updateSelectionBox(from, to)
		local minX, minY = math.min(from.X, to.X), math.min(from.Y, to.Y)
		local maxX, maxY = math.max(from.X, to.X), math.max(from.Y, to.Y)
		selectionBox.Position = UDim2.fromOffset(minX, minY)
		selectionBox.Size = UDim2.fromOffset(maxX - minX, maxY - minY)
	end

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
		return totalPosition / count
	end

	local function handleDragMovement(input)
		if (input.Position - dragStart).Magnitude > DRAG_THRESHOLD then
			isDragging = true
			selectionBox.Visible = true
			updateSelectionBox(dragStart, input.Position)
		end
	end

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

	local function finishBoxSelection(input)
		selectionBox.Visible = false
		SelectionManager.ClearAll()
		for _, u in ipairs(getUnitsInBox(dragStart, input.Position)) do
			SelectionManager.SelectUnit(u)
		end
	end

	local function handleSingleClickOrMove(isShift)
		local target = mouse.Target and mouse.Target:FindFirstAncestorOfClass("Model")

		if target and target:FindFirstChild("Owner") and target.Owner.Value == plr then
			if not isShift then
				SelectionManager.ClearAll()
			end
			SelectionManager.SelectUnit(target)
		elseif mouse.Hit and #SelectionManager.SelectedUnits > 0 then
			local pos = mouse.Hit.Position
			VisualManager.ClickEffect()

			local currentCenter = getCenterOfUnits(SelectionManager.SelectedUnits)

			for _, unit in ipairs(SelectionManager.SelectedUnits) do
				if unit.PrimaryPart and unit:FindFirstChild("Type") and unit.Type.Value == "UNIT" then
					local finalUnitTarget = pos

					if currentCenter then
						local offset = unit.PrimaryPart.Position - currentCenter
						if offset.Magnitude > 5 then
							offset = offset.Unit * 2
						end
						local targetOffset = Vector3.new(offset.X, 0, offset.Z)
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

	local function handleUnitInteraction()
		for _, unit in ipairs(SelectionManager.SelectedUnits) do
			interactEvent:FireServer(unit)
		end
	end

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

	UserInputService.InputBegan:Connect(function(input, gameProcessed)
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

	UserInputService.InputChanged:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseMovement then
			if dragStart then
				handleDragMovement(input)
			end
			handleUnitHover()
		end
	end)

	UserInputService.InputEnded:Connect(function(input, gameProcessed)
		if gameProcessed then
			return
		end

		if input.UserInputType == Enum.UserInputType.MouseButton1 then
			if isDragging then
				finishBoxSelection(input)
			else
				local isShiftPressed = UserInputService:IsKeyDown(Enum.KeyCode.LeftShift)
					or UserInputService:IsKeyDown(Enum.KeyCode.RightShift)
				handleSingleClickOrMove(isShiftPressed)
			end
			dragStart, isDragging = nil, false
		elseif input.KeyCode == Enum.KeyCode.Q then
			handleUnitInteraction()
		elseif input.UserInputType == Enum.UserInputType.MouseButton2 then
			handleRightClick()
		end
	end)
end

function ClientController.IsGameStarted()
	return hasStarted
end

function ClientController.StartVoting()
	if hasStarted then
		return
	end

	local modules = loadModules()
	local GuiManager = modules.GuiManager
	GuiManager.OnVotingStarted()
end

function ClientController.StartGame()
	if hasStarted then
		return
	end

	local team = plr.Team
	if not team or team.Name == "Neutral" then
		print("Player has no team assigned")
		return
	end

	local modules = loadModules()
	hasStarted = true
	ClientController.StartPlacementSystem()
	ClientController.StartUnitSystem()
	modules.GuiManager.OnGameStarted()
end

function ClientController.StopGame()
	hasStarted = false
	placementStarted = false
	unitStarted = false
	local modules = loadModules()
	modules.GuiManager.OnGameStopped()
end

return ClientController
