local building = {}
building.__index = building

--// Servisler
local ServerScriptService = game:GetService("ServerScriptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")
local TweenService = game:GetService("TweenService")

--// Variables
local sharedFolder = ReplicatedStorage.Shared
local data = sharedFolder.Data
local server = ServerScriptService.Server
local modules = server.Modules
local classes = server.Classes

--// Remotelar
local events = ReplicatedStorage.Remotes
local removeSelectionEvent = events.RemoveSelectionEvent
local castleDestroyed = events.CastleDestroyed

--// Modules
local buildingData = require(data.BuildingData)
local unitData = require(data.UnitData)
local gameManager = require(modules.GameManager)
local unitClass = require(classes.UnitClass)

--// Assets
local uiAssets = ReplicatedStorage.Assets.UI
local modelAssets = ReplicatedStorage.Assets.Models

--=========================================

local function getClosestUnit(model, unitTable)
	if not model then
		return nil
	end

	local closest = nil
	local closestDistance = math.huge

	for _, v in ipairs(unitTable) do
		if not v.Model or not v.Model.PrimaryPart then
			continue
		end

		local distance = (v.Model.PrimaryPart.Position - model.PrimaryPart.Position).Magnitude
		if distance < closestDistance then
			closest = v
			closestDistance = distance
		end
	end

	return closest
end

local function getSafeSpawnPosition(rootPart, tag)
	if not rootPart then
		return nil
	end

	local buildingSize = math.max(rootPart.Size.X, rootPart.Size.Z)
	local maxRadius = buildingSize * 2.5
	local spawnPosition = nil
	local attempts = 0

	while not spawnPosition and attempts < 10 do
		attempts += 1

		local angle = math.rad(math.random(0, 360))
		local radius = math.random(maxRadius * 30, maxRadius * 90) / 100

		local offsetX = math.cos(angle) * radius
		local offsetZ = math.sin(angle) * radius

		local startRayPos = rootPart.Position + Vector3.new(offsetX, 15, offsetZ)

		local raycastParams = RaycastParams.new()
		raycastParams.FilterType = Enum.RaycastFilterType.Include
		raycastParams.FilterDescendantsInstances = CollectionService:GetTagged(tag)

		local raycastResult = workspace:Raycast(startRayPos, Vector3.new(0, -30, 0), raycastParams)

		if raycastResult then
			local checkOverlap = workspace:GetPartBoundsInRadius(raycastResult.Position + Vector3.new(0, 2, 0), 2.5)
			local isSpaceOccupied = false

			for _, part in ipairs(checkOverlap) do
				if
					part:FindFirstAncestorOfClass("Model")
					and part:FindFirstAncestorOfClass("Model"):FindFirstChild("Owner")
				then
					isSpaceOccupied = true
					break
				end
			end

			if not isSpaceOccupied then
				spawnPosition = raycastResult.Position + Vector3.new(0, 3, 0)
			end
		end
	end

	if not spawnPosition then
		spawnPosition = rootPart.Position + Vector3.new(math.random(-2, 2), 0, math.random(-2, 2))
	end

	return spawnPosition
end

--=========================================

local function getCurrentEnergy(owner)
	if not owner then
		return nil
	end
	local stats = owner:FindFirstChild("stats")
	if not stats then
		return
	end
	local energy = stats:FindFirstChild("Energy")
	if not energy then
		return
	end
	return energy
end

local function addEnergy(owner, energyAmount)
	local currentEnergy = getCurrentEnergy(owner)
	if not currentEnergy then
		return
	end
	currentEnergy.Value += energyAmount
end

local function removeEnergy(owner, energyAmount)
	local currentEnergy = getCurrentEnergy(owner)
	if not currentEnergy then
		return
	end
	currentEnergy.Value -= energyAmount
end

local function upgradeMaxEnergy(owner, energyAmount)
	if not owner then
		return
	end
	local maxEnergy = owner:FindFirstChild("stats") and owner.stats.EnergyLimit
	if not maxEnergy then
		return
	end
	maxEnergy.Value += energyAmount
end

local function removeMaxEnergy(owner, energyAmount)
	if not owner then
		return
	end
	local maxEnergy = owner:FindFirstChild("stats") and owner.stats.EnergyLimit
	if not maxEnergy then
		return
	end
	maxEnergy.Value -= energyAmount
end

