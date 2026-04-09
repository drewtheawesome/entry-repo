local Players = game:GetService("Players") -- player service used for iterating enemy targets
local RunService = game:GetService("RunService") -- heartbeat loop used for real-time AI updates
local Debris = game:GetService("Debris") -- automatic cleanup of temporary objects like bullets
local TweenService = game:GetService("TweenService") -- used to smoothly rotate the sentry instead of snapping
local Tool = script.Parent -- the tool this script is inside of (wrench)
local player = Tool.Parent.Parent -- assumes tool is inside character, character inside player
-- controller table used as a pseudo-class
-- this allows multiple independent wrench systems if needed later
local WrenchController = {}
WrenchController.__index = WrenchController -- enables OOP-like behavior
-- constructor function (creates a new controller instance)
function WrenchController.new(player)
	local self = setmetatable({}, WrenchController) -- create object instance
	-- caching references early avoids repeated expensive lookups later
	self.Player = player -- owner of the wrench
	self.Character = player.Character or player.CharacterAdded:Wait() -- ensures character exists
	self.Humanoid = self.Character:WaitForChild("Humanoid") -- required for animations and health
	self.Root = self.Character:WaitForChild("HumanoidRootPart") -- used for positioning and direction
	self.Tool = Tool -- store tool reference for future expansion
	self.Assets = Tool:WaitForChild("Assets") -- container holding sentry + animations
	-- simple string-based state system for easier debugging during development
	self.State = "Idle"
	self.Sentry = nil -- will store the active sentry instance
	self.Target = nil -- currently tracked enemy target
	-- upgrade system kept linear for predictability (no branching yet)
	self.Level = 1
	self.MaxLevel = 3
	self.SentryHealth = 100 -- starting health
	self.ProjectileSpeed = 120 -- baseline projectile velocity
	-- cooldown prevents absurd fire rate due to Heartbeat running every frame
	self.FireCooldown = 0.4
	self.LastShot = 0 -- timestamp of last shot
	self.Debounce = false -- prevents spam clicking melee
	self.DebugEnabled = true -- toggle debug output
	self:_loadAnimations() -- preload animations to avoid runtime lag spikes
	self:_initDebugger() -- initialize debug function
	return self -- return constructed object
end
-- initializes debug logger
function WrenchController:_initDebugger()
	-- wrapper function so debug can be toggled globally
	self.Debug = function(msg)
		if self.DebugEnabled then
			print("[WrenchController]: "..tostring(msg))
		end
	end
	self:Debug("Controller initialized") -- confirms system boot
end
-- loads animations once instead of every use
function WrenchController:_loadAnimations()
	self.Animations = {} -- container for animation tracks
	local animator = self.Humanoid:WaitForChild("Animator") -- required for playing animations
	-- preload all animations for smoother gameplay
	for _, anim in ipairs(self.Assets.Anims:GetChildren()) do
		self.Animations[anim.Name] = animator:LoadAnimation(anim)
	end
end
-- determines where the sentry should be placed
function WrenchController:_calculatePlacement()
	-- forward offset prevents placing the sentry inside the player model
	local forward = self.Root.CFrame.LookVector
	local offset = forward * 4
	local startPosition = self.Root.Position + offset
	local params = RaycastParams.new()
	params.FilterDescendantsInstances = {self.Character} -- ignore self
	params.FilterType = Enum.RaycastFilterType.Blacklist
	-- raycast downward to find ground (prevents floating sentries)
	local result = workspace:Raycast(startPosition, Vector3.new(0,-12,0), params)
	if result then
		self:Debug("Ground detected for placement")
		return CFrame.new(result.Position) -- snap to ground
	end
	-- fallback ensures placement still works even if raycast fails
	return self.Root.CFrame
end
-- creates and spawns the sentry
function WrenchController:PlaceSentry()
	if self.Sentry then return end -- prevents multiple sentries
	local sentry = self.Assets.Sentry:Clone() -- duplicate model
	local cf = self:_calculatePlacement() -- get valid placement
	sentry:SetPrimaryPartCFrame(cf) -- move sentry into position
	sentry.Parent = workspace -- make visible in game
	self.Sentry = sentry -- store reference
	self:Debug("Sentry placed")
	self:_startSentryAI() -- start behavior loop
