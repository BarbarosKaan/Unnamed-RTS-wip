local UnitClass = {}
UnitClass.__index = UnitClass

local ServerScriptService = game:GetService("ServerScriptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")
local TweenService = game:GetService("TweenService")

local server = ServerScriptService.Server
local modules = server.Modules

local BuildingData = require(ReplicatedStorage.Shared.Data.BuildingData)
local unitManager = require(modules.UnitManager)

local events = ReplicatedStorage.Remotes
local removeSelectionEvent = events.RemoveSelectionEvent
local notificationEvent = events.NotificationEvent

function UnitClass:ApplyTeamColor()
	if not self.Model or not self.Model:FindFirstChild("ColorParts") then
		return
	end

	local color = self.Owner and self.Owner.TeamColor or BrickColor.new("Dark stone grey")
	for _, part in pairs(self.Model.ColorParts:GetDescendants()) do
		if part:IsA("BasePart") then
			part.BrickColor = color
		end
	end

	local buildBeam = self.Model and self.Model:FindFirstChild("Beam")
	if buildBeam then
		buildBeam.Color = ColorSequence.new(color.Color)
	end
end

function UnitClass:AddOwner(newOwner)
	self.Owner = newOwner
	self.TeamData = newOwner and newOwner.Team or nil
	if self.Model and self.Model:FindFirstChild("Owner") then
		self.Model.Owner.Value = newOwner
	end

	if self.Kind == "Troop" then
		self:addPopulation()
	elseif self.Kind == "Building" then
		self:addEnergy()

		if self.IsBuilt then
			if table.find(self.Type.Behaviour, "AddEnergy") then
				self:upgradeMaxEnergy()
			end
			if table.find(self.Type.Behaviour, "AddPopulation") then
				self:upgradeMaxPopulation()
			end
		end

		local cashPerTick = self.Type.CashPerTick
		local cashWait = self.Type.CashCooldown
		local cashPerMin = (60 / cashWait) * cashPerTick
		local cpmVal = self.Owner and self.Owner:FindFirstChild("stats") and self.Owner.stats:FindFirstChild("CPM")
		cpmVal.Value += cashPerMin
	end

	self.UnitsInRange = {}
	self:ApplyTeamColor()
end

function UnitClass:RemoveOwner()
	self.Owner = nil

	if self.Model and self.Model:FindFirstChild("Owner") then
		self.Model.Owner.Value = nil
	end

	self.UnitsInRange = {}
	self:ApplyTeamColor()
end

function UnitClass:Bullet(endPos)
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

function UnitClass:TakeDamage(amount)
	if not self.Health then
		return
	end
	self.Health -= amount

	local healthBar = self.Model and self.Model.PrimaryPart and self.Model.PrimaryPart:FindFirstChild("HealthBar")
	if healthBar then
		local healthLabel = healthBar.Frame.HealthLabel
		if not healthBar.Enabled then
			healthBar.Enabled = true
		end
		healthBar.Frame.Fill.Size = UDim2.fromScale(math.max(0, self.Health / self.Type.MaxHealth), 1)
		healthLabel.Text = math.floor(self.Health) .. "/" .. self.Type.MaxHealth
	end

	if self.Health <= 0 then
		self:Destroy()
	end
end

function UnitClass:Heal(amount)
	if self.Health <= 0 then
		return
	end
	self.Health = math.min(self.Health + amount, self.Type.MaxHealth)

	local healthBar = self.Model and self.Model.PrimaryPart and self.Model.PrimaryPart:FindFirstChild("HealthBar")
	if healthBar then
		local healthLabel = healthBar.Frame.HealthLabel
		if healthBar.Enabled and self.Health >= self.Type.MaxHealth then
			healthBar.Enabled = false
		end
		healthBar.Frame.Fill.Size = UDim2.fromScale(self.Health / self.Type.MaxHealth, 1)
		healthLabel.Text = math.floor(self.Health) .. "/" .. self.Type.MaxHealth
	end
