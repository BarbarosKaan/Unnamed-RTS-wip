local unit = {}
unit.__index = unit

--// Servisler
local ServerScriptService = game:GetService("ServerScriptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")
local TweenService = game:GetService("TweenService")

--// Variables
local sharedFolder = ReplicatedStorage.Shared
local dataFolder = sharedFolder.Data
local server = ServerScriptService.Server
local modules = server.Modules

--// Modules
local unitData = require(dataFolder.UnitData)
local gameManager = require(modules.GameManager)

--// Remotelar
local events = ReplicatedStorage.Remotes
local removeSelectionEvent = events.RemoveSelectionEvent
local notificationEvent = events.NotificationEvent

--// Assets
local assets = ReplicatedStorage.Assets
local uiAssets = assets.UI
local modelAssets = assets.Models

--=========================================

local function getClosestUnit(model, unitTable)
	if not model or not model.PrimaryPart then
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

local function getSafeSpawnPosition(rangePart, tag, owner)
	if not rangePart then
		return nil
	end

	local maxRadius = rangePart.Size.X / 2
	local spawnPosition = nil
	local attempts = 0

	while not spawnPosition and attempts < 10 do
		attempts += 1

		local angle = math.rad(math.random(0, 360))
		local randomPercentage = math.random(20, 90) / 100
		local radius = maxRadius * randomPercentage

		local offsetX = math.cos(angle) * radius
		local offsetZ = math.sin(angle) * radius

		local startRayPos = rangePart.Position + Vector3.new(offsetX, 15, offsetZ)

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
				spawnPosition = raycastResult.Position
			end
		end
	end

	if not spawnPosition and owner then
		notificationEvent:FireClient(owner, "Red", "No available location found")
	end

	return spawnPosition
end

--=========================================

local function getCurrentPopulation(owner)
	if not owner then
		return nil
	end
	local stats = owner:FindFirstChild("stats")
	if not stats then
		return
	end
	local population = stats:FindFirstChild("Population")
	if not population then
		return
	end
	return population
end

function unit.addPopulation(owner, population)
	local currentPopulation = getCurrentPopulation(owner)
	if not currentPopulation then
		return
	end
	currentPopulation.Value += population
end

function unit.removePopulation(owner, population)
	local currentPopulation = getCurrentPopulation(owner)
	if not currentPopulation then
		return
	end
	currentPopulation.Value -= population
end

function unit.isPopulationEnough(owner, population)
	if not owner then
		return true
	end
	local currentPopulation = getCurrentPopulation(owner)
	if not currentPopulation then
		return false
	end
	local maxPopulation = owner:FindFirstChild("stats") and owner.stats.PopulationLimit.Value or 10
	return currentPopulation.Value + population <= maxPopulation
end

function unit.checkForLimit(owner, data)
	if not owner then
		return false
	end
	local limit = data.Limit
	if not limit then
		return false
	end
	local currentCount = 0
	for _, u in pairs(gameManager.GetQueueAndActiveUnits()) do
		if (u.Type == unitData or u == unitData) and u.Owner == owner then
			currentCount += 1
		end
	end
	return currentCount >= limit
end

--=========================================

function unit.New(unitType, owner, model)
	local self = setmetatable({}, unit)

	self.Type = unitData[unitType]
	self.Model = model
	self.Health = self.Type.MaxHealth
	self.unitsInRange = {}
	self.Connections = {}

	if owner then
		self.Owner = owner
		self.TeamData = owner.Team

		if model and model:FindFirstChild("Owner") then
			model.Owner.Value = owner
		end

		unit.addPopulation(owner, self.Type.Space)
	end

	self:ApplyTeamColor()

	gameManager.RegisterUnit(model, self)

	self:Setup()

	return self
end

--=========================================

