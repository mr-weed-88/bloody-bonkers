extends Node3D

@export_category("Gun Settings")
@export var fire_rate: float = 0.08      # Time between shots
@export var weapon_damage: float = 15.0
@export var max_range: float = 1000.0

@export_category("Audio Settings")
@export var sound_pitch_variation: float = 0.1 # Changes pitch slightly per shot for variety

@export_category("Mouse Aiming")
@export var rotation_smoothness: float = 50.0  # Higher = snappier, Lower = smoother
@export var min_pitch_deg: float = -30.0       # Maximum downward angle
@export var max_pitch_deg: float = 60.0        # Maximum upward angle

@export_category("Spray Pattern Settings")
@export var recoil_pitch_kick: float = 0.5     # (Was 1.0) Less vertical climb per shot
@export var recoil_yaw_kick: float = 0.3       # (Was 1.5) Drastically reduces the width of the "8"
@export var max_recoil_pitch: float = 6.0      # (Was 15.0) Stops the gun from kicking too high overall
@export var max_recoil_yaw: float = 2.5        # (Was 10.0) The "cage" for the 8-pattern is now much tighter
@export var pattern_zigzag_speed: float = 0.4  # Keep the same rhythm, just smaller movements
@export var random_spread: float = 0.1         # (Was 0.3) Keeps the bullets closer to the crosshair
@export var recoil_snap_speed: float = 30.0    
@export var recoil_recovery_speed: float = 7.0 
@export var recoil_recovery_delay: float = 0.1

@onready var gun_ray: RayCast3D = $mounted_mg/gun_pivot/Gun_Barrel_Ray
@onready var turret_pivot: Node3D = $mounted_mg/gun_pivot
@onready var cpu_particles_3d: CPUParticles3D = $mounted_mg/gun_pivot/CPUParticles3D

# Link to the audio node you just created
@onready var gun_audio: AudioStreamPlayer3D = $mounted_mg/gun_pivot/GunAudio

const HALF_PI = PI / 2.0

# Independent angle tracking
var target_yaw: float = 0.0
var target_pitch: float = 0.0
var current_yaw: float = 0.0
var current_pitch: float = 0.0

# Continuous Recoil tracking
var target_recoil_pitch: float = 0.0
var target_recoil_yaw: float = 0.0
var current_recoil_pitch: float = 0.0
var current_recoil_yaw: float = 0.0

var fire_timer: float = 0.0
var time_since_last_shot: float = 0.0
var consecutive_shots: int = 0

func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_CONFINED
	if cpu_particles_3d:
		cpu_particles_3d.emitting = false

func _input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		if Input.mouse_mode == Input.MOUSE_MODE_CONFINED:
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		else:
			Input.mouse_mode = Input.MOUSE_MODE_CONFINED

func _physics_process(delta: float) -> void:
	if fire_timer > 0.0:
		fire_timer -= delta
		
	time_since_last_shot += delta
	
	# 1. RECOIL RECOVERY LOGIC
	if time_since_last_shot > recoil_recovery_delay:
		target_recoil_pitch = lerp(target_recoil_pitch, 0.0, recoil_recovery_speed * delta)
		target_recoil_yaw = lerp(target_recoil_yaw, 0.0, recoil_recovery_speed * delta)
		consecutive_shots = 0
		
	current_recoil_pitch = lerp(current_recoil_pitch, target_recoil_pitch, recoil_snap_speed * delta)
	current_recoil_yaw = lerp(current_recoil_yaw, target_recoil_yaw, recoil_snap_speed * delta)

	# 2. SCREEN-TO-3D MOUSE POSITION TRACKING (Perfect tracking restored)
	var camera = get_viewport().get_camera_3d()
	if camera:
		var mouse_pos = get_viewport().get_mouse_position()
		
		var ray_origin = camera.project_ray_origin(mouse_pos)
		var ray_normal = camera.project_ray_normal(mouse_pos)
		var world_target = ray_origin + (ray_normal * max_range)
		
		var local_target = global_transform.affine_inverse() * world_target
		
		target_yaw = atan2(local_target.z, -local_target.x) 
		var distance_2d = Vector2(local_target.x, local_target.z).length()
		target_pitch = atan2(-local_target.y, distance_2d)  
		
		target_yaw = clamp(target_yaw, -HALF_PI, HALF_PI)
		target_pitch = clamp(target_pitch, deg_to_rad(min_pitch_deg), deg_to_rad(max_pitch_deg))

	current_yaw = lerp_angle(current_yaw, target_yaw, rotation_smoothness * delta)
	current_pitch = lerp_angle(current_pitch, target_pitch, rotation_smoothness * delta)
	
	# 3. APPLY AIM AND RECOIL OFFSETS COMBINED
	if turret_pivot:
		turret_pivot.rotation.y = current_yaw + current_recoil_yaw
		turret_pivot.rotation.z = current_pitch + current_recoil_pitch

	# 4. SHOOT INPUT
	if Input.is_action_pressed("shoot") and fire_timer <= 0.0:
		shoot()

