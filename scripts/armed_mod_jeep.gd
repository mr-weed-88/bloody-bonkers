extends RigidBody3D

# --- NEW: Global speed variables so other scripts can read them ---
#var current_speed: float = 0.0
#var current_speed_kmh: float = 0.0
var current_speed: float = 0.0
var current_speed_display: float = 0.0
# ------------------------------------------------------------------

@export_group("Movement Settings")
@export var max_speed: float = 100.0   
@export var display_top_speed_kmh: float = 200.0    
@export var acceleration: float = 15.0      
@export var turn_speed: float = 3.0         
@export var turn_acceleration: float = 1.0

@export_group("Boost System (NFS Style)")
@export var boost_multiplier: float = 2.5
@export var max_boost_amount: float = 10.0  
@export var boost_deplete_rate: float = 3.5 
@export var boost_refill_rate: float = 1.5  
@export var boost_cooldown_time: float = 5.0       # Delay before refilling starts
@export var drift_refill_multiplier: float = 3.0   # How much faster drifting fills NOS
var current_boost: float = 10.0             
var boost_timer: float = 0.0                       # Internal cooldown tracker

@export_group("Car Physics & Grip")
@export var tire_grip: float = 1.0      
@export var brake_strength: float = 20.0    
@export var drift_grip: float = 0.1        # UPDATED: Lowered from 1.0 so the car actually slides

@export_group("Heavy Vehicle Physics")
@export var custom_gravity_scale: float = 5.0 

@export_group("Raycast Suspension Physics")
@export var suspension_rest_distance: float = 0.8
@export var spring_stiffness: float = 80.0
@export var spring_damping: float = 8.0
@export var wheel_radius: float = 0.50

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
@export var suspension_lean_roll: float = 0.08     
@export var suspension_dive_pitch: float = 0.03   
@export var lean_return_speed: float = 12.0 # UPDATED: Bumped to 12.0 to smooth out chassis snap

@export_group("Engine Idle Shake")
@export var engine_shake_amount: float = 0.10
@export var engine_shake_speed: float = 20.0      

# FIXED: Split rolling trackers to calculate realistic wheel-ground velocities
var current_front_wheel_roll: float = 0.0
var current_rear_wheel_roll: float = 0.0
var current_steer_angle: float = 0.0

var scale_fl: Vector3 = Vector3.ONE
var scale_fr: Vector3 = Vector3.ONE
var scale_rl: Vector3 = Vector3.ONE
var scale_rr: Vector3 = Vector3.ONE

var original_body_pos: Vector3 = Vector3.ZERO
var current_pitch: float = 0.0
var current_roll: float = 0.0
var shake_time: float = 0.0

func _ready() -> void:
	contact_monitor = false
	gravity_scale = custom_gravity_scale
	
	if car_body:
		original_body_pos = car_body.transform.origin
	
	if front_left_wheel: scale_fl = front_left_wheel.transform.basis.get_scale()
	if front_right_wheel: scale_fr = front_right_wheel.transform.basis.get_scale()
	if rear_left_wheel: scale_rl = rear_left_wheel.transform.basis.get_scale()
	if rear_right_wheel: scale_rr = rear_right_wheel.transform.basis.get_scale()

