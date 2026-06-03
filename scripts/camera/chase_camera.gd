extends Camera3D

@export_category("Target & Setup")
@onready var target_vehicle: RigidBody3D = $"../../Jeep"

@export_category("Camera Positioning")
@export var base_follow_distance: float = 6.0
@export var max_speed_distance_add: float = 3.5 
@export var follow_height: float = 2.5
@export var position_smoothness: float = 6.0 # Lowered slightly for more rubber-band lag

@export_category("Cinematic Drift & Feel")
@export var drift_swing_amount: float = 1.5 # Increased to swing wide during drifts
@export var look_ahead_distance: float = 3.0 # Looks ahead of the car, not at the roof
@export var look_height_offset: float = 1.0
@export var look_smoothness: float = 12.0 

@export_category("Dynamic Speed & FOV")
@export var base_fov: float = 75.0
@export var max_speed_fov_add: float = 20.0 # Stretches the screen more at high speeds
@export var boost_fov_kick: float = 15.0
@export var fov_smooth_speed: float = 5.0
@export var max_expected_speed: float = 40.0 

# Internal tracking variables
var smoothed_look_target: Vector3
var current_fov: float

func _ready() -> void:
	if not target_vehicle:
		push_warning("Chase Camera: No Target Vehicle assigned!")
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
	var car_velocity = target_vehicle.linear_velocity
	var current_speed = car_velocity.length()
	
	# 2. DYNAMIC VELOCITY TRAILING (The Drift Swing)
	# This determines where the camera should sit behind the car
	var path_dir = car_forward 
	if current_speed > 3.0:
		# Blend the car's physical facing direction with its actual movement direction
		# This causes the camera to swing to the outside during a drift
		path_dir = car_velocity.normalized()
		
	var blend_weight = clamp(current_speed / 20.0, 0.0, 1.0) * drift_swing_amount
	var ideal_backward = -(car_forward.lerp(path_dir, blend_weight).normalized())
	
	# 3. DYNAMIC DISTANCE SCALING
	var speed_factor = clamp(current_speed / max_expected_speed, 0.0, 1.0)
	var active_distance = base_follow_distance + (max_speed_distance_add * speed_factor)
	
	# 4. POSITION SMOOTHING (Rubber-banding)
	var ideal_position = car_pos + (ideal_backward * active_distance) + (Vector3.UP * follow_height)
	global_position = global_position.lerp(ideal_position, position_smoothness * delta)
	
	# 5. LOOK AHEAD TARGET
	# Instead of looking at the car's center, look at where the car is going
	var forward_look_offset = car_forward * (speed_factor * look_ahead_distance)
	var ideal_look_target = car_pos + (Vector3.UP * look_height_offset) + forward_look_offset
	smoothed_look_target = smoothed_look_target.lerp(ideal_look_target, look_smoothness * delta)
	
	if global_position.distance_to(smoothed_look_target) > 0.1:
		look_at(smoothed_look_target, Vector3.UP)
		
	# 6. SENSE OF SPEED FOV
	var is_boosting = Input.is_action_pressed("boost_speed")
	var target_fov = base_fov + (max_speed_fov_add * speed_factor)
	
	if is_boosting and current_speed > 5.0:
		target_fov += boost_fov_kick
		
	current_fov = lerp(current_fov, target_fov, fov_smooth_speed * delta)
	fov = current_fov
