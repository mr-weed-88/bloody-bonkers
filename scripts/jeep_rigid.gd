extends RigidBody3D

@export_group("Movement Settings")
@export var speed: float = 20.0             
@export var acceleration: float = 0.1
@export var turn_speed: float = 2.0
@export var turn_acceleration: float = 0.25
@export var boost_multiplier: float = 1.25

@export_group("Car Physics & Grip")
@export var tire_grip: float = 0.85   
@export var brake_strength: float = 0.3     
@export var drift_grip: float = 0.20          # Lower = wider, longer slides | Higher = tighter, safer slides

@export_group("Raycast Suspension Physics")
@export var suspension_rest_distance: float = 0.50  # INCREASED: Gives the wheel more room to travel down
@export var spring_stiffness: float = 120.0        # INCREASED SIGNIFCANTLY: Holds up a heavy chassis on slopes
@export var spring_damping: float = 12.0           # INCREASED: Rule of thumb is (Stiffness / 10) to stop bouncing
@export var wheel_radius: float = 0.40             # Kept matching your tire profile mesh

@export_group("Suspension RayCast Nodes")
@export var raycast_fl: RayCast3D        
@export var raycast_fr: RayCast3D
@export var raycast_rl: RayCast3D
@export var raycast_rr: RayCast3D

@export_group("Wheel Visual Nodes")
@onready var front_left_wheel: Node3D = $Suspension_FL/FL_Wheel
@onready var front_right_wheel: Node3D = $Suspension_FR/FR_Wheel
@onready var rear_left_wheel: Node3D = $Suspension_RL/RL_Wheel
@onready var rear_right_wheel: Node3D =  $Suspension_RR/RR_Wheel

@onready var car_body: Node3D =  $Body/Body_Object

@export_group("Body Lean Aesthetics")
@export var suspension_lean_roll: float = 0.1     # Leans outward away from turn
@export var suspension_dive_pitch: float = 0.01   # Nose goes UP on gas, DOWN on reverse/brakes
@export var lean_return_speed: float = 10.0

@export_group("Engine Idle Shake")
@export var engine_shake_amount: float = 0.25     # Intensity of the body vibration/rattle
@export var engine_shake_speed: float = 45.0      # Frequency of the engine vibration cycles

var current_wheel_roll: float = 0.0
var current_steer_angle: float = 0.0

# Scale memories for safe Blender meshes
var scale_fl: Vector3 = Vector3.ONE
var scale_fr: Vector3 = Vector3.ONE
var scale_rl: Vector3 = Vector3.ONE
var scale_rr: Vector3 = Vector3.ONE

# Trackers for visual adjustments
var original_body_pos: Vector3 = Vector3.ZERO
var current_pitch: float = 0.0
var current_roll: float = 0.0
var shake_time: float = 0.0

func _ready() -> void:
	contact_monitor = false
	
	if car_body:
		original_body_pos = car_body.transform.origin
	
	# Save the exact scale sizes from your scene tree setup
	if front_left_wheel: scale_fl = front_left_wheel.transform.basis.get_scale()
	if front_right_wheel: scale_fr = front_right_wheel.transform.basis.get_scale()
	if rear_left_wheel: scale_rl = rear_left_wheel.transform.basis.get_scale()
	if rear_right_wheel: scale_rr = rear_right_wheel.transform.basis.get_scale()