function unit:AddOwner(newOwner)
	if not newOwner or self.Owner == newOwner then
		return
	end

	-- Reduce the old owner's population limit.
	if self.Owner then
		unit.removePopulation(self.Owner, self.Type.Space)
	end

	self.Owner = newOwner
	self.TeamData = newOwner and newOwner.Team or nil

	-- Update the model ownership tag.
	if self.Model and self.Model:FindFirstChild("Owner") then
		self.Model.Owner.Value = newOwner
	end

	-- Add the new owner's population capacity.
	unit.addPopulation(newOwner, self.Type.Space)

	-- Update color and laser visuals.
	self:ApplyTeamColor()

	-- Update the build beam color if this is a builder unit.
	local buildBeam = self.Model and self.Model:FindFirstChild("Beam")
	if buildBeam and newOwner then
		buildBeam.Color = ColorSequence.new(newOwner.TeamColor.Color)
	end

	-- Reset targets.
	self.unitsInRange = {}
end

function unit:RemoveOwner()
	if not self.Owner then
		return
	end

	self.Owner = nil

	if self.Model and self.Model:FindFirstChild("Owner") then
		self.Model.Owner.Value = nil
	end

	self:ApplyTeamColor()

	local buildBeam = self.Model and self.Model:FindFirstChild("Beam")
	if buildBeam then
		buildBeam.Color = ColorSequence.new(Color3.fromRGB(120, 120, 120))
	end

	self.unitsInRange = {}
end

function unit:ApplyTeamColor()
	if not self.Model or not self.Model:FindFirstChild("ColorParts") then
		return
	end

	-- Use team color when owned, otherwise use dark gray for neutral or wild units.
	local color = self.Owner and self.Owner.TeamColor or BrickColor.new("Dark stone grey")

	for _, part in pairs(self.Model.ColorParts:GetDescendants()) do
		if part:IsA("BasePart") then
			part.BrickColor = color
		end
	end
end

--=========================================

function unit:Setup()
	local model = self.Model
	local primaryPart = model.PrimaryPart
	local maxHealth = self.Type.MaxHealth

	-- Value objects for ownership and state.
	local ownerValue = Instance.new("ObjectValue")
	ownerValue.Name = "Owner"
	ownerValue.Value = self.Owner -- Remains nil if the unit is neutral.
	ownerValue.Parent = model

	local tv = Instance.new("StringValue")
	tv.Name = "Type"
	tv.Value = "UNIT"
	tv.Parent = model

	local att = Instance.new("Attachment")
	att.Name = "Attachment"
	att.Parent = primaryPart

	-- UI setup.
	local healthBar = uiAssets.HealthBar:Clone()
	healthBar.Size = UDim2.fromScale(1 + maxHealth * 0.05, 1)
	healthBar.Parent = primaryPart
	healthBar.Frame.Fill.Size = UDim2.fromScale(self.Health / self.Type.MaxHealth, 1)
	healthBar.Enabled = false

	-- Humanoid setup.
	local humanoid = modelAssets.Humanoid:Clone()
	if self.Type.Flying == true then
		humanoid.HipHeight = 8
	end
	humanoid.Name = "Humanoid"
	humanoid.Parent = model
	humanoid.WalkSpeed = self.Type.Speed

	-- Selection ring.
	local selectPart = Instance.new("Part")
	selectPart.Name = "SelectionPart"
	selectPart.Shape = Enum.PartType.Cylinder
	selectPart.CollisionGroup = "NoCollission"

	local baseSize = math.max(primaryPart.Size.Y, primaryPart.Size.Z)
	selectPart.Size = Vector3.new(0.2, baseSize + 0.5, baseSize + 0.5)

	selectPart.Material = Enum.Material.Plastic
	selectPart.Color = Color3.fromRGB(255, 255, 255)
	selectPart.CanCollide = false
	selectPart.CanQuery = false
	selectPart.CanTouch = false
	selectPart.CastShadow = false
	selectPart.Transparency = 1

	selectPart.CFrame = primaryPart.CFrame
		* CFrame.new(0, -primaryPart.Size.Y / 2, 0)
		* CFrame.Angles(0, 0, math.rad(90))
	selectPart.Parent = model

	local weld = Instance.new("WeldConstraint")
	weld.Name = "SelectionWeld"
	weld.Part0 = primaryPart
	weld.Part1 = selectPart
	weld.Parent = selectPart

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

	local alignOrientation = Instance.new("AlignOrientation")
	alignOrientation.Name = "AlignOrientation"
	alignOrientation.Attachment0 = att
	alignOrientation.Mode = Enum.OrientationAlignmentMode.OneAttachment
	alignOrientation.MaxTorque = 100000
	alignOrientation.Responsiveness = 15
	alignOrientation.Parent = model
	alignOrientation.Enabled = false

	-- Activate the supporting systems.
	self:Optimize()
	self:SetupRange()

	if self.Type.Behaviour == "Attack" then
		self:SetupAttack()
	elseif self.Type.Behaviour == "Heal" or self.Type.Behaviour == "Repair" then
		self:SetupHeal()
	elseif self.Type.Behaviour == "Build" then
		self:SetupBuild()
	elseif self.Type.Behaviour == "Transport" then
		self:SetupTransport()
	end
