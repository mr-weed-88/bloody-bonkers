extends Camera3D

@export var smooth_speed: float = 5.0       # Higher = snappier position catch-up
@export_group("Orthographic Zoom Effect")
@export var zoom_speed: float = 4.0         # How fast the camera expands/shrinks its lens size
@export var boost_zoom_increase: float = 10.0 # How many extra units to zoom out during boost

# Kept as a generic Node3D to ensure position and tracking math NEVER fails to link
var target: Node3D
var offset: Vector3

# Dynamic tracking properties
var base_size: float
var target_size: float

func _ready() -> void:
	# 1. Automatically find your Jeep in the world scene tree
	target = get_tree().current_scene.find_child("Jeep", true, false) as Node3D
	
	if target:
		# 2. Calculate the baseline distance offset based on where you manually placed the camera
		offset = global_position - target.global_position
	else:
		push_warning("Orthographic Camera Script: Could not find your vehicle node named 'Jeep'!")
		
	# 3. Capture the initial Size property set in the inspector as our standard view baseline
	base_size = size
	target_size = base_size

func _physics_process(delta: float) -> void:
	if not target:
		return
		
	# --- POSITION TRACKING ---
	var target_position = target.global_position + offset
	global_position = global_position.lerp(target_position, smooth_speed * delta)
	
	
	# --- SMART CONTEXTUAL ZOOM ---
	# 1. Check direct keyboard/controller inputs
	var is_boosting = Input.is_action_pressed("boost_speed")
	var is_driving = Input.is_action_pressed("move_forward") or Input.is_action_pressed("move_backward")
	
	# 2. Extract grounded contact status safely via your new RayCast suspension setup
	var is_touching_ground = false
	
	# Find the 4 structural suspension raycasts on your vehicle
	var ray_fl = target.find_child("Suspension_FL", true, false) as RayCast3D
	var ray_fr = target.find_child("Suspension_FR", true, false) as RayCast3D
	var ray_rl = target.find_child("Suspension_RL", true, false) as RayCast3D
	var ray_rr = target.find_child("Suspension_RR", true, false) as RayCast3D
	
	# If any single suspension raycast is hitting the ground, the car is driving
	if (ray_fl and ray_fl.is_colliding()) or \
	   (ray_fr and ray_fr.is_colliding()) or \
	   (ray_rl and ray_rl.is_colliding()) or \
	   (ray_rr and ray_rr.is_colliding()):
		is_touching_ground = true
	
	# 3. Combine strict requirements: Input flags + actual raycast physics contact
	if is_boosting and is_driving and is_touching_ground:
		target_size = base_size + boost_zoom_increase
	else:
		target_size = base_size
		
	# Smoothly ease the orthographic sizing window back and forth
	size = lerp(size, target_size, zoom_speed * delta)