func _physics_process(delta: float) -> void:
	# 1. RAYCAST suspension updates & tracking grounding state
	var wheels_grounded: int = 0
	
	if _process_suspension_spring(raycast_fl, front_left_wheel): wheels_grounded += 1
	if _process_suspension_spring(raycast_fr, front_right_wheel): wheels_grounded += 1
	if _process_suspension_spring(raycast_rl, rear_left_wheel): wheels_grounded += 1
	if _process_suspension_spring(raycast_rr, rear_right_wheel): wheels_grounded += 1
	
	var is_touching_ground = wheels_grounded > 0

	# 2. ARCADE INPUT FILTER
	var left = Input.is_action_pressed("move_left")
	var right = Input.is_action_pressed("move_right")
	
	var forward = Input.is_action_pressed("move_forward") if is_touching_ground else false
	var backward = Input.is_action_pressed("move_backward") if is_touching_ground else false
	var boost = Input.is_action_pressed("boost_speed") if is_touching_ground else false
	var is_braking = Input.is_action_pressed("ui_accept") if is_touching_ground else false

	# 3. Orientation Vectors
	var forward_vec = -global_transform.basis.z
	var right_vec = global_transform.basis.x
	var forward_speed = linear_velocity.dot(forward_vec)
	var steer_input = (1.0 if left else 0.0) - (1.0 if right else 0.0)

	# 4. ENGINE DRIVE FORCE & TRACTION LATERAL GRIP CONTROL
	var current_max_speed = speed * boost_multiplier if boost else speed
	if is_touching_ground:
		var drive_dir = (1.0 if forward else 0.0) - (1.0 if backward else 0.0)
		var lateral_speed = linear_velocity.dot(right_vec)

		var target_forward_speed = drive_dir * current_max_speed
		
		# Spacebar works entirely as a brake/stop using brake_strength
		var current_accel_rate = acceleration
		if is_braking:
			current_accel_rate = brake_strength
			target_forward_speed = 0.0
		elif backward and forward_speed > 0.5:
			current_accel_rate = brake_strength
			target_forward_speed = 0.0

		# Safety evaluations to prevent Nil runtime crashes
		var current_grip_setting = tire_grip if tire_grip != null else 0.85
		var active_drift_grip = drift_grip if drift_grip != null else 0.20

		# DUAL-DIRECTION STEERING DRIFT LOGIC
		# Triggers drift when steering hard while moving over a minimum speed threshold,
		# working perfectly for both forward and backward driving states.
		var active_grip = current_grip_setting
		var is_moving_with_intent = (forward and forward_speed > 4.0) or (backward and forward_speed < -4.0)
		
		if steer_input != 0.0 and is_moving_with_intent:
			active_grip = active_drift_grip

		var next_forward_speed = lerp(forward_speed, target_forward_speed, current_accel_rate)
		var next_lateral_speed = lerp(lateral_speed, 0.0, active_grip)

		var new_ground_velocity = (forward_vec * next_forward_speed) + (right_vec * next_lateral_speed)
		linear_velocity.x = new_ground_velocity.x
		linear_velocity.z = new_ground_velocity.z

	# 5. CAR STEERING MOMENTUM PIVOT
	var target_ang_vel = 0.0

	if steer_input != 0.0:
		if is_touching_ground:
			var gear_dir = 1.0 if forward_speed >= -0.1 else -1.0
			var speed_turn_factor = clamp(abs(forward_speed) / 10.0, 0.0, 1.2)
			target_ang_vel = steer_input * turn_speed * speed_turn_factor * gear_dir
		else:
			target_ang_vel = steer_input * turn_speed 

	angular_velocity.y = lerp(angular_velocity.y, target_ang_vel, turn_acceleration)
	
	# Stabilize rolling/pitching to keep car upright
	var stabilize_rate = 0.2 if is_touching_ground else 0.02
	angular_velocity.x = lerp(angular_velocity.x, 0.0, stabilize_rate)
	angular_velocity.z = lerp(angular_velocity.z, 0.0, stabilize_rate)

	# 6. VISUAL WHEEL ROTATION AND STEERING ANIMATION 
	var effective_roll_speed = forward_speed
	
	if is_braking:
		effective_roll_speed = 0.0
	elif not forward and not backward and is_touching_ground:
		effective_roll_speed = move_toward(forward_speed, 0.0, delta * speed * 2.0)

	if wheel_radius > 0.0:
		current_wheel_roll += (effective_roll_speed / wheel_radius) * delta
	else:
		current_wheel_roll += effective_roll_speed * delta * 2.8
		
	current_wheel_roll = wrapf(current_wheel_roll, -PI, PI)

	var target_steer_angle = steer_input * 0.45
	current_steer_angle = lerp(current_steer_angle, target_steer_angle, 0.2)

	var front_steer_basis = Basis(Vector3.UP, current_steer_angle)
	var roll_basis = Basis(Vector3.RIGHT, current_wheel_roll)
	var combined_front_basis = front_steer_basis * roll_basis

	if front_left_wheel: front_left_wheel.transform.basis = combined_front_basis.scaled(scale_fl)
	if front_right_wheel: front_right_wheel.transform.basis = combined_front_basis.scaled(scale_fr)
	if rear_left_wheel: rear_left_wheel.transform.basis = roll_basis.scaled(scale_rl)
	if rear_right_wheel: rear_right_wheel.transform.basis = roll_basis.scaled(scale_rr)

	# 7. CHASSIS BODY LEAN (WEIGHT TRANSFER & CENTRIFUGAL FORCE)
	if car_body:
		var target_pitch = 0.0
		var target_roll = 0.0
		
		if is_touching_ground:
			if (is_braking or backward) and abs(forward_speed) > 1.0:
				target_pitch = suspension_dive_pitch * 1.5 
			elif forward and forward_speed < current_max_speed:
				var boost_factor = 1.6 if boost else 1.0
				target_pitch = -suspension_dive_pitch * boost_factor
			elif backward:
				target_pitch = suspension_dive_pitch
				
			var turn_intensity = clamp(forward_speed / 10.0, -1.0, 1.0)
			target_roll = -steer_input * suspension_lean_roll * abs(turn_intensity)

		current_pitch = lerp(current_pitch, target_pitch, lean_return_speed * delta)
		current_roll = lerp(current_roll, target_roll, lean_return_speed * delta)
		
		car_body.transform.basis = Basis.from_euler(Vector3(current_pitch, 0.0, current_roll))

		# --- ENGINE SHAKE MODIFICATION ---
		var dynamic_speed_mod = 1.5 if boost else (1.2 if (forward or backward) else 1.0)
		var dynamic_shake_mod = 1.0
		if forward or backward:
			dynamic_shake_mod = 0.333
			if boost:
				dynamic_shake_mod = 0.5 
		
		shake_time += delta * engine_shake_speed * dynamic_speed_mod
		
		car_body.transform.origin.x = original_body_pos.x + (sin(shake_time) * engine_shake_amount * dynamic_shake_mod * 0.4)
		car_body.transform.origin.y = original_body_pos.y + (sin(shake_time * 1.2) * engine_shake_amount * dynamic_shake_mod)
		car_body.transform.origin.z = original_body_pos.z + (cos(shake_time * 0.9) * engine_shake_amount * dynamic_shake_mod * 0.3)


