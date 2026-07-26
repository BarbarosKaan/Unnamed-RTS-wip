local PlacementManager = {}

local buildingData = require(game.ReplicatedStorage.Shared.Data.BuildingData)
local GuiManager

local runService = game:GetService("RunService")
local collectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local players = game:GetService("Players")
local camera = workspace.CurrentCamera
local plr = players.LocalPlayer
local mouse = plr:GetMouse()

mouse.TargetFilter = workspace.Walls

local buildEvent = ReplicatedStorage.Remotes.BuildEvent
local enoughCashRemote = ReplicatedStorage.Remotes.EnoughCash
local enoughEnergyRemote = ReplicatedStorage.Remotes.EnoughEnergy
local isLimitRemote = ReplicatedStorage.Remotes.IsLimit

local currentRotation = 0
local placementConn = nil
local currentClone = nil
local currentData = nil

local function checkPlacementStatus()
	if not currentClone or not currentData then
		return nil, false, nil
	end

	local playerChars = {}
	for _, player in pairs(players:GetPlayers()) do
		table.insert(playerChars, player.Character)
	end

	local ray = camera:ScreenPointToRay(mouse.X, mouse.Y)
	local rayParams = RaycastParams.new()
	rayParams.FilterType = Enum.RaycastFilterType.Exclude

	rayParams.FilterDescendantsInstances = { currentClone, workspace.Walls, workspace.Units, playerChars }

	local result = workspace:Raycast(ray.Origin, ray.Direction * 1000, rayParams)
	if not result then
		return nil, false, nil
	end

	local targetPosition = result.Position + Vector3.new(0, currentClone.PrimaryPart.Size.Y / 2, 0)
	local targetSize = currentClone.PrimaryPart.Size
	local hitPart = result.Instance

	local isCorrectGround = false
	if currentData.PlaceOnWater == true then
		if
			collectionService:HasTag(hitPart, "Water")
			or (hitPart.Name == "RigZone" and hitPart.Parent == workspace:FindFirstChild("RigZones"))
		then
			isCorrectGround = true
		end
	else
		if
			collectionService:HasTag(hitPart, "Ground")
			or (hitPart.Name == "FarmZone" and hitPart.Parent == workspace:FindFirstChild("FarmZones"))
		then
			isCorrectGround = true
		end
	end

	local plrHasEnergy = enoughEnergyRemote:InvokeServer(currentData)
	if not plrHasEnergy then
		return targetPosition, true, "Not Enough Energy!"
	end

	if not isCorrectGround and currentData then
		if currentData.PlaceOnWater == true then
			return targetPosition, true, "Must Place On Water!"
		else
			return targetPosition, true, "Must Place On Ground!"
		end
	end

	if not currentData then
		return
	end
	local plrHasCash = enoughCashRemote:InvokeServer("BUILDING", currentData.Name)
	if not plrHasCash then
		return targetPosition, true, "Not Enough Cash!"
	end

	if currentData and table.find(currentData.Behaviour, "Farm") then
		local available = hitPart:FindFirstChild("Available")
		local farmZonesFolder = workspace:FindFirstChild("FarmZones")

		if not farmZonesFolder or hitPart.Name ~= "FarmZone" or hitPart.Parent ~= farmZonesFolder then
			return targetPosition, true, "Place Farms On Farm Spots!"
		elseif available and available.Value == false then
			return targetPosition, true, "This Farm Spot Is Full!"
		end
	end

	if currentData and table.find(currentData.Behaviour, "Rig") then
		local available = hitPart:FindFirstChild("Available")
		local rigZonesFolder = workspace:FindFirstChild("RigZones")

		if not rigZonesFolder or hitPart.Name ~= "RigZone" or hitPart.Parent ~= rigZonesFolder then
			return targetPosition, true, "Place Rigs On Oil Rig Spots!"
		elseif available and available.Value == false then
			return targetPosition, true, "This Oil Rig Spot Is Full!"
		end
	end

	local overlapParams = OverlapParams.new()
	overlapParams.FilterType = Enum.RaycastFilterType.Exclude
	overlapParams.FilterDescendantsInstances = { currentClone, playerChars }

	local collidingParts = workspace:GetPartBoundsInBox(CFrame.new(targetPosition), targetSize, overlapParams)

	local actualCollisions = 0
	for _, part in ipairs(collidingParts) do
		if
			not collectionService:HasTag(part, "Ground")
			and not collectionService:HasTag(part, "Water")
			and part.Name ~= "Zone"
		then
			actualCollisions = actualCollisions + 1
		end
	end

	if actualCollisions > 0 then
		return targetPosition, true, "Can't Place Here!"
	end

	local closeToAnyOwnedUnit = false
	local tooCloseToEnemy = false
	local unitsFolder = workspace:FindFirstChild("Units")

	if unitsFolder then
		for _, unitModel in ipairs(unitsFolder:GetChildren()) do
			if unitModel:IsA("Model") and unitModel.PrimaryPart then
				local ownerValue = unitModel:FindFirstChild("Owner")

				local enemyRangeVisual = unitModel:FindFirstChild("RangeVisual")
				if not enemyRangeVisual then
					return
				end
				local enemyRange = enemyRangeVisual.Size.X / 2

				if ownerValue then
					local myPos = Vector3.new(targetPosition.X, 0, targetPosition.Z)
					local enemyPos = Vector3.new(unitModel.PrimaryPart.Position.X, 0, unitModel.PrimaryPart.Position.Z)
					local distance = (enemyPos - myPos).Magnitude

					if ownerValue.Value == plr then
						if distance <= 10 then
							closeToAnyOwnedUnit = true
						end
					else
						if enemyRange > 0 and distance <= enemyRange then
							tooCloseToEnemy = true
							break
						end
					end
				end
			end
		end
	end

	if tooCloseToEnemy then
		return targetPosition, true, "Too Close To Enemy!"
	end

	if not closeToAnyOwnedUnit then
		return targetPosition, true, "No Units Nearby"
	end

	return targetPosition, false, nil
