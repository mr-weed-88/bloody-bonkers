extends RigidBody3D

@export_group("Movement Settings")
@export var speed: float = 20.0             
@export var acceleration: float = 0.08      
@export var turn_speed: float = 3.5          
@export var turn_acceleration: float = 0.3

@export_group("NOS System (NFS Style)")
@export var nos_top_speed_multiplier: float = 1.5
@export var nos_acceleration_boost: float = 0.12
@export var nos_build_up_speed: float = 2.0
@export var nos_fade_speed: float = 4.0

@export_group("Car Physics & Grip")
@export var tire_grip: float = 1        
@export var brake_strength: float = 0.4     
@export var drift_grip: float = 1.0       
@export var coast_friction: float = 0.1   
@export var coast_grip_bite: float = 0.1  
@export var coast_turn_multiplier: float = 0.2
@export var drift_fade_speed: float = 2.0

@export_group("Raycast Suspension Physics")
@export var suspension_rest_distance: float = 0.55  
@export var spring_stiffness: float = 18000.0       
@export var spring_damping: float = 2800.0          
@export var wheel_radius: float = 0.35             

@export_group("Anti-Roll System")
@export var anti_roll_stiffness: float = 10000.0    
@export var auto_upright_force: float = 8.0 # Increased for better flipping        

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

@export_group("Engine Idle Shake")
@export var engine_shake_amount: float = 0.05    
@export var engine_shake_speed: float = 100.0      

var current_wheel_roll: float = 0.0
var current_steer_angle: float = 0.0

var scale_fl: Vector3 = Vector3.ONE
var scale_fr: Vector3 = Vector3.ONE
var scale_rl: Vector3 = Vector3.ONE
var scale_rr: Vector3 = Vector3.ONE

var original_body_pos: Vector3 = Vector3.ZERO
var shake_time: float = 0.0

var current_drift_intensity: float = 0.0
var current_nos_intensity: float = 0.0 

func _ready() -> void:
	contact_monitor = false
	center_of_mass = Vector3(0, -0.6, 0)
	
	if car_body:
		original_body_pos = car_body.transform.origin
	
	if front_left_wheel: scale_fl = front_left_wheel.transform.basis.get_scale()
	if front_right_wheel: scale_fr = front_right_wheel.transform.basis.get_scale()
	if rear_left_wheel: scale_rl = rear_left_wheel.transform.basis.get_scale()
	if rear_right_wheel: scale_rr = rear_right_wheel.transform.basis.get_scale()

