local manager = {}

local activeTroops = {}
local queueTroops = {}
local activeBuildings = {}
local activeAll = {}

----------------------------------------
-- REGISTRATION FUNCTIONS
----------------------------------------
function manager.RegisterTroop(troopModel, troopObject)
	activeTroops[troopModel] = troopObject
	activeAll[troopModel] = troopObject
end

function manager.UnregisterTroop(troopModel)
	activeTroops[troopModel] = nil
	activeAll[troopModel] = nil
end

function manager.RegisterTroopQueue(troopObject, owner)
	troopObject.Owner = owner
	table.insert(queueTroops, troopObject)
end

function manager.UnregisterTroopQueue(troopObject)
	local idx = table.find(queueTroops, troopObject)
	if idx then
		table.remove(queueTroops, idx)
	end
end

function manager.RegisterBuilding(buildingModel, buildingObject)
	activeBuildings[buildingModel] = buildingObject
	activeAll[buildingModel] = buildingObject
end

function manager.UnregisterBuilding(buildingModel)
	activeBuildings[buildingModel] = nil
	activeAll[buildingModel] = nil
end

----------------------------------------
-- ACCESSOR FUNCTIONS
----------------------------------------
function manager.GetTroop(troopModel)
	return activeTroops[troopModel]
end

function manager.GetBuilding(buildingModel)
	return activeBuildings[buildingModel]
end

-- Retrieve all buildings or units in one place when needed.
function manager.GetAllBuildings()
	return activeBuildings
end

function manager.GetAllTroops()
	return activeTroops
end

function manager.GetQueueAndActiveTroops()
	local troops = {}
	for _, troop in ipairs(queueTroops) do
		table.insert(troops, troop)
	end
	for _, troop in pairs(activeTroops) do
		table.insert(troops, troop)
	end
	return troops
end

function manager.GetEverything()
	return activeAll
end

return manager
