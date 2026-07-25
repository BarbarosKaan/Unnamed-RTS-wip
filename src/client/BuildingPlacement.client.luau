local plr = game.Players.LocalPlayer
local starterPlayer = game:GetService("StarterPlayer")
local starterPlayerScripts = starterPlayer.StarterPlayerScripts
local UIS = game:GetService("UserInputService")
local ts = game:GetService("TweenService")

local PlacementManager = require(starterPlayerScripts.Client.Modules.PlacementManager)
local GuiManager = require(starterPlayerScripts.Client.Modules.GuiManager)

local screenGui = plr:WaitForChild("PlayerGui"):WaitForChild("ScreenGui")

local farmZones = workspace:WaitForChild("FarmZones")
local rigZones = workspace:WaitForChild("RigZones")

local buildingsFrame = screenGui:WaitForChild("Buildings")
local buildingButtonsFrame = buildingsFrame:WaitForChild("Buttons")
local buildingButtons = GuiManager.SetupBuildingButtons(buildingButtonsFrame)
buildingsFrame.Visible = true

local function onBuildingStart(name)
	if name == "Farm" then
		for _, zone in pairs(farmZones:GetChildren()) do
			ts:Create(zone, TweenInfo.new(0.5, Enum.EasingStyle.Linear), { Transparency = 0.7 }):Play()
		end
	elseif name == "Oil Rig" then
		for _, zone in pairs(rigZones:GetChildren()) do
			ts:Create(zone, TweenInfo.new(0.5, Enum.EasingStyle.Linear), { Transparency = 0.7 }):Play()
		end
	end
end

local function onBuildingEnd()
	for _, zone in pairs(farmZones:GetChildren()) do
		ts:Create(zone, TweenInfo.new(0.5, Enum.EasingStyle.Linear), { Transparency = 1 }):Play()
	end
	for _, zone in pairs(rigZones:GetChildren()) do
		ts:Create(zone, TweenInfo.new(0.5, Enum.EasingStyle.Linear), { Transparency = 1 }):Play()
	end
end

-- Butonlara tıklanınca yerleştirmeyi başlat
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

-- Klavyeden ve fareden gelen emirleri yönet
UIS.InputBegan:Connect(function(input, gameProcessed)
	if gameProcessed then
		return
	end
	if not PlacementManager.IsPlacing() then
		return
	end -- Eğer modül aktif değilse hiçbir şey yapma

	if input.KeyCode == Enum.KeyCode.E then
		-- İptal Et
		PlacementManager.Cancel()
		onBuildingEnd()
	elseif input.UserInputType == Enum.UserInputType.MouseButton1 then
		-- Yerleştir
		local success = PlacementManager.Place()
		if success then
			onBuildingEnd()
		end
	elseif input.KeyCode == Enum.KeyCode.R then
		-- Döndür
		PlacementManager.Rotate()
	end
end)