end

function unit:Optimize()
	local humanoid = self.Model:FindFirstChildWhichIsA("Humanoid")
	if not humanoid then
		return
	end

	self.Model.PrimaryPart:SetNetworkOwner(nil)

	humanoid:SetStateEnabled(Enum.HumanoidStateType.Swimming, false)
	humanoid:SetStateEnabled(Enum.HumanoidStateType.Climbing, false)
	humanoid:SetStateEnabled(Enum.HumanoidStateType.FallingDown, false)
	humanoid:SetStateEnabled(Enum.HumanoidStateType.Ragdoll, false)
	humanoid:SetStateEnabled(Enum.HumanoidStateType.GettingUp, false)
end

--=========================================

function unit:MoveTo(pos: Vector3)
	local model = self.Model
	if not model then
		return
	end
	local humanoid = model:FindFirstChild("Humanoid")
	local rootPart = model:FindFirstChild("HumanoidRootPart")
	if not humanoid or not rootPart then
		return
	end

	humanoid.WalkToPoint = pos

	while true do
		if not model.Parent or not rootPart.Parent then
			break
		end

		local currentPos = Vector3.new(rootPart.Position.X, 0, rootPart.Position.Z)
		local targetPos = Vector3.new(pos.X, 0, pos.Z)

		humanoid.WalkToPoint = pos

		if (currentPos - targetPos).Magnitude <= 3 then
			break
		end

		task.wait(0.2)
	end
end

function unit:SetupRange()
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

				local otherUnitData = otherUnit.Type
				local targetOwner = otherUnit.Owner
				local targetType = typeObj.Value

				-- Enemy detection logic for all hostile targets.
				local isEnemy = false

				if self.Owner == nil then
					if targetOwner ~= nil or (self.TeamData ~= otherUnit.TeamData and otherUnit.TeamData ~= nil) then
						isEnemy = true
					end
				else
					if targetOwner == nil or (targetOwner ~= self.Owner and self.TeamData ~= otherUnit.TeamData) then
						isEnemy = true
					end
				end

				if isEnemy then
					if
						self.Type.Target == "Enemy"
						or (self.Type.Target == "EnemyGround" and not otherUnitData.Flying)
						or (self.Type.Target == "EnemyAir" and otherUnitData.Flying)
						or (self.Type.Target == "EnemyBuilding" and targetType == "BUILDING")
					then
						table.insert(self.unitsInRange, otherUnit)
					end
				else
					if self.Type.Target == "Ally" then
						if self.Owner and targetOwner == self.Owner and targetType == "UNIT" then
							table.insert(self.unitsInRange, otherUnit)
						end
					elseif self.Type.Target == "AllyBuilding" then
						if self.Owner and targetOwner == self.Owner and targetType == "BUILDING" then
							table.insert(self.unitsInRange, otherUnit)
						end
					end
				end
			end
			task.wait(0.2)
		end
	end)

	table.insert(self.Connections, rangeThread)
