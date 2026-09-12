local GameServerController = {}

local ServerScriptService = game:GetService("ServerScriptService")
local server = ServerScriptService.Server

local playerAddedService = require(server.Modules.PlayerAddedService)
local eventManager = require(server.Modules.EventService)

local gameStartedVal = game:GetService("ReplicatedStorage").GameStarted
local isGameActive = false

local chosenMap = nil

function GameServerController.SetChosenMap(map)
	chosenMap = map
end

function GameServerController.LoadMap(map)
	local mapClone = map:Clone()
	local oldBaseplate = workspace:FindFirstChild("Baseplate")
	if oldBaseplate then
		oldBaseplate:Destroy()
	end

	for _, child in ipairs(mapClone:GetChildren()) do
		child.Parent = workspace
	end

	mapClone:Destroy()
end

function GameServerController.Init()
	playerAddedService.Init(GameServerController)
	eventManager.Init(GameServerController)
end

function GameServerController.GetGameMode()
	return "1v1"
end

function GameServerController.StartGame()
	if isGameActive then
		return
	end
	GameServerController.LoadMap(chosenMap)
	isGameActive = true
	playerAddedService.Start()
	gameStartedVal.Value = true
	print("Game start requested")
end

function GameServerController.StopGame()
	if not isGameActive then
		return
	end

	isGameActive = false
	playerAddedService.Stop()
	gameStartedVal.Value = false
	print("Game stopped")
end

function GameServerController.IsGameActive()
	return isGameActive
end

return GameServerController