local function upgradeMaxPopulation(owner, population)
	if not owner then
		return
	end
	local maxPopulation = owner:FindFirstChild("stats") and owner.stats.PopulationLimit
	if not maxPopulation then
		return
	end
	maxPopulation.Value += population
end

local function removeMaxPopulation(owner, population)
	if not owner then
		return
	end
	local maxPopulation = owner:FindFirstChild("stats") and owner.stats.PopulationLimit
	if not maxPopulation then
		return
	end
	maxPopulation.Value -= population
end

function building.isEnergyEnough(owner, energyCost)
	if not owner then
		return true
	end -- Neutral buildings do not have energy limits
	local currentEnergy = getCurrentEnergy(owner)
	if not currentEnergy then
		return false
	end
	local maxEnergy = owner:FindFirstChild("stats") and owner.stats.EnergyLimit.Value or 10
	return currentEnergy.Value + energyCost <= maxEnergy
end

function building.checkForLimit(owner, bData)
	if not owner then
		return false
	end
	local limit = bData.Limit
	if not limit then
		return false
	end
	local currentCount = 0
	for _, build in pairs(gameManager.GetAllBuildings()) do
		if build.Owner == owner and build.Type == bData then
			currentCount += 1
		end
	end
	return currentCount >= limit
end

--=========================================

function building.New(buildingType, owner, model, zone)
	local self = setmetatable({}, building)

	self.Type = buildingData[buildingType]
	self.Model = model
	self.Owner = owner -- owner nil gelebilir (Sahipsiz Bina)
	self.Health = math.floor(self.Type.MaxHealth * 0.1)
	self.BuildProgress = 0
	self.IsBuilt = false
	self.Queue = {}
	self.unitsInRange = {}
	self.Connections = {}

	if zone then
		self.Zone = zone
	end

	if owner then
		self.TeamData = owner.Team
		addEnergy(owner, self.Type.Space)
	end

	gameManager.RegisterBuilding(model, self)
	self:Setup()

	-- Use team color when owned, otherwise leave the building neutral gray.
	self:ApplyTeamColor()

	if buildingType == "HQ" then
		self:BuildingFinish()
	else
		-- Start hidden during construction.
		for _, v in pairs(model:GetDescendants()) do
			if v:IsA("BasePart") and v.Name ~= "Primary" and v.Name ~= "Floor" and v.Name ~= "RangeVisual" then
				v.Transparency = 1
			end
		end
	end

	return self
end

--=========================================

function building:AddOwner(newOwner)
	if not newOwner or self.Owner == newOwner then
		return
	end

	-- Remove the previous owner's effects before assigning a new owner.
	if self.Owner then
		removeEnergy(self.Owner, self.Type.Space)
		if self.IsBuilt then
			if table.find(self.Type.Behaviour, "AddEnergy") then
				removeMaxEnergy(self.Owner, self.Type.AddEnergy)
			end
			if table.find(self.Type.Behaviour, "AddPopulation") then
				removeMaxPopulation(self.Owner, self.Type.AddPopulation)
			end
		end
	end

	-- Assign the new owner.
	self.Owner = newOwner
	self.TeamData = newOwner and newOwner.Team or nil

	-- Update the model ownership tag.
	if self.Model and self.Model:FindFirstChild("Owner") then
		self.Model.Owner.Value = newOwner
	end

	-- Update the new owner's statistics.
	addEnergy(newOwner, self.Type.Space)
	if self.IsBuilt then
		if table.find(self.Type.Behaviour, "AddEnergy") then
			upgradeMaxEnergy(newOwner, self.Type.AddEnergy)
		end
		if table.find(self.Type.Behaviour, "AddPopulation") then
			upgradeMaxPopulation(newOwner, self.Type.AddPopulation)
		end
	end

	local cashPerTick = self.Type.CashPerTick
	local cashWait = self.Type.CashCooldown
	local cashPerMin = (60 / cashWait) * cashPerTick
	local cpmVal = self.Owner and self.Owner:FindFirstChild("stats") and self.Owner.stats:FindFirstChild("CPM")
	cpmVal.Value += cashPerMin

	-- Update the team color based on the new owner.
	self:ApplyTeamColor()

	-- Reset range and targets so they can be recalculated for the new allies or enemies.
	self.unitsInRange = {}
end

function building:RemoveOwner()
	if not self.Owner then
		return
	end

	self.Owner = nil

	if self.Model and self.Model:FindFirstChild("Owner") then
		self.Model.Owner.Value = nil
	end

	self.unitsInRange = {}

	self:ApplyTeamColor()
