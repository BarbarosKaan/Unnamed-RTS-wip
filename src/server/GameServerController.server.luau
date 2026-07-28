local ServerScriptService = game:GetService("ServerScriptService")
local server = ServerScriptService.Server

local gameServerController = require(server.Modules.GameServerController)

gameServerController.Init()
task.wait(2)
print("STARTING GAME")
gameServerController.StartGame()