# Core function calculating Hooke's Law Spring equations + Damping via Raycast properties
func _process_suspension_spring(raycast: RayCast3D, wheel_mesh: Node3D) -> bool:
	if not raycast: return false
	
	var max_ray_extension = suspension_rest_distance + wheel_radius
	raycast.target_position = Vector3(0, -max_ray_extension - 0.2, 0)
	raycast.force_raycast_update()
	
	if raycast.is_colliding():
		var collision_point = raycast.get_collision_point()
		var raycast_origin = raycast.global_transform.origin
		var total_ray_length = raycast_origin.distance_to(collision_point)
		
		var current_spring_length = total_ray_length - wheel_radius
		var compression = suspension_rest_distance - current_spring_length
		
		var upward_spring_force = compression * spring_stiffness
		var body_velocity_at_wheel = _calculate_velocity_at_global_point(raycast.global_transform.origin)
		var spring_dir = raycast.global_transform.basis.y 
		var shock_velocity = body_velocity_at_wheel.dot(spring_dir)
		var damping_force = shock_velocity * spring_damping
		
		var total_suspension_force = (upward_spring_force - damping_force) * spring_dir
		total_suspension_force = total_suspension_force.clamp(Vector3(-500,-500,-500), Vector3(500,500,500))
		
		apply_force(total_suspension_force, raycast.global_transform.origin - global_transform.origin)
		
		if wheel_mesh:
			wheel_mesh.transform.origin.y = -current_spring_length
			
		return true
	else:
		if wheel_mesh:
			wheel_mesh.transform.origin.y = -suspension_rest_distance
		return false

func _calculate_velocity_at_global_point(global_point: Vector3) -> Vector3:
	var global_center_of_mass = global_transform.origin + global_transform.basis * center_of_mass
	var relative_point_position = global_point - global_center_of_mass
	return linear_velocity + angular_velocity.cross(relative_point_position)
