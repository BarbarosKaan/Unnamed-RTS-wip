local plr = game.Players.LocalPlayer
local mouse = plr:GetMouse()
local camera = workspace.CurrentCamera
local UIS = game:GetService("UserInputService")
local StarterPlayer = game:GetService("StarterPlayer")
local StarterPlayerScripts = StarterPlayer.StarterPlayerScripts
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Modules = StarterPlayerScripts.Client:WaitForChild("Modules")
local Remotes = ReplicatedStorage:WaitForChild("Remotes")

-- Farenin görünmez duvarları yok sayması için filtre (Klasör adı: Walls)
mouse.TargetFilter = workspace:WaitForChild("Walls")

-- Modüller
local SelectionManager = require(Modules.SelectionManager)
local VisualManager = require(Modules.VisualManager)
local GuiManager = require(Modules.GuiManager)

-- Uzak Etkinlikler (Remotes)
local moveEvent = Remotes.MoveEvent
local removeSelectionEvent = Remotes.RemoveSelectionEvent
local interactEvent = Remotes.InteractEvent

local unitsFolder = workspace:WaitForChild("Units")

-- Sürükleme ve Hover Değişkenleri
local currentHoveredUnit = nil
local selectionBox = plr.PlayerGui:WaitForChild("ScreenGui").SelectionBox
local dragStart = nil
local isDragging = false
local DRAG_THRESHOLD = 20

--- ==========================================
--- YARDIMCI FONKSİYONLAR (UTILITIES)
--- ==========================================

-- Seçim kutusunun ekrandaki boyutunu ve pozisyonunu günceller
local function updateSelectionBox(from, to)
	local minX, minY = math.min(from.X, to.X), math.min(from.Y, to.Y)
	local maxX, maxY = math.max(from.X, to.X), math.max(from.Y, to.Y)
	selectionBox.Position = UDim2.fromOffset(minX, minY)
	selectionBox.Size = UDim2.fromOffset(maxX - minX, maxY - minY)
end

-- Sürükleme kutusunun içindeki oyuncuya ait üniteleri bulur
local function getUnitsInBox(from, to)
	local minX, minY = math.min(from.X, to.X), math.min(from.Y, to.Y)
	local maxX, maxY = math.max(from.X, to.X), math.max(from.Y, to.Y)
	local result = {}

	for _, model in ipairs(unitsFolder:GetChildren()) do
		if model:FindFirstChild("Owner") and model.Owner.Value == plr and model.PrimaryPart then
			local screenPos, onScreen = camera:WorldToScreenPoint(model.PrimaryPart.Position)
			if
				onScreen
				and screenPos.X >= minX
				and screenPos.X <= maxX
				and screenPos.Y >= minY
				and screenPos.Y <= maxY
			then
				if model:FindFirstChild("Type") and model.Type.Value == "UNIT" then
					table.insert(result, model)
				end
			end
		end
	end
	return result
end

local function getCenterOfUnits(selectedUnits)
	local totalPosition = Vector3.new(0, 0, 0)
	local count = #selectedUnits

	if count == 0 then
		return nil
	end

	for _, unit in ipairs(selectedUnits) do
		totalPosition = totalPosition + unit.PrimaryPart.Position
	end

	-- Ortalamasını alarak tam merkez koordinatı buluyoruz
	return totalPosition / count
end

--- ==========================================
--- GİRDİ MANTIKSAL FONKSİYONLARI (INPUT LOGIC)
--- ==========================================

-- Fare hareket ettikçe sürükleme kutusunu büyütür/küçültür
local function handleDragMovement(input)
	if (input.Position - dragStart).Magnitude > DRAG_THRESHOLD then
		isDragging = true
		selectionBox.Visible = true
		updateSelectionBox(dragStart, input.Position)
	end
end

-- Fare bir ünitenin üzerine geldiğinde (Hover) efektleri yönetir
local function handleUnitHover()
	local target = mouse.Target and mouse.Target:FindFirstAncestorOfClass("Model")
	local foundUnit = nil

	if target and target:FindFirstChild("Type") then
		foundUnit = target
	end

	if foundUnit ~= currentHoveredUnit then
		if currentHoveredUnit then
			SelectionManager.HoverEnd(currentHoveredUnit)
			GuiManager.HoverEnd()
		end

		currentHoveredUnit = foundUnit

		if currentHoveredUnit then
			SelectionManager.HoverStart(currentHoveredUnit)
			GuiManager.HoverStart(currentHoveredUnit)
		end
	end
end

-- Sürükleyerek çoklu ünite seçimini tamamlar
local function finishBoxSelection(input)
	selectionBox.Visible = false
	SelectionManager.ClearAll()
	for _, u in ipairs(getUnitsInBox(dragStart, input.Position)) do
		SelectionManager.SelectUnit(u)
	end
end

