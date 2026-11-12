--!strict
-- Quaesitor replay, client side.
-- Ghosts move through the world on the viewer's screen only: everything here is created
-- or copied by this client and never replicates. A bar at the top of the screen plays,
-- pauses and scrubs the case, and the camera can follow any of the ghosts.
-- Ghosts start as simple markers; the server then builds the avatars (body, clothes,
-- accessories, tools) and hands them to this client alone, and they replace the markers.
-- While the replay runs, the server streams the map around what the camera watches.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Theme = require(script.Parent.Theme)
local Components = require(script.Parent.Components)

local C = Theme.colors
local P = Theme.fonts
local create = Components.create

local GAP = 2.5 -- seconds without a sample: the player was gone or had no character
local EDGE = 0.6 -- a ghost stays this long before its first and after its last sample
local EVENT_SHOWN = 6 -- seconds an event stays in the bar
local MAX_DOTS = 400 -- path markers per ghost
local SKIP = 10 -- seconds for the back / forward buttons
local FOCUS_EVERY = 1 -- seconds between two streaming requests
local FOCUS_MOVE = 24 -- studs the camera moves before the map is streamed again
local AVATAR_WAIT = 15 -- seconds to wait for the avatars built by the server
local OTHERS_DISTANCE = 250 -- studs beyond which the names of other players are hidden

-- Sample fields (see Quaesitor on the server).
local T, X, Y, Z, YAW, HEALTH, FLAGS, TOOL, OUTFIT = 1, 2, 3, 4, 5, 6, 7, 8, 9
local DEAD, SEATED, AIRBORNE = 1, 2, 4

-- Offsets of the markers from the root part of a character.
local BODY = CFrame.new(0, -0.7, 0)
local HEAD = CFrame.new(0, 2.1, 0)
local FRONT = CFrame.new(0, 2.1, -0.75)
local FEET = Vector3.new(0, -2.8, 0)
local LYING = CFrame.new(0, -2, 0) * CFrame.Angles(-math.pi / 2, 0, 0)

-- Default Roblox animations, played on the avatars.
local ANIMATIONS = {
	R15 = { walk = "rbxassetid://507777826", idle = "rbxassetid://507766388" },
	R6 = { walk = "rbxassetid://180426354", idle = "rbxassetid://180435571" },
}
local WALK_SPEED = 16 -- studs per second of the walk animation at normal speed

local ROLES: { [string]: { label: string, color: Color3 } } = {
	reporter = { label = "Reporter", color = C.info },
	reported = { label = "Reported", color = C.danger },
	suspect = { label = "Suspect", color = C.danger },
	nearby = { label = "Nearby", color = C.textMuted },
	other = { label = "On server", color = C.textMuted },
}

local EVENT_COLORS: { [string]: Color3 } = {
	lictor = C.danger,
	death = C.warning,
	staff = C.accent,
	left = C.textFaint,
	trigger = C.info,
}

type Ghost = {
	track: any,
	color: Color3,
	involved: boolean,
	model: Model, -- markers, then the avatar
	subject: Instance, -- what the camera follows
	-- Markers
	markers: { BasePart }?,
	-- Avatar
	root: BasePart?,
	accessories: { [number]: { Instance } }, -- index in track.accessories -> parts and decals
	tools: { [number]: Model }, -- index in track.tools -> held model
	animations: { [string]: AnimationTrack },
	playing: string?,
	outfit: number?,
	tool: number?,
	-- Shared
	billboard: BillboardGui,
	status: TextLabel,
	visible: boolean,
}

local Replay = {}

local running: { stop: () -> () }? = nil

