local SelectionManager = {}

local VisualManager
local GuiManager

SelectionManager.SelectedUnits = {}

function SelectionManager.Init(modules)
	VisualManager = modules.VisualManager
	GuiManager = modules.GuiManager
end

function SelectionManager.IsSelected(model)
	return table.find(SelectionManager.SelectedUnits, model) ~= nil
end

function SelectionManager.SelectUnit(model)
	if not model or SelectionManager.IsSelected(model) then
		return
	end
	table.insert(SelectionManager.SelectedUnits, model)

	GuiManager.SelectNew(model, SelectionManager.SelectedUnits)
	VisualManager.AddSelectionBox(model)
end

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

function SelectionManager.ClearAll()
	for _, unit in ipairs(table.clone(SelectionManager.SelectedUnits)) do
		SelectionManager.DeselectUnit(unit)
	end
end

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
