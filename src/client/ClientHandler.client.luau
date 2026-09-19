local StarterPlayerScripts = game:GetService("StarterPlayer").StarterPlayerScripts
local Players = game:GetService("Players")
local ClientController = require(StarterPlayerScripts.Client.Modules.ClientController)
local GameStartedVal = game:GetService("ReplicatedStorage"):WaitForChild("GameStarted")
local player = Players.LocalPlayer
local firstCheck = true
local teamConnection

ClientController.Init()

local function startWhenReady()
	if not GameStartedVal.Value then
		return
	end

	if player.Team and player.Team.Name ~= "Neutral" then
		if teamConnection then
			teamConnection:Disconnect()
			teamConnection = nil
		end
		ClientController.StartGame()
	elseif not teamConnection then
		teamConnection = player:GetPropertyChangedSignal("Team"):Connect(startWhenReady)
	end
end

local function onGameStartedChanged()
	if GameStartedVal.Value then
		startWhenReady()
	else
		if teamConnection then
			teamConnection:Disconnect()
			teamConnection = nil
		end
		if not firstCheck then
			ClientController.StopGame()
		end
		firstCheck = false
	end
end

onGameStartedChanged() -- Call the function initially to set the correct state based on the current value of GameStartedVal
GameStartedVal.Changed:Connect(onGameStartedChanged)