end
-- upgrades sentry stats
function WrenchController:UpgradeSentry()
	if not self.Sentry then return end -- must exist
	if self.Level >= self.MaxLevel then return end -- prevent overflow
	self.Level += 1
	-- scaling multiple stats gives upgrades more impact
	self.SentryHealth += 50
	self.ProjectileSpeed += 20
	self.FireCooldown *= 0.9 -- faster fire rate
	self:Debug("Upgraded to level "..self.Level)
end
-- removes sentry completely
function WrenchController:DestroySentry()
	if not self.Sentry then return end
	self.Sentry:Destroy() -- remove model
	self.Sentry = nil -- clear reference
	-- reset ensures next placement starts fresh
	self.Level = 1
	self.SentryHealth = 100
	self:Debug("Sentry destroyed")
end
-- melee attack using wrench
function WrenchController:Swing()
	if self.Debounce then return end -- prevents spam
	self.Debounce = true
	self.Animations.SwingWrenchAnim:Play() -- play animation
	local origin = self.Root.Position
	local direction = self.Root.CFrame.LookVector * 6 -- short range attack
	local params = RaycastParams.new()
	params.FilterDescendantsInstances = {self.Character}
	params.FilterType = Enum.RaycastFilterType.Blacklist
	local result = workspace:Raycast(origin, direction, params)
	if result then
		local hum = result.Instance.Parent:FindFirstChild("Humanoid")
		if hum then
			hum:TakeDamage(10) -- apply damage
			self:Debug("Hit enemy with wrench")
		end
	end
	task.delay(0.5,function()
		self.Debounce = false -- reset after delay
	end)
end
-- finds nearest valid enemy
function WrenchController:_findTarget()
	local closest = nil
	local distance = math.huge
	for _, plr in ipairs(Players:GetPlayers()) do
		if plr ~= self.Player then -- ignore owner
			local char = plr.Character
			if char and char:FindFirstChild("HumanoidRootPart") then
				local d = (char.HumanoidRootPart.Position - self.Sentry.PrimaryPart.Position).Magnitude
				-- distance cap prevents shooting across entire map
				if d < distance and d < 60 then
					closest = char
					distance = d
				end
			end
		end
	end
	return closest
end
-- rotates sentry smoothly toward target
function WrenchController:_rotateSentry(target)
	local lookAt = CFrame.lookAt(
		self.Sentry.PrimaryPart.Position,
		target.HumanoidRootPart.Position
	)
	-- tween avoids robotic snapping rotation
	local tween = TweenService:Create(
		self.Sentry.PrimaryPart,
		TweenInfo.new(0.2, Enum.EasingStyle.Linear),
		{CFrame = lookAt}
	)
	tween:Play()
end
-- fires projectile toward target
function WrenchController:_fireProjectile(target)
	local now = tick()
	-- cooldown prevents excessive firing due to frame updates
	if now - self.LastShot < self.FireCooldown then return end
	self.LastShot = now
	local bullet = Instance.new("Part") -- dynamic projectile
	bullet.Size = Vector3.new(.4,.4,.4)
	bullet.Shape = Enum.PartType.Ball
	bullet.Material = Enum.Material.Neon
	bullet.CanCollide = false -- prevents physics issues
	bullet.CFrame = self.Sentry.PrimaryPart.CFrame
	bullet.Parent = workspace
	local velocity = (target.HumanoidRootPart.Position - bullet.Position).Unit * self.ProjectileSpeed
	local bodyVel = Instance.new("BodyVelocity")
	bodyVel.Velocity = velocity
	bodyVel.MaxForce = Vector3.new(1e5,1e5,1e5)
	bodyVel.Parent = bullet
	bullet.Touched:Connect(function(hit)
		local hum = hit.Parent:FindFirstChild("Humanoid")
		if hum then
			hum:TakeDamage(15)
		end
		bullet:Destroy()
	end)
	Debris:AddItem(bullet,5) -- failsafe cleanup
end
-- AI loop
function WrenchController:_startSentryAI()
	RunService.Heartbeat:Connect(function()
		if not self.Sentry then return end -- stop if destroyed
		local target = self:_findTarget()
		if target then
			self.Target = target
			self:_rotateSentry(target) -- face target
			self:_fireProjectile(target) -- attack
		end
	end)
end
-- tool usage behavior
function WrenchController:Activate()
	-- single input with context-based behavior keeps controls simple
	if not self.Sentry then
		self:PlaceSentry()
	else
		self:Swing()
	end
end
-- create controller instance
local controller = WrenchController.new(player)
-- bind tool click to controller logic
Tool.Activated:Connect(function()
	controller:Activate()
end)
