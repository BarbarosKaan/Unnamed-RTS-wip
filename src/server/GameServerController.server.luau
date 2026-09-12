local ServerScriptService = game:GetService("ServerScriptService")
local server = ServerScriptService.Server

local gameServerController = require(server.Modules.GameServerController)
local votingServerManager = require(server.Modules.VotingServerManager)

gameServerController.Init()
task.wait(2)
print("STARTING GAME")
votingServerManager.StartVoting()
