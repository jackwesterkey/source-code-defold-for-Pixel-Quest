-- player.script

-- These are the tweaks for the mechanics, feel free to change them for a different feeling
local move_acceleration = 3500
local air_acceleration_factor = 0.8
local max_speed = 100
local gravity = -1000
local jump_takeoff_speed = 550
local touch_jump_timeout = 0.2

-- Initial health value
local health = 100

-- Pre-hashing ids improves performance
local msg_contact_point_response = hash("contact_point_response")
local msg_animation_done = hash("animation_done")
local msg_enemy_attack_done = hash("attack_done") -- New message for enemy attack completion
local group_obstacle = hash("ground")
local group_enemy = hash("enemy") -- Assuming your enemy group is named "enemy"
local input_left = hash("left")
local input_right = hash("right")
local input_jump = hash("jump")
local input_Space = hash("sword") -- Hash for the attack action
local input_Down = hash("block") -- Hash for the block action
local input_kick = hash("Kick") -- Hash for the kick action

local anim_run = hash("walk") -- Force anim_run to be "walk"
local anim_idle = hash("idle right")
local anim_jump = hash("jump")
local anim_fall = hash("jump")
local anim_attack = hash("Attack") -- Attack animation
local anim_block = hash("block")
local anim_kick = hash("Kick") -- Kick animation



function init(self)
	-- This lets us handle input in this script
	msg.post(".", "acquire_input_focus")

	-- Initial player velocity
	self.velocity = vmath.vector3(0, 0, 0)
	self.correction = vmath.vector3()
	self.ground_contact = false
	self.move_input = 0
	self.anim = nil
	self.touch_jump_timer = 0
	self.last_direction = 0
	self.is_attacking = false -- New variable to track attacking state
	self.is_running = false -- New variable to track running animation state
	self.input_disabled = false -- New variable to track input state
	self.health = health -- Assign the health to the player
	self.invulnerable = false -- Flag to track if the player is invulnerable after being hit
	self.player_in_contact = false -- Track if the player is in contact with the enemy
	self.is_blocking = false -- New variable to track blocking state
end

local function set_animation(self, anim)
	-- Only play animations which are not already playing unless we are attacking or blocking
	if not self.is_attacking or anim == anim_attack or anim == anim_kick then
		if self.anim ~= anim then -- Check if the current animation is different
			-- Tell the sprite to play the animation
			sprite.play_flipbook("#player", anim)
			-- Remember which animation is playing
			self.anim = anim
			self.is_running = (anim == anim_run) -- Set running state if it's the running animation
		end
	end
end

local function update_animations(self)
	-- Make sure the player character faces the right way based on last movement direction
	sprite.set_hflip("#player", self.last_direction < 0)

	-- Update animations based on the current state
	if self.is_attacking then
		if self.anim ~= anim_kick then
			set_animation(self, anim_attack)
		end
	elseif self.is_blocking then
		set_animation(self, anim_block) -- Play block animation while blocking
	elseif not self.ground_contact then
		if self.velocity.y > 0 then
			set_animation(self, anim_jump)
		else
			set_animation(self, anim_fall)
		end
	else
		if self.velocity.x == 0 then
			set_animation(self, anim_idle)
		else
			set_animation(self, anim_run) -- Use anim_run which is always "walk"
		end
	end
end

function update(self, dt)
	local target_speed = self.move_input * max_speed
	local speed_diff = target_speed - self.velocity.x
	local acceleration = vmath.vector3(0, gravity, 0)
	if speed_diff ~= 0 then
		if speed_diff < 0 then
			acceleration.x = -move_acceleration
		else
			acceleration.x = move_acceleration
		end
		if not self.ground_contact then
			acceleration.x = air_acceleration_factor * acceleration.x
		end
	end
	local dv = acceleration * dt
	if math.abs(dv.x) > math.abs(speed_diff) then
		dv.x = speed_diff
	end
	local v0 = self.velocity
	self.velocity = self.velocity + dv
	local dp = (v0 + self.velocity) * dt * 0.5
	go.set_position(go.get_position() + dp)

	if self.touch_jump_timer > 0 then
		self.touch_jump_timer = self.touch_jump_timer - dt
	end

	if self.move_input ~= 0 then
		self.last_direction = self.move_input
	end

	update_animations(self)

	self.correction = vmath.vector3()
	self.move_input = 0
	self.ground_contact = false
