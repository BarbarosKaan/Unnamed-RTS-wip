local folder = game.StarterPlayer.StarterPlayerScripts.Client.Modules
local Loader = {}

for _, child in ipairs(folder:GetChildren()) do
	if child:IsA("ModuleScript") then
		Loader[child.Name] = require(child)
	end
end

for _, module in pairs(Loader) do
	if type(module.Init) == "function" then
		module.Init(Loader)
	end
end
