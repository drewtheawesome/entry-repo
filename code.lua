local Players = game:GetService("Players") -- used to detect players
local RunService = game:GetService("RunService") -- used for AI update loops
local Debris = game:GetService("Debris") -- used for cleaning temporary objects
local PhysicsService = game:GetService("PhysicsService") -- used for collision handling
local TweenService = game:GetService("TweenService") -- used for rotating sentry smoothly

local Tool = script.Parent -- wrench tool instance

-- obtain player from tool
local player = Tool.Parent.Parent

-- create controller table which acts like a class
local WrenchController = {} -- main controller table
WrenchController.__index = WrenchController -- enable OOP behaviour

-- function to initialize a new controller

function WrenchController.new(player) -- player represents tool owner

	local self = setmetatable({}, WrenchController) -- create object

	self.Player = player -- store player reference
	self.Character = player.Character or player.CharacterAdded:Wait() -- ensure character exists
	self.Humanoid = self.Character:WaitForChild("Humanoid") -- get humanoid
	self.Root = self.Character:WaitForChild("HumanoidRootPart") -- root part for positioning

	self.Tool = Tool -- store tool reference
	self.Assets = Tool:WaitForChild("Assets") -- asset folder

	self.State = "Idle" -- controller state
	self.Sentry = nil -- sentry reference
	self.Target = nil -- current target

	self.Level = 1 -- upgrade level
	self.MaxLevel = 3 -- max upgrade level

	self.SentryHealth = 100 -- sentry health

	self.ProjectileSpeed = 120 -- projectile speed

	self.Debounce = false -- attack debounce

	self.DebugEnabled = true -- debug toggle

	self:_loadAnimations() -- load animations
	
	self:_initDebugger() -- initialize debug system

	return self -- return object

end

-- load animation assets into memory

function WrenchController:_loadAnimations()

	self.Animations = {} -- animation container

	local animator = self.Humanoid:WaitForChild("Animator") -- animator object

	for _, anim in ipairs(self.Assets.Anims:GetChildren()) do -- iterate animations

		self.Animations[anim.Name] = animator:LoadAnimation(anim) -- load animation

	end -- animation loop end

end -- animation loader end

-- debugger function

function WrenchController:_initDebugger()

	self.Debug = function(msg) -- create debug function

		if self.DebugEnabled then -- check debug toggle

			print("[WrenchController]: "..tostring(msg)) -- print message

		end -- debug condition

	end -- debug function

	self:Debug("Debugger initialized") -- startup message

end

-- function for playing sound folders

function WrenchController:_playSound(folder)

	for _, sound in ipairs(folder:GetChildren()) do -- iterate sounds

		local clone = sound:Clone() -- clone sound

		clone.Parent = self.Root -- parent to player

		clone:Play() -- play sound

		Debris:AddItem(clone, clone.TimeLength) -- auto cleanup

	end -- sound loop end

end

-- calculate sentry placement using raycast

function WrenchController:_calculatePlacement()

	local forward = self.Root.CFrame.LookVector -- forward vector

	local offset = forward * 4 -- forward offset

	local startPosition = self.Root.Position + offset -- raycast start

	local params = RaycastParams.new() -- raycast params

	params.FilterDescendantsInstances = {self.Character} -- ignore player

	params.FilterType = Enum.RaycastFilterType.Blacklist -- blacklist filter

	local result = workspace:Raycast(startPosition, Vector3.new(0,-12,0), params) -- cast ray

	if result then -- if hit surface

		self:Debug("Surface detected for sentry placement") -- debug log

		return CFrame.new(result.Position) -- placement cframe

	end -- raycast check

	self:Debug("Fallback placement used") -- fallback message

	return self.Root.CFrame -- fallback

end

-- spawn sentry

function WrenchController:PlaceSentry()

	if self.Sentry then return end -- prevent duplicates

	local sentry = self.Assets.Sentry:Clone() -- clone sentry

	local cf = self:_calculatePlacement() -- calculate placement

	sentry:SetPrimaryPartCFrame(cf) -- position sentry

	sentry.Parent = workspace -- parent to world

	self.Sentry = sentry -- store reference

	self:Debug("Sentry placed") -- debug message

	self:_startSentryAI() -- start AI

end

-- upgrade sentry

function WrenchController:UpgradeSentry()

	if not self.Sentry then return end -- ensure sentry exists

	if self.Level >= self.MaxLevel then return end -- prevent over upgrade

	self.Level += 1 -- increment level

	self.SentryHealth += 50 -- increase health

	self.ProjectileSpeed += 20 -- increase fire speed

	self:Debug("Sentry upgraded to level "..self.Level) -- debug log