end

--=========================================

function unit:LookAt(target)
	local ao = self.Model:FindFirstChild("AlignOrientation")
	if not ao or not target or not target.Model or not target.Model.PrimaryPart then
		self:ResetLook()
		return
	end

	local currentPos = self.Model.PrimaryPart.Position
	local pos = target.Model.PrimaryPart.Position
	local lookVector = Vector3.new(pos.X, currentPos.Y, pos.Z)

	if (lookVector - currentPos).Magnitude > 0.1 then
		ao.Enabled = true
		ao.CFrame = CFrame.lookAt(currentPos, lookVector)
	end
end

function unit:ResetLook()
	if self.Model:FindFirstChild("AlignOrientation") then
		self.Model:FindFirstChild("AlignOrientation").Enabled = false
	end
end

function unit:Bullet(endPos)
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
	beam.Color = ColorSequence.new(self.Owner and self.Owner.TeamColor.Color or Color3.fromRGB(255, 65, 65)) -- Neutral units use a reddish laser by default.
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

function unit:SetupAttack()
	task.spawn(function()
		while true do
			task.wait(self.Type.Cooldown)
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
				self:LookAt(target)
				if self.Type.SplashDmg == true and self.Model and self.Model.PrimaryPart then
					local explosionCenter = target.Model
						and target.Model.PrimaryPart
						and target.Model.PrimaryPart.Position
					if explosionCenter then
						for model, u in gameManager.GetAllUnits() do
							if
								u ~= target
								and model
								and model.PrimaryPart
								and u.Owner ~= self.Owner -- Neutral units take splash damage because they are not allied.
								and (model.PrimaryPart.Position - explosionCenter).Magnitude
									<= self.Type.SplashRadius
							then
								u:TakeDamage(self.Type.Damage / 2)
							end
						end
					end
				end
			else
				self:ResetLook()
			end
		end
	end)
end

function unit:SetupHeal()
	task.spawn(function()
		while true do
			task.wait(self.Type.Cooldown)
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
				self:LookAt(target)
			else
				self:ResetLook()
			end
		end
	end)
end

function unit:SetupBuild()
	local lastTarget = nil

	task.spawn(function()
		local buildBeam = Instance.new("Beam")
		buildBeam.Width0 = 0.2
		buildBeam.Width1 = 0.2
		buildBeam.Parent = self.Model
		buildBeam.FaceCamera = true
		buildBeam.Attachment0 = self.Model.PrimaryPart:WaitForChild("Attachment")

		if self.Owner then
			buildBeam.Color = ColorSequence.new(self.Owner.TeamColor.Color)
		end

		table.insert(self.Connections, buildBeam)

		while true do
			task.wait(self.Type.Cooldown)
			if not self.Model then
				return
			end
			if not self.Owner then
				if buildBeam.Attachment1 then
					buildBeam.Attachment1 = nil
				end
				continue
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
					if closest.IsBuilt then
						local index = table.find(self.unitsInRange, closest)
						if index then
							table.remove(self.unitsInRange, index)
						end
					else
						target = closest
						break
					end
				end
			end

			if target ~= lastTarget then
				if target and target.Model and target.Model.PrimaryPart then
					local targetAtt = target.Model.PrimaryPart:FindFirstChild("Attachment")
					if targetAtt then
						buildBeam.Attachment1 = targetAtt
						target:Build()
						self:LookAt(target)
					end
				else
					buildBeam.Attachment1 = nil
					self:ResetLook()
				end
				lastTarget = target
			elseif target == lastTarget and target ~= nil then
				target:Build()
				self:LookAt(target)
			end
		end
	end)
end

function unit:SetupTransport()
	local folder = Instance.new("Folder")
	folder.Parent = self.Model
	folder.Name = "Transporting"

	local gui = uiAssets.TransportGui:Clone()
	gui.Parent = self.Model.PrimaryPart
	gui.Adornee = self.Model.PrimaryPart
	gui.TextLabel.Text = "0/" .. self.Type.TransportLimit
	gui.Enabled = true
