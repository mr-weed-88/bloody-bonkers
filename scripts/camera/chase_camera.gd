extends Camera3D

@export_category("Target & Setup")
@onready var target_vehicle: RigidBody3D = $"../../Jeep"

@export_category("Camera Positioning")
@export var base_follow_distance: float = 5.5
@export var max_speed_distance_add: float = 2.0 
@export var follow_height: float = 2.2
@export var position_smoothness: float = 8.0 

@export_category("Cinematic Drift & Feel")
@export var drift_swing_amount: float = 0.7 
@export var look_height_offset: float = 1.2
@export var look_smoothness: float = 15.0 

@export_category("Dynamic Turn Swing (The NFS Feel)")
@export var turn_swing_multiplier: float = 0.08 
@export var max_swing_distance: float = 2.5 
@export var swing_return_speed: float = 4.0 

@export_category("Dynamic Speed & FOV")
@export var base_fov: float = 75.0
@export var max_speed_fov_add: float = 15.0
@export var boost_fov_kick: float = 10.0
@export var fov_smooth_speed: float = 5.0
@export var max_expected_speed: float = 40.0 

# Internal tracking variables
var smoothed_look_target: Vector3
var current_fov: float
var current_side_offset: float = 0.0 

func _ready() -> void:
	if not target_vehicle:
		push_warning("Chase Camera: No Target Vehicle assigned in the inspector!")
		return
		
	global_position = target_vehicle.global_position + (target_vehicle.global_transform.basis.z * base_follow_distance)
	smoothed_look_target = target_vehicle.global_position
	current_fov = base_fov
	fov = current_fov

func _physics_process(delta: float) -> void:
	if not target_vehicle:
		return
		
	# 1. GET VEHICLE DATA
	var car_pos = target_vehicle.global_position
	var car_basis = target_vehicle.global_transform.basis
	var car_forward = -car_basis.z.normalized()
	var car_right = car_basis.x.normalized()
	var car_velocity = target_vehicle.linear_velocity
	var current_speed = car_velocity.length()
	
	# 2. DYNAMIC VELOCITY TRAILING
	var path_dir = car_forward 
	if current_speed > 2.0:
		path_dir = car_velocity.normalized()
		
	var blend_weight = clamp(current_speed / 15.0, 0.0, 1.0) * drift_swing_amount
	var ideal_forward = car_forward.lerp(path_dir, blend_weight).normalized()
	var ideal_backward = -ideal_forward
	
	# 3. CENTRIFUGAL TURN SWING 
	var local_ang_vel = car_basis.inverse() * target_vehicle.angular_velocity
	var turn_yaw_rate = local_ang_vel.y
	
	var target_swing = turn_yaw_rate * current_speed * turn_swing_multiplier
	target_swing = clamp(target_swing, -max_swing_distance, max_swing_distance)
	current_side_offset = lerp(current_side_offset, target_swing, swing_return_speed * delta)
	
	# 4. DYNAMIC DISTANCE SCALING
	var speed_factor = clamp(current_speed / max_expected_speed, 0.0, 1.0)
	var active_distance = base_follow_distance + (max_speed_distance_add * speed_factor)
	
	# 5. POSITION SMOOTHING
	var ideal_position = car_pos + (ideal_backward * active_distance) + (Vector3.UP * follow_height) + (car_right * current_side_offset)
	global_position = global_position.lerp(ideal_position, position_smoothness * delta)
	
	# 6. SHOCK-ABSORBED LOOK TARGET
	var ideal_look_target = car_pos + (Vector3.UP * look_height_offset)
	smoothed_look_target = smoothed_look_target.lerp(ideal_look_target, look_smoothness * delta)
	
	if global_position.distance_to(smoothed_look_target) > 0.1:
		look_at(smoothed_look_target, Vector3.UP)
		
	# 7. SENSE OF SPEED FOV
	var is_boosting = Input.is_action_pressed("boost_speed")
	var target_fov = base_fov + (max_speed_fov_add * speed_factor)
	
	if is_boosting and current_speed > 5.0:
		target_fov += boost_fov_kick
		
	current_fov = lerp(current_fov, target_fov, fov_smooth_speed * delta)
	fov = current_fov