-- Tek bir üniteye tıklama veya boş yere tıklayıp hareket emri verme mantığı
local function handleSingleClickOrMove(isCtrl)
	local target = mouse.Target and mouse.Target:FindFirstAncestorOfClass("Model")

	-- Eğer oyuncu kendi ünitesine tıkladıysa seç/bırak
	if target and target:FindFirstChild("Owner") and target.Owner.Value == plr then
		if not isCtrl then
			SelectionManager.ClearAll()
		end
		SelectionManager.SelectUnit(target)

		-- Eğer boş bir yere tıklandıysa ve seçili ünite varsa hareket ettir
	elseif mouse.Hit and #SelectionManager.SelectedUnits > 0 then
		local ctrl = UIS:IsKeyDown(Enum.KeyCode.LeftControl) or UIS:IsKeyDown(Enum.KeyCode.RightControl)
		local pos = mouse.Hit.Position

		VisualManager.ClickEffect()

		local currentCenter = getCenterOfUnits(SelectionManager.SelectedUnits)

		for _, unit in ipairs(SelectionManager.SelectedUnits) do
			if unit.PrimaryPart and unit:FindFirstChild("Type") and unit.Type.Value == "UNIT" then
				local finalUnitTarget = pos

				if currentCenter then
					-- Birimin merkeze göre olan orijinal X ve Z farkını buluyoruz
					local offset = unit.PrimaryPart.Position - currentCenter
					if offset.Magnitude > 10 then
						offset = offset.Unit * 5 -- 5 birime düşür
					end
					local targetOffset = Vector3.new(offset.X, 0, offset.Z)

					-- Yeni Hedef = Tıklanan yer + Birimin orijinal ofseti
					finalUnitTarget = pos + targetOffset
				end

				if ctrl then
					VisualManager.AddWaypoint(unit, finalUnitTarget)
					moveEvent:FireServer(unit, { finalUnitTarget }, false)
				else
					VisualManager.ClearBeams(unit)
					VisualManager.AddWaypoint(unit, finalUnitTarget)
					moveEvent:FireServer(unit, { finalUnitTarget }, true)
				end
			end
		end
	end
end

-- Seçili tüm ünitelerin etkileşime (Q yeteneği/aksiyonu) geçmesini sağlar
local function handleUnitInteraction()
	for _, unit in ipairs(SelectionManager.SelectedUnits) do
		interactEvent:FireServer(unit)
	end
end

--Sağ Clickle Menüleri Aç
local function handleRightClick()
	local target = mouse.Target and mouse.Target:FindFirstAncestorOfClass("Model")

	if
		target
		and target:FindFirstChild("Owner")
		and target.Owner.Value == plr
		and target:FindFirstChild("Type")
		and target:FindFirstChild("Type").Value == "BUILDING"
	then
		local isOpen = GuiManager.IsSpawnGuiOpen(target)
		if isOpen then
			GuiManager.CloseSpawnGui(target)
		else
			GuiManager.OpenSpawnGui(target)
		end
	end
end

--- ==========================================
--- EVENT LISTENERS (BAĞLANTILAR)
--- ==========================================

-- Sunucudan gelen ünite silme talebi
removeSelectionEvent.OnClientEvent:Connect(function(unit)
	if not unit then
		return
	end
	local idx = table.find(SelectionManager.SelectedUnits, unit)
	if not idx then
		return
	end
	SelectionManager.DeselectUnit(unit)
end)

-- Girdi Başlangıcı (Tıklama veya Tuşa Basma)
UIS.InputBegan:Connect(function(input, gameProcessed)
	if gameProcessed then
		return
	end

	if input.KeyCode == Enum.KeyCode.E then
		SelectionManager.ClearAll()
		GuiManager.CloseAllSpawnGuis()
	elseif input.UserInputType == Enum.UserInputType.MouseButton1 then
		dragStart = input.Position
	end
end)

-- Girdi Değişimi (Fareyi Oynatma)
UIS.InputChanged:Connect(function(input)
	if input.UserInputType == Enum.UserInputType.MouseMovement then
		if dragStart then
			handleDragMovement(input)
		end
		handleUnitHover()
	end
end)

-- Girdi Bitişi (Tıklamayı Bırakma)
UIS.InputEnded:Connect(function(input, gameProcessed)
	if gameProcessed then
		return
	end

	if input.UserInputType == Enum.UserInputType.MouseButton1 then
		if isDragging then
			finishBoxSelection(input)
		else
			local isCtrlPressed = UIS:IsKeyDown(Enum.KeyCode.LeftControl) or UIS:IsKeyDown(Enum.KeyCode.RightControl)
			handleSingleClickOrMove(isCtrlPressed)
		end
		dragStart, isDragging = nil, false
	elseif input.KeyCode == Enum.KeyCode.Q then
		handleUnitInteraction()
	elseif input.UserInputType == Enum.UserInputType.MouseButton2 then
		handleRightClick()
	end
end)
