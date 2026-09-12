local UnitClass = require(script.Parent.UnitClass)

local troop = setmetatable({}, UnitClass)
troop.__index = troop

--// Servisler
local ServerScriptService = game:GetService("ServerScriptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

--// Variables
local sharedFolder = ReplicatedStorage.Shared
local remotesFolder = ReplicatedStorage.Remotes
local dataFolder = sharedFolder.Data
local server = ServerScriptService.Server
local modules = server.Modules

--// Modules
local troopData = require(dataFolder.TroopData)
local unitManager = require(modules.UnitManager)

--// Remotes
local removeMoveBeam = remotesFolder.RemoveMoveBeam

--// Assets
local assets = ReplicatedStorage.Assets
local uiAssets = assets.UI
local modelAssets = assets.Models
local effectAssets = assets.Effects

local damageBoostAura = effectAssets.DamageBoost

--=========================================

function troop.New(troopType, owner, model)
	local self = setmetatable({}, troop)

	self.Kind = "Troop"
	self.Active = true
	self.Data = troopData[troopType]
	self.Model = model
	self.Health = self.Data.MaxHealth
	self.Damage = self.Data["Damage"] or nil
	self.unitsInRange = {}
	self.Connections = {}

	if owner then
		self.Owner = owner
		self.TeamData = owner.Team

		if model and model:FindFirstChild("Owner") then
			model.Owner.Value = owner
		end
	end

	self:ApplyTeamColor()

	unitManager.RegisterTroop(model, self)

	self:Setup()

	return self
end

--=========================================

function troop:Setup()
	local model = self.Model
	local primaryPart = model.PrimaryPart
	local maxHealth = self.Data.MaxHealth

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
	healthBar.Frame.Fill.Size = UDim2.fromScale(self.Health / self.Data.MaxHealth, 1)
	healthBar.Enabled = false

	-- Humanoid setup.
	local humanoid = modelAssets.Humanoid:Clone()
	if self.Data.Flying == true then
		humanoid.HipHeight = 8
	end
	humanoid.Name = "Humanoid"
	humanoid.Parent = model
	humanoid.WalkSpeed = self.Data.Speed

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

	if self.Data.Range then
		local rangeVisual = uiAssets.RangeVisual:Clone()
		rangeVisual.Size = Vector3.new(self.Data.Range * 2, 0.001, self.Data.Range * 2)
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

	if self.Data.Behaviour == "Attack" then
		self:SetupAttack()
	elseif self.Data.Behaviour == "Heal" or self.Data.Behaviour == "Repair" then
		self:SetupHeal()
	elseif self.Data.Behaviour == "Build" then
		self:SetupBuild()
	elseif self.Data.Behaviour == "Transport" then
		self:SetupTransport()
	elseif self.Data.Behaviour == "BoostAttack" then
		self:SetupBoost()
	end
end

function troop:Optimize()
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

function troop:MoveTo(pos: Vector3)
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

		if not self.Active then
			break
		end

		task.wait(0.2)
	end
end

function troop:SetupRange()
	local range = self.Data.Range
	if not range then
		return
	end

	local rangeThread = task.spawn(function()
		while true do
			task.wait(0.2)

			if not self.Model or not self.Model.PrimaryPart then
				break
			end

			if not self.Active then
				continue
			end

			local myPos = self.Model.PrimaryPart.Position

			for _, otherUnit in pairs(unitManager.GetEverything()) do
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

				local otherUnitData = otherUnit.Data
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
						self.Data.Target == "Enemy"
						or (self.Data.Target == "EnemyGround" and not otherUnitData.Flying)
						or (self.Data.Target == "EnemyAir" and otherUnitData.Flying)
						or (self.Data.Target == "EnemyBuilding" and targetType == "BUILDING")
					then
						table.insert(self.unitsInRange, otherUnit)
					end
				else
					if self.Data.Target == "Ally" then
						if self.Owner and targetOwner == self.Owner and targetType == "UNIT" then
							table.insert(self.unitsInRange, otherUnit)
						end
					elseif self.Data.Target == "AllyBuilding" then
						if self.Owner and targetOwner == self.Owner and targetType == "BUILDING" then
							table.insert(self.unitsInRange, otherUnit)
						end
					end
				end
			end
		end
	end)

	table.insert(self.Connections, rangeThread)
end

--=========================================

function troop:LookAt(target)
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

function troop:ResetLook()
	if self.Model:FindFirstChild("AlignOrientation") then
		self.Model:FindFirstChild("AlignOrientation").Enabled = false
	end
end

--=========================================

function troop:SetupAttack()
	task.spawn(function()
		while true do
			task.wait(self.Data.Cooldown)
			if not self.Model then
				return
			end
			if not self.Active then
				continue
			end

			local target = nil

			while #self.unitsInRange > 0 do
				local closest = self:getClosestUnit(self.unitsInRange)

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
				target:TakeDamage(self.Damage)
				self:LookAt(target)
				if self.Data.SplashDmg == true and self.Model and self.Model.PrimaryPart then
					local explosionCenter = target.Model
						and target.Model.PrimaryPart
						and target.Model.PrimaryPart.Position
					if explosionCenter then
						for model, u in unitManager.GetAllTroops() do
							if
								u ~= target
								and model
								and model.PrimaryPart
								and u.Owner ~= self.Owner -- Neutral units take splash damage because they are not allied.
								and (model.PrimaryPart.Position - explosionCenter).Magnitude
									<= self.Data.SplashRadius
							then
								u:TakeDamage(self.Damage / 2)
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

function troop:SetupHeal()
	task.spawn(function()
		while true do
			task.wait(self.Data.Cooldown)
			if not self.Model then
				return
			end
			if not self.Active then
				continue
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

				local closest = self:getClosestUnit(validTargets)

				if not closest or not closest.Model then
					if closest then
						local index = table.find(self.unitsInRange, closest)
						if index then
							table.remove(self.unitsInRange, index)
						end
					else
						break
					end
				elseif closest.Health >= closest.Data.MaxHealth then
					table.insert(ignoredUnits, closest)
				else
					target = closest
					break
				end
			end

			if target then
				self:Bullet(target.Model.PrimaryPart.Position)
				target:Heal(self.Data.Heal)
				self:LookAt(target)
			else
				self:ResetLook()
			end
		end
	end)
end

function troop:SetupBuild()
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
			task.wait(self.Data.Cooldown)
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
				local closest = self:getClosestUnit(self.unitsInRange)

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

function troop:SetupBoost()
	local boostedUnits = {}

	local boostAttack = self.Data.Behaviour == "BoostAttack" or false

	task.spawn(function()
		while true do
			task.wait(1)
			if not self.Model then
				return
			end
			if not self.Active then
				continue
			end

			while #self.unitsInRange > 0 do
				task.wait(1)
				for _, u in ipairs(self.unitsInRange) do
					local idx = table.find(boostedUnits, u)
					if not idx then
						table.insert(boostedUnits, u)

						if boostAttack and u.Damage and not u.AttackBoosted then
							u:Boost("Attack", self.Data.Boost)
						end
					end
				end
				for _, u in ipairs(boostedUnits) do
					local idx = table.find(self.unitsInRange, u)
					if not idx then
						if boostAttack and u.Damage and u.AttackBoosted then
							u:RemoveBoost("Attack", self.Data.Boost)
						end
						local index = table.find(boostedUnits, u)
						if index then
							table.remove(boostedUnits, index)
						end
					end
				end
			end
		end
	end)
end

function troop:Boost(stat, amount)
	print("Boosting", self.Model.Name, "stat:", stat, "amount:", amount)
	if stat == "Attack" and self.Damage and not self.AttackBoosted then
		local aura = damageBoostAura:Clone()
		aura.Parent = self.Model.PrimaryPart
		self.Damage = self.Damage + amount
		self.AttackBoosted = true
	end
end

function troop:RemoveBoost(stat, amount)
	print("Unboosting", self.Model.Name, "stat:", stat, "amount:", amount)
	if stat == "Attack" and self.Damage and self.AttackBoosted then
		local aura = self.Model.PrimaryPart:FindFirstChild("DamageBoost")
		if aura then
			aura:Destroy()
		end
		self.Damage = self.Damage - amount
		self.AttackBoosted = false
	end
end

function troop:SetupTransport()
	local folder = Instance.new("Folder")
	folder.Parent = self.Model
	folder.Name = "Transporting"

	local gui = uiAssets.TransportGui:Clone()
	gui.Parent = self.Model.PrimaryPart
	gui.Adornee = self.Model.PrimaryPart
	gui.TextLabel.Text = "0/" .. self.Data.TransportLimit
	gui.Enabled = true
end
-- TODO: Movelarken transporta alınca troopu move beamı gitmiyor
function troop:Transport()
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

			local spawnPosition = self:getSafeSpawnPosition("Ground", self.Owner, rangePart)
			if not spawnPosition then
				continue
			end

			local modelSizeY = unitModel.PrimaryPart and unitModel.PrimaryPart.Size.Y or 2
			unitModel:PivotTo(CFrame.new(spawnPosition + Vector3.new(0, modelSizeY / 2, 0)))
			local unit = unitManager.GetTroop(unitModel)
			if unit then
				unit.Active = true
			end
			unitModel.PrimaryPart.Anchored = false
			val:Destroy()

			task.wait()
		end
	else
		local count = 0
		local ignoredUnits = {}

		while count < self.Data.TransportLimit and #unitsInRange > 0 do
			local validTargets = {}
			for _, u in ipairs(unitsInRange) do
				if not table.find(ignoredUnits, u) then
					table.insert(validTargets, u)
				end
			end

			if #validTargets == 0 then
				break
			end

			local u = self:getClosestUnit(validTargets)

			if not u or not u.Model or not u.Model.PrimaryPart then
				if u then
					local index = table.find(unitsInRange, u)
					if index then
						table.remove(unitsInRange, index)
					end
				else
					break
				end
			elseif u.Data.Carriable ~= true then
				table.insert(ignoredUnits, u)
			else
				local index = table.find(unitsInRange, u)
				if index then
					table.remove(unitsInRange, index)
				end

				local val = Instance.new("ObjectValue")
				val.Parent = transportingFolder
				val.Value = u.Model

				removeMoveBeam:FireClient(self.Owner, u.Model)

				u.Model.PrimaryPart.Anchored = true
				u.Active = false
				u.Model:PivotTo(CFrame.new(999, 999, 999))
				count = count + 1
			end
		end
	end
	gui.TextLabel.Text = #transportingFolder:GetChildren() .. "/" .. self.Data.TransportLimit
end

function troop:Interact(plr)
	if not self.Model or not self.Model.PrimaryPart then
		return
	end
	if self.Owner ~= plr then
		return
	end
	if self.Data.Behaviour == "Transport" then
		self:Transport()
	end
end

return troop
