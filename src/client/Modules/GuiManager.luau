local GuiManager = {}

local SelectionManager

local plr = game.Players.LocalPlayer
local camera = workspace.CurrentCamera
local playerGui = plr:WaitForChild("PlayerGui")

local replicatedStorage = game:GetService("ReplicatedStorage")
local runService = game:GetService("RunService")
local uiService = game:GetService("UserInputService")

local sharedFolder = replicatedStorage:WaitForChild("Shared")
local dataFolder = sharedFolder.Data
local remotes = replicatedStorage.Remotes
local assets = replicatedStorage.Assets
local guiAssets = assets.UI

local unitData = require(dataFolder.UnitData)
local buildingData = require(dataFolder.BuildingData)

local queueEvent = remotes.QueueEvent
local enoughCashRemote = remotes.EnoughCash
local enoughPopulationRemote = remotes.EnoughPopulation
local isLimitRemote = remotes.IsLimit
local sellEvent = remotes.SellEvent
local interactEvent = remotes.InteractEvent
local notificationEvent = remotes.NotificationEvent
local endScreenEvent = remotes.EndScreenEvent

local iconTemplate = guiAssets:WaitForChild("IconTemplate")
local selectionContainer = plr:WaitForChild("PlayerGui"):WaitForChild("ScreenGui"):WaitForChild("SelectedInfo")
local selectedsFrame = selectionContainer:WaitForChild("Selecteds")
local selectedName = selectionContainer:WaitForChild("SelectedName")
local selectedAmount = selectionContainer:WaitForChild("SelectedAmount")
local buttonsFrame = selectionContainer:WaitForChild("Buttons")
local sellButton = buttonsFrame:WaitForChild("SellButton")
local interactButton = buttonsFrame:WaitForChild("InteractButton")

local spawnGuiTemplate = guiAssets:WaitForChild("SpawnGuiTemplate")
local spawnBtnTemplate = guiAssets:WaitForChild("SpawnTemplate")
local queueBtnTemplate = guiAssets:WaitForChild("QueueTemplate")
local connectedGuis = {}

local hoverInfo = playerGui.ScreenGui:WaitForChild("HoverInfo")
local lastRSConn = nil

local notificationFrame = playerGui.ScreenGui:WaitForChild("NotificationFrame")
local redNotification = notificationFrame:WaitForChild("RedNotification")
local greenNotification = notificationFrame:WaitForChild("GreenNotification")

local buildingPlacing = playerGui.ScreenGui:WaitForChild("BuildingPlacing")
local warningTemp = guiAssets:WaitForChild("WarningTemplate")
local lastWarning = {}

local HUD = playerGui.ScreenGui:WaitForChild("HUD")
local cashFrame = HUD:WaitForChild("CashFrame")
local cashLabel = cashFrame:WaitForChild("CashLabel")
local cpmLabel = cashFrame:WaitForChild("CPMLabel")
local energyFrame = HUD:WaitForChild("EnergyFrame")
local energyLabel = energyFrame:WaitForChild("EnergyLabel")
local populationFrame = HUD:WaitForChild("PopulationFrame")
local populationLabel = populationFrame:WaitForChild("PopulationLabel")

local buildingTemp = guiAssets:WaitForChild("BuildingTemplate")

local endFrame = playerGui.ScreenGui:WaitForChild("EndFrame")
local infoFrame = endFrame.InfoFrame
local stateLabel = infoFrame:WaitForChild("State")
local returnButton = infoFrame:WaitForChild("ReturnButton")
local stayButton = infoFrame:WaitForChild("StayButton")

local isCooldown = false
local lastCooldownThread = nil

local function startCooldown()
	if lastCooldownThread then
		task.cancel(lastCooldownThread)
		lastCooldownThread = nil
	end
	isCooldown = true
	lastCooldownThread = task.delay(0.2, function()
		isCooldown = false
	end)
end

local function ifCooldown()
	if isCooldown then
		GuiManager.NewRedNotification("You're clicking too fast")
		return true
	end
	return false
end

