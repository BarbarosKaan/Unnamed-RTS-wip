local replicatedStorage = game:GetService("ReplicatedStorage")
local serverScriptService = game:GetService("ServerScriptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local server = serverScriptService.Server
local classes = server.Classes

local sharedF = replicatedStorage.Shared
local dataFolder = sharedF.Data
local modules = server.Modules
local remotes = ReplicatedStorage.Remotes

local unitClass = require(classes.UnitClass)
local unitData = require(dataFolder.UnitData)
local buildingClass = require(classes.BuildingClass)
local buildingData = require(dataFolder.BuildingData)

local gameManager = require(modules.GameManager)

local queueEvent = remotes.QueueEvent
local moveEvent = remotes.MoveEvent
local buildEvent = remotes.BuildEvent
local sellEvent = remotes.SellEvent
local interactEvent = remotes.InteractEvent
local enoughCashRemote = remotes.EnoughCash
local enoughEnergyRemote = remotes.EnoughEnergy
local enoughPopulationRemote = remotes.EnoughPopulation
local isLimitRemote = remotes.IsLimit
local castleDestroyed = remotes.CastleDestroyed
local endScreenRemote = remotes.EndScreenEvent

local gameEnded = false

local function getPlayerCash(plr)
	local plrStats = plr:FindFirstChild("stats")
	if not plrStats then
		return false
	end
	local cash = plrStats:FindFirstChild("Cash")
	if not cash then
		return false
	end
	return cash
end

local function checkPlrEnergy(plr, data)
	if not data then
		return false
	end
	local energy = data.Space
	return buildingClass.isEnergyEnough(plr, energy)
end

local function checkPlrPopulation(plr, data)
	if not data then
		return false
	end
	local population = data.Space
	return unitClass.isPopulationEnough(plr, population)
end

moveEvent.OnServerEvent:Connect(function(plr, model, newWaypoints, isReset)
	local owner = model:FindFirstChild("Owner")
	if not owner or owner.Value ~= plr then
		return
	end

	local myUnit = gameManager.GetUnit(model)

	if isReset then
		if myUnit._waypointThread then
			task.cancel(myUnit._waypointThread)
			myUnit._waypointThread = nil
		end
		myUnit._queue = {}

		local pp = myUnit.Model.PrimaryPart
		if pp then
			myUnit.Model.Humanoid:MoveTo(pp.Position)
		end
	end

	if not myUnit._queue then
		myUnit._queue = {}
	end
	for _, pos in ipairs(newWaypoints) do
		table.insert(myUnit._queue, pos)
	end

	if myUnit._waypointThread then
		return
	end

	myUnit._waypointThread = task.spawn(function()
		while #myUnit._queue > 0 do
			local pos = table.remove(myUnit._queue, 1)

			myUnit:MoveTo(pos)
		end

		myUnit._waypointThread = nil
	end)
end)

queueEvent.OnServerEvent:Connect(function(plr, building, unit, isAdding)
	local myBuilding = gameManager.GetBuilding(building)
	if myBuilding.Owner ~= plr or not table.find(myBuilding.Type.Behaviour, "Spawn") then
		return
	end

	if isAdding then
		local data = unitData[unit]
		local isLimit = unitClass.checkForLimit(plr, data)
		if isLimit then
			print("limit")
			return
		end
		if not checkPlrPopulation(plr, data) then
			print("Not enough population")
			return
		end

		local unitCost = data.Cost
		local playerCash = getPlayerCash(plr)
		if playerCash.Value < unitCost then
			print("not enough cash")
			return
		end

		playerCash.Value -= unitCost
		myBuilding:AddQueue(unit)
	else
		local success = myBuilding:RemoveQueue(unit)
		if not success then
			return
		end
		local unitCost = unitData[unit].Cost
		local playerCash = getPlayerCash(plr)
		playerCash.Value += unitCost * 0.1
	end
end)

buildEvent.OnServerEvent:Connect(function(plr, building, pos, zonePart)
	if not building or not plr or not pos then
		return
	end

	local data = buildingData[building]
	if not data then
		return
	end

	local isLimit = buildingClass.checkForLimit(plr, data)
	if isLimit then
		print("limit")
		return
	end

	if not checkPlrEnergy(plr, data) then
		print("Not enough energy")
		return
	end

	if table.find(data.Behaviour, "Farm") or table.find(data.Behaviour, "Rig") then
		if not zonePart or (zonePart.Name ~= "FarmZone" and zonePart.Name ~= "RigZone") then
			print(plr.Name .. " geçersiz veya yüklenmemiş bir alana yerleştirmeye çalıştı (zonePart Yok)")
			return
		end

		local available = zonePart:FindFirstChild("Available")
		if not available then
			return
		end
	end

	local buildingCost = buildingData[building].Cost
	local playerCash = getPlayerCash(plr)
	if playerCash.Value < buildingCost then
		print("not enough cash")
		return
	end

	playerCash.Value -= buildingCost

	local model = game.ReplicatedStorage.Assets.Models.BuildingModels:FindFirstChild(building):Clone()
	model:PivotTo(pos)
	model.Parent = workspace

	buildingClass.New(building, plr, model, zonePart or nil)

	if table.find(data.Behaviour, "Farm") or table.find(data.Behaviour, "Rig") and zonePart then
		local tag = zonePart:FindFirstChild("Available")
		tag.Value = false
	end
end)

sellEvent.OnServerEvent:Connect(function(plr, unit)
	local myUnit = gameManager.GetUnit(unit)
	local isBuilding = false

	if not myUnit then
		myUnit = gameManager.GetBuilding(unit)
		if myUnit then
			isBuilding = true
		end
	end

	if not myUnit or myUnit.Owner ~= plr then
		return
	end

	local playerCash = getPlayerCash(plr)
	local cost = 0

	if isBuilding then
		if buildingData[unit.Name] then
			cost = buildingData[unit.Name].Cost
		end
	else
		if unitData[unit.Name] then
			cost = unitData[unit.Name].Cost
		end
	end

	if not cost then
		return
	end

	playerCash.Value += cost / 10
	myUnit:Destroy()
end)

interactEvent.OnServerEvent:Connect(function(plr, unit)
	local myUnit = gameManager.GetUnit(unit) or gameManager.GetBuilding(unit)
	if not myUnit then
		return
	end
	myUnit:Interact(plr)
end)

enoughCashRemote.OnServerInvoke = function(plr, type, unit)
	local data
	if not unit then
		return false
	end
	if type == "UNIT" then
		data = unitData[unit]
	elseif type == "BUILDING" then
		data = buildingData[unit]
	end
	if not data then
		return false
	end
	local cost = data.Cost
	local playerCash = getPlayerCash(plr)
	return playerCash.Value >= cost
end

enoughEnergyRemote.OnServerInvoke = function(plr, building)
	return checkPlrEnergy(plr, building)
end

enoughPopulationRemote.OnServerInvoke = function(plr, unit)
	return checkPlrPopulation(plr, unit)
end

isLimitRemote.OnServerInvoke = function(plr, uType, unit)
	local data
	if uType == "UNIT" then
		data = unitData[unit.Name]
		return unitClass.checkForLimit(plr, data)
	elseif uType == "BUILDING" then
		data = buildingData[unit.Name]
		return buildingClass.checkForLimit(plr, data)
	end
	return false
end

castleDestroyed.Event:Connect(function(data)
	if gameEnded then
		return
	end
	local owner = data.Owner
	local allTeams = game.Teams:GetChildren()

	if owner then
		local team = owner.Team
		if table.find(allTeams, team) then
			if team:GetAttribute("Lost") == false then
				print(data, "LOST")
				team:SetAttribute("Lost", true)
				endScreenRemote:FireClient(owner, false)
			end
		end
	else
		for _, t in allTeams do
			if t:GetAttribute("Lost") == false and #t:GetPlayers() <= 0 then
				if data.TeamData then
					if data.TeamData == t then
						print(data, "LOST")
						t:SetAttribute("Lost", true)
						break
					end
				else
					t:SetAttribute("Lost", true)
					break
				end
			end
		end
	end

	local i = 0
	local winnerTeam
	for _, t in allTeams do
		if t:GetAttribute("Lost") == false then
			i += 1
			winnerTeam = t
		end
	end
	if i <= 1 then
		gameEnded = true
		endScreenRemote:FireClient(winnerTeam:GetPlayers()[1], true)
		print("Winner", winnerTeam)
	end
end)