end

function building:ApplyTeamColor()
	if not self.Model or not self.Model:FindFirstChild("ColorParts") then
		return
	end

	-- Use team color when owned, otherwise use Dark Stone Grey for neutral buildings.
	local color = self.Owner and self.Owner.TeamColor or BrickColor.new("Dark stone grey")

	for _, part in pairs(self.Model.ColorParts:GetDescendants()) do
		if part:IsA("BasePart") then
			part.BrickColor = color
		end
	end
end

--=========================================

function building:Setup()
	local model = self.Model
	local primaryPart = model.PrimaryPart
	local floor = model:FindFirstChild("Floor")
	local maxHealth = self.Type.MaxHealth

	-- Value objects for ownership and state.
	local ov = Instance.new("ObjectValue")
	ov.Name = "Owner"
	ov.Value = self.Owner -- Remains nil if the building is neutral.
	ov.Parent = model

	local bv = Instance.new("BoolValue")
	bv.Name = "Built"
	bv.Value = false
	bv.Parent = model

	local tv = Instance.new("StringValue")
	tv.Name = "Type"
	tv.Value = "BUILDING"
	tv.Parent = model

	local att = Instance.new("Attachment")
	att.Name = "Attachment"
	att.Parent = model.PrimaryPart

	-- UI setup.
	local healthBar = uiAssets.HealthBar:Clone()
	local size = math.min(21, 1 + maxHealth * 0.05)
	healthBar.Size = UDim2.fromScale(size, 1)
	healthBar.Parent = primaryPart
	healthBar.Frame.Fill.Size = UDim2.fromScale(self.Health / self.Type.MaxHealth, 1)
	healthBar.Enabled = false

	local buildingProgress = uiAssets.BuildingProgress:Clone()
	buildingProgress.Frame.Fill.Size = UDim2.fromScale(self.BuildProgress / 100, 1)
	buildingProgress.Parent = model.PrimaryPart
	buildingProgress.Adornee = model.PrimaryPart
	buildingProgress.Enabled = true

	-- Selection part for highlighting.
	local selectPart = Instance.new("Part")
	selectPart.Name = "SelectionPart"
	selectPart.Shape = Enum.PartType.Block
	selectPart.CollisionGroup = "NoCollission"

	local baseSize = math.max(floor.Size.X, floor.Size.Z)
	selectPart.Size = Vector3.new(baseSize + 0.5, 0.95, baseSize + 0.5)

	selectPart.Material = Enum.Material.Plastic
	selectPart.Color = Color3.fromRGB(255, 255, 255)
	selectPart.CanCollide = false
	selectPart.CanQuery = false
	selectPart.CanTouch = false
	selectPart.CastShadow = false
	selectPart.Anchored = true
	selectPart.TopSurface = Enum.SurfaceType.Smooth
	selectPart.Transparency = 1

	selectPart.CFrame = floor.CFrame * CFrame.new(0, -floor.Size.Y / 2, 0)
	selectPart.Parent = model

	if self.Type.Range then
		local rangeVisual = uiAssets.RangeVisual:Clone()
		rangeVisual.Size = Vector3.new(self.Type.Range * 2, 0.001, self.Type.Range * 2)
		rangeVisual.Parent = model
		rangeVisual.CFrame = primaryPart.CFrame * CFrame.new(0, -primaryPart.Size.Y / 2, 0)

		local weld2 = Instance.new("WeldConstraint")
		weld2.Name = "RangeWeld"
		weld2.Part0 = primaryPart
		weld2.Part1 = rangeVisual
		weld2.Parent = rangeVisual
	end

	if table.find(self.Type.Behaviour, "Spawn") then
		local queueProgress = uiAssets.QueueProgress:Clone()
		queueProgress.Parent = model.PrimaryPart
		queueProgress.Adornee = model.PrimaryPart
		queueProgress.Enabled = false
	end
end