local function processQueue(buildingModel)
	local data = connectedGuis[buildingModel]
	local currentBuildingData = buildingData[buildingModel.Name]
	if not data or data.IsProcessing then
		return
	end
	data.IsProcessing = true

	while data and #data.Queue > 0 do
		task.wait(currentBuildingData.SpawnTime)
		if not data.Gui or not data.Gui.Adornee then
			break
		end

		local firstButton = data.Queue[1]
		if firstButton and firstButton.Parent then
			firstButton:Destroy()
		end
		table.remove(data.Queue, 1)
	end

	if data then
		data.IsProcessing = false
	end
end

local function checkUnitAmount(checkFor, Table)
	local amt
	for _, unit in ipairs(Table) do
		if unit.Name and unit.Name == checkFor then
			amt = amt or 0
			amt += 1
		end
	end
	return amt
end

local function clearSelecteds()
	for _, child in ipairs(selectedsFrame:GetChildren()) do
		if child:IsA("Frame") then
			child:Destroy()
		end
	end
	selectedName.Text = ""
	selectedAmount.Text = ""
	selectionContainer.Visible = false
	interactButton.Visible = false
end

local function onCashChanged(cash)
	cashLabel.Text = cash.Value .. "$"
end

local function onCPMChanged(cpm)
	cpmLabel.Text = cpm.Value .. " Cash/Min"
end

local function onEnergyChanged(energy, eLimit)
	energyLabel.Text = energy.Value .. "/" .. eLimit.Value
end

local function onPopulationChanged(population, pLimit)
	populationLabel.Text = population.Value .. "/" .. pLimit.Value
end

function GuiManager.Init(modules)
	SelectionManager = modules.SelectionManager

	sellButton.MouseButton1Click:Connect(function()
		local cooldown = ifCooldown()
		if cooldown then
			return
		end
		startCooldown()
		local selecteds = {}
		for _, unit in ipairs(SelectionManager.SelectedUnits) do
			table.insert(selecteds, unit)
		end

		if #selecteds == 0 then
			return
		end
		SelectionManager.ClearAll()
		clearSelecteds()
		for _, unit in selecteds do
			sellEvent:FireServer(unit)
		end
	end)
	interactButton.MouseButton1Click:Connect(function()
		local cooldown = ifCooldown()
		if cooldown then
			return
		end
		startCooldown()
		for _, unit in ipairs(SelectionManager.SelectedUnits) do
			local data = unitData[unit.Name] or buildingData[unit.Name]
			if data.Interactable == true then
				interactEvent:FireServer(unit)
			end
		end
	end)
	notificationEvent.OnClientEvent:Connect(function(color, msg)
		if color == "Red" then
			GuiManager.NewRedNotification(msg)
		elseif color == "Green" then
			GuiManager.NewGreenNotification(msg)
		end
	end)
	endScreenEvent.OnClientEvent:Connect(function(state)
		if state then
			stateLabel.Text = "You won!"
		else
			stateLabel.Text = "You lost!"
		end
		endFrame.Visible = true
	end)

	returnButton.MouseButton1Click:Connect(function()
		print("Teleportla")
	end)

	stayButton.MouseButton1Click:Connect(function()
		endFrame.Visible = false
	end)

	local stats = plr:WaitForChild("stats")
	local cash = stats:WaitForChild("Cash")
	local cpm = stats:WaitForChild("CPM")
	local energy = stats:WaitForChild("Energy")
	local eLimit = stats:WaitForChild("EnergyLimit")
	local population = stats:WaitForChild("Population")
	local pLimit = stats:WaitForChild("PopulationLimit")

	cash.Changed:Connect(function()
		onCashChanged(cash)
	end)
	cpm.Changed:Connect(function()
		onCPMChanged(cpm)
	end)

	energy.Changed:Connect(function()
		onEnergyChanged(energy, eLimit)
	end)
	eLimit.Changed:Connect(function()
		onEnergyChanged(energy, eLimit)
	end)

	population.Changed:Connect(function()
		onPopulationChanged(population, pLimit)
	end)
	pLimit.Changed:Connect(function()
		onPopulationChanged(population, pLimit)
	end)

	onCashChanged(cash)
	onCPMChanged(cpm)
	onEnergyChanged(energy, eLimit)
	onPopulationChanged(population, pLimit)

	HUD.Visible = true