func shoot() -> void:
	fire_timer = fire_rate
	apply_recoil()
	
	# PLAY SOUND WITH RANDOMIZED PITCH
	if gun_audio and gun_audio.stream:
		gun_audio.pitch_scale = 1.0 + randf_range(-sound_pitch_variation, sound_pitch_variation)
		gun_audio.play()
	
	# CLONING LOGIC FOR SHELLS
	if cpu_particles_3d:
		var shell_clone = cpu_particles_3d.duplicate() as CPUParticles3D
		get_tree().root.add_child(shell_clone)
		shell_clone.global_transform = cpu_particles_3d.global_transform
		shell_clone.emitting = true
		get_tree().create_timer(shell_clone.lifetime + 0.1).timeout.connect(shell_clone.queue_free)
	
	gun_ray.force_raycast_update()
	
	var hit_point: Vector3
	if gun_ray.is_colliding():
		hit_point = gun_ray.get_collision_point()
		var target = gun_ray.get_collider()
		if target.has_method("take_damage"):
			target.take_damage(weapon_damage)
	else:
		hit_point = gun_ray.to_global(gun_ray.target_position)
		
	create_tracer(gun_ray.global_position, hit_point)

func apply_recoil() -> void:
	time_since_last_shot = 0.0
	consecutive_shots += 1
	
	# PITCH: Climb Upwards
	var kick_pitch = -deg_to_rad(recoil_pitch_kick)
	target_recoil_pitch += kick_pitch
	target_recoil_pitch = max(target_recoil_pitch, -deg_to_rad(max_recoil_pitch))
	
	# YAW: Spray Pattern 
	var pattern_drift = sin(consecutive_shots * pattern_zigzag_speed) 
	var random_variance = randf_range(-random_spread, random_spread) 
	
	var kick_yaw = (pattern_drift + random_variance) * deg_to_rad(recoil_yaw_kick)
	target_recoil_yaw += kick_yaw
	target_recoil_yaw = clamp(target_recoil_yaw, -deg_to_rad(max_recoil_yaw), deg_to_rad(max_recoil_yaw))

func create_tracer(start_pos: Vector3, end_pos: Vector3) -> void:
	if start_pos.distance_squared_to(end_pos) < 0.1:
		return

	var tracer = MeshInstance3D.new()
	var mesh = BoxMesh.new()
	var distance = start_pos.distance_to(end_pos)
	mesh.size = Vector3(0.05, 0.05, distance) 
	tracer.mesh = mesh
	
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(1.0, 0.95, 0.6)
	mat.emission_enabled = true
	mat.emission = Color(1.0, 0.85, 0.1)
	mat.emission_energy_multiplier = 20.0
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	tracer.material_override = mat
	
	get_tree().root.add_child(tracer)
	tracer.global_position = start_pos.lerp(end_pos, 0.5)
	tracer.look_at(end_pos, Vector3.UP)
	
	var tween = get_tree().create_tween()
	tween.tween_property(tracer, "scale", Vector3(0.0, 0.0, 1.0), 0.05)
	tween.tween_callback(tracer.queue_free)
