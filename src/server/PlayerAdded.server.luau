local ServerScriptService = game:GetService("ServerScriptService")
local Teams = game:GetService("Teams")

local server = ServerScriptService.Server
local classes = server.Classes

local gameManager = require(server.Modules.GameManager)
local buildingClass = require(classes.BuildingClass)
local unitClass = require(classes.UnitClass)

local spawnPoints = {}

local GAME_MODE = "1v1"

local function setCharacterCollisionGroup(character)
	for _, descendant in ipairs(character:GetDescendants()) do
		if descendant:IsA("BasePart") then
			descendant.CollisionGroup = "Player"
			descendant.CanQuery = false
		end
	end
end

local function createTeams()
	if GAME_MODE == "1v1" then
		local team1 = Instance.new("Team")
		team1.Name = "Blue"
		team1.TeamColor = BrickColor.new("Really blue")
		team1.Parent = Teams
		team1.AutoAssignable = false
		team1:SetAttribute("Lost", false)
		local team2 = Instance.new("Team")
		team2.Name = "Red"
		team2.TeamColor = BrickColor.new("Really red")
		team2.Parent = Teams
		team2.AutoAssignable = false
		team2:SetAttribute("Lost", false)

		spawnPoints = {
			Blue = nil,
			Red = nil,
		}
	end
end

createTeams()

for _, object in ipairs(workspace:GetChildren()) do
	if object.Name == "HQ" and object:IsA("Model") then
		local hqBuilding = buildingClass.New("HQ", nil, object)

		local builderModel = game.ReplicatedStorage.Assets.Models.UnitModels.Builder:Clone()
		builderModel.Parent = workspace.Units
		builderModel:PivotTo(object:GetPivot() * CFrame.new(7, 0, 0))

		local builderUnit = unitClass.New("Builder", nil, builderModel)

		local dataPacket = {
			HQ = hqBuilding,
			HQModel = object,
			Builder = builderUnit,
		}

		local teamTag = object:FindFirstChild("Team")
		if teamTag then
			spawnPoints[teamTag.Value] = dataPacket
		else
			if not spawnPoints.Blue then
				spawnPoints.Blue = dataPacket
			else
				spawnPoints.Red = dataPacket
			end
		end
	end
end

local function assign1v1Team()
	local bluePlayers = Teams.Blue:GetPlayers()
	local redPlayers = Teams.Red:GetPlayers()

	if #bluePlayers == 0 then
		return Teams.Blue
	elseif #redPlayers == 0 then
		return Teams.Red
	else
		return nil
	end
end

game.Players.PlayerAdded:Connect(function(plr)
	local assignedTeam = assign1v1Team()

	if assignedTeam then
		plr.Team = assignedTeam

		local stats = Instance.new("Folder")
		stats.Name = "stats"
		stats.Parent = plr

		local cash = Instance.new("IntValue")
		cash.Name = "Cash"
		cash.Value = 100
		cash.Parent = stats

		local cpm = Instance.new("IntValue")
		cpm.Name = "CPM"
		cpm.Value = 0
		cpm.Parent = stats

		local populationLimit = Instance.new("IntValue")
		populationLimit.Name = "PopulationLimit"
		populationLimit.Value = 0
		populationLimit.Parent = stats

		local population = Instance.new("IntValue")
		population.Name = "Population"
		population.Value = 0
		population.Parent = stats

		local energyLimit = Instance.new("IntValue")
		energyLimit.Name = "EnergyLimit"
		energyLimit.Value = 0
		energyLimit.Parent = stats

		local energy = Instance.new("IntValue")
		energy.Name = "Energy"
		energy.Value = 0
		energy.Parent = stats

		local mySpawn = spawnPoints[assignedTeam.Name]

		for _, unit in pairs(gameManager.GetEverything()) do
			if not unit.Owner and unit.TeamData == plr.Team then
				unit:AddOwner(plr)
			end
		end

		if mySpawn then
			mySpawn.HQModel.Parent = workspace.Assigned
			mySpawn.HQ:AddOwner(plr)
			mySpawn.Builder:AddOwner(plr)
		end
	else
		print(plr.Name .. " oyuna sonradan girdi ve izleyici (Neutral) olarak kaldı.")
	end

	plr.CharacterAdded:Connect(function(character)
		task.wait(0.1)
		setCharacterCollisionGroup(character)

		if plr.Team and spawnPoints[plr.Team.Name] then
			local myHQModel = spawnPoints[plr.Team.Name].HQModel
			if myHQModel and myHQModel.PrimaryPart then
				character:PivotTo(myHQModel:GetPivot() * CFrame.new(0, 10, 0))
			end
		end

		character.DescendantAdded:Connect(function(descendant)
			if descendant:IsA("BasePart") then
				descendant.CollisionGroup = "Player"
				descendant.CanQuery = false
			end
		end)
	end)
end)

game.Players.PlayerRemoving:Connect(function(plr)
	for _, unit in pairs(gameManager.GetEverything()) do
		if unit.Owner == plr then
			unit:RemoveOwner()
		end
	end
end)