end

function GuiManager.SetupBuildingButtons(currentFrame)
	for _, building in pairs(buildingData) do
		if building.NotBuildable then
			continue
		end
		local frame = buildingTemp:Clone()
		frame.Name = building.Name
		local button = frame:WaitForChild("Button")
		button.Text = building.Name
		local cost = building.Cost or 0
		local costLabel = frame:WaitForChild("Cost")
		costLabel.Text = cost .. "$"
		local space = building.Space or 0
		local spaceLabel = frame:WaitForChild("Space")
		spaceLabel.Text = space .. "⚡"

		frame.LayoutOrder = cost
		frame.Parent = currentFrame
	end
	local infoCont = currentFrame:FindFirstAncestor("Buildings").InfoContainer
	local desc = infoCont:FindFirstChild("Description")
	local name = infoCont:FindFirstChild("Name")

	local buttons = {}
	for _, button in ipairs(currentFrame:GetDescendants()) do
		if button:IsA("TextButton") then
			table.insert(buttons, button)
			button.MouseEnter:Connect(function()
				infoCont.Visible = true
				name.Text = buildingData[button.Text].Name or "TBA"
				desc.Text = buildingData[button.Text].Description or "TBA"
			end)
			button.MouseLeave:Connect(function()
				infoCont.Visible = false
			end)
		end
	end

	return buttons
end

function GuiManager.NewRedNotification(text)
	local notification = redNotification:Clone()
	notification.Visible = true
	notification.Text = text
	notification.Parent = notificationFrame
	task.delay(3, function()
		notification:Destroy()
	end)
	return
end

function GuiManager.NewGreenNotification(text)
	local notification = greenNotification:Clone()
	notification.Visible = true
	notification.Text = text
	task.delay(3, function()
		notification:Destroy()
	end)
	return
end

function GuiManager.IsSpawnGuiOpen(buildingModel)
	return connectedGuis[buildingModel] and connectedGuis[buildingModel].Gui.Enabled
end

