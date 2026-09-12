local VotingManager = {}

local GuiManager

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local remotes = ReplicatedStorage.Remotes
local ToggleVotingEvent = remotes:WaitForChild("ToggleVotingEvent")
local SendVoteEvent = remotes:WaitForChild("SendVoteEvent")
local UpdateVotesEvent = remotes:WaitForChild("UpdateVotesEvent")

local screenGui
local container
local skipButton
local timerLabel
local optionsFrame

local function setupVariables()
	container = screenGui:WaitForChild("Container")
	skipButton = container:WaitForChild("SkipButton")
	timerLabel = container:WaitForChild("Timer")
	optionsFrame = container:WaitForChild("Options")
end

function VotingManager.Init(modules)
	GuiManager = modules.GuiManager

	ToggleVotingEvent.OnClientEvent:Connect(function(isVoting, ChosenMaps, timer, skipNeeded)
		if isVoting then
			VotingManager.StartVoting(ChosenMaps, timer, skipNeeded)
		else
			VotingManager.StopVoting()
		end
	end)

	UpdateVotesEvent.OnClientEvent:Connect(function(voteCounts, skipCount, skipNeeded)
		VotingManager.UpdateVotes(voteCounts, skipCount, skipNeeded)
	end)
end

function VotingManager.StartVoting(ChosenMaps, timer, skipNeeded)
	print(GuiManager)
	screenGui = GuiManager.OnVotingStarted()
	setupVariables()

	skipButton.Text = "Skip (0/" .. skipNeeded .. ")"
	timerLabel.Text = timer.Value .. "s"

	for i, mapName in ipairs(ChosenMaps) do
		local optionFrame = optionsFrame:WaitForChild("Frame" .. i)
		local imageButton = optionFrame:WaitForChild("ImageButton")
		local nameLabel = optionFrame:WaitForChild("NameLabel")
		local countLabel = optionFrame:WaitForChild("CountLabel")
		optionFrame.Name = mapName
		countLabel.Text = "0"
		nameLabel.Text = mapName
		imageButton.MouseButton1Click:Connect(function()
			SendVoteEvent:FireServer(mapName)
		end)
	end

	skipButton.MouseButton1Click:Connect(function()
		SendVoteEvent:FireServer("Skip")
	end)

	timer.Changed:Connect(function()
		timerLabel.Text = timer.Value .. "s"
	end)
end

function VotingManager.StopVoting()
	if screenGui then
		GuiManager.OnVotingEnded()
	end
end

function VotingManager.UpdateVotes(voteCounts, skipCount, skipNeeded)
	skipButton.Text = "Skip (" .. skipCount .. "/" .. skipNeeded .. ")"

	for mapName, count in pairs(voteCounts) do
		local optionFrame = optionsFrame:WaitForChild(mapName)
		local countLabel = optionFrame:WaitForChild("CountLabel")
		countLabel.Text = count
	end
end

return VotingManager