function building:Build()
	if self.IsBuilt then
		return
	end
	self.BuildProgress += 1

	local buildingProgress = self.Model.PrimaryPart:FindFirstChild("BuildingProgress")
	if buildingProgress then
		buildingProgress.Frame.Fill.Size = UDim2.fromScale(self.BuildProgress / 100, 1)
	end

	local transparency = 1 - (self.BuildProgress / 100)
	for _, part in ipairs(self.Model:GetDescendants()) do
		if
			part:IsA("BasePart")
			and part.Name ~= "Floor"
			and part.Name ~= "Range"
			and part.Name ~= "RangeVisual"
			and part.Name ~= "Primary"
			and part.Name ~= "SelectionPart"
		then
			part.Transparency = transparency
		end
	end

	if self.BuildProgress >= 100 then
		self:BuildingFinish()
	end
end

function building:BuildingFinish()
	self.BuildProgress = 100
	if table.find(self.Type.Behaviour, "Spawn") then
		self:SetupQueue()
	end
	if self.Type.Range then
		self:SetupRange()
	end
	if table.find(self.Type.Behaviour, "Attack") then
		self:SetupAttack()
	end
	if table.find(self.Type.Behaviour, "Heal") then
		self:SetupHeal()
	end
	if table.find(self.Type.Behaviour, "GiveCash") then
		self:SetupCash()
	end
	if table.find(self.Type.Behaviour, "Tower") then
		self:ToggleWall()
	end

	-- Increase limits only when the building has an owner.
	if self.Owner then
		if table.find(self.Type.Behaviour, "AddEnergy") then
			upgradeMaxEnergy(self.Owner, self.Type.AddEnergy)
		end
		if table.find(self.Type.Behaviour, "AddPopulation") then
			upgradeMaxPopulation(self.Owner, self.Type.AddPopulation)
		end
	end

	self.IsBuilt = true
	self.Model:FindFirstChild("Built").Value = true
	self.Health = self.Type.MaxHealth
	self:Heal(0)

	local buildingProgress = self.Model.PrimaryPart:FindFirstChild("BuildingProgress")
	if buildingProgress then
		buildingProgress:Destroy()
	end
end

--=========================================

function building:Bullet(endPos)
	local startPos = self.Model.PrimaryPart.Position
	local distance = (endPos - startPos).Magnitude

	local bulletPart = Instance.new("Part")
	bulletPart.Size = Vector3.new(0.1, 0.1, 0.1)
	bulletPart.Transparency = 1
	bulletPart.Anchored = true
	bulletPart.CanCollide = false
	bulletPart.CanTouch = false
	bulletPart.CanQuery = false
	bulletPart.Name = "Bullet"
	bulletPart.Parent = workspace

	bulletPart.CFrame = CFrame.lookAt(startPos, endPos)

	local att0 = Instance.new("Attachment")
	att0.Name = "Att0"
	att0.Position = Vector3.new(0, 0, 0)
	att0.Parent = bulletPart

	local att1 = Instance.new("Attachment")
	att1.Name = "Att1"
	att1.Position = Vector3.new(0, 0, -2)
	att1.Parent = bulletPart

	local beam = Instance.new("Beam")
	beam.Attachment0 = att0
	beam.Attachment1 = att1
	beam.TextureSpeed = 0
	beam.Width0 = 0.6
	beam.Width1 = 0.6

	-- Use team color for the laser when owned; otherwise use white.
	beam.Color = ColorSequence.new(self.Owner and self.Owner.TeamColor.Color or Color3.fromRGB(255, 255, 255))
	beam.Parent = bulletPart
	beam.FaceCamera = true

	local speed = 150
	local duration = distance / speed

	local track = TweenService:Create(
		bulletPart,
		TweenInfo.new(duration, Enum.EasingStyle.Linear),
		{ CFrame = CFrame.lookAt(endPos, endPos + bulletPart.CFrame.LookVector) }
	)

	track:Play()

	task.spawn(function()
		track.Completed:Wait()
		bulletPart:Destroy()
	end)
end

--=========================================

function building:SetupQueue()
	local progressBar = self.Model.PrimaryPart:FindFirstChild("QueueProgress")
	local fill = progressBar.Frame.Fill

	task.spawn(function()
		while true do
			task.wait()
			if not self.Model then
				return
			end

			-- Neutral buildings cannot train units without an owner.
			if not self.Owner then
				progressBar.Enabled = false
				task.wait(1)
				continue
			end

			if #self.Queue > 0 then
				fill.Size = UDim2.fromScale(0, 1)
				progressBar.Enabled = true

				local unit = self.Queue[1]
				if not unit then
					continue
				end

				local tween = TweenService:Create(
					fill,
					TweenInfo.new(self.Type.SpawnTime, Enum.EasingStyle.Linear),
					{ Size = UDim2.fromScale(1, 1) }
				)
				tween:Play()
				task.wait(self.Type.SpawnTime)

				if not self.Model or not self.Owner then
					return
				end
				self:Spawn(unit)
			else
				progressBar.Enabled = false
				task.wait(0.5)
			end
		end
	end)
