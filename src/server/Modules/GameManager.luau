local manager = {}

local activeUnits = {}
local queueUnits = {}
local activeBuildings = {}
local activeAll = {}

----------------------------------------
-- KAYIT ETME FONKSİYONLARI (Setters)
----------------------------------------
function manager.RegisterUnit(unitModel, unitObject)
	activeUnits[unitModel] = unitObject
	activeAll[unitModel] = unitObject
end

function manager.UnregisterUnit(unitModel)
	activeUnits[unitModel] = nil
	activeAll[unitModel] = nil
end

function manager.RegisterUnitQueue(unitObject, owner)
	unitObject.Owner = owner
	table.insert(queueUnits, unitObject)
end

function manager.UnregisterUnitQueue(unitObject)
	local idx = table.find(queueUnits, unitObject)
	if idx then
		table.remove(queueUnits, idx)
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
-- ERİŞİM FONKSİYONLARI (Getters)
----------------------------------------
function manager.GetUnit(unitModel)
	return activeUnits[unitModel]
end

function manager.GetBuilding(buildingModel)
	return activeBuildings[buildingModel]
end

-- Tüm binaları veya askerleri toplu almak istersen (Örn: Yapay zeka hedef ararken)
function manager.GetAllBuildings()
	return activeBuildings
end

function manager.GetAllUnits()
	return activeUnits
end

function manager.GetQueueAndActiveUnits()
	local units = {}
	for _, unit in ipairs(queueUnits) do
		table.insert(units, unit)
	end
	for _, unit in pairs(activeUnits) do
		table.insert(units, unit)
	end
	return units
end

function manager.GetEverything()
	return activeAll
end

return manager
