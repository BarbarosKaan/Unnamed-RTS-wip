local SelectionManager = {}

local VisualManager
local GuiManager

SelectionManager.SelectedUnits = {}

-- Initialize the selection manager and wire it to the supporting modules.
function SelectionManager.Init(modules)
	VisualManager = modules.VisualManager
	GuiManager = modules.GuiManager
end

-- Return whether a model is currently selected.
function SelectionManager.IsSelected(model)
	return table.find(SelectionManager.SelectedUnits, model) ~= nil
end

-- Add a unit to the current selection list.
function SelectionManager.SelectUnit(model)
	if not model or SelectionManager.IsSelected(model) then
		return
	end
	table.insert(SelectionManager.SelectedUnits, model)

	GuiManager.SelectNew(model, SelectionManager.SelectedUnits)
	VisualManager.AddSelectionBox(model)
end

-- Remove a unit from the current selection list.
function SelectionManager.DeselectUnit(model)
	if not model then
		return
	end
	local idx = table.find(SelectionManager.SelectedUnits, model)
	if not idx then
		return
	end

	table.remove(SelectionManager.SelectedUnits, idx)

	GuiManager.Deselect(model, SelectionManager.SelectedUnits)
	VisualManager.RemoveSelectionBox(model)
end

-- Clear the full current selection.
function SelectionManager.ClearAll()
	for _, unit in ipairs(table.clone(SelectionManager.SelectedUnits)) do
		SelectionManager.DeselectUnit(unit)
	end
end

-- Apply hover visuals to a unit.
function SelectionManager.HoverStart(model)
	if not model then
		return
	end

	local range = model:FindFirstChild("RangeVisual") and model.RangeVisual.SurfaceGui.ImageLabel
	if range then
		range.ImageTransparency = 0.5
	end

	VisualManager.AddHighlight(model)
end

-- Remove hover visuals from a unit.
function SelectionManager.HoverEnd(model)
	if not model then
		return
	end

	local range = model:FindFirstChild("RangeVisual") and model.RangeVisual.SurfaceGui.ImageLabel
	if range then
		range.ImageTransparency = 1
	end

	VisualManager.RemoveHighlight(model)
end

-- Return all selected units that match a given name.
function SelectionManager.GetAllOfName(name)
	local results = {}
	for _, unit in ipairs(SelectionManager.SelectedUnits) do
		if unit.Name == name then
			table.insert(results, unit)
		end
	end
	return results
end

return SelectionManager