func _physics_process(delta: float) -> void:
	gravity_scale = custom_gravity_scale

	# 1. SUSPENSION & GROUNDING
	var wheels_grounded: int = 0
	
	if _process_suspension_spring(raycast_fl, front_left_wheel): wheels_grounded += 1
	if _process_suspension_spring(raycast_fr, front_right_wheel): wheels_grounded += 1
	if _process_suspension_spring(raycast_rl, rear_left_wheel): wheels_grounded += 1
	if _process_suspension_spring(raycast_rr, rear_right_wheel): wheels_grounded += 1
	
	var is_touching_ground = wheels_grounded > 0

	# 2. ARCADE INPUT FILTER
	var left = Input.is_action_pressed("move_left")
	var right = Input.is_action_pressed("move_right")
	var forward = Input.is_action_pressed("move_forward")
	var backward = Input.is_action_pressed("move_backward")
	var boost = Input.is_action_pressed("boost_speed") if is_touching_ground else false
	var is_braking = Input.is_action_pressed("ui_accept") if is_touching_ground else false

	# 3. ORIENTATION & SPEED TRACKING
	var forward_vec = -global_transform.basis.z
	var right_vec = global_transform.basis.x
	var forward_speed = linear_velocity.dot(forward_vec)
	
	# --- NEW: Store the calculated speed so UI/Cameras can access it ---
	current_speed = forward_speed

	var speed_ratio_display = clamp(
		abs(forward_speed) / max_speed,
		0.0,
		1.0
	)

	current_speed_display = speed_ratio_display * display_top_speed_kmh
	# -------------------------------------------------------------------
	
	var speed_ratio = clamp(abs(forward_speed) / max_speed, 0.0, 1.0) 
	var steer_input = (1.0 if left else 0.0) - (1.0 if right else 0.0)

	# 4. BOOST INTENT
	var is_boosting = false
	if boost and current_boost > 0.0 and (forward or backward):
		is_boosting = true

	# 5. DRIVE FORCE, TORQUE CURVE & GRIP
	var current_max_speed = max_speed * boost_multiplier if is_boosting else max_speed
	var is_drifting = false
	
	if is_touching_ground:
		var drive_dir = (1.0 if forward else 0.0) - (1.0 if backward else 0.0)
		var lateral_speed = linear_velocity.dot(right_vec)

		var target_forward_speed = drive_dir * current_max_speed
		var next_forward_speed = forward_speed

		var current_acceleration = acceleration
		if speed_ratio < 0.4 and drive_dir != 0:
			current_acceleration *= 1.8 

		# DRIFT & BRAKE LOGIC
		if is_braking:
			# UPDATED: Changed threshold from 15.0 to 30.0
			if abs(forward_speed) > 40.0 and steer_input != 0.0:
				is_drifting = true
				if drive_dir == 0.0:
					next_forward_speed = move_toward(forward_speed, 0.0, (brake_strength * 0.25) * delta)
				else:
					next_forward_speed = move_toward(forward_speed, target_forward_speed, current_acceleration * delta)
			else:
				target_forward_speed = 0.0
				next_forward_speed = move_toward(forward_speed, target_forward_speed, brake_strength * delta)
		else:
			if drive_dir == 0.0:
				# FIXED: Progressive hill-hold deceleration to counter-act custom gravity scale on planes
				var hill_hold_force = brake_strength if abs(forward_speed) < 6.0 else (brake_strength * 0.4)
				next_forward_speed = move_toward(forward_speed, 0.0, hill_hold_force * delta)
			else:
				next_forward_speed = move_toward(forward_speed, target_forward_speed, current_acceleration * delta)
		
		# --- THE HARD CAP ---
		# This forcibly clamps the velocity so it cannot physically exceed your top limits
		next_forward_speed = clamp(next_forward_speed, -current_max_speed, current_max_speed)
		# --------------------
		
		# FIXED: Replaced loose lerp() loop with linear move_toward to completely kill lateral sliding on hills
		var target_grip = drift_grip if is_drifting else tire_grip
		var lateral_friction_limit = 55.0 * target_grip
		var next_lateral_speed = move_toward(lateral_speed, 0.0, lateral_friction_limit * delta)

		var new_ground_velocity = (forward_vec * next_forward_speed) + (right_vec * next_lateral_speed)
		linear_velocity.x = new_ground_velocity.x
		linear_velocity.z = new_ground_velocity.z

	# 5.5 BOOST GAUGE MANAGEMENT (NFS Style)
	if is_boosting:
		current_boost = max(0.0, current_boost - (boost_deplete_rate * delta))
		boost_timer = boost_cooldown_time 
	else:
		if boost_timer > 0.0:
			boost_timer -= delta
		elif abs(forward_speed) > 10.0:
			var active_refill = boost_refill_rate
			if is_drifting:
				active_refill *= drift_refill_multiplier
			current_boost = min(max_boost_amount, current_boost + (active_refill * delta))

	# 6. DYNAMIC STEERING WEIGHT
	var target_ang_vel = 0.0

	if steer_input != 0.0:
		if is_touching_ground:
			var gear_dir = 1.0 if forward_speed >= -0.1 else -1.0
			
			var dynamic_turn_speed = lerp(turn_speed, turn_speed * 0.6, speed_ratio)
			if is_drifting:
				# UPDATED: Lowered from 1.5 to 1.15 to prevent the violent over-rotation
				dynamic_turn_speed = turn_speed * 1.15 

			var speed_turn_factor = clamp(abs(forward_speed) / 5.0, 0.0, 1.2)
			target_ang_vel = steer_input * dynamic_turn_speed * speed_turn_factor * gear_dir
		else:
			target_ang_vel = steer_input * turn_speed * 0.3 

	angular_velocity.y = lerp(angular_velocity.y, target_ang_vel, turn_acceleration)
	
	# AGGRESSIVE STABILIZATION
	var stabilize_rate = 0.25 if is_touching_ground else 0.8 
	angular_velocity.x = lerp(angular_velocity.x, 0.0, stabilize_rate)
	angular_velocity.z = lerp(angular_velocity.z, 0.0, stabilize_rate)

	# 7. FIXED: ACCURATE VISUAL WHEEL ROTATION
	var target_steer_angle = steer_input * 0.45 
	current_steer_angle = lerp(current_steer_angle, target_steer_angle, 0.2)

	var rear_roll_speed = forward_speed
	
	# Calculate travel speed along the front wheels' exact steered heading in world space
	var front_steer_local = Vector3.FORWARD.rotated(Vector3.UP, current_steer_angle)
	var front_steer_world = (global_transform.basis * front_steer_local).normalized()
	var front_roll_speed = linear_velocity.dot(-front_steer_world)
	
	if is_braking and not is_drifting:
		rear_roll_speed = 0.0
		front_roll_speed = 0.0
	# Removed the faulty "elif not forward and not backward" block. 
	# Now, if you are coasting without holding W/S, the wheels will correctly keep spinning based on actual physics!

	# Flipped back to -= so it rotates the correct direction in the Y-Up/Right-Handed system.
	if wheel_radius > 0.0:
		current_front_wheel_roll -= (front_roll_speed / wheel_radius) * delta
		current_rear_wheel_roll -= (rear_roll_speed / wheel_radius) * delta
	else:
		current_front_wheel_roll -= front_roll_speed * delta * 2.8
		current_rear_wheel_roll -= rear_roll_speed * delta * 2.8
		
	current_front_wheel_roll = wrapf(current_front_wheel_roll, -PI, PI)
	current_rear_wheel_roll = wrapf(current_rear_wheel_roll, -PI, PI)

	var front_steer_basis = Basis(Vector3.UP, current_steer_angle)
	var front_roll_basis = Basis(Vector3.RIGHT, current_front_wheel_roll)
	var rear_roll_basis = Basis(Vector3.RIGHT, current_rear_wheel_roll)
	var combined_front_basis = front_steer_basis * front_roll_basis

	if front_left_wheel: front_left_wheel.transform.basis = combined_front_basis.scaled(scale_fl)
	if front_right_wheel: front_right_wheel.transform.basis = combined_front_basis.scaled(scale_fr)
	if rear_left_wheel: rear_left_wheel.transform.basis = rear_roll_basis.scaled(scale_rl)
	if rear_right_wheel: rear_right_wheel.transform.basis = rear_roll_basis.scaled(scale_rr)

	# 8. CHASSIS BODY LEAN 
	if car_body:
		var target_pitch = 0.0
		var target_roll = 0.0 
		
		if is_touching_ground:
			if (is_braking or backward) and abs(forward_speed) > 1.0:
				target_pitch = suspension_dive_pitch * 2.0 
			elif forward and forward_speed < current_max_speed:
				var boost_factor = 2.0 if is_boosting else 1.0
				target_pitch = -suspension_dive_pitch * boost_factor
			elif backward:
				target_pitch = suspension_dive_pitch

		current_pitch = lerp(current_pitch, target_pitch, lean_return_speed * delta)
		current_roll = lerp(current_roll, target_roll, lean_return_speed * delta)
		
		car_body.transform.basis = Basis.from_euler(Vector3(current_pitch, 0.0, current_roll))

		# --- ENGINE SHAKE ---
		var dynamic_speed_mod = 1.5 if is_boosting else (1.2 if (forward or backward) else 1.0)
		var dynamic_shake_mod = 1.0
		if forward or backward:
			dynamic_shake_mod = 0.333
			if is_boosting:
				dynamic_shake_mod = 0.6 
		
		shake_time += delta * engine_shake_speed * dynamic_speed_mod
		
		car_body.transform.origin.x = original_body_pos.x + (sin(shake_time) * engine_shake_amount * dynamic_shake_mod * 0.4)
		car_body.transform.origin.y = original_body_pos.y + (sin(shake_time * 1.2) * engine_shake_amount * dynamic_shake_mod)
		car_body.transform.origin.z = original_body_pos.z + (cos(shake_time * 0.9) * engine_shake_amount * dynamic_shake_mod * 0.3)

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
		
		total_suspension_force = total_suspension_force.clamp(Vector3(-2500,-2500,-2500), Vector3(2500,2500,2500))
		
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