end

local function handle_obstacle_contact(self, normal, distance)
	local proj = vmath.dot(self.correction, normal)
	local comp = (distance - proj) * normal
	self.correction = self.correction + comp
	go.set_position(go.get_position() + comp)
	if normal.y > 0.7 then
		self.ground_contact = true
	end
	proj = vmath.dot(self.velocity, normal)
	if proj < 0 then
		self.velocity = self.velocity - proj * normal
	end
end

local function take_damage(self, amount)
	if not self.invulnerable and not self.is_blocking then -- Check if the player is not blocking
		self.health = self.health - amount
		print("Player took damage! Health: " .. self.health) -- Log the damage taken
		self.invulnerable = true -- Set invulnerable state
		if self.health <= 0 then
			-- Handle player death here (e.g., restart the level or show game over)
			print("Player is dead")
		else
			-- Reset invulnerability after a short duration (e.g., 1 second)
			timer.delay(1, false, function()
				self.invulnerable = false
			end)
		end
	end
end

function on_message(self, message_id, message, sender)
	if message_id == msg_contact_point_response then
		if message.group == group_obstacle then
			handle_obstacle_contact(self, message.normal, message.distance)
		elseif message.group == group_enemy then
			self.player_in_contact = true -- Mark the player as in contact with the enemy
		end
	elseif message_id == msg_animation_done then
		if self.anim == anim_kick then
			self.is_attacking = false -- Reset attacking state
			self.input_disabled = false -- Re-enable input
			if self.is_blocking then
				set_animation(self, anim_block) -- Switch back to block animation if blocking
			else
				set_animation(self, anim_idle) -- Switch back to idle animation
			end
		elseif self.anim == anim_attack then
			self.is_attacking = false -- Reset attacking state
			self.input_disabled = false -- Re-enable input
			if self.is_blocking then
				set_animation(self, anim_block) -- Switch back to block animation if blocking
			else
				set_animation(self, anim_idle) -- Switch back to idle animation
			end
		elseif self.anim == anim_run then
			self.is_running = false -- Reset running state when running animation finishes
		end
	elseif message_id == msg_enemy_attack_done then
		if self.player_in_contact then -- Only take damage if still in contact
			take_damage(self, 10) -- Apply damage when the enemy's attack is done
		end
	end
end

function on_input(self, action_id, action)
	if self.input_disabled then
		return -- Ignore input if it's disabled
	end

	if action_id == input_Down then
		if action.pressed then
			self.is_blocking = true -- Set blocking state to true when down is pressed
		elseif action.released then
			self.is_blocking = false -- Reset blocking state when down is released
			if not self.is_attacking then -- Ensure input is re-enabled only if not attacking
				self.input_disabled = false
			end
		end
	elseif action_id == input_kick and action.pressed and not self.is_attacking then
		self.is_attacking = true -- Set attacking state to true
		self.input_disabled = true -- Disable input during kick
		set_animation(self, anim_kick) -- Play the kick animation
	elseif action_id == input_Space and action.pressed and not self.is_attacking then
		self.is_attacking = true -- Set attacking state to true
		self.input_disabled = true -- Disable input during attack
		set_animation(self, anim_attack) -- Play the attack animation
	elseif not self.is_blocking or self.is_attacking then -- Only process movement inputs if not blocking or if attacking
		if action_id == input_left then
			self.move_input = -action.value
		elseif action_id == input_right then
			self.move_input = action.value
		elseif action_id == input_jump then
			if action.pressed then
				jump(self)
			elseif action.released then
				abort_jump(self)
			end
		end
	end
end

function jump(self)
	if self.ground_contact then
		self.velocity.y = jump_takeoff_speed
		set_animation(self, anim_jump)
	end
end

function abort_jump(self)
	if self.velocity.y > 0 then
		self.velocity.y = self.velocity.y * 0.5 -- Cut the jump height
	end
end