end

function PlacementManager.Init(modules)
	GuiManager = modules.GuiManager
end

-- 1. Yerleştirmeyi Başlat
function PlacementManager.Start(buildingName)
	if placementConn then
		return
	end
	local data = buildingData[buildingName]
	if not data then
		return
	end
	local isLimit = isLimitRemote:InvokeServer("BUILDING", data)
	if isLimit then
		GuiManager.NewRedNotification("This building limit reached! (" .. data.Limit .. ")")
		return
	end

	currentData = data

	local buildingModel = game.ReplicatedStorage.Assets.Models.BuildingModels:FindFirstChild(buildingName)
	if not buildingModel then
		return
	end

	currentClone = buildingModel:Clone()

	if data.Range then
		local oldVisual = currentClone:FindFirstChild("RangeVisual")
		if oldVisual then
			oldVisual:Destroy()
		end

		local rangeVisual = game.ReplicatedStorage.Assets.UI.RangeVisual:Clone()

		rangeVisual.Size = Vector3.new(data.Range * 2, 0.001, data.Range * 2)
		rangeVisual.Parent = currentClone

		local primaryPart = currentClone.PrimaryPart
		if primaryPart then
			rangeVisual.CFrame = primaryPart.CFrame * CFrame.new(0, -primaryPart.Size.Y / 2, 0)

			local weld = Instance.new("WeldConstraint")
			weld.Name = "RangeWeld"
			weld.Part0 = primaryPart
			weld.Part1 = rangeVisual
			weld.Parent = rangeVisual
		end
	end

	for _, v in pairs(currentClone:GetDescendants()) do
		if v:IsA("BasePart") and v.Name ~= "Primary" and v.Name ~= "Range" and v.Name ~= "RangeVisual" then
			v.Anchored = true
			v.Transparency = 0.5
			v.CanCollide = false
		elseif v:IsA("ImageLabel") then
			v.ImageTransparency = 0.5
		end
	end

	GuiManager.BuildingStart()

	-- Her karede binayı farenin ucuna taşı ve çakışma rengini ayarla
	placementConn = runService.RenderStepped:Connect(function()
		local targetPosition, isColliding, msg = checkPlacementStatus()

		GuiManager.BuildingNewPos(targetPosition, msg)

		if targetPosition and currentClone and currentData then
			currentClone:PivotTo(CFrame.new(targetPosition) * CFrame.Angles(0, math.rad(currentRotation), 0))

			local color = isColliding and BrickColor.new("Really red") or BrickColor.new("Lime green")
			for _, part in pairs(currentClone:GetDescendants()) do
				if part:IsA("BasePart") and part.Name ~= "Primary" and part.Name ~= "RangeVisual" then
					part.BrickColor = color
				end
			end
		end
	end)

	currentClone.Parent = workspace
end

-- 2. Binayı Yerleştir (Tıklandığında)
function PlacementManager.Place()
	if not placementConn or not currentClone then
		return
	end

	local targetPosition, isColliding, errorMessage = checkPlacementStatus()

	if isColliding then
		GuiManager.NewRedNotification(errorMessage or "Can't Place Here!")
		return false
	end

	local enoughCash = enoughCashRemote:InvokeServer("BUILDING", currentData.Name)
	if not enoughCash then
		GuiManager.NewRedNotification("Not Enough Cash!")
		return false
	end

	if targetPosition then
		targetPosition = CFrame.new(targetPosition) * CFrame.Angles(0, math.rad(currentRotation), 0)
		local ray = camera:ScreenPointToRay(mouse.X, mouse.Y)
		local rayParams = RaycastParams.new()
		rayParams.FilterType = Enum.RaycastFilterType.Include
		rayParams.FilterDescendantsInstances =
			{ workspace:FindFirstChild("FarmZones"), workspace:FindFirstChild("RigZones") }
		local result = workspace:Raycast(ray.Origin, ray.Direction * 1000, rayParams)

		local instance = result and result.Instance

		local zonePart = (instance and (instance.Name == "FarmZone" or instance.Name == "RigZone")) and instance or nil

		buildEvent:FireServer(currentClone.Name, targetPosition, zonePart)
		PlacementManager.Cancel()
		GuiManager.BuildingEnd()
		return true
	end
	return false
end

-- 3. İptal Et (E tuşuna basıldığında veya işlem bittiğinde)
function PlacementManager.Cancel()
	if placementConn then
		placementConn:Disconnect()
		placementConn = nil
	end
	if currentClone then
		currentClone:Destroy()
		currentClone = nil
	end
	GuiManager.BuildingEnd()
	currentData = nil
	currentRotation = 0
end

function PlacementManager.Rotate()
	currentRotation += 15
end

-- Şu an bir şey yerleştiriyor muyuz kontrolü
function PlacementManager.IsPlacing()
	return placementConn ~= nil
end

return PlacementManager
