extends Camera3D

@export_category("Target & Setup")
@onready var target_vehicle: RigidBody3D = $"../../Jeep"

@export_category("Camera Positioning")
@export var base_follow_distance: float = 3.2   # LOWERED: Very close to the car at idle/low speeds
@export var max_speed_distance_add: float = 0.8 # LOWERED: Barely pulls back, even at absolute max speed
@export var follow_height: float = 2.6          # BALANCED: Adjusted down slightly to maintain the angle at closer range
@export var position_smoothness: float = 7.0    # INCREASED: Snappier tracking to match the tight distance

@export_category("Cinematic Drift & Turn Swing")
@export var drift_swing_amount: float = 0.6    # REDUCED: Prevents the camera from clipping or whipping too far wide
@export var steering_swing_amount: float = 1.2  # REDUCED: Keeps the framing stable at close range
@export var swing_smoothness: float = 5.0       
@export var look_ahead_distance: float = 2.5    
@export var look_height_offset: float = 0.2     # LOWERED: Keeps the camera looking slightly down at the trunk/ground
@export var look_smoothness: float = 10.0  

@export_category("Balanced Speed & FOV")
@export var base_fov: float = 72.0              
@export var max_speed_fov_add: float = 3.0      
@export var boost_fov_kick: float = 1.0         
@export var fov_smooth_speed: float = 7.0
@export var max_expected_speed: float = 110.0   

# Internal tracking variables
var smoothed_look_target: Vector3
var current_fov: float
var current_lateral_swing: Vector3 = Vector3.ZERO 

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
	var car_right = car_basis.x.normalized()
	var car_velocity = target_vehicle.linear_velocity
	var current_speed = car_velocity.length()
	
	# 2. DYNAMIC DISTANCE SCALING
	var speed_factor = clamp(current_speed / max_expected_speed, 0.0, 1.0)
	var active_distance = base_follow_distance + (max_speed_distance_add * speed_factor)
	
	# 3. DYNAMIC VELOCITY TRAILING (Drift Outward Slide)
	var path_dir = car_forward 
	if current_speed > 3.0:
		path_dir = car_velocity.normalized()
		
	var blend_weight = clamp(current_speed / 20.0, 0.0, 1.0) * drift_swing_amount
	var ideal_backward = -(car_forward.lerp(path_dir, blend_weight).normalized())
	
	# 4. ACTIVE CORNERING PROFILE SWING (Smoothed Side-Profile Reveal)
	var turning_force = target_vehicle.angular_velocity.y
	var target_lateral_offset = car_right * (turning_force * steering_swing_amount * lerp(0.5, 1.0, speed_factor))
	
	current_lateral_swing = current_lateral_swing.lerp(target_lateral_offset, swing_smoothness * delta)
	
	# 5. POSITION SMOOTHING & ASSEMBLY
	var ideal_position = car_pos + (ideal_backward * active_distance) + (Vector3.UP * follow_height) + current_lateral_swing
	global_position = global_position.lerp(ideal_position, position_smoothness * delta)
	
	# 6. LOOK AHEAD TARGET
	var forward_look_offset = car_forward * (speed_factor * look_ahead_distance)
	var ideal_look_target = car_pos + (Vector3.UP * look_height_offset) + forward_look_offset
	smoothed_look_target = smoothed_look_target.lerp(ideal_look_target, look_smoothness * delta)
	
	if global_position.distance_to(smoothed_look_target) > 0.1:
		look_at(smoothed_look_target, Vector3.UP)
		
	# 7. BALANCED SENSE OF SPEED FOV
	var is_boosting = Input.is_action_pressed("boost_speed")
	var target_fov = base_fov + (max_speed_fov_add * speed_factor)
	
	if is_boosting and current_speed > 5.0:
		target_fov += boost_fov_kick
		
	current_fov = lerp(current_fov, target_fov, fov_smooth_speed * delta)
	fov = current_fov	