end

function building:AddQueue(unitType)
	if not self.Owner then
		print("Neutral buildings cannot train units")
		return
	end
	local unit = unitData[unitType]
	if not unit or not table.find(self.Type.Spawnables, unit) then
		print("Invalid unit type")
		return
	end
	table.insert(self.Queue, unit)
	unitClass.addPopulation(self.Owner, unit.Space)
	gameManager.RegisterUnitQueue(unit, self.Owner)
end

function building:RemoveQueue(unitType)
	if not self.Owner then
		return false
	end
	local idx = table.find(self.Queue, unitData[unitType])
	if not idx then
		print("Unit not in queue")
		return false
	end
	if idx == 1 then
		return false
	end
	table.remove(self.Queue, idx)
	unitClass.removePopulation(self.Owner, unitData[unitType].Space)
	gameManager.UnregisterUnitQueue(unitData[unitType])
	return true
end

function building:Spawn(unit)
	if not self.Model or not self.Owner then
		return
	end

	local unitInfo = self.Queue[1]
	if not unitInfo then
		return
	end

	if unit ~= unitInfo then
		return
	end

	table.remove(self.Queue, 1)

	local modelTemplate = modelAssets.UnitModels:FindFirstChild(unitInfo.Name)
	if not modelTemplate then
		return
	end

	local pos = self.Type.SpawnOnWater and getSafeSpawnPosition(self.Model.PrimaryPart, "Water")
		or getSafeSpawnPosition(self.Model.PrimaryPart, "Ground")

	local clone = modelTemplate:Clone()
	clone.Parent = workspace.Units
	clone:PivotTo(CFrame.new(pos))

	gameManager.UnregisterUnitQueue(unitInfo)
	unitClass.New(unitInfo.Name, self.Owner, clone)
end

function building:SetupRange()
	local range = self.Type.Range
	if not range then
		return
	end

	local rangeThread = task.spawn(function()
		while true do
			if not self.Model or not self.Model.PrimaryPart then
				break
			end

			local myPos = self.Model.PrimaryPart.Position

			for _, otherUnit in pairs(gameManager.GetEverything()) do
				if otherUnit == self then
					continue
				end
				if not otherUnit.Model or not otherUnit.Model.PrimaryPart then
					continue
				end

				local unitPos = otherUnit.Model.PrimaryPart.Position
				local distance = (Vector3.new(unitPos.X, 0, unitPos.Z) - Vector3.new(myPos.X, 0, myPos.Z)).Magnitude

				local idx = table.find(self.unitsInRange, otherUnit)

				if distance > range then
					if idx then
						table.remove(self.unitsInRange, idx)
					end
					continue
				end

				if idx then
					continue
				end

				local typeObj = otherUnit.Model:FindFirstChild("Type")
				if not typeObj then
					continue
				end

				local targetOwner = otherUnit.Owner
				local targetType = typeObj.Value

				local isAttack = table.find(self.Type.Behaviour, "Attack")
				local isHeal = table.find(self.Type.Behaviour, "Heal")
				local isTower = table.find(self.Type.Behaviour, "Tower")

				if isAttack then
					local isEnemy = false

					if self.Owner == nil then
						if
							targetOwner ~= nil or (self.TeamData ~= otherUnit.TeamData and otherUnit.TeamData ~= nil)
						then
							isEnemy = true
						end
					else
						if
							targetOwner == nil or (targetOwner ~= self.Owner and self.TeamData ~= otherUnit.TeamData)
						then
							isEnemy = true
						end
					end

					if isEnemy then
						table.insert(self.unitsInRange, otherUnit)
					end
				elseif isHeal then
					if self.Owner and targetOwner == self.Owner and targetType == "UNIT" then
						table.insert(self.unitsInRange, otherUnit)
					end
				elseif isTower then
					if
						self.Owner
						and targetOwner == self.Owner
						and targetType == "BUILDING"
						and otherUnit.Type.Name == "Tower"
					then
						table.insert(self.unitsInRange, otherUnit)
					end
				end
			end
			task.wait(0.2)
		end
	end)

	table.insert(self.Connections, rangeThread)