local function minutes(seconds: number): string
	local s = math.max(0, math.floor(seconds))
	return string.format("%d:%02d", s // 60, s % 60)
end

local function isFlag(flags: number, flag: number): boolean
	return (flags // flag) % 2 == 1
end

local function ghostPart(name: string, size: Vector3, color: Color3, parent: Instance): Part
	return create("Part", {
		Name = name,
		Size = size,
		Color = color,
		Material = Enum.Material.SmoothPlastic,
		Transparency = 0.35,
		Anchored = true,
		CanCollide = false,
		CanQuery = false,
		CanTouch = false,
		CastShadow = false,
		Parent = parent,
	})
end

local function buildGhost(folder: Instance, track: any): Ghost
	local role = ROLES[track.role]
	local color = if role then role.color else C.warning
	local involved = track.role ~= "nearby" and track.role ~= "other"
	local model = create("Model", { Name = track.name, Parent = folder }) :: Model
	local body = ghostPart("Body", Vector3.new(2, 4.4, 1), color, model)
	local head = ghostPart("Head", Vector3.new(1.3, 1.3, 1.3), color, model)
	head.Shape = Enum.PartType.Ball
	local front = ghostPart("Front", Vector3.new(0.5, 0.3, 0.5), C.text, model)
	model.PrimaryPart = body

	-- The players involved are seen through walls: the point is to find them.
	-- (A client shows at most 31 highlights: the others go without.)
	if involved then
		create("Highlight", {
			FillColor = color,
			OutlineColor = color,
			FillTransparency = 0.75,
			OutlineTransparency = 0.1,
			DepthMode = Enum.HighlightDepthMode.AlwaysOnTop,
			Adornee = model,
			Parent = model,
		})
	end

	local billboard = create("BillboardGui", {
		Size = UDim2.fromOffset(200, 44),
		StudsOffset = Vector3.new(0, 2, 0),
		AlwaysOnTop = involved,
		MaxDistance = if involved then math.huge else OTHERS_DISTANCE,
		LightInfluence = 0,
		Adornee = head,
		Parent = model,
	}, {
		Components.stack("V", 0, Enum.HorizontalAlignment.Center),
	}) :: BillboardGui
	Components.text({
		Text = `{track.name}{if role then `  ·  {role.label}` else ""}`,
		FontFace = P.bold,
		TextSize = if involved then 14 else 12,
		TextColor3 = if involved then color else C.text,
		TextStrokeTransparency = 0.4,
		TextXAlignment = Enum.TextXAlignment.Center,
		TextWrapped = false,
		Size = UDim2.new(1, 0, 0, 20),
		LayoutOrder = 1,
		Parent = billboard,
	})
	local status = Components.text({
		Text = "",
		TextSize = 12,
		TextColor3 = C.text,
		TextStrokeTransparency = 0.4,
		TextXAlignment = Enum.TextXAlignment.Center,
		TextWrapped = false,
		Size = UDim2.new(1, 0, 0, 18),
		LayoutOrder = 2,
		Parent = billboard,
	})

	return {
		track = track,
		color = color,
		involved = involved,
		model = model,
		subject = body,
		markers = { body, head, front },
		accessories = {},
		tools = {},
		animations = {},
		billboard = billboard,
		status = status,
		visible = true,
	}
end

-- Avatars ------------------------------------------------------------------------------

local function playAnimation(ghost: Ghost, name: string?, rate: number)
	if ghost.playing ~= name then
		if ghost.playing and ghost.animations[ghost.playing] then
			ghost.animations[ghost.playing]:Stop(0.15)
		end
		ghost.playing = name
		if name and ghost.animations[name] then
			ghost.animations[name]:Play(0.15)
		end
	end
	if name and ghost.animations[name] then
		ghost.animations[name]:AdjustSpeed(rate)
	end
end

-- Puts a copy of the avatar built by the server in place of the markers.
local function useAvatar(ghost: Ghost, source: Model, folder: Instance)
	local avatar = source:Clone()
	avatar.Name = ghost.track.name
	local humanoid = avatar:FindFirstChildOfClass("Humanoid")
	local root = avatar:FindFirstChild("HumanoidRootPart") or avatar.PrimaryPart
	if not humanoid or not root or not root:IsA("BasePart") then
		avatar:Destroy()
		return
	end
	humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
	humanoid.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOff
	humanoid.EvaluateStateMachine = false
	for _, part in avatar:GetDescendants() do
		if part:IsA("BasePart") then
			part.Anchored = false
			part.CanCollide = false
			part.CanQuery = false
			part.CanTouch = false
		end
	end
	root.Anchored = true
	root.Transparency = 1
	avatar.PrimaryPart = root

	-- Accessories, so they can be shown or hidden as they were worn.
	local accessories = {}
	for i, name in ghost.track.accessories or {} do
		local parts = {}
		for _, child in avatar:GetChildren() do
			if child:IsA("Accessory") and child.Name == name then
				for _, descendant in child:GetDescendants() do
					if descendant:IsA("BasePart") or descendant:IsA("Decal") then
						table.insert(parts, descendant)
					end
				end
			end
		end
		accessories[i] = parts
	end

	-- Tools, welded in the right hand and shown while they were held.
	local tools = {}
	local hand = avatar:FindFirstChild("RightHand") or avatar:FindFirstChild("Right Arm")
	local toolFolder = avatar:FindFirstChild("QuaesitorTools")
	if toolFolder and hand and hand:IsA("BasePart") then
		local gripAttachment = hand:FindFirstChild("RightGripAttachment")
		local c0 = if gripAttachment and gripAttachment:IsA("Attachment")
			then gripAttachment.CFrame
			else CFrame.new(0, -1, 0) * CFrame.Angles(-math.pi / 2, 0, 0)
		for i, name in ghost.track.tools or {} do
			local tool = toolFolder:FindFirstChild(name)
			local handle = tool and tool:FindFirstChild("Handle")
			if tool and tool:IsA("Model") and handle and handle:IsA("BasePart") then
				local grip = tool:GetAttribute("Grip")
				create("Weld", {
					Part0 = hand,
					Part1 = handle,
					C0 = c0,
					C1 = if typeof(grip) == "CFrame" then grip else CFrame.identity,
					Parent = handle,
				})
				tool.Parent = nil
				tools[i] = tool
			end
		end
	end
	if toolFolder then
		toolFolder:Destroy()
	end

	-- Name, role and state above the head; seen through walls for the players involved.
	if ghost.involved then
		create("Highlight", {
			FillColor = ghost.color,
			OutlineColor = ghost.color,
			FillTransparency = 0.85,
			OutlineTransparency = 0.1,
			DepthMode = Enum.HighlightDepthMode.AlwaysOnTop,
			Adornee = avatar,
			Parent = avatar,
		})
	end
	ghost.billboard.Adornee = avatar:FindFirstChild("Head") or root
	ghost.billboard.StudsOffset = Vector3.new(0, 2.6, 0)
	ghost.billboard.Parent = avatar

	local animator = humanoid:FindFirstChildOfClass("Animator") or create("Animator", { Parent = humanoid })
	local ids = ANIMATIONS[humanoid.RigType.Name] or ANIMATIONS.R15
	for name, id in ids do
		local ok, track = pcall(function()
			return (animator :: Animator):LoadAnimation(create("Animation", { AnimationId = id }))
		end)
		if ok and track then
			track.Looped = true
			ghost.animations[name] = track
		end
	end

	local old = ghost.model
	ghost.model = avatar
	ghost.subject = humanoid
	ghost.root = root
	ghost.markers = nil
	ghost.accessories = accessories
	ghost.tools = tools
	ghost.outfit = nil
	ghost.tool = nil
	ghost.playing = nil
	avatar.Parent = if ghost.visible then folder else nil
	old:Destroy()
end

local function setOutfit(ghost: Ghost, outfit: number?)
	if outfit == ghost.outfit then
		return
	end
	ghost.outfit = outfit
	local worn = if outfit then ghost.track.outfits[outfit] else nil
	if not worn then
		return
	end
	for i, parts in ghost.accessories do
		local hidden = if table.find(worn, i) then 0 else 1
		for _, part in parts do
			(part :: any).LocalTransparencyModifier = hidden
		end
	end
end

local function setTool(ghost: Ghost, tool: number?)
	local index = if tool and tool > 0 then tool else nil
	if index == ghost.tool then
		return
	end
	if ghost.tool and ghost.tools[ghost.tool] then
		ghost.tools[ghost.tool].Parent = nil
	end
	ghost.tool = index
	if index and ghost.tools[index] then
		ghost.tools[index].Parent = ghost.model
	end
end

-- Paths and poses --------------------------------------------------------------------

-- Small markers along the whole path, so the route reads at a glance.
local function drawPath(folder: Instance, ghost: Ghost)
	local samples = ghost.track.samples
	local step = math.max(1, math.ceil(#samples / MAX_DOTS))
	for i = 1, #samples, step do
		local s = samples[i]
		local dot = ghostPart("Dot", Vector3.new(0.4, 0.4, 0.4), ghost.color, folder)
		dot.Shape = Enum.PartType.Ball
		dot.Transparency = 0.45
		dot.Position = Vector3.new(s[X], s[Y], s[Z]) + FEET
	end
end

-- Index of the last sample at or before t, by bisection.
local function before(samples: { any }, t: number): number
	local low, high = 1, #samples
	if high == 0 or samples[1][T] > t then
		return 0
	end
	while low < high do
		local middle = (low + high + 1) // 2
		if samples[middle][T] <= t then
			low = middle
		else
			high = middle - 1
		end
	end
	return low
end

local function cframeOf(position: Vector3, yaw: number): CFrame
	return CFrame.new(position) * CFrame.Angles(0, math.rad(yaw), 0)
end

-- Where the ghost is at time t, the closest sample and its horizontal speed.
-- Nil when it was not there.
local function poseAt(samples: { any }, t: number, gap: number): (CFrame?, any, number)
	local count = #samples
	if count == 0 then
		return nil, nil, 0
	end
	local i = before(samples, t)
	if i == 0 then
		local first = samples[1]
		if first[T] - t > EDGE then
			return nil, nil, 0
		end
		return cframeOf(Vector3.new(first[X], first[Y], first[Z]), first[YAW]), first, 0
	end
	local a = samples[i]
	local b = samples[i + 1]
	if not b or b[T] - a[T] > gap then
		if t - a[T] > EDGE then
			return nil, nil, 0
		end
		return cframeOf(Vector3.new(a[X], a[Y], a[Z]), a[YAW]), a, 0
	end
	local span = math.max(b[T] - a[T], 0.01)
	local alpha = math.clamp((t - a[T]) / span, 0, 1)
	local from = Vector3.new(a[X], a[Y], a[Z])
	local to = Vector3.new(b[X], b[Y], b[Z])
	local speed = Vector3.new(to.X - from.X, 0, to.Z - from.Z).Magnitude / span
	-- Shortest turn between the two headings.
	local turn = ((b[YAW] - a[YAW] + 180) % 360) - 180
	return cframeOf(from:Lerp(to, alpha), a[YAW] + turn * alpha), if alpha < 0.5 then a else b, speed
end

local function statusOf(ghost: Ghost, sample: any): string
	local parts = { `{sample[HEALTH]} HP` }
	local flags = sample[FLAGS]
	if isFlag(flags, DEAD) then
		parts = { "Dead" }
	elseif isFlag(flags, SEATED) then
		table.insert(parts, "seated")
	elseif isFlag(flags, AIRBORNE) then
		table.insert(parts, "in the air")
	end
	local tool = sample[TOOL]
	if tool and tool > 0 and ghost.track.tools and ghost.track.tools[tool] then
		table.insert(parts, ghost.track.tools[tool])
	end
	return table.concat(parts, "  ·  ")
end

function Replay.isRunning(): boolean
	return running ~= nil
end

function Replay.stop()
	if running then
		running.stop()
	end
end

-- Plays a case. onStop runs once the replay is closed, by the bar or by Replay.stop.
-- request sends a Consul action (avatars and streaming).
function Replay.start(screen: ScreenGui, case: any, onStop: () -> (), request: (string, any?) -> any)
	Replay.stop()

	local camera = workspace.CurrentCamera
	local duration = math.max(case.duration, 1)
	local gap = math.max(GAP, (case.interval or 1) * 2.5)
	local time = 0
	local playing = true
	local speed = 1
	local showPath = true
	local showOthers = true
	local watched: Ghost? = nil
	local connections: { RBXScriptConnection } = {}
	local stopped = false

	-- Created by this client, so nobody else sees it.
	local folder = create("Folder", { Name = "ImperiumQuaesitorReplay", Parent = workspace })
	local pathFolder = create("Folder", { Name = "Paths", Parent = folder })
	local ghosts: { Ghost } = {}
	local involved: { Ghost } = {}
	local others: { Ghost } = {}
	for _, track in case.tracks do
		local ghost = buildGhost(folder, track)
		table.insert(ghosts, ghost)
		if ghost.involved then
			drawPath(pathFolder, ghost)
			table.insert(involved, ghost)
		else
			table.insert(others, ghost)
		end
	end

	-- Bar --------------------------------------------------------------------------------

	local bar = create("Frame", {
		Name = "QuaesitorReplay",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 64),
		Size = UDim2.new(0.94, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundColor3 = C.panel,
		ZIndex = 30,
		Parent = screen,
	}, {
		create("UISizeConstraint", { MaxSize = Vector2.new(760, math.huge) }),
		Components.corners(),
		Components.stroke(C.border),
		Components.padding(10, 14),
		Components.stack("V", 8),
	})

	local function row(order: number, height: number): Frame
		return create("Frame", {
			BackgroundTransparency = 1,
			Size = UDim2.new(1, 0, 0, height),
			-- Buttons wrap on a narrow screen.
			AutomaticSize = Enum.AutomaticSize.Y,
			LayoutOrder = order,
			ZIndex = 31,
			Parent = bar,
		})
	end

	-- Title
	local titleRow = row(1, 20)
	Components.text({
		Text = `CASE #{case.id}  ·  {case.label}`,
		FontFace = P.bold,
		TextColor3 = C.accent,
		TextTruncate = Enum.TextTruncate.AtEnd,
		TextWrapped = false,
		Size = UDim2.new(1, -230, 1, 0),
		ZIndex = 31,
		Parent = titleRow,
	})
	local noticeLabel = Components.text({
		Text = "Only you can see this replay",
		TextSize = 12,
		TextColor3 = C.textFaint,
		TextXAlignment = Enum.TextXAlignment.Right,
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.fromScale(1, 0),
		Size = UDim2.new(0, 230, 1, 0),
		ZIndex = 31,
		Parent = titleRow,
	})

	-- Controls
	local controls = row(2, 30)
	local layout = Components.stack("H", 6)
	layout.VerticalAlignment = Enum.VerticalAlignment.Center
	layout.Wraps = true
	layout.Parent = controls

	local function control(label: string, style: string, onClick: () -> (), order: number): TextButton
		return Components.button(label, style :: any, onClick, {
			Size = UDim2.new(0, 0, 0, 28),
			LayoutOrder = order,
			ZIndex = 31,
			Parent = controls,
		})
	end

	local playButton: TextButton
	local function refreshPlay()
		playButton.Text = Components.uppercase(if playing then "Pause" else "Play")
	end
	playButton = control("Pause", "primary", function()
		if not playing and time >= duration then
			time = 0
		end
		playing = not playing
		refreshPlay()
	end, 1)
	control(`-{SKIP}s`, "ghost", function()
		time = math.max(0, time - SKIP)
	end, 2)
	control(`+{SKIP}s`, "ghost", function()
		time = math.min(duration, time + SKIP)
	end, 3)
	if case.triggerAt then
		control("Go to trigger", "ghost", function()
			time = math.clamp(case.triggerAt - 5, 0, duration)
		end, 4)
	end
	local speeds = Components.selector({
		{ value = "1", label = "1x" },
		{ value = "2", label = "2x" },
		{ value = "4", label = "4x" },
	}, "1", function(value)
		speed = tonumber(value) or 1
	end)
	speeds.Size = UDim2.new(0, 0, 0, 30)
	speeds.LayoutOrder = 5
	speeds.Parent = controls
	local pathButton: TextButton
	pathButton = control("Hide path", "ghost", function()
		showPath = not showPath
		pathFolder.Parent = if showPath then folder else nil
		pathButton.Text = Components.uppercase(if showPath then "Hide path" else "Show path")
	end, 6)
	if #others > 0 then
		local othersButton: TextButton
		othersButton = control(`Hide others ({#others})`, "ghost", function()
			showOthers = not showOthers
			othersButton.Text =
				Components.uppercase(if showOthers then `Hide others ({#others})` else `Show others ({#others})`)
		end, 7)
	end
	control("Stop replay", "danger", function()
		Replay.stop()
	end, 8)

	-- Timeline: events as ticks, a fill for the time played, drag to scrub.
	local timeline = row(3, 22)
	local track = create("Frame", {
		BackgroundColor3 = C.border,
		BorderSizePixel = 0,
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.fromScale(0, 0.5),
		Size = UDim2.new(1, 0, 0, 6),
		ZIndex = 31,
		Parent = timeline,
	}, { Components.corners(Theme.radiusSmall) })
	local fill = create("Frame", {
		BackgroundColor3 = C.accent,
		BorderSizePixel = 0,
		Size = UDim2.fromScale(0, 1),
		ZIndex = 32,
		Parent = track,
	}, { Components.corners(Theme.radiusSmall) })
	for _, event in case.events do
		create("Frame", {
			BackgroundColor3 = EVENT_COLORS[event.kind] or C.text,
			BorderSizePixel = 0,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.new(math.clamp(event.t / duration, 0, 1), 0, 0.5, 0),
			-- The report or alert stands out from the other events.
			Size = if event.kind == "trigger" then UDim2.fromOffset(5, 24) else UDim2.fromOffset(3, 18),
			ZIndex = 33,
			Parent = timeline,
		})
	end
	local knob = create("Frame", {
		BackgroundColor3 = C.text,
		BorderSizePixel = 0,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0, 0.5),
		Size = UDim2.fromOffset(10, 20),
		ZIndex = 34,
		Parent = timeline,
	}, { Components.corners(Theme.radiusSmall) })
	local scrubArea = create("TextButton", {
		Text = "",
		BackgroundTransparency = 1,
		AutoButtonColor = false,
		Size = UDim2.fromScale(1, 1),
		ZIndex = 35,
		Parent = timeline,
	})

	-- Clock and the event of the moment
	local infoRow = row(4, 18)
	local clockLabel = Components.text({
		Text = "",
		TextSize = 12,
		TextColor3 = C.textMuted,
		FontFace = P.code,
		TextWrapped = false,
		Size = UDim2.new(0, 220, 1, 0),
		ZIndex = 31,
		Parent = infoRow,
	})
	local eventLabel = Components.text({
		Text = "",
		TextSize = 12,
		TextXAlignment = Enum.TextXAlignment.Right,
		TextTruncate = Enum.TextTruncate.AtEnd,
		TextWrapped = false,
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.fromScale(1, 0),
		Size = UDim2.new(1, -230, 1, 0),
		ZIndex = 31,
		Parent = infoRow,
	})

	-- Camera: free, following one of the players involved, or cycling through the others.
	local cameraRow = row(5, 30)
	local cameraSelector: Frame? = nil
	local otherIndex = 0

	local function watch(ghost: Ghost?)
		watched = ghost
		if ghost then
			camera.CameraSubject = ghost.subject
		else
			local character = Players.LocalPlayer.Character
			local humanoid = character and character:FindFirstChildOfClass("Humanoid")
			camera.CameraSubject = humanoid
		end
	end

	local drawCameraSelector: (string) -> ()
	drawCameraSelector = function(selected: string)
		if cameraSelector then
			cameraSelector:Destroy()
		end
		local options = { { value = "free", label = "My camera" } }
		for i, ghost in involved do
			table.insert(options, { value = tostring(i), label = `Follow {ghost.track.name}` })
		end
		if #others > 0 then
			local current = others[otherIndex]
			table.insert(options, {
				value = "other",
				label = if current and selected == "other" then `{current.track.name} (next)` else "Follow others",
			})
		end
		local selector = Components.selector(options, selected, function(value)
			if value == "free" then
				watch(nil)
			elseif value == "other" then
				otherIndex = otherIndex % #others + 1
				watch(others[otherIndex])
				drawCameraSelector("other")
			else
				watch(involved[tonumber(value) :: number])
			end
		end)
		selector.Size = UDim2.new(0, 0, 0, 30)
		selector.Parent = cameraRow
		cameraSelector = selector
	end

	-- Starts on the player the case is about.
	local first: number? = nil
	for i, ghost in involved do
		if ghost.track.role ~= "reporter" then
			first = i
			break
		end
	end
	first = first or (if involved[1] then 1 else nil)
	drawCameraSelector(if first then tostring(first) else "free")
	watch(if first then involved[first] else nil)

	-- Rendering --------------------------------------------------------------------------

	local function setVisible(ghost: Ghost, visible: boolean)
		if ghost.visible == visible then
			return
		end
		ghost.visible = visible
		ghost.model.Parent = if visible then folder else nil
	end

	local function render()
		for _, ghost in ghosts do
			local cf, sample, moving = poseAt(ghost.track.samples, time, gap)
			if not cf or not sample or (not ghost.involved and not showOthers) then
				setVisible(ghost, false)
				continue
			end
			setVisible(ghost, true)
			local dead = isFlag(sample[FLAGS], DEAD)
			ghost.status.Text = statusOf(ghost, sample)
			if ghost.markers then
				local markers = ghost.markers
				markers[1].CFrame = cf * BODY
				markers[2].CFrame = cf * HEAD
				markers[3].CFrame = cf * FRONT
				local color = if dead then C.textFaint else ghost.color
				markers[1].Color = color
				markers[2].Color = color
			elseif ghost.root then
				ghost.root.CFrame = if dead then cf * LYING else cf
				setOutfit(ghost, sample[OUTFIT])
				setTool(ghost, sample[TOOL])
				local rate = if playing then speed else 0
				if dead or isFlag(sample[FLAGS], SEATED) then
					playAnimation(ghost, nil, 0)
				elseif moving > 2 then
					playAnimation(ghost, "walk", rate * moving / WALK_SPEED)
				else
					playAnimation(ghost, "idle", rate)
				end
			end
		end

		local alpha = math.clamp(time / duration, 0, 1)
		fill.Size = UDim2.fromScale(alpha, 1)
		knob.Position = UDim2.fromScale(alpha, 0.5)
		local wall = os.date("%H:%M:%S", math.floor(case.startedAt + time)) :: string
		clockLabel.Text = `{minutes(time)} / {minutes(duration)}  ·  {wall}`

		local shown = nil
		for _, event in case.events do
			if event.t <= time and time - event.t <= EVENT_SHOWN then
				shown = event
			end
		end
		eventLabel.Text = if shown then shown.text else ""
		eventLabel.TextColor3 = if shown then EVENT_COLORS[shown.kind] or C.text else C.text
	end

	-- Streaming: the server loads the map around what the camera watches.
	local lastFocus: Vector3? = nil
	local focusClock = 0
	local focusBusy = false
	local function streamAround()
		if focusBusy or os.clock() - focusClock < FOCUS_EVERY then
			return
		end
		local position = camera.Focus.Position
		if watched and watched.visible then
			local pivot = watched.model:GetPivot()
			position = pivot.Position
		end
		if lastFocus and (position - lastFocus).Magnitude < FOCUS_MOVE then
			return
		end
		focusClock = os.clock()
		lastFocus = position
		focusBusy = true
		task.spawn(function()
			request("quaesitor.focus", { x = position.X, y = position.Y, z = position.Z })
			focusBusy = false
		end)
	end

	local scrubbing = false
	local resumeAfterScrub = false
	local function scrubTo(x: number)
		local left = timeline.AbsolutePosition.X
		local width = math.max(timeline.AbsoluteSize.X, 1)
		time = math.clamp((x - left) / width, 0, 1) * duration
	end

	local function isPress(input: InputObject): boolean
		return input.UserInputType == Enum.UserInputType.MouseButton1
			or input.UserInputType == Enum.UserInputType.Touch
	end

	table.insert(
		connections,
		scrubArea.InputBegan:Connect(function(input)
			if isPress(input) then
				scrubbing = true
				resumeAfterScrub = playing
				playing = false
				scrubTo(input.Position.X)
			end
		end)
	)
	table.insert(
		connections,
		UserInputService.InputChanged:Connect(function(input)
			if
				scrubbing
				and (
					input.UserInputType == Enum.UserInputType.MouseMovement
					or input.UserInputType == Enum.UserInputType.Touch
				)
			then
				scrubTo(input.Position.X)
			end
		end)
	)
	table.insert(
		connections,
		UserInputService.InputEnded:Connect(function(input)
			if scrubbing and isPress(input) then
				scrubbing = false
				playing = resumeAfterScrub and time < duration
				refreshPlay()
			end
		end)
	)

	table.insert(
		connections,
		RunService.RenderStepped:Connect(function(dt)
			if playing then
				time = math.min(duration, time + dt * speed)
				if time >= duration then
					playing = false
					refreshPlay()
				end
			end
			render()
			streamAround()
		end)
	)

	-- Avatars: built by the server, handed to this client alone, copied here.
	task.spawn(function()
		noticeLabel.Text = "Loading avatars…"
		local response = request("quaesitor.ghosts", { id = case.id })
		if stopped then
			return
		end
		local loaded = 0
		if response.ok and response.count > 0 then
			local gui = Players.LocalPlayer:WaitForChild("PlayerGui")
			local container = gui:WaitForChild(response.folder, AVATAR_WAIT)
			local deadline = os.clock() + AVATAR_WAIT
			while container and #container:GetChildren() < response.count and os.clock() < deadline do
				task.wait(0.2)
			end
			if stopped then
				return
			end
			for _, ghost in ghosts do
				local source = container and container:FindFirstChild(tostring(ghost.track.userId))
				if source and source:IsA("Model") then
					local ok = pcall(useAvatar, ghost, source, folder)
					if ok and ghost.markers == nil then
						loaded += 1
						if watched == ghost then
							camera.CameraSubject = ghost.subject
						end
					end
				end
			end
		end
		noticeLabel.Text = if loaded > 0
			then "Only you can see this replay"
			else "Avatars unavailable  ·  only you can see this"
	end)

	local session = {}
	function session.stop()
		if running ~= session then
			return
		end
		running = nil
		stopped = true
		for _, connection in connections do
			connection:Disconnect()
		end
		if watched then
			watch(nil)
		end
		for _, ghost in ghosts do
			for _, tool in ghost.tools do
				tool:Destroy()
			end
			ghost.model:Destroy()
		end
		pathFolder:Destroy()
		folder:Destroy()
		bar:Destroy()
		task.spawn(request, "quaesitor.end")
		onStop()
	end
	running = session

	refreshPlay()
	render()
end

return Replay
