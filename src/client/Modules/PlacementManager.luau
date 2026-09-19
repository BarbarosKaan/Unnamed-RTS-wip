local PlacementManager = {}

local buildingData = require(game.ReplicatedStorage.Shared.Data.BuildingData)
local GuiManager

local runService = game:GetService("RunService")
local collectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local players = game:GetService("Players")
local camera = workspace.CurrentCamera
local plr = players.LocalPlayer
local playerGui = plr:WaitForChild("PlayerGui")
local mouse = plr:GetMouse()

local buildEvent = ReplicatedStorage.Remotes.BuildEvent
local enoughCashRemote = ReplicatedStorage.Remotes.EnoughCash
local enoughEnergyRemote = ReplicatedStorage.Remotes.EnoughEnergy
local isLimitRemote = ReplicatedStorage.Remotes.IsLimit

local currentRotation = 0
local placementConn = nil
local currentClone = nil
local currentData = nil
local placementEndCallback = nil
local mobileButtonConnections = {}
local lastTargetPosition = nil
local lastIsColliding = true
local lastErrorMessage = nil
local lastHitPart = nil

local function disconnectMobileButtonConnections()
	for _, connection in ipairs(mobileButtonConnections) do
		connection:Disconnect()
	end
	table.clear(mobileButtonConnections)
end

-- Validate whether the current building can be placed at the target location.
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
		lastHitPart = nil
		return nil, false, nil
	end
	lastHitPart = result.Instance

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
					continue
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

-- Connect the placement manager to the GUI module.
function PlacementManager.Init(modules)
	GuiManager = modules.GuiManager
end

-- Start a new placement session for the selected building.
function PlacementManager.Start(buildingName, onEnd)
	mouse.TargetFilter = workspace.Walls

	local isMobile = UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled

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

	local enoughCash = enoughCashRemote:InvokeServer("BUILDING", data.Name)
	if not enoughCash then
		GuiManager.NewRedNotification("Not Enough Cash!")
		return
	end

	local enoughEnergy = enoughEnergyRemote:InvokeServer(data)
	if not enoughEnergy then
		GuiManager.NewRedNotification("Not Enough Energy!")
		return
	end

	currentData = data
	placementEndCallback = onEnd

	local buildingModel = game.ReplicatedStorage.Assets.Models.BuildingModels:FindFirstChild(buildingName)
	if not buildingModel then
		return
	end

	currentClone = buildingModel:Clone()

	for _, part in pairs(currentClone:GetDescendants()) do
		if part ~= currentClone.PrimaryPart then
			part:Destroy()
		end
	end

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
		if v:IsA("BasePart") and v.Name ~= "Range" and v.Name ~= "RangeVisual" then
			v.Anchored = true
			v.Transparency = 0.5
			v.CanCollide = false
		elseif v:IsA("ImageLabel") then
			v.ImageTransparency = 0.5
		end
	end

	local mobileButtons = GuiManager.BuildingStart(isMobile)
	lastTargetPosition = nil
	lastIsColliding = true
	lastErrorMessage = nil
	lastHitPart = nil

	-- Move the preview building with the mouse each frame and update its color.
	placementConn = runService.RenderStepped:Connect(function()
		local targetPosition = lastTargetPosition
		local isColliding = lastIsColliding
		local msg = lastErrorMessage
		local isOverMobileButtons = false

		if mobileButtons then
			for _, guiObject in ipairs(playerGui:GetGuiObjectsAtPosition(mouse.X, mouse.Y)) do
				if guiObject == mobileButtons or guiObject:IsDescendantOf(mobileButtons) then
					isOverMobileButtons = true
					break
				end
			end
		end

		if not isOverMobileButtons then
			targetPosition, isColliding, msg = checkPlacementStatus()
			lastTargetPosition = targetPosition
			lastIsColliding = isColliding
			lastErrorMessage = msg
		end

		GuiManager.BuildingNewPos(targetPosition, msg)

		if targetPosition and currentClone and currentData then
			currentClone:PivotTo(CFrame.new(targetPosition) * CFrame.Angles(0, math.rad(currentRotation), 0))

			local color = isColliding and BrickColor.new("Really red") or BrickColor.new("Lime green")
			for _, part in pairs(currentClone:GetDescendants()) do
				if part:IsA("BasePart") and part.Name ~= "RangeVisual" then
					part.BrickColor = color
				end
			end
		end
	end)

	if mobileButtons then
		local rotateButton = mobileButtons:FindFirstChild("RotateButton")
		if rotateButton then
			table.insert(
				mobileButtonConnections,
				rotateButton.MouseButton1Click:Connect(function()
					PlacementManager.Rotate()
				end)
			)
		end

		local placeButton = mobileButtons:FindFirstChild("PlaceButton")
		if placeButton then
			table.insert(
				mobileButtonConnections,
				placeButton.MouseButton1Click:Connect(function()
					PlacementManager.Place()
				end)
			)
		end

		local cancelButton = mobileButtons:FindFirstChild("CancelButton")
		if cancelButton then
			table.insert(
				mobileButtonConnections,
				cancelButton.MouseButton1Click:Connect(function()
					PlacementManager.Cancel()
				end)
			)
		end
	end

	currentClone.Parent = workspace
end

-- Place the building on the current valid position.
function PlacementManager.Place()
	if not placementConn or not currentClone then
		return
	end
	local activeClone = currentClone
	local activeData = currentData

	local targetPosition = lastTargetPosition
	local isColliding = lastIsColliding
	local errorMessage = lastErrorMessage

	if isColliding then
		GuiManager.NewRedNotification(errorMessage or "Can't Place Here!")
		return false
	end

	local enoughCash = enoughCashRemote:InvokeServer("BUILDING", activeData.Name)
	if not enoughCash then
		GuiManager.NewRedNotification("Not Enough Cash!")
		return false
	end

	local enoughEnergy = enoughEnergyRemote:InvokeServer(activeData)
	if not enoughEnergy then
		GuiManager.NewRedNotification("Not Enough Energy!")
		return false
	end

	if targetPosition then
		if not placementConn or currentClone ~= activeClone or currentData ~= activeData then
			return false
		end

		targetPosition = CFrame.new(targetPosition) * CFrame.Angles(0, math.rad(currentRotation), 0)
		local zonePart = (lastHitPart and (lastHitPart.Name == "FarmZone" or lastHitPart.Name == "RigZone"))
				and lastHitPart
			or nil

		buildEvent:FireServer(activeClone.Name, targetPosition, zonePart)
		PlacementManager.Cancel()
		return true
	end
	return false
end

-- Cancel the active placement session and clean up the preview.
function PlacementManager.Cancel()
	local endCallback = placementEndCallback
	disconnectMobileButtonConnections()
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
	placementEndCallback = nil
	currentRotation = 0
	lastTargetPosition = nil
	lastIsColliding = true
	lastErrorMessage = nil
	lastHitPart = nil
	if endCallback then
		endCallback()
	end
end

-- Rotate the preview building by 15 degrees.
function PlacementManager.Rotate()
	currentRotation += 15
end

-- Return whether a building placement session is currently active.
function PlacementManager.IsPlacing()
	return placementConn ~= nil
end

return PlacementManager
