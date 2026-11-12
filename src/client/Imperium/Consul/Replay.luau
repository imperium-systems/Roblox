--!strict
-- Quaesitor replay, client side.
-- Ghost markers move through the world on the viewer's screen only: everything here is
-- created by this client and never replicates. A bar at the top of the screen plays,
-- pauses and scrubs the case, and the camera can follow any of the ghosts.

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

-- Sample fields (see Quaesitor on the server).
local T, X, Y, Z, YAW, HEALTH, FLAGS = 1, 2, 3, 4, 5, 6, 7
local DEAD, SEATED, AIRBORNE = 1, 2, 4

-- Offsets from the root part of a character.
local BODY = CFrame.new(0, -0.7, 0)
local HEAD = CFrame.new(0, 2.1, 0)
local FRONT = CFrame.new(0, 2.1, -0.75)
local FEET = Vector3.new(0, -2.8, 0)

local ROLES: { [string]: { label: string, color: Color3 } } = {
	reporter = { label = "Reporter", color = C.info },
	reported = { label = "Reported", color = C.danger },
	suspect = { label = "Suspect", color = C.danger },
}

local EVENT_COLORS: { [string]: Color3 } = {
	lictor = C.danger,
	death = C.warning,
	staff = C.accent,
	left = C.textFaint,
}

