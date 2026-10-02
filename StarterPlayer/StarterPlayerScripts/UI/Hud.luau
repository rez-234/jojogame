--!strict
-- The always-on HUD: wallet and zone at the top left, vitals at the bottom
-- left (health, stamina, Stand durability, level and XP), the move hotbar
-- with cooldowns at the bottom, and a boss bar when a boss is close.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local StandData = require(ReplicatedStorage.Shared.StandData)
local Progression = require(ReplicatedStorage.Shared.Progression)
local Util = require(ReplicatedStorage.Shared.Util)
local Types = require(ReplicatedStorage.Shared.Types)
local Kit = require(script.Parent.Kit)
local State = require(script.Parent.Parent.Controllers.State)
local InputController = require(script.Parent.Parent.Controllers.InputController)
local AmbienceController = require(script.Parent.Parent.Controllers.AmbienceController)

local Hud = {}

local C = Kit.Colors
local S = Kit.Space
local player = Players.LocalPlayer

type Slot = {
	Frame: TextButton,
	Name: TextLabel,
	Tier: TextLabel,
	Shade: Frame,
	Timer: TextLabel,
	MoveId: string?,
}

local screen: ScreenGui
local cashLabel: TextLabel
local zoneLabel: TextLabel
local statusLabel: TextLabel
local levelLabel: TextLabel
local healthBar: Kit.Bar
local staminaBar: Kit.Bar
local standBar: Kit.Bar
local standRow: Frame
local xpBar: Kit.Bar
local slots: { Slot } = {}
local hotbar: Frame
local hint: TextLabel
local bossFrame: Frame
local bossName: TextLabel
local bossInfo: TextLabel
local bossBar: Kit.Bar

