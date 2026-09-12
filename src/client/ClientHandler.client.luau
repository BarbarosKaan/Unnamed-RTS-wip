local StarterPlayerScripts = game:GetService("StarterPlayer").StarterPlayerScripts
local ClientController = require(StarterPlayerScripts.Client.Modules.ClientController)
local GameStartedVal = game:GetService("ReplicatedStorage"):WaitForChild("GameStarted")
local firstCheck = true

ClientController.Init()

local function onGameStartedChanged()
	if GameStartedVal.Value then
		ClientController.StartGame()
	else
		if not firstCheck then
			ClientController.StopGame()
		end
		firstCheck = false
	end
end

onGameStartedChanged() -- Call the function initially to set the correct state based on the current value of GameStartedVal
GameStartedVal.Changed:Connect(onGameStartedChanged)