function GuiManager.OpenSpawnGui(buildingModel)
	if not table.find(buildingData[buildingModel.Name].Behaviour, "Spawn") then
		return
	end
	if connectedGuis[buildingModel] then
		connectedGuis[buildingModel].Gui.Enabled = true
		return
	end

	local buildVal = buildingModel:FindFirstChild("Built")
	if not buildVal or not buildVal.Value then
		return
	end

	local spawnGui = spawnGuiTemplate:Clone()
	if not spawnGui then
		return
	end
	spawnGui.Adornee = buildingModel.PrimaryPart or buildingModel:FindFirstChild("Primary")
	spawnGui.Parent = plr.PlayerGui
	spawnGui.Name = "SpawnGui"
	spawnGui:WaitForChild("Container"):FindFirstChild("Title").Text = buildingModel.Name

	local spawnables = buildingData[buildingModel.Name].Spawnables
	for _, spawnable in ipairs(spawnables) do
		local currentData = spawnable
		local frame = spawnBtnTemplate:Clone()
		frame.Name = spawnable.Name
		local button = frame:FindFirstChild("Button")
		button.Name = spawnable.Name
		button.Text = spawnable.Name
		if currentData.Cost then
			local price = currentData.Cost
			local cost = frame:FindFirstChild("Cost")
			cost.Text = tostring(price) .. "$"
			frame.LayoutOrder = price
		end
		if currentData.Space then
			local space = currentData.Space
			local sp = frame:FindFirstChild("Space")
			sp.Text = space .. "👤"
		end
		frame.Parent = spawnGui.Container.SpawnContainer
	end

	spawnGui.Enabled = true

	connectedGuis[buildingModel] = { Gui = spawnGui, Queue = {}, IsProcessing = false }

	for _, button in ipairs(spawnGui.Container.SpawnContainer:GetDescendants()) do
		if button:IsA("TextButton") then
			button.MouseButton1Click:Connect(function()
				local cooldown = ifCooldown()
				if cooldown then
					return
				end
				startCooldown()
				local enoughCash = enoughCashRemote:InvokeServer("UNIT", button.Name)
				if not enoughCash then
					GuiManager.NewRedNotification("Not enough cash!")
					return
				end

				local enoughPopulation = enoughPopulationRemote:InvokeServer(unitData[button.Name])
				if not enoughPopulation then
					GuiManager.NewRedNotification("Not enough population!")
					return
				end

				local isLimit = isLimitRemote:InvokeServer("UNIT", unitData[button.Name])
				if isLimit then
					GuiManager.NewRedNotification("Unit limit reached! (" .. unitData[button.Name].Limit .. ")")
					return
				end

				queueEvent:FireServer(buildingModel, button.Name, true)

				local queueFrame = queueBtnTemplate:Clone()
				queueFrame.Name = button.Name
				local qButton = queueFrame:FindFirstChild("Button")
				qButton.Text = button.Name
				qButton.Name = button.Name

				queueFrame.LayoutOrder = 0

				table.insert(connectedGuis[buildingModel].Queue, queueFrame)

				local highest = -1
				for _, unit in ipairs(connectedGuis[buildingModel].Queue) do
					if unit.LayoutOrder > highest then
						highest = unit.LayoutOrder
					end
				end
				queueFrame.LayoutOrder = highest + 1
				queueFrame.Parent = spawnGui.Container.QueueContainer

				qButton.MouseButton1Click:Connect(function()
					local cooldown2 = ifCooldown()
					if cooldown2 then
						return
					end
					startCooldown()
					local qFrame = qButton.Parent
					local name = qFrame.Name
					local idx = table.find(connectedGuis[buildingModel].Queue, qFrame)
					if idx == 1 then
						return
					end
					table.remove(connectedGuis[buildingModel].Queue, idx)
					queueEvent:FireServer(buildingModel, name, false)
					qFrame:Destroy()
				end)

				task.spawn(processQueue, buildingModel)
			end)

			button.MouseEnter:Connect(function()
				local desc = unitData[button.Name].Description
				if not desc then
					return
				end

				local infoCont = button:FindFirstAncestor("SpawnGui"):FindFirstChild("InfoContainer")
				local unitName = infoCont.UnitName
				local unitDesc = infoCont.Description
				unitName.Text = button.Name
				unitDesc.Text = desc
				infoCont.Visible = true
			end)

			button.MouseLeave:Connect(function()
				local infoCont = button:FindFirstAncestor("SpawnGui"):FindFirstChild("InfoContainer")
				infoCont.Visible = false
			end)
		end
	end
end

function GuiManager.CloseSpawnGui(buildingModel)
	if not table.find(buildingData[buildingModel.Name].Behaviour, "Spawn") then
		return
	end
	if connectedGuis[buildingModel] then
		connectedGuis[buildingModel].Gui.Enabled = false
	end
end

function GuiManager.CloseAllSpawnGuis()
	for _, data in pairs(connectedGuis) do
		data.Gui.Enabled = false
	end
end