end

function building:SetupAttack()
	task.spawn(function()
		while task.wait(self.Type.Cooldown) do
			if not self.Model then
				return
			end

			local target = nil

			while #self.unitsInRange > 0 do
				local closest = getClosestUnit(self.Model, self.unitsInRange)

				if not closest or not closest.Model then
					if closest then
						local index = table.find(self.unitsInRange, closest)
						if index then
							table.remove(self.unitsInRange, index)
						end
					else
						break
					end
				else
					target = closest
					break
				end
			end

			if target then
				self:Bullet(target.Model.PrimaryPart.Position)
				target:TakeDamage(self.Type.Damage)
			end
		end
	end)
end

function building:SetupHeal()
	task.spawn(function()
		while task.wait(self.Type.Cooldown) do
			if not self.Model then
				return
			end
			if not self.Owner then
				continue
			end

			local target = nil
			local ignoredUnits = {}

			while #self.unitsInRange > 0 do
				local validTargets = {}
				for _, u in ipairs(self.unitsInRange) do
					if not table.find(ignoredUnits, u) then
						table.insert(validTargets, u)
					end
				end

				if #validTargets == 0 then
					break
				end

				local closest = getClosestUnit(self.Model, validTargets)

				if not closest or not closest.Model then
					if closest then
						local index = table.find(self.unitsInRange, closest)
						if index then
							table.remove(self.unitsInRange, index)
						end
					else
						break
					end
				elseif closest.Health >= closest.Type.MaxHealth then
					table.insert(ignoredUnits, closest)
				else
					target = closest
					break
				end
			end

			if target then
				self:Bullet(target.Model.PrimaryPart.Position)
				target:Heal(self.Type.Heal)
			end
		end
	end)
end

function building:SetupCash()
	local cashPerTick = self.Type.CashPerTick
	local cashWait = self.Type.CashCooldown
	if self.Owner then
		local cashPerMin = (60 / cashWait) * cashPerTick
		local cpmVal = self.Owner and self.Owner:FindFirstChild("stats") and self.Owner.stats:FindFirstChild("CPM")
		cpmVal.Value += cashPerMin
	end
	local conn
	conn = task.spawn(function()
		while true do
			task.wait(cashWait)
			if not self.Model then
				return
			end
			if self.Owner then
				local ownerStats = self.Owner:FindFirstChild("stats")
				local ownerCash = ownerStats and ownerStats:FindFirstChild("Cash")
				if ownerCash then
					ownerCash.Value += cashPerTick
				end
			end
		end
	end)
	table.insert(self.Connections, conn)
end

function building:ToggleWall()
	if not self.Owner then
		return
	end
	if not self.Walls then
		self.Walls = {}
	end
	if not self.Connections then
		self.Connections = {}
	end

	local towersInRange = self.unitsInRange
	local wallPairs = self.Walls
	if #towersInRange == 0 then
		return
	end

	for _, tower in ipairs(towersInRange) do
		local model = tower.Model
		if not model then
			continue
		end
		if not tower.IsBuilt then
			return
		end

		if not tower.Walls then
			tower.Walls = {}
		end
		if not tower.Connections then
			tower.Connections = {}
		end

		local wall = wallPairs[model]
		if wall then
			wall:Destroy()

			local myIdx = table.find(self.Connections, wall)
			local wallIdx = table.find(tower.Connections, wall)
			if myIdx then
				table.remove(self.Connections, myIdx)
			end
			if wallIdx then
				table.remove(tower.Connections, wallIdx)
			end

			wallPairs[model] = nil
			tower.Walls[self.Model] = nil
		else
			local startPart = self.Model and self.Model.PrimaryPart
			local endPart = model and model.PrimaryPart

			if startPart and endPart then
				local startPos = startPart.Position
				local endPos = endPart.Position

				local distance = (startPos - endPos).Magnitude
				local centerPos = (startPos + endPos) / 2

				local wallPart = Instance.new("Part")
				wallPart.Name = "Wall"
				wallPart.CanQuery = false
				wallPart.CollisionGroup = "Wall"
				wallPart.Anchored = true
				wallPart.TopSurface = Enum.SurfaceType.Smooth
				wallPart.Size = Vector3.new(0.5, 2, distance)
				wallPart.CFrame = CFrame.lookAt(centerPos, endPos)

				wallPart.Parent = workspace
				wallPairs[model] = wallPart
				tower.Walls[self.Model] = wallPart
				table.insert(self.Connections, wallPart)
				table.insert(tower.Connections, wallPart)

				local lastOverlapTime = 0
				local isOpened = false

				wall.Touched:Connect(function(hit)
					local hitModel = hit:FindFirstAncestorOfClass("Model")
					if hitModel and hitModel:FindFirstChild("Owner") and hitModel.Owner.Value == self.Owner then
						lastOverlapTime = os.clock()

						if not isOpened then
							isOpened = true
							wall.CanCollide = false
							wall.Transparency = 0.5

							task.spawn(function()
								while os.clock() - lastOverlapTime < 0.8 do
									task.wait(0.2)
								end
								wall.CanCollide = true
								wall.Transparency = 0
								isOpened = false
							end)
						end
					end
				end)
			end
		end
	end
