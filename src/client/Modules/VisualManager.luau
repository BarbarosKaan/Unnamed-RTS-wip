local VisualManager = {}
local beamSegments = {}

-- Click efekti
local clickAtt = game.ReplicatedStorage.Shared.Assets.Effects.ClickAttachment

function VisualManager.AddHighlight(model)
	if not model.PrimaryPart then
		return
	end
	local highlight = Instance.new("SelectionBox")
	highlight.Color3 = Color3.new(0.890196, 0.890196, 0.890196)
	highlight.LineThickness = 0.05
	highlight.Parent = model
	highlight.Adornee = model.PrimaryPart
end

function VisualManager.RemoveHighlight(model)
	if not model then
		return
	end
	local highlight = model:FindFirstChild("SelectionBox")
	if highlight then
		highlight:Destroy()
	end
end

function VisualManager.AddSelectionBox(model)
	if not model then
		return
	end
	local box = model:FindFirstChild("SelectionPart")
	if box then
		box.Transparency = 0
	end
end

function VisualManager.RemoveSelectionBox(model)
	if not model then
		return
	end
	local box = model:FindFirstChild("SelectionPart")
	if box then
		box.Transparency = 1
	end
end

function VisualManager.ClearBeams(model)
	if beamSegments[model] then
		for _, data in ipairs(beamSegments[model]) do
			data.active = false
			if data.beam then
				data.beam:Destroy()
			end
			if data.toPart then
				data.toPart:Destroy()
			end
		end
		beamSegments[model] = nil
	end
end

function VisualManager.AddWaypoint(model, pos)
	local plr = game.Players.LocalPlayer
	local moveAtt = model.PrimaryPart:FindFirstChild("Attachment")
	if not moveAtt then
		return
	end
	if not beamSegments[model] then
		beamSegments[model] = {}
	end

	local fromAtt = #beamSegments[model] == 0 and moveAtt or beamSegments[model][#beamSegments[model]].toAtt

	local toPart = Instance.new("Part")
	toPart.Size = Vector3.new(1, 1, 1)
	toPart.Anchored = true
	toPart.CanCollide = false
	toPart.CanTouch = false
	toPart.CanQuery = false
	toPart.Transparency = 1
	toPart.Position = pos + Vector3.new(0, 1, 0)
	toPart.Parent = workspace

	local toAtt = Instance.new("Attachment")
	toAtt.Parent = toPart

	local beam = Instance.new("Beam")
	beam.Attachment0 = fromAtt
	beam.Attachment1 = toAtt
	beam.FaceCamera = true
	beam.Parent = model
	beam.Color = ColorSequence.new(plr.TeamColor.Color)
	beam.Width0 = 0.2
	beam.Width1 = 0.2

	local segmentData = { beam = beam, toPart = toPart, toAtt = toAtt, active = true }
	table.insert(beamSegments[model], segmentData)

	task.spawn(function()
		while toPart and toPart.Parent and segmentData.active do
			task.wait(0.1)
			if not model.PrimaryPart then
				break
			end

			if beamSegments[model] and beamSegments[model][1] == segmentData then
				local modelPos2D = Vector2.new(model.PrimaryPart.Position.X, model.PrimaryPart.Position.Z)
				local toPartPos2D = Vector2.new(toPart.Position.X, toPart.Position.Z)

				if (modelPos2D - toPartPos2D).Magnitude < 3 then
					beam:Destroy()
					toPart:Destroy()
					table.remove(beamSegments[model], 1)
					if beamSegments[model][1] then
						beamSegments[model][1].beam.Attachment0 = moveAtt
					end
					break
				end
			end
		end
	end)
end

function VisualManager.ClickEffect()
	local plr = game.Players.LocalPlayer
	local mouse = plr:GetMouse()
	local pos = mouse.Hit.Position + Vector3.new(0, 0.05, 0)
	if not pos then
		return
	end
	local clone = clickAtt:Clone()
	clone.Parent = workspace
	clone.Position = pos
	local particle = clone:FindFirstChild("ParticleEmitter")
	particle.Color = ColorSequence.new(plr.TeamColor.Color)
	particle:Emit(1)
	game.Debris:AddItem(clone, 1)
end

return VisualManager
