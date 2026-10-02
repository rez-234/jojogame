--!strict
-- Skins tab: a turning preview of your Stand in the chosen skin, and every
-- skin for its family with where it comes from, buy and equip buttons.

local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local StandData = require(ReplicatedStorage.Shared.StandData)
local SkinData = require(ReplicatedStorage.Shared.SkinData)
local Util = require(ReplicatedStorage.Shared.Util)
local StandBuilder = require(ReplicatedStorage.Builders.StandBuilder)
local Kit = require(script.Parent.Parent.Kit)
local State = require(script.Parent.Parent.Parent.Controllers.State)

local Skins = {}
Skins.Name = "Skins"

local C = Kit.Colors
local S = Kit.Space

local previewId: string? = nil

local function owns(profile: any, skin: SkinData.Skin): boolean
	return skin.Source.Kind == "Default" or profile.Skins.Owned[skin.Id] == true
end

local function buildPreview(parent: Instance, standId: string, skin: SkinData.Skin?)
	local viewport = Kit.new("ViewportFrame", {
		BackgroundColor3 = C.ParchmentDark,
		BorderSizePixel = 0,
		Size = UDim2.new(0.5, -S.S, 1, 0),
		Ambient = Color3.fromRGB(170, 160, 150),
		LightColor = Color3.fromRGB(255, 244, 228),
		LightDirection = Vector3.new(-1, -1, -1),
		Parent = parent,
	}, { Kit.Corner(2) }) :: ViewportFrame
	local world = Instance.new("WorldModel")
	world.Parent = viewport
	local ok, model = pcall(StandBuilder.Build, standId, { Skin = skin })
	if not ok or not model then
		return
	end
	local stand = model :: Model
	stand:PivotTo(CFrame.new())
	stand.Parent = world
	local _, size = stand:GetBoundingBox()
	local radius = math.max(size.X, size.Y, size.Z)
	local cam = Instance.new("Camera")
	cam.FieldOfView = 40
	cam.CFrame = CFrame.lookAt(Vector3.new(0, size.Y * 0.1, radius * 1.9), Vector3.new(0, 0, 0))
	cam.Parent = viewport
	viewport.CurrentCamera = cam
	local angle = math.pi
	local conn: RBXScriptConnection
	conn = RunService.RenderStepped:Connect(function(dt: number)
		if not viewport.Parent then
			conn:Disconnect()
			return
		end
		angle += dt * 0.6
		stand:PivotTo(CFrame.Angles(0, angle, 0) * CFrame.new(0, math.sin(os.clock() * 2) * 0.15, 0))
	end)
end

function Skins.Render(page: ScrollingFrame, ctx: any)
	local profile = State.Profile
	if not profile then
		Kit.Paragraph("Loading...", { Parent = page })
		return
	end
	local stand = StandData.Get(profile.Stand)
	if not stand then
		Kit.Paragraph("Awaken a Stand first. Skins belong to a Stand family and stay with it through evolution.", { Parent = page })
		return
	end
	local list = SkinData.ForFamily(stand.Family)
	local equippedId = profile.Skins.Equipped[stand.Family] or (SkinData.DefaultFor(stand.Family) and (SkinData.DefaultFor(stand.Family) :: SkinData.Skin).Id)
	local selected = if previewId and SkinData.Skins[previewId] and SkinData.Skins[previewId].Family == stand.Family then previewId else equippedId
	local selectedSkin = if selected then SkinData.Skins[selected] else nil

	local top = Kit.new("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 260), LayoutOrder = 1, Parent = page })
	buildPreview(top, stand.Id, selectedSkin)
	local info = Kit.new("Frame", {
		BackgroundTransparency = 1,
		Position = UDim2.new(0.5, S.S, 0, 0),
		Size = UDim2.new(0.5, -S.S, 1, 0),
		Parent = top,
	}, { Kit.List(S.S) })
	Kit.Heading(if selectedSkin then selectedSkin.Name else "Classic", Kit.Text.Title, { LayoutOrder = 1, Parent = info })
	Kit.Label(stand.Name, { LayoutOrder = 2, TextColor3 = C.InkSoft, Parent = info })
	if selectedSkin then
		Kit.Paragraph("How to get it: " .. selectedSkin.Source.Text, { LayoutOrder = 3, Parent = info })
		if selected == equippedId then
			Kit.Label("Equipped", { LayoutOrder = 4, FontFace = Kit.Fonts.BodyBold, TextColor3 = C.Good, Parent = info })
		elseif owns(profile, selectedSkin) then
			Kit.Button("Equip", "Primary", function()
				ctx.Do("EquipSkin", "Skin equipped.", selectedSkin.Id)
			end, { LayoutOrder = 4, Parent = info })
		elseif selectedSkin.Source.Kind == "Shop" and selectedSkin.Source.Price then
			local price = selectedSkin.Source.Price :: number
			local buy = Kit.Button("Buy $" .. Util.formatNumber(price), "Primary", function()
				ctx.Do("BuySkin", "Skin bought.", selectedSkin.Id)
			end, { LayoutOrder = 4, Size = UDim2.fromOffset(160, 34), Parent = info })
			buy.SetEnabled(profile.Cash >= price)
		else
			Kit.Label("Not unlocked yet", { LayoutOrder = 4, TextColor3 = C.InkSoft, Parent = info })
		end
	end

	local section = Kit.Section({ LayoutOrder = 2, Parent = page })
	Kit.Heading("All skins for " .. stand.Name, Kit.Text.Label, { LayoutOrder = 0, Parent = section })
	for i, skin in list do
		local row = Kit.new("Frame", {
			BackgroundColor3 = if skin.Id == selected then C.ParchmentDark else C.Parchment,
			BorderSizePixel = 0,
			Size = UDim2.new(1, 0, 0, 40),
			LayoutOrder = i,
			Parent = section,
		}, { Kit.Corner(2), Kit.Padding(0, S.M) })
		-- A flat swatch of the skin's main color.
		Kit.new("Frame", {
			AnchorPoint = Vector2.new(0, 0.5),
			BackgroundColor3 = skin.Body or stand.Look.Body,
			BorderSizePixel = 0,
			Position = UDim2.fromScale(0, 0.5),
			Size = UDim2.fromOffset(18, 18),
			Parent = row,
		}, { Kit.Corner(2) })
		Kit.Label(skin.Name, { FontFace = Kit.Fonts.BodyBold, Position = UDim2.fromOffset(28, 0), Size = UDim2.new(0.4, -28, 1, 0), Parent = row })
		local status = if skin.Id == equippedId then "Equipped" elseif owns(profile, skin) then "Owned" else skin.Source.Text
		Kit.Label(status, { TextSize = 14, TextColor3 = if owns(profile, skin) then C.Good else C.InkSoft, Position = UDim2.fromScale(0.4, 0), Size = UDim2.new(0.6, -100, 1, 0), TextTruncate = Enum.TextTruncate.AtEnd, Parent = row })
		Kit.Button("Preview", "Ghost", function()
			previewId = skin.Id
			ctx.Rerender()
		end, { AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, 0, 0.5, 0), Size = UDim2.fromOffset(90, 28), Parent = row })
	end
end

return Skins
