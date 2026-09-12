local VotingServer = {}

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local Players = game:GetService("Players")

local server = ServerScriptService.Server
local GameServerController = require(server.Modules.GameServerController)

local remotes = ReplicatedStorage.Remotes
local ToggleVotingEvent = remotes:WaitForChild("ToggleVotingEvent")
local SendVoteEvent = remotes:WaitForChild("SendVoteEvent")
local UpdateVotesEvent = remotes:WaitForChild("UpdateVotesEvent")

local countdownThread

local ChosenMaps = {}
local PlayerVotes = {}
local Skippers = {}

--TODO:IMPLEMENT CLIENT VOTING GUI AND SERVER VOTING LOGIC

function IsSkip()
	local plrAmt = #Players:GetPlayers()
	local skipAmt = 0

	for _, isSkipping in pairs(Skippers) do
		if isSkipping then
			skipAmt += 1
		end
	end

	if skipAmt >= math.ceil(plrAmt * 0.5) then
		return true
	end
	return false
end

function ProcessFinish()
	local winner = VotingServer.GetWinningMap()
	if winner then
		print("Winning map is: " .. winner)
		local mapsFolder = ReplicatedStorage.Assets.Models.Maps:FindFirstChild(GameServerController.GetGameMode())
		local winningMap = mapsFolder:FindFirstChild(winner)
		if winningMap then
			GameServerController.SetChosenMap(winningMap)
		end
	end
	ToggleVotingEvent:FireAllClients(false)
	VotingServer.ClearVotes()

	task.wait(1)
	GameServerController.StartGame()
end

function VotingServer.GetRandomMaps()
	local gameMode = GameServerController.GetGameMode()
	local mapsFolder = ReplicatedStorage.Assets.Models.Maps:FindFirstChild(gameMode)

	if not mapsFolder then
		warn(`Map folder not found for game mode: {gameMode}`)
		return {}
	end

	local availableMaps = mapsFolder:GetChildren()

	if #availableMaps < 3 then
		warn("At least 3 maps are required for voting")
		return {}
	end

	for _ = 1, 3 do
		local randomIndex = math.random(1, #availableMaps)
		local selectedMap = table.remove(availableMaps, randomIndex)
		table.insert(ChosenMaps, selectedMap.Name)
	end

	return ChosenMaps
end

function VotingServer.CastVote(player, mapName)
	if typeof(mapName) ~= "string" then
		return false
	end

	local isValidMap = false
	for _, name in ipairs(ChosenMaps) do
		if name == mapName then
			isValidMap = true
			break
		end
	end

	if not isValidMap then
		return false
	end

	PlayerVotes[player.UserId] = mapName
	return true
end

function VotingServer.GetVoteAmounts()
	local voteCounts = {}

	for _, mapName in ipairs(ChosenMaps) do
		voteCounts[mapName] = 0
	end

	for _, mapName in pairs(PlayerVotes) do
		voteCounts[mapName] = (voteCounts[mapName] or 0) + 1
	end

	local skipAmt = 0

	for _, isSkipping in pairs(Skippers) do
		if isSkipping then
			skipAmt += 1
		end
	end

	return voteCounts, skipAmt
end

function VotingServer.GetWinningMap()
	local voteCounts = VotingServer.GetVoteAmounts()
	local maxVotes = -1
	local winningMaps = {}

	for mapName, count in pairs(voteCounts) do
		if count > maxVotes then
			maxVotes = count
			winningMaps = { mapName }
		elseif count == maxVotes then
			table.insert(winningMaps, mapName)
		end
	end

	if #winningMaps == 0 then
		return nil
	elseif #winningMaps == 1 then
		return winningMaps[1]
	else
		local randomIndex = math.random(1, #winningMaps)
		return winningMaps[randomIndex]
	end
end

function VotingServer.ClearVotes()
	table.clear(PlayerVotes)
end

function VotingServer.StartTimer()
	local timerDuration = 30
	local timerInstance = Instance.new("IntValue")
	timerInstance.Name = "VotingTimer"
	timerInstance.Value = timerDuration
	timerInstance.Parent = ReplicatedStorage

	countdownThread = task.spawn(function()
		while timerInstance.Value > 0 do
			task.wait(1)
			timerInstance.Value -= 1
		end
		ProcessFinish()
		timerInstance:Destroy()
	end)
	return timerInstance
end

function VotingServer.StopTimer()
	if countdownThread then
		task.cancel(countdownThread)
		countdownThread = nil
	end

	local timerInstance = ReplicatedStorage:FindFirstChild("VotingTimer")
	if timerInstance then
		timerInstance:Destroy()
	end
end

function VotingServer.HowManySkipsNeeded()
	local plrAmt = #Players:GetPlayers()
	return math.ceil(plrAmt * 0.5)
end

function VotingServer.SkipVote(player)
	local currentVote = Skippers[player.UserId]
	Skippers[player.UserId] = not currentVote
	local skip = IsSkip()
	if skip then
		ProcessFinish()
		VotingServer.StopTimer()
	end
end

function VotingServer.StartVoting()
	ChosenMaps = VotingServer.GetRandomMaps()
	PlayerVotes = {}
	Skippers = {}
	local timer = VotingServer.StartTimer()
	local skipNeeded = VotingServer.HowManySkipsNeeded()

	ToggleVotingEvent:FireAllClients(true, ChosenMaps, timer, skipNeeded)

	SendVoteEvent.OnServerEvent:Connect(function(player, mapName)
		if mapName == "Skip" then
			VotingServer.SkipVote(player)
		else
			VotingServer.CastVote(player, mapName)
		end
		local voteCounts, skipCount = VotingServer.GetVoteAmounts()

		local skipNeeded2 = VotingServer.HowManySkipsNeeded()
		UpdateVotesEvent:FireAllClients(voteCounts, skipCount, skipNeeded2)
	end)
end

return VotingServer