type Ghost = {
	track: any,
	color: Color3,
	model: Model,
	body: BasePart,
	head: BasePart,
	front: BasePart,
	highlight: Highlight,
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
	local model = create("Model", { Name = track.name, Parent = folder }) :: Model
	local body = ghostPart("Body", Vector3.new(2, 4.4, 1), color, model)
	local head = ghostPart("Head", Vector3.new(1.3, 1.3, 1.3), color, model)
	head.Shape = Enum.PartType.Ball
	local front = ghostPart("Front", Vector3.new(0.5, 0.3, 0.5), C.text, model)
	model.PrimaryPart = body

	-- Seen through walls: the point is to find them.
	local highlight = create("Highlight", {
		FillColor = color,
		OutlineColor = color,
		FillTransparency = 0.75,
		OutlineTransparency = 0.1,
		DepthMode = Enum.HighlightDepthMode.AlwaysOnTop,
		Adornee = model,
		Parent = model,
	}) :: Highlight

	local billboard = create("BillboardGui", {
		Size = UDim2.fromOffset(200, 44),
		StudsOffset = Vector3.new(0, 2, 0),
		AlwaysOnTop = true,
		LightInfluence = 0,
		Adornee = head,
		Parent = model,
	}, {
		Components.stack("V", 0, Enum.HorizontalAlignment.Center),
	}) :: BillboardGui
	Components.text({
		Text = `{track.name}{if role then `  ·  {role.label}` else ""}`,
		FontFace = P.bold,
		TextSize = 14,
		TextColor3 = color,
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
		model = model,
		body = body,
		head = head,
		front = front,
		highlight = highlight,
		billboard = billboard,
		status = status,
		visible = true,
	}
end

local function setGhostVisible(ghost: Ghost, visible: boolean)
	if ghost.visible == visible then
		return
	end
	ghost.visible = visible
	for _, part in { ghost.body, ghost.head, ghost.front } do
		part.LocalTransparencyModifier = if visible then 0 else 1
	end
	ghost.highlight.Enabled = visible
	ghost.billboard.Enabled = visible
end

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

-- Where the ghost is at time t, and the closest sample. Nil when it was not there.
local function poseAt(samples: { any }, t: number): (CFrame?, any)
	local count = #samples
	if count == 0 then
		return nil, nil
	end
	local i = before(samples, t)
	if i == 0 then
		local first = samples[1]
		if first[T] - t > EDGE then
			return nil, nil
		end
		return cframeOf(Vector3.new(first[X], first[Y], first[Z]), first[YAW]), first
	end
	local a = samples[i]
	local b = samples[i + 1]
	if not b or b[T] - a[T] > GAP then
		if t - a[T] > EDGE then
			return nil, nil
		end
		return cframeOf(Vector3.new(a[X], a[Y], a[Z]), a[YAW]), a
	end
	local alpha = math.clamp((t - a[T]) / math.max(b[T] - a[T], 0.01), 0, 1)
	local from = Vector3.new(a[X], a[Y], a[Z])
	local to = Vector3.new(b[X], b[Y], b[Z])
	-- Shortest turn between the two headings.
	local turn = ((b[YAW] - a[YAW] + 180) % 360) - 180
	return cframeOf(from:Lerp(to, alpha), a[YAW] + turn * alpha), if alpha < 0.5 then a else b
end

local function statusOf(sample: any): string
	local parts = { `{sample[HEALTH]} HP` }
	local flags = sample[FLAGS]
	if isFlag(flags, DEAD) then
		parts = { "Dead" }
	elseif isFlag(flags, SEATED) then
		table.insert(parts, "seated")
	elseif isFlag(flags, AIRBORNE) then
		table.insert(parts, "in the air")
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
function Replay.start(screen: ScreenGui, case: any, onStop: () -> ())
	Replay.stop()

	local camera = workspace.CurrentCamera
	local duration = math.max(case.duration, 1)
	local time = 0
	local playing = true
	local speed = 1
	local showPath = true
	local watched: Ghost? = nil
	local connections: { RBXScriptConnection } = {}

	-- Created by this client, so nobody else sees it.
	local folder = create("Folder", { Name = "ImperiumQuaesitorReplay", Parent = workspace })
	local pathFolder = create("Folder", { Name = "Paths", Parent = folder })
	local ghosts: { Ghost } = {}
	for _, track in case.tracks do
		local ghost = buildGhost(folder, track)
		drawPath(pathFolder, ghost)
		table.insert(ghosts, ghost)
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
		Size = UDim2.new(1, -160, 1, 0),
		ZIndex = 31,
		Parent = titleRow,
	})
	Components.text({
		Text = "Only you can see this replay",
		TextSize = 12,
		TextColor3 = C.textFaint,
		TextXAlignment = Enum.TextXAlignment.Right,
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.fromScale(1, 0),
		Size = UDim2.new(0, 160, 1, 0),
		ZIndex = 31,
		Parent = titleRow,
	})

	-- Controls
	local controls = row(2, 30)
	local layout = Components.stack("H", 6)
	layout.VerticalAlignment = Enum.VerticalAlignment.Center
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
	local speeds = Components.selector({
		{ value = "1", label = "1x" },
		{ value = "2", label = "2x" },
		{ value = "4", label = "4x" },
	}, "1", function(value)
		speed = tonumber(value) or 1
	end)
	speeds.Size = UDim2.new(0, 0, 0, 30)
	speeds.LayoutOrder = 4
	speeds.Parent = controls
	local pathButton: TextButton
	pathButton = control("Hide path", "ghost", function()
		showPath = not showPath
		pathFolder.Parent = if showPath then folder else nil
		pathButton.Text = Components.uppercase(if showPath then "Hide path" else "Show path")
	end, 5)
	control("Stop replay", "danger", function()
		Replay.stop()
	end, 6)

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
			Size = UDim2.fromOffset(3, 18),
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

	-- Camera: free, or following one of the ghosts.
	local cameraRow = row(5, 30)
	local function watch(ghost: Ghost?)
		watched = ghost
		if ghost then
			camera.CameraSubject = ghost.body
		else
			local character = Players.LocalPlayer.Character
			local humanoid = character and character:FindFirstChildOfClass("Humanoid")
			camera.CameraSubject = humanoid
		end
	end
	local options = { { value = "free", label = "My camera" } }
	for i, ghost in ghosts do
		table.insert(options, { value = tostring(i), label = `Follow {ghost.track.name}` })
	end
	-- Starts on the player the case is about.
	local first = 1
	for i, ghost in ghosts do
		if ghost.track.role ~= "reporter" then
			first = i
			break
		end
	end
	local cameraSelector = Components.selector(options, if ghosts[first] then tostring(first) else "free", function(value)
		watch(if value == "free" then nil else ghosts[tonumber(value) :: number])
	end)
	cameraSelector.Size = UDim2.new(0, 0, 0, 30)
	cameraSelector.Parent = cameraRow
	watch(ghosts[first])

	-- Rendering --------------------------------------------------------------------------

	local function render()
		for _, ghost in ghosts do
			local cf, sample = poseAt(ghost.track.samples, time)
			if cf and sample then
				setGhostVisible(ghost, true)
				ghost.body.CFrame = cf * BODY
				ghost.head.CFrame = cf * HEAD
				ghost.front.CFrame = cf * FRONT
				local dead = isFlag(sample[FLAGS], DEAD)
				local color = if dead then C.textFaint else ghost.color
				ghost.body.Color = color
				ghost.head.Color = color
				ghost.status.Text = statusOf(sample)
			else
				setGhostVisible(ghost, false)
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
		end)
	)

	local session = {}
	function session.stop()
		if running ~= session then
			return
		end
		running = nil
		for _, connection in connections do
			connection:Disconnect()
		end
		if watched then
			watch(nil)
		end
		pathFolder:Destroy()
		folder:Destroy()
		bar:Destroy()
		onStop()
	end
	running = session

	refreshPlay()
	render()
end

return Replay
