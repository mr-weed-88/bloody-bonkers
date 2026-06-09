extends Camera3D

@export_group("Tracking")
@export var target: Node3D 
@export var smooth_speed: float = 5.0
@onready var target_vehicle: RigidBody3D = $"../../Mod_Jeep"

# NEW: Automatically pushes the camera node back to prevent environment clipping
@export var physical_distance_buffer: float = 120.0 

@export_group("Orthographic Zoom Effect")
@export var zoom_speed: float = 4.0
@export var boost_zoom_increase: float = 10.0

# Internal variables
var offset: Vector3
var base_size: float
var target_size: float

func _ready() -> void:
	if not target:
		target = target_vehicle
	
	if target:
		# Calculate the direction angle from the editor placement, 
		# then force it out to our safe physical distance buffer.
		var raw_offset = global_position - target.global_position
		offset = raw_offset.normalized() * physical_distance_buffer
	else:
		push_error("Orthographic Camera: No target found!")
		
	base_size = size
	target_size = base_size

func _physics_process(delta: float) -> void:
	if not target:
		return
		
	# 1. POSITION TRACKING (World Space)
	var target_position = target.global_position + offset
	global_position = global_position.lerp(target_position, smooth_speed * delta)
	
	# 2. CAMERA LOOK (Locked to World Up)
	look_at(target.global_position, Vector3.UP)
	
	# 3. SMART CONTEXTUAL ZOOM
	var is_boosting = Input.is_action_pressed("boost_speed")
	var is_driving = Input.is_action_pressed("move_forward") or Input.is_action_pressed("move_backward")
	
	# Raycast checks
	var ray_fl = target.find_child("Suspension_FL", true, false) as RayCast3D
	var ray_fr = target.find_child("Suspension_FR", true, false) as RayCast3D
	var ray_rl = target.find_child("Suspension_RL", true, false) as RayCast3D
	var ray_rr = target.find_child("Suspension_RR", true, false) as RayCast3D
	
	var is_touching_ground = false
	if (ray_fl and ray_fl.is_colliding()) or (ray_fr and ray_fr.is_colliding()) or \
	   (ray_rl and ray_rl.is_colliding()) or (ray_rr and ray_rr.is_colliding()):
		is_touching_ground = true
	
	if is_boosting and is_driving and is_touching_ground:
		target_size = base_size + boost_zoom_increase
	else:
		target_size = base_size
		
	size = lerp(size, target_size, zoom_speed * delta)