end

function UnitClass:Destroy()
	if self.Connections then
		for _, connection in ipairs(self.Connections) do
			if connection then
				if typeof(connection) == "RBXScriptConnection" then
					connection:Disconnect()
				elseif typeof(connection) == "Instance" then
					connection:Destroy()
				elseif typeof(connection) == "thread" then
					task.cancel(connection)
				end
			end
		end
		self.Connections = nil
	end

	for _, v in pairs(unitManager.GetEverything()) do
		if v.unitsInRange then
			local index = table.find(v.unitsInRange, self)
			if index then
				table.remove(v.unitsInRange, index)
			end
		end
	end

	if self.Owner then
		removeSelectionEvent:FireClient(self.Owner, self.Model)
	end

	if self.Kind == "Troop" then
		unitManager.UnregisterTroop(self.Model)
		self:removePopulation()
	elseif self.Kind == "Building" then
		unitManager.UnregisterBuilding(self.Model)
		self:removeEnergy()
		if table.find(self.Type.Behaviour, "AddEnergy") then
			self:removeMaxEnergy()
		end
		if table.find(self.Type.Behaviour, "AddPopulation") then
			self:removeMaxPopulation()
		end
	end

	if self.Model then
		self.Model:Destroy()
		self.Model = nil
	end
end

function UnitClass:getClosestUnit(unitTable)
	if not self.Model or not self.Model.PrimaryPart then
		return nil
	end

	local closest = nil
	local closestDistance = math.huge

	for _, v in ipairs(unitTable) do
		if not v.Model or not v.Model.PrimaryPart then
			continue
		end

		local distance = (v.Model.PrimaryPart.Position - self.Model.PrimaryPart.Position).Magnitude
		if distance < closestDistance then
			closest = v
			closestDistance = distance
		end
	end

	return closest
end

function UnitClass:getSafeSpawnPosition(tag, owner, rangePart, primaryPart)
	local maxRadius = rangePart and (rangePart.Size.X / 2) or 5
	local basePosition = rangePart and rangePart.Position
		or primaryPart and primaryPart.Position
		or (self.Model and self.Model.PrimaryPart and self.Model.PrimaryPart.Position)
		or Vector3.new(0, 0, 0)

	local spawnPosition = nil
	local attempts = 0

	while not spawnPosition and attempts < 10 do
		attempts += 1

		local angle = math.random() * math.pi * 2
		local randomPercentage = 0.20 + (math.random() * 0.70)
		local radius = maxRadius * randomPercentage

		local offsetX = math.cos(angle) * radius
		local offsetZ = math.sin(angle) * radius

		local startRayPos = basePosition + Vector3.new(offsetX, 15, offsetZ)
		local raycastResult = workspace:Raycast(startRayPos, Vector3.new(0, -30, 0))

		if raycastResult then
			local hitPart = raycastResult.Instance

			if not hitPart or not CollectionService:HasTag(hitPart, tag) then
				print(hitPart and hitPart.Name or "No part hit", "does not have the required tag:", tag)
				continue
			end

			local checkOverlap = workspace:GetPartBoundsInRadius(raycastResult.Position + Vector3.new(0, 2, 0), 2.5)
			local isSpaceOccupied = false

			for _, part in ipairs(checkOverlap) do
				local ancestorModel = part:FindFirstAncestorOfClass("Model")
				if ancestorModel and ancestorModel:FindFirstChild("Owner") then
					isSpaceOccupied = true
					break
				end
			end

			if not isSpaceOccupied then
				spawnPosition = raycastResult.Position
			end
		end
	end

	if not spawnPosition and owner then
		notificationEvent:FireClient(owner, "Red", "No available location found")
	end

	return spawnPosition
end

function UnitClass:addPopulation(space, owner)
	local realOwner = owner or self.Owner
	local population = space or self.Type.Space
	local stats = realOwner and realOwner:FindFirstChild("stats")
	local populationValue = stats and stats:FindFirstChild("Population")
	if populationValue then
		populationValue.Value += population
	end