end -- upgrade end

-- apply damage to sentry

function WrenchController:DamageSentry(amount)

	self.SentryHealth -= amount -- subtract health

	self:Debug("Sentry damaged") -- debug log

	if self.SentryHealth <= 0 then -- check death

		self:DestroySentry() -- destroy sentry

	end -- health check

end

-- destroy sentry
function WrenchController:DestroySentry()

	if self.Sentry then

		self.Sentry:Destroy() -- destroy model

		self.Sentry = nil -- remove reference

		self.Level = 1 -- reset level

		self.SentryHealth = 100 -- reset health

		self:Debug("Sentry destroyed") -- debug log

	end -- existence check

end

-- wrench melee attack

function WrenchController:Swing()

	if self.Debounce then return end -- debounce protection

	self.Debounce = true -- activate debounce

	self.Animations.SwingWrenchAnim:Play() -- play animation

	local origin = self.Root.Position -- attack origin

	local direction = self.Root.CFrame.LookVector * 6 -- attack direction

	local params = RaycastParams.new() -- raycast parameters

	params.FilterDescendantsInstances = {self.Character} -- ignore player

	params.FilterType = Enum.RaycastFilterType.Blacklist -- blacklist

	local result = workspace:Raycast(origin, direction, params) -- cast ray

	if result then -- if hit

		local hum = result.Instance.Parent:FindFirstChild("Humanoid") -- detect humanoid

		if hum then -- ensure humanoid exists

			hum:TakeDamage(10) -- apply damage

			self:Debug("Enemy hit by wrench") -- debug log

		end -- humanoid check

	end -- raycast result

	task.delay(.5,function() -- delay reset

		self.Debounce = false -- reset debounce

	end) -- delay end

end -- swing end

-- find nearest enemy player

function WrenchController:_findTarget()

	local closest = nil -- closest enemy

	local distance = math.huge -- initial distance

	for _, plr in ipairs(Players:GetPlayers()) do -- iterate players

		if plr ~= self.Player then -- ignore owner

			local char = plr.Character -- get character

			if char and char:FindFirstChild("HumanoidRootPart") then -- validate character

				local d = (char.HumanoidRootPart.Position - self.Sentry.PrimaryPart.Position).Magnitude -- distance

				if d < distance and d < 60 then -- closer target

					closest = char -- update closest

					distance = d -- update distance

				end -- distance check

			end -- character check

		end -- owner check

	end -- player loop

	return closest -- return target

end -- finder end

-- fire projectile
function WrenchController:_fireProjectile(target)

	local bullet = Instance.new("Part") -- create projectile

	bullet.Size = Vector3.new(.4,.4,.4) -- projectile size

	bullet.Shape = Enum.PartType.Ball -- spherical bullet

	bullet.Material = Enum.Material.Neon -- glowing look

	bullet.CFrame = self.Sentry.PrimaryPart.CFrame -- spawn location

	bullet.CanCollide = false -- disable collision

	bullet.Parent = workspace -- parent to world

	local velocity = (target.HumanoidRootPart.Position - bullet.Position).Unit * self.ProjectileSpeed -- velocity

	local bodyVel = Instance.new("BodyVelocity") -- physics object

	bodyVel.Velocity = velocity -- apply velocity

	bodyVel.MaxForce = Vector3.new(1e5,1e5,1e5) -- large force

	bodyVel.Parent = bullet -- attach to projectile

	bullet.Touched:Connect(function(hit) -- hit detection

		local hum = hit.Parent:FindFirstChild("Humanoid") -- find humanoid

		if hum then hum:TakeDamage(15) end -- apply damage

		bullet:Destroy() -- destroy bullet

	end) -- touched event

	Debris:AddItem(bullet,5) -- auto cleanup

end -- projectile end

-- sentry AI loop

function WrenchController:_startSentryAI()

	RunService.Heartbeat:Connect(function() -- frame update

		if not self.Sentry then return end -- ensure sentry exists

		local target = self:_findTarget() -- search enemy

		if target then -- if enemy found

			self.Target = target -- store target

			self:_fireProjectile(target) -- fire projectile

		end -- target condition

	end) -- heartbeat connection

end -- ai loop end

-- tool activation

function WrenchController:Activate()

	if not self.Sentry then -- if no sentry exists

		self:PlaceSentry() -- place sentry

	else

		self:Swing() -- perform attack

	end -- branch end

end

-- create controller instance

local controller = WrenchController.new(player) -- initialize controller

-- connect tool activation

Tool.Activated:Connect(function() -- event connection

	controller:Activate() -- call activation

end)