-- Top left: cash, zone and fight status.
local function buildWallet()
	local panel = Kit.Panel({
		Name = "Wallet",
		Position = UDim2.fromOffset(S.L, S.L),
		Size = UDim2.fromOffset(220, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		Parent = screen,
	})
	Kit.Padding(S.S, S.M).Parent = panel
	Kit.List(2).Parent = panel
	cashLabel = Kit.Label("$0", { FontFace = Kit.Fonts.Numbers, TextSize = Kit.Text.Title, Size = UDim2.new(1, 0, 0, 28), LayoutOrder = 1, Parent = panel })
	zoneLabel = Kit.Label("", { FontFace = Kit.Fonts.BodyBold, TextSize = Kit.Text.Body, LayoutOrder = 2, Parent = panel })
	statusLabel = Kit.Label("", { TextColor3 = C.InkSoft, TextSize = Kit.Text.Small, LayoutOrder = 3, Parent = panel })
end

-- Bottom left: name, level, health, stamina, Stand and XP.
local function buildVitals()
	local panel = Kit.Panel({
		Name = "Vitals",
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0, S.L, 1, -S.L),
		Size = UDim2.fromOffset(300, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		Parent = screen,
	})
	Kit.Padding(S.M).Parent = panel
	Kit.List(S.S).Parent = panel
	local header = Kit.new("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 24), LayoutOrder = 1, Parent = panel })
	Kit.Heading(player.DisplayName, 18, { Size = UDim2.new(0.65, 0, 1, 0), TextTruncate = Enum.TextTruncate.AtEnd, Parent = header })
	levelLabel = Kit.Label("Level 1", {
		Size = UDim2.new(0.35, 0, 1, 0),
		Position = UDim2.fromScale(0.65, 0),
		TextXAlignment = Enum.TextXAlignment.Right,
		FontFace = Kit.Fonts.Numbers,
		Parent = header,
	})
	healthBar = Kit.Bar(C.Health, 20, { LayoutOrder = 2, Parent = panel })
	staminaBar = Kit.Bar(C.Stamina, 14, { LayoutOrder = 3, Parent = panel })
	standRow = Kit.new("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 14), LayoutOrder = 4, Parent = panel })
	standBar = Kit.Bar(C.Leather, 14, { Parent = standRow })
	xpBar = Kit.Bar(C.XP, 10, { LayoutOrder = 5, Parent = panel })
	xpBar.Label.TextSize = 10
end

local KEYS = InputController.MoveKeys

local function buildHotbar()
	hotbar = Kit.new("Frame", {
		Name = "Hotbar",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -(S.L + 22)),
		Size = UDim2.fromOffset(5 * 104 + 4 * S.S, 62),
		Parent = screen,
	}, { Kit.List(S.S, true, Enum.HorizontalAlignment.Center) })
	for i = 1, 5 do
		local button = Kit.new("TextButton", {
			AutoButtonColor = false,
			Text = "",
			BackgroundColor3 = C.Leather,
			BorderSizePixel = 0,
			Size = UDim2.fromOffset(104, 62),
			LayoutOrder = i,
			ClipsDescendants = true,
			Parent = hotbar,
		}, { Kit.Corner(2), Kit.Stroke(C.Ink, 2) }) :: TextButton
		local shade = Kit.new("Frame", {
			BackgroundColor3 = C.LeatherDark,
			BorderSizePixel = 0,
			AnchorPoint = Vector2.new(0, 1),
			Position = UDim2.fromScale(0, 1),
			Size = UDim2.fromScale(1, 0),
			Parent = button,
		}) :: Frame
		Kit.Label(KEYS[i], {
			FontFace = Kit.Fonts.Numbers,
			TextColor3 = C.Brass,
			TextSize = 14,
			Position = UDim2.fromOffset(S.S, S.XS),
			Size = UDim2.fromOffset(20, 16),
			ZIndex = 2,
			Parent = button,
		})
		local tier = Kit.Label("", {
			TextColor3 = C.ParchmentDark,
			TextSize = 12,
			TextXAlignment = Enum.TextXAlignment.Right,
			Position = UDim2.new(0, 0, 0, S.XS),
			Size = UDim2.new(1, -S.S, 0, 16),
			ZIndex = 2,
			Parent = button,
		})
		local name = Kit.Label("", {
			FontFace = Kit.Fonts.BodyBold,
			TextColor3 = C.Parchment,
			TextSize = 14,
			TextWrapped = true,
			TextXAlignment = Enum.TextXAlignment.Center,
			TextYAlignment = Enum.TextYAlignment.Bottom,
			Position = UDim2.fromOffset(S.XS, 20),
			Size = UDim2.new(1, -S.S, 1, -24),
			ZIndex = 2,
			Parent = button,
		})
		local timer = Kit.Label("", {
			FontFace = Kit.Fonts.Numbers,
			TextColor3 = C.Paper,
			TextSize = 20,
			TextXAlignment = Enum.TextXAlignment.Center,
			Size = UDim2.fromScale(1, 1),
			ZIndex = 3,
			Parent = button,
		})
		button.Activated:Connect(function()
			InputController.UseMove(i)
		end)
		table.insert(slots, { Frame = button, Name = name, Tier = tier, Shade = shade, Timer = timer, MoveId = nil })
	end
	hint = Kit.Label("Click punch   Q Stand   F block   Ctrl dodge   E ride   H horse   M menu   P duels", {
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -S.S),
		Size = UDim2.fromOffset(640, 16),
		TextSize = 13,
		TextColor3 = C.Paper,
		TextXAlignment = Enum.TextXAlignment.Center,
		Parent = screen,
	})
	local stroke = Kit.Stroke(C.Ink, 1)
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual
	stroke.Parent = hint
	hint.Visible = not UserInputService.TouchEnabled
end

local function buildBossBar()
	bossFrame = Kit.Panel({
		Name = "Boss",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 92),
		Size = UDim2.fromOffset(460, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		Visible = false,
		Parent = screen,
	})
	Kit.Padding(S.S, S.M).Parent = bossFrame
	Kit.List(S.XS).Parent = bossFrame
	local header = Kit.new("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 24), LayoutOrder = 1, Parent = bossFrame })
	bossName = Kit.Heading("", 18, { Size = UDim2.fromScale(0.6, 1), Parent = header })
	bossInfo = Kit.Label("", { Size = UDim2.fromScale(0.4, 1), Position = UDim2.fromScale(0.6, 0), TextXAlignment = Enum.TextXAlignment.Right, TextColor3 = C.InkSoft, Parent = header })
	bossBar = Kit.Bar(C.Health, 16, { LayoutOrder = 2, Parent = bossFrame })
end

local function refreshProfile(profile: Types.Profile)
	cashLabel.Text = "$" .. Util.formatNumber(profile.Cash)
	levelLabel.Text = "Level " .. profile.Level
	local need = Progression.XPForLevel(profile.Level)
	xpBar.Set(profile.XP / math.max(1, need), Util.formatNumber(profile.XP) .. " / " .. Util.formatNumber(need) .. " XP")
	local stand = StandData.Get(profile.Stand)
	for i, slot in slots do
		local moveId = stand and stand.Moves[i]
		local move = moveId and StandData.GetMove(moveId)
		slot.MoveId = moveId
		if move and stand then
			slot.Name.Text = move.Name
			local xp = Progression.MasteryXP(profile, stand.Family, move.Id)
			local tier = Progression.MasteryTier(xp)
			slot.Tier.Text = if tier.Index > 1 then tier.Name else ""
			slot.Tier.TextColor3 = if tier.Name == "Perfected" then C.Brass else C.ParchmentDark
			slot.Frame.BackgroundColor3 = C.Leather
		else
			slot.Name.Text = if stand then "" else "No Stand"
			slot.Tier.Text = ""
			slot.Frame.BackgroundColor3 = C.LeatherDark
		end
	end
	standRow.Visible = stand ~= nil
	hotbar.Visible = true
end

local function nearestBoss(root: BasePart): Model?
	local folder = workspace:FindFirstChild("NPCs")
	if not folder then
		return nil
	end
	local best: Model? = nil
	local bestDist = 220
	for _, model in folder:GetChildren() do
		if model:IsA("Model") and model:GetAttribute("Boss") then
			local r = model:FindFirstChild("HumanoidRootPart") :: BasePart?
			if r then
				local d = (r.Position - root.Position).Magnitude
				if d < bestDist then
					best = model
					bestDist = d
				end
			end
		end
	end
	return best
end

local function step()
	local character, humanoid, root = State.Character()
	if humanoid then
		local maxHealth = math.max(1, humanoid.MaxHealth)
		healthBar.Set(humanoid.Health / maxHealth, string.format("%d / %d", math.ceil(math.max(0, humanoid.Health)), maxHealth))
	end
	if character then
		local stamina = tonumber(character:GetAttribute("Stamina")) or 0
		local staminaMax = math.max(1, tonumber(character:GetAttribute("StaminaMax")) or 100)
		staminaBar.Set(stamina / staminaMax, string.format("Stamina %d", stamina))
		local dur = tonumber(character:GetAttribute("StandDurability")) or 0
		local durMax = math.max(1, tonumber(character:GetAttribute("StandMaxDurability")) or 100)
		if character:GetAttribute("StandBroken") == true then
			standBar.Fill.BackgroundColor3 = C.Accent
			standBar.Set(dur / durMax, "Stand broken")
		elseif character:GetAttribute("Silenced") == true then
			standBar.Fill.BackgroundColor3 = C.InkSoft
			standBar.Set(dur / durMax, "Stand silenced")
		else
			standBar.Fill.BackgroundColor3 = C.LeatherLight
			standBar.Set(dur / durMax, string.format("Stand %d", dur))
		end
		local safe = character:GetAttribute("Safe") == true
		local pvp = character:GetAttribute("PvP") == true
		if safe then
			statusLabel.Text = "Safe in town"
			statusLabel.TextColor3 = C.Good
		elseif pvp then
			statusLabel.Text = "Duels on (P to turn off)"
			statusLabel.TextColor3 = C.Accent
		else
			statusLabel.Text = "Duels off (P to turn on)"
			statusLabel.TextColor3 = C.InkSoft
		end
		local zoneName = character:GetAttribute("Zone")
		if type(zoneName) == "string" and zoneName ~= "" then
			zoneLabel.Text = zoneName
		end
	end
	-- Cooldowns.
	for _, slot in slots do
		local moveId = slot.MoveId
		local left = if moveId then State.CooldownLeft(moveId) else 0
		local total = if moveId then State.CooldownLengths[moveId] or 1 else 1
		if left > 0 then
			slot.Shade.Size = UDim2.fromScale(1, math.clamp(left / total, 0, 1))
			slot.Timer.Text = if left >= 10 then string.format("%d", math.ceil(left)) else string.format("%.1f", left)
		else
			slot.Shade.Size = UDim2.fromScale(1, 0)
			slot.Timer.Text = ""
		end
	end
	-- Boss bar.
	local boss = if root then nearestBoss(root) else nil
	if boss then
		local h = boss:FindFirstChildOfClass("Humanoid")
		bossFrame.Visible = h ~= nil and h.Health > 0
		if h then
			local bn = boss:GetAttribute("BossName")
			bossName.Text = if type(bn) == "string" then bn else boss.Name
			local phase = boss:GetAttribute("Phase")
			local standName = boss:GetAttribute("BossStand")
			bossInfo.Text = string.format("%sPhase %s", if type(standName) == "string" then standName .. ", " else "", tostring(phase or 1))
			bossBar.Set(h.Health / math.max(1, h.MaxHealth), string.format("%d / %d", math.ceil(h.Health), h.MaxHealth))
		end
	else
		bossFrame.Visible = false
	end
end

function Hud.Init()
	screen = Kit.Screen("SBR_Hud", 1)
	buildWallet()
	buildVitals()
	buildHotbar()
	buildBossBar()
	State.ProfileChanged:Connect(refreshProfile)
	if State.Profile then
		refreshProfile(State.Profile)
	end
	-- Zone names come from the local classifier until the server confirms.
	task.spawn(function()
		while true do
			task.wait(1)
			local character = State.Character()
			if character and character:GetAttribute("Zone") == nil then
				zoneLabel.Text = AmbienceController.ZoneKind
			end
		end
	end)
	RunService.RenderStepped:Connect(step)
end

-- Hides gameplay HUD pieces while a full screen menu is open on small screens.
function Hud.SetVisible(visible: boolean)
	if screen then
		screen.Enabled = visible
	end
end

return Hud