end

function building:Interact(plr)
	if not self.IsBuilt then
		return
	end
	if not self.Model or not self.Model.PrimaryPart then
		return
	end
	if self.Owner ~= plr then
		return
	end

	local isTower = table.find(self.Type.Behaviour, "Tower")
	if isTower then
		self:ToggleWall()
	end
end

--=========================================

function building:TakeDamage(amount)
	self.Health -= amount

	local healthBar = self.Model.PrimaryPart:FindFirstChild("HealthBar")
	if healthBar then
		local healthLabel = healthBar.Frame.HealthLabel
		local maxHealth = self.Type.MaxHealth
		if not self.IsBuilt then
			maxHealth = math.floor(maxHealth * 0.1)
		end
		healthBar.Frame.Fill.Size = UDim2.fromScale(self.Health / maxHealth, 1)
		healthLabel.Text = math.floor(self.Health) .. "/" .. maxHealth
		if not healthBar.Enabled then
			healthBar.Enabled = true
		end
	end

	if self.Health <= 0 then
		self:Destroy()
	end
end

function building:Heal(amount)
	self.Health = math.min(self.Health + amount, self.Type.MaxHealth)

	local healthBar = self.Model.PrimaryPart:FindFirstChild("HealthBar")
	if healthBar then
		local healthLabel = healthBar.Frame.HealthLabel
		healthBar.Frame.Fill.Size = UDim2.fromScale(self.Health / self.Type.MaxHealth, 1)
		healthLabel.Text = math.floor(self.Health) .. "/" .. self.Type.MaxHealth
		if self.Health >= self.Type.MaxHealth then
			healthBar.Enabled = false
		end
	end
end

function building:Destroy()
	if self.Connections then
		for _, connection in ipairs(self.Connections) do
			if connection then
				local typeName = typeof(connection)

				if typeName == "RBXScriptConnection" then
					connection:Disconnect()
				elseif typeName == "Instance" then
					connection:Destroy()
				elseif typeName == "thread" then
					task.cancel(connection)
				end
			end
		end
		self.Connections = nil
	end

	for _, v in pairs(gameManager.GetEverything()) do
		if v.unitsInRange then
			local index = table.find(v.unitsInRange, self)
			if index then
				table.remove(v.unitsInRange, index)
			end
		end
	end

	if self.Owner then
		if table.find(self.Type.Behaviour, "AddEnergy") then
			removeMaxEnergy(self.Owner, self.Type.AddEnergy)
		end
		if table.find(self.Type.Behaviour, "AddPopulation") then
			removeMaxPopulation(self.Owner, self.Type.AddPopulation)
		end
		if table.find(self.Type.Behaviour, "GiveCash") then
			local cashPerTick = self.Type.CashPerTick
			local cashWait = self.Type.CashCooldown
			local cashPerMin = (60 / cashWait) * cashPerTick
			local cpmVal = self.Owner and self.Owner:FindFirstChild("stats") and self.Owner.stats:FindFirstChild("CPM")
			cpmVal.Value -= cashPerMin
		end
		removeEnergy(self.Owner, self.Type.Space)
		removeSelectionEvent:FireClient(self.Owner, self.Model)
	end

	if self.Type.Name == "HQ" then
		castleDestroyed:Fire(self)
	end

	gameManager.UnregisterBuilding(self.Model)

	if self.Model then
		self.Model:Destroy()
		self.Model = nil
	end

	local zone = self.Zone
	if zone then
		local tag = zone:FindFirstChild("Available")
		if tag then
			tag.Value = true
		end
	end
end

return building
