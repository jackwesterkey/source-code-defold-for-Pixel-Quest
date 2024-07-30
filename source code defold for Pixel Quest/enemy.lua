-- enemy.script

-- Tweaks for enemy mechanics
local move_acceleration = 350
local max_speed = 50
local gravity = -1000
local anim_idle = hash("idle")
local anim_walk = hash("walk")
local anim_attack = hash("Attack")
local anim_knock = hash("knock")
local input_take_health = hash("take_health") -- Hash for the take_health action

-- Time to wait before resuming movement after attack
local attack_delay = 0.5

-- Store the player contact status
local player_in_contact = false

-- Enemy health
local health = 100

function init(self)
	self.velocity = vmath.vector3(0, 0, 0)
	self.correction = vmath.vector3()
	self.ground_contact = false
	self.anim = nil
	self.attack_state = "none" -- Can be "none", "attacking"
	self.move_direction = 1
	self.attack_timer = 0 -- Initialize attack timer
end

local function play_animation(self, anim)
	if self.anim ~= anim then
		msg.post("#sprite", "play_animation", { id = anim })
		self.anim = anim
	end
end

local function update_animations(self)
	sprite.set_hflip("#sprite", self.move_direction < 0)
	if self.attack_state == "attacking" then
		play_animation(self, anim_attack)
	elseif self.ground_contact then
		if self.velocity.x == 0 then
			play_animation(self, anim_idle)
		else
			play_animation(self, anim_walk)
		end
	end
end

function update(self, dt)
	if self.attack_state == "attacking" then
		if self.attack_timer > 0 then
			self.attack_timer = self.attack_timer - dt
		else
			-- Attack done
			self.attack_state = "none"
			self.velocity.x = self.move_direction * max_speed
			play_animation(self, anim_walk) -- Force transition to walking animation
		end
	else
		local target_speed = self.move_direction * max_speed
		local speed_diff = target_speed - self.velocity.x

		-- Smooth acceleration using lerp
		local acceleration = move_acceleration * dt
		if math.abs(speed_diff) < acceleration then
			self.velocity.x = target_speed
		else
			if speed_diff > 0 then
				self.velocity.x = self.velocity.x + acceleration
			else
				self.velocity.x = self.velocity.x - acceleration
			end
		end

		-- Apply gravity
		self.velocity.y = self.velocity.y + gravity * dt

		-- Smooth position update using interpolation
		local new_position = go.get_position() + self.velocity * dt
		go.set_position(new_position)
	end

	-- Reset correction and ground contact for the next frame
	self.correction = vmath.vector3()
	self.ground_contact = false

	-- Update animations
	update_animations(self)

	-- Check for damage application
	if player_in_contact and self.attack_state == "attacking" then
		msg.post("player", "attack_done") -- This will be called in the player's script only if not blocking
	end
end

local function handle_obstacle_contact(self, normal, distance)
	local proj = vmath.dot(self.correction, normal)
	local comp = (distance - proj) * normal
	self.correction = self.correction + comp
	go.set_position(go.get_position() + comp)

	if normal.y > 0.7 then
		self.ground_contact = true
	end

	-- Check for vertical wall contact
	if math.abs(normal.x) > 0.7 then
		if self.move_direction == 1 and normal.x < 0 then
			self.move_direction = -1
			sprite.set_hflip("#sprite", self.move_direction < 0)
		elseif self.move_direction == -1 and normal.x > 0 then
			self.move_direction = 1
			sprite.set_hflip("#sprite", self.move_direction < 0)
		end
	end

	proj = vmath.dot(self.velocity, normal)
	if proj < 0 then
		self.velocity = self.velocity - proj * normal
	end
end

local function handle_player_contact(self, normal, distance)
	-- Prevent the player from walking through the enemy
	local proj = vmath.dot(self.correction, normal)
	local comp = (distance - proj) * normal
	self.correction = self.correction + comp
	go.set_position(go.get_position() + comp)

	proj = vmath.dot(self.velocity, normal)
	if proj < 0 then
		self.velocity = self.velocity - proj * normal
	end

	-- Mark player as in contact
	player_in_contact = true

	-- Deduct health from the enemy when attacked
	if self.attack_state == "attacking" then
		health = health - 10
		if health <= 0 then
			-- Handle enemy death
			print("Enemy has died") -- Add enemy death logic here
		else
			print("Enemy health: " .. health) -- Display remaining enemy health
		end
	end
end

function on_message(self, message_id, message, sender)
	if message_id == hash("contact_point_response") then
		if message.group == hash("ground") or message.group == hash("wall") then
			handle_obstacle_contact(self, message.normal, message.distance)
		elseif message.group == hash("player") then
			-- Handle collision with player
			handle_player_contact(self, message.normal, message.distance)

			if self.attack_state == "none" then
				self.attack_state = "attacking"
				self.attack_timer = attack_delay
				self.velocity.x = 0
				-- Start playing attack animation
				play_animation(self, anim_attack)

				-- Flip based on player's position
				local enemy_pos = go.get_position()
				local player_pos = message.position
				if player_pos.x < enemy_pos.x then
					self.move_direction = -1
				else
					self.move_direction = 1
				end
				sprite.set_hflip("#sprite", self.move_direction < 0) -- Flip sprite based on direction
			end
		end
	elseif message_id == hash("contact_point_response_end") and message.group == hash("player") then
		player_in_contact = false -- Reset contact status when player leaves
	end
end

function on_input(self, action_id, action)
	if action_id == input_take_health and action.pressed then
		health = health - 10
		if health <= 0 then
			-- Handle enemy death
			print("Enemy has died from player input") -- Handle death logic here
		else
			print("Enemy health: " .. health) -- Display remaining enemy health
		end
	end
end