func _physics_process(delta: float) -> void:
	# 1. RAYCAST SUSPENSION & ANTI-ROLL BAR
	var comp_fl = _process_suspension_spring(raycast_fl, front_left_wheel)
	var comp_fr = _process_suspension_spring(raycast_fr, front_right_wheel)
	var comp_rl = _process_suspension_spring(raycast_rl, rear_left_wheel)
	var comp_rr = _process_suspension_spring(raycast_rr, rear_right_wheel)
	
	var wheels_grounded: int = 0
	if comp_fl > 0.0: wheels_grounded += 1
	if comp_fr > 0.0: wheels_grounded += 1
	if comp_rl > 0.0: wheels_grounded += 1
	if comp_rr > 0.0: wheels_grounded += 1
	
	var is_touching_ground = wheels_grounded > 0

	if is_touching_ground:
		var ar_force_front = (comp_fl - comp_fr) * anti_roll_stiffness
		var ar_force_rear = (comp_rl - comp_rr) * anti_roll_stiffness
		var up_dir = global_transform.basis.y
		
		if abs(ar_force_front) > 1.0:
			if comp_fl > 0.0: apply_force(up_dir * ar_force_front, raycast_fl.global_transform.origin - global_transform.origin)
			if comp_fr > 0.0: apply_force(up_dir * -ar_force_front, raycast_fr.global_transform.origin - global_transform.origin)
		if abs(ar_force_rear) > 1.0:
			if comp_rl > 0.0: apply_force(up_dir * ar_force_rear, raycast_rl.global_transform.origin - global_transform.origin)
			if comp_rr > 0.0: apply_force(up_dir * -ar_force_rear, raycast_rr.global_transform.origin - global_transform.origin)

	# 2. ARCADE INPUT FILTER
	var left = Input.is_action_pressed("move_left")
	var right = Input.is_action_pressed("move_right")
	var forward = Input.is_action_pressed("move_forward") if is_touching_ground else false
	var backward = Input.is_action_pressed("move_backward") if is_touching_ground else false
	var is_braking = Input.is_action_pressed("ui_accept") if is_touching_ground else false
	
	var boost = Input.is_action_pressed("boost_speed") if (is_touching_ground and forward and not backward and not is_braking) else false

	# 3. ORIENTATION & INPUT VECTORS
	var forward_vec = -global_transform.basis.z
	var right_vec = global_transform.basis.x
	var up_vec = global_transform.basis.y
	
	var forward_speed = linear_velocity.dot(forward_vec)
	var steer_input = (1.0 if left else 0.0) - (1.0 if right else 0.0)
	var drive_dir = (1.0 if forward else 0.0) - (1.0 if backward else 0.0)

	# 4. 3D HILL-CLIMBING DRIVE FORCE, COASTING & DRIFTING
	if boost:
		current_nos_intensity = move_toward(current_nos_intensity, 1.0, delta * nos_build_up_speed)
	else:
		current_nos_intensity = move_toward(current_nos_intensity, 0.0, delta * nos_fade_speed)

	var active_nos_multiplier = lerp(1.0, nos_top_speed_multiplier, current_nos_intensity)
	var current_max_speed = speed * active_nos_multiplier
	var active_grip = tire_grip 
	
	if is_touching_ground:
		var lateral_speed = linear_velocity.dot(right_vec)
		var suspension_vertical_speed = linear_velocity.dot(up_vec) 
		
		var target_forward_speed = drive_dir * current_max_speed
		var current_accel_rate = acceleration + (nos_acceleration_boost * current_nos_intensity)
		var baseline_grip = tire_grip
		
		if is_braking:
			current_accel_rate = brake_strength
			target_forward_speed = 0.0
			baseline_grip = coast_grip_bite
		elif drive_dir == 0.0:
			current_accel_rate = coast_friction
			target_forward_speed = 0.0
			baseline_grip = coast_grip_bite
		elif backward and forward_speed > 2.0: 
			current_accel_rate = brake_strength
			target_forward_speed = 0.0
			baseline_grip = coast_grip_bite

		var is_going_fast = abs(forward_speed) > 12.0
		if steer_input != 0.0 and is_going_fast and is_braking:
			current_drift_intensity = move_toward(current_drift_intensity, 1.0, delta * 4.0)
			if current_nos_intensity > 0.1: target_forward_speed *= 1.1 
		else:
			current_drift_intensity = move_toward(current_drift_intensity, 0.0, delta * drift_fade_speed)

		active_grip = lerp(baseline_grip, drift_grip, current_drift_intensity)

		var next_forward_speed = lerp(forward_speed, target_forward_speed, current_accel_rate)
		var next_lateral_speed = lerp(lateral_speed, 0.0, active_grip)

		var new_ground_velocity = (forward_vec * next_forward_speed) + (right_vec * next_lateral_speed) + (up_vec * suspension_vertical_speed)
		linear_velocity = new_ground_velocity

		if drive_dir == 0.0 and abs(forward_speed) < 1.0 and steer_input == 0.0 and current_drift_intensity < 0.1:
			linear_velocity.x = lerp(linear_velocity.x, 0.0, 5.0 * delta)
			linear_velocity.z = lerp(linear_velocity.z, 0.0, 5.0 * delta)
			angular_velocity = angular_velocity.lerp(Vector3.ZERO, 5.0 * delta)

	# 5. STEERING MOMENTUM
	var target_ang_vel = 0.0

	if is_touching_ground:
		if steer_input != 0.0:
			var gear_dir = 1.0 if forward_speed >= -0.1 else -1.0
			var speed_turn_factor = clamp(abs(forward_speed) / 8.0, 0.0, 1.4) 
			target_ang_vel = steer_input * turn_speed * speed_turn_factor * gear_dir
			
			if drive_dir == 0.0:
				target_ang_vel *= coast_turn_multiplier
		elif current_drift_intensity > 0.05:
			target_ang_vel = angular_velocity.y * 0.88

		var weight = 0.45 if (steer_input == 0.0 and current_drift_intensity < 0.1) else turn_acceleration
		angular_velocity.y = lerp(angular_velocity.y, target_ang_vel, weight)
	
	# 6. MID-AIR STRANDED AUTO-UPRIGHT FIX
	if not is_touching_ground:
		var current_up = global_transform.basis.y
		if current_up.y < 0.95: 
			var align_axis = current_up.cross(Vector3.UP)
			if align_axis.length_squared() < 0.001:
				align_axis = global_transform.basis.z
				
			angular_velocity += align_axis.normalized() * auto_upright_force * delta
			angular_velocity.x = lerp(angular_velocity.x, 0.0, 2.0 * delta)
			angular_velocity.z = lerp(angular_velocity.z, 0.0, 2.0 * delta)

	# 7. VISUAL WHEELS 
	var effective_roll_speed = forward_speed
	if is_braking and current_drift_intensity > 0.5:
		effective_roll_speed = 0.0 
	elif drive_dir == 0.0 and is_touching_ground:
		effective_roll_speed = forward_speed

	if wheel_radius > 0.0:
		current_wheel_roll += (effective_roll_speed / wheel_radius) * delta
	else:
		current_wheel_roll += effective_roll_speed * delta * 2.8
		
	current_wheel_roll = wrapf(current_wheel_roll, -PI, PI)
	
	var target_steer_angle = steer_input * 0.6 
	current_steer_angle = lerp(current_steer_angle, target_steer_angle, 0.15)

	var front_steer_basis = Basis(Vector3.UP, current_steer_angle)
	var roll_basis = Basis(Vector3.RIGHT, current_wheel_roll)
	var combined_front_basis = front_steer_basis * roll_basis

	if front_left_wheel: front_left_wheel.transform.basis = combined_front_basis.scaled(scale_fl)
	if front_right_wheel: front_right_wheel.transform.basis = combined_front_basis.scaled(scale_fr)
	if rear_left_wheel: rear_left_wheel.transform.basis = roll_basis.scaled(scale_rl)
	if rear_right_wheel: rear_right_wheel.transform.basis = roll_basis.scaled(scale_rr)

	# 8. ENGINE IDLE SHAKE 
	if car_body:
		var dynamic_shake_mod = lerp(0.2, 1.2, current_nos_intensity) if boost else (0.2 if (forward or backward) else 1.0)
		shake_time += delta * engine_shake_speed
		
		car_body.transform.origin.x = original_body_pos.x + (sin(shake_time) * engine_shake_amount * dynamic_shake_mod * 0.4)
		car_body.transform.origin.y = original_body_pos.y + (sin(shake_time * 1.2) * engine_shake_amount * dynamic_shake_mod)
		car_body.transform.origin.z = original_body_pos.z + (cos(shake_time * 0.9) * engine_shake_amount * dynamic_shake_mod * 0.3)
		car_body.transform.basis = Basis.IDENTITY