function GuiManager.SelectNew(newSelected, allSelecteds)
	-- Önce eski ikonların hepsini temizleyelim ki üst üste binmesinler
	clearSelecteds()

	selectionContainer.Visible = true
	selectedAmount.Text = "x" .. #allSelecteds

	if #allSelecteds > 1 then
		selectedName.Text = "Multiple"

		local added = {}

		for _, unit in ipairs(allSelecteds) do
			local unitName = unit.Name

			local data = unitData[unit.Name]
			if not data then
				data = buildingData[unit.Name]
			end
			if not data then
				continue
			end

			if data.Interactable == true then
				interactButton.Visible = true
			end

			if unitName and not added[unitName] then
				added[unitName] = true

				local clone = iconTemplate:Clone()
				local amt = checkUnitAmount(unitName, allSelecteds)

				clone.Name = unitName

				clone:FindFirstChild("Name").Text = unitName

				if amt and amt > 1 then
					clone.Amount.Text = "x" .. amt
				else
					clone.Amount.Text = "x1"
				end

				clone.Parent = selectedsFrame

				local button = clone:FindFirstChild("Button")
				if button then
					button.MouseButton1Click:Connect(function()
						local units = SelectionManager.GetAllOfName(unitName)
						if units then
							for _, u in ipairs(units) do
								SelectionManager.DeselectUnit(u)
							end
						end
					end)
				end
			end
		end
	else
		-- Sadece tek bir eleman seçiliyse
		selectedName.Text = newSelected.Name

		local data = unitData[newSelected.Name]
		if not data then
			data = buildingData[newSelected.Name]
		end
		if not data then
			return
		end

		if data.Interactable == true then
			interactButton.Visible = true
		end

		local clone = iconTemplate:Clone()

		clone.Name = newSelected.Name
		clone:FindFirstChild("Name").Text = newSelected.Name

		clone.Amount.Text = "x1"
		clone.Parent = selectedsFrame

		local button = clone:FindFirstChild("Button")
		if button then
			button.MouseButton1Click:Connect(function()
				local cooldown = ifCooldown()
				if cooldown then
					return
				end
				startCooldown()
				local units = SelectionManager.GetAllOfName(newSelected.Name)
				if units then
					for _, unit in ipairs(units) do
						SelectionManager.DeselectUnit(unit)
					end
				end
			end)
		end
	end
end

function GuiManager.Deselect(deselected, allSelecteds)
	selectedAmount.Text = "x" .. #allSelecteds
	if #allSelecteds == 0 then
		clearSelecteds()
		return
	else
		if #allSelecteds == 1 then
			selectedName.Text = allSelecteds[1].Name
		end

		local icon = selectedsFrame:FindFirstChild(deselected.Name)
		if not icon then
			return
		end

		local amt = checkUnitAmount(deselected.Name, allSelecteds)
		if not amt or amt <= 0 then
			icon:Destroy()
		else
			icon.Amount.Text = "x" .. amt
		end
	end
end

function GuiManager.HoverStart(unit)
	if lastRSConn then
		lastRSConn:Disconnect()
		lastRSConn = nil
	end

	hoverInfo.UnitName.Text = unit.Name
	local owner = unit:FindFirstChild("Owner").Value
	if owner then
		hoverInfo.OwnerName.Text = owner.Name
	else
		hoverInfo.OwnerName.Text = "Neutral"
	end
	lastRSConn = runService.RenderStepped:Connect(function()
		local pos = uiService:GetMouseLocation()
		local inset, _ = game.GuiService:GetGuiInset()

		local actualX = pos.X - inset.X
		local actualY = pos.Y - inset.Y

		hoverInfo.Position = UDim2.fromOffset(actualX, actualY)
	end)
	hoverInfo.Visible = true
end

function GuiManager.HoverEnd()
	hoverInfo.Visible = false
	lastRSConn:Disconnect()
	lastRSConn = nil
end

function GuiManager.BuildingStart()
	buildingPlacing.Visible = true
	for w, instance in lastWarning do
		instance:Destroy()
		lastWarning[w] = nil
	end
end

function GuiManager.BuildingNewPos(pos, warning)
	if not pos then
		return
	end
	local uiPos = camera:WorldToScreenPoint(pos)
	buildingPlacing.Position = UDim2.fromOffset(uiPos.X, uiPos.Y)

	for w, instance in lastWarning do
		if w ~= warning then
			instance:Destroy()
			lastWarning[w] = nil
		else
			return
		end
	end

	if warning then
		local clone = warningTemp:Clone()
		clone.Text = warning
		clone.Parent = buildingPlacing
		clone.Visible = true
		lastWarning[warning] = clone
	end
end

function GuiManager.BuildingEnd()
	buildingPlacing.Visible = false
	for w, instance in lastWarning do
		instance:Destroy()
		lastWarning[w] = nil
	end
end

return GuiManager