end

function unit:Transport()
	local unitsInRange = self.unitsInRange
	local transportingFolder = self.Model:FindFirstChild("Transporting")
	local gui = self.Model.PrimaryPart:FindFirstChild("TransportGui")
	local rangePart = self.Model:FindFirstChild("RangeVisual")

	if not rangePart then
		return
	end

	if #transportingFolder:GetChildren() > 0 then
		for _, val in ipairs(transportingFolder:GetChildren()) do
			local unitModel = val.Value
			if not unitModel then
				continue
			end

			local spawnPosition = getSafeSpawnPosition(rangePart, "Ground", self.Owner)
			if not spawnPosition then
				continue
			end

			local modelSizeY = unitModel.PrimaryPart and unitModel.PrimaryPart.Size.Y or 2
			unitModel:PivotTo(CFrame.new(spawnPosition + Vector3.new(0, modelSizeY / 2, 0)))
			unitModel.PrimaryPart.Anchored = false
			val:Destroy()

			task.wait()
		end
	else
		local count = 0
		local ignoredUnits = {}

		while count < self.Type.TransportLimit and #unitsInRange > 0 do
			local validTargets = {}
			for _, u in ipairs(unitsInRange) do
				if not table.find(ignoredUnits, u) then
					table.insert(validTargets, u)
				end
			end

			if #validTargets == 0 then
				break
			end

			local u = getClosestUnit(self.Model, validTargets)

			if not u or not u.Model or not u.Model.PrimaryPart then
				if u then
					local index = table.find(unitsInRange, u)
					if index then
						table.remove(unitsInRange, index)
					end
				else
					break
				end
			elseif u.Type.Carriable ~= true then
				table.insert(ignoredUnits, u)
			else
				local index = table.find(unitsInRange, u)
				if index then
					table.remove(unitsInRange, index)
				end

				local val = Instance.new("ObjectValue")
				val.Parent = transportingFolder
				val.Value = u.Model

				u.Model.PrimaryPart.Anchored = true
				u.Model:PivotTo(CFrame.new(999, 999, 999))
				count = count + 1
			end
		end
	end
	gui.TextLabel.Text = #transportingFolder:GetChildren() .. "/" .. self.Type.TransportLimit
end

function unit:Interact(plr)
	if not self.Model or not self.Model.PrimaryPart then
		return
	end
	if self.Owner ~= plr then
		return
	end
	if self.Type.Behaviour == "Transport" then
		self:Transport()
	end
end

--=========================================

function unit:TakeDamage(amount)
	if not self.Health then
		return
	end
	self.Health -= amount

	local healthBar = self.Model and self.Model.PrimaryPart:FindFirstChild("HealthBar")
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

function unit:Heal(amount)
	if self.Health <= 0 then
		return
	end
	self.Health = math.min(self.Health + amount, self.Type.MaxHealth)

	local healthBar = self.Model and self.Model.PrimaryPart:FindFirstChild("HealthBar")
	if healthBar then
		local healthLabel = healthBar.Frame.HealthLabel
		if healthBar.Enabled and self.Health >= self.Type.MaxHealth then
			healthBar.Enabled = false
		end
		healthBar.Frame.Fill.Size = UDim2.fromScale(self.Health / self.Type.MaxHealth, 1)
		healthLabel.Text = math.floor(self.Health) .. "/" .. self.Type.MaxHealth
	end
end

function unit:Destroy()
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

	for _, v in pairs(gameManager.GetEverything()) do
		if v.unitsInRange then
			local index = table.find(v.unitsInRange, self)
			if index then
				table.remove(v.unitsInRange, index)
			end
		end
	end

	if self.Owner then
		removeSelectionEvent:FireClient(self.Owner, self.Model)
		unit.removePopulation(self.Owner, self.Type.Space)
	end

	gameManager.UnregisterUnit(self.Model)

	if self.Model then
		self.Model:Destroy()
		self.Model = nil
	end
end

return unit