func _process_suspension_spring(raycast: RayCast3D, wheel_mesh: Node3D) -> float:
	if not raycast: return 0.0
	
	var max_ray_extension = suspension_rest_distance + wheel_radius
	raycast.target_position = Vector3(0, -max_ray_extension - 0.4, 0)
	raycast.force_raycast_update()
	
	if raycast.is_colliding():
		var collision_point = raycast.get_collision_point()
		var raycast_origin = raycast.global_transform.origin
		var total_ray_length = raycast_origin.distance_to(collision_point)
		
		var current_spring_length = total_ray_length - wheel_radius
		var compression = suspension_rest_distance - current_spring_length
		var active_stiffness = spring_stiffness
		
		if compression > (suspension_rest_distance * 0.8):
			active_stiffness *= 4.0 
		
		var upward_spring_force = compression * active_stiffness
		var body_velocity_at_wheel = _calculate_velocity_at_global_point(raycast.global_transform.origin)
		var spring_dir = raycast.global_transform.basis.y 
		var shock_velocity = body_velocity_at_wheel.dot(spring_dir)
		var damping_force = shock_velocity * spring_damping
		
		var total_suspension_force = (upward_spring_force - damping_force) * spring_dir
		
		apply_force(total_suspension_force, raycast.global_transform.origin - global_transform.origin)
		
		if wheel_mesh:
			wheel_mesh.transform.origin.y = -current_spring_length
			
		return max(0.0, compression)
	else:
		if wheel_mesh:
			wheel_mesh.transform.origin.y = -suspension_rest_distance
		return 0.0

func _calculate_velocity_at_global_point(global_point: Vector3) -> Vector3:
	var global_center_of_mass = global_transform.origin + global_transform.basis * center_of_mass
	var relative_point_position = global_point - global_center_of_mass
	return linear_velocity + angular_velocity.cross(relative_point_position)