end

function UnitClass:removePopulation(space, owner)
	local realOwner = owner or self.Owner
	local population = space or self.Type.Space
	local stats = realOwner and realOwner:FindFirstChild("stats")
	local populationValue = stats and stats:FindFirstChild("Population")
	if populationValue then
		populationValue.Value -= population
	end
end

function UnitClass:upgradeMaxPopulation()
	local population = self.Type.AddPopulation
	if not self.Owner then
		return
	end
	local maxPopulation = self.Owner:FindFirstChild("stats") and self.Owner.stats.PopulationLimit
	if not maxPopulation then
		return
	end
	maxPopulation.Value += population
end

function UnitClass:removeMaxPopulation()
	local population = self.Type.AddPopulation
	if not self.Owner then
		return
	end
	local maxPopulation = self.Owner:FindFirstChild("stats") and self.Owner.stats.PopulationLimit
	if not maxPopulation then
		return
	end
	maxPopulation.Value -= population
end

function UnitClass.isPopulationEnough(owner, population)
	local stats = owner:FindFirstChild("stats")
	local currentPopulation = stats and stats:FindFirstChild("Population")
	local maxPopulation = owner:FindFirstChild("stats") and owner.stats.PopulationLimit.Value or 10
	if not currentPopulation then
		return false
	end
	return currentPopulation.Value + population <= maxPopulation
end

function UnitClass:getCurrentEnergy()
	if not self.Owner then
		return nil
	end
	local stats = self.Owner:FindFirstChild("stats")
	if not stats then
		return
	end
	local energy = stats:FindFirstChild("Energy")
	if not energy then
		return
	end
	return energy
end

function UnitClass:addEnergy()
	local energyAmount = self.Type.Space
	local currentEnergy = self:getCurrentEnergy()
	if not currentEnergy then
		return
	end
	currentEnergy.Value += energyAmount
end

function UnitClass:removeEnergy()
	local energyAmount = self.Type.Space
	local currentEnergy = self:getCurrentEnergy()
	if not currentEnergy then
		return
	end
	currentEnergy.Value -= energyAmount
end

function UnitClass:upgradeMaxEnergy()
	local energyAmount = self.Type.AddEnergy
	if not self.Owner then
		return
	end
	local maxEnergy = self.Owner:FindFirstChild("stats") and self.Owner.stats.EnergyLimit
	if not maxEnergy then
		return
	end
	maxEnergy.Value += energyAmount
end

function UnitClass:removeMaxEnergy()
	local energyAmount = self.Type.AddEnergy
	if not self.Owner then
		return
	end
	local maxEnergy = self.Owner:FindFirstChild("stats") and self.Owner.stats.EnergyLimit
	if not maxEnergy then
		return
	end
	maxEnergy.Value -= energyAmount
end

function UnitClass.isEnergyEnough(owner, energyCost)
	local stats = owner:FindFirstChild("stats")
	local currentEnergy = stats and stats:FindFirstChild("Energy")
	local maxEnergy = owner:FindFirstChild("stats") and owner.stats.EnergyLimit.Value or 10
	if not currentEnergy then
		return false
	end
	return currentEnergy.Value + energyCost <= maxEnergy
end

function UnitClass.checkForLimit(owner, data)
	if not owner or not data or not data.Limit then
		return false
	end

	local isBuilding = false
	if BuildingData[data.Name] then
		isBuilding = true
	end

	local currentCount = 0
	if not isBuilding then
		for _, u in pairs(unitManager.GetQueueAndActiveTroops()) do
			if u.Owner == owner and u.Type == data then
				currentCount += 1
			end
		end
	else
		for _, u in pairs(unitManager.GetAllBuildings()) do
			if u.Owner == owner and u.Type == data then
				currentCount += 1
			end
		end
	end
	return currentCount >= data.Limit
end

return UnitClass
