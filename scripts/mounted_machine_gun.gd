extends Node3D

@export_category("Gun Settings")
@export var fire_rate: float = 0.1      # Time between shots
@export var weapon_damage: float = 15.0
@export var max_range: float = 1000.0

@export_category("Mouse Aiming")
@export var rotation_smoothness: float = 50.0  # Higher = snappier, Lower = smoother
@export var min_pitch_deg: float = -30.0       # Maximum downward angle
@export var max_pitch_deg: float = 60.0        # Maximum upward angle

@export_category("Recoil Settings")
@export var recoil_pitch_kick: float = 3.0     # How many degrees the gun kicks UP
@export var recoil_yaw_kick: float = 0.5       # Random horizontal kick (spread)
@export var recoil_time_in: float = 0.02       # Speed of the backward kick
@export var recoil_time_out: float = 0.08      # Speed of returning to center

@onready var gun_ray: RayCast3D = $mounted_mg/gun_pivot/Gun_Barrel_Ray
@onready var turret_pivot: Node3D = $mounted_mg/gun_pivot
@onready var _50_cal_shell: Node3D = $"mounted_mg/gun_pivot/body/50_cal_shell"
@onready var _50_mg_shell: MeshInstance3D = $"mounted_mg/gun_pivot/body/50_cal_shell/50_mg_shell"

@onready var cpu_particles_3d: CPUParticles3D = $mounted_mg/gun_pivot/CPUParticles3D

const HALF_PI = PI / 2.0

# Independent angle tracking
var target_yaw: float = 0.0
var target_pitch: float = 0.0
var current_yaw: float = 0.0
var current_pitch: float = 0.0

# Recoil tracking
var current_recoil_pitch: float = 0.0
var current_recoil_yaw: float = 0.0
var recoil_tween: Tween

var fire_timer: float = 0.0

func _ready() -> void:
	# Confines the cursor inside the game window so it can move freely as a crosshair
	Input.mouse_mode = Input.MOUSE_MODE_CONFINED

func _input(event: InputEvent) -> void:
	# Press Escape to free your mouse cursor from the window restriction while testing
	if event.is_action_pressed("ui_cancel"):
		if Input.mouse_mode == Input.MOUSE_MODE_CONFINED:
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		else:
			Input.mouse_mode = Input.MOUSE_MODE_CONFINED

func _physics_process(delta: float) -> void:
	if fire_timer > 0.0:
		fire_timer -= delta
		
	# 1. SCREEN-TO-3D MOUSE POSITION TRACKING
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

	# 2. SMOOTH ROTATION INTERPOLATION
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
	
	# Trigger the recoil animation
	apply_recoil()
	
	# Trigger the shell particle system emission burst
	if cpu_particles_3d:
		cpu_particles_3d.restart()
	
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
	if recoil_tween and recoil_tween.is_valid():
		recoil_tween.kill()
		
	recoil_tween = get_tree().create_tween()
	
	var rand_yaw = deg_to_rad(randf_range(-recoil_yaw_kick, recoil_yaw_kick))
	var target_kick_pitch = -deg_to_rad(recoil_pitch_kick)
	
	recoil_tween.tween_property(self, "current_recoil_pitch", target_kick_pitch, recoil_time_in).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_SINE)
	recoil_tween.parallel().tween_property(self, "current_recoil_yaw", rand_yaw, recoil_time_in).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_SINE)
	
	recoil_tween.chain().tween_property(self, "current_recoil_pitch", 0.0, recoil_time_out).set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_SINE)
	recoil_tween.parallel().tween_property(self, "current_recoil_yaw", 0.0, recoil_time_out).set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_SINE)

func create_tracer(start_pos: Vector3, end_pos: Vector3) -> void:
	if start_pos.distance_squared_to(end_pos) < 0.1:
		return

	var tracer = MeshInstance3D.new()
	var mesh = BoxMesh.new()
	
	var distance = start_pos.distance_to(end_pos)
	mesh.size = Vector3(0.05, 0.05, distance) 
	tracer.mesh = mesh
	
	var mat = StandardMaterial3D.new()
	mat.albedo_color = Color(1.0, 1.0, 0.5) 
	mat.emission_enabled = true
	mat.emission = Color(1.0, 0.8, 0.0)     
	mat.emission_energy_multiplier = 8.0
	tracer.material_override = mat
	
	get_tree().root.add_child(tracer)
	
	tracer.global_position = start_pos.lerp(end_pos, 0.5)
	tracer.look_at(end_pos, Vector3.UP)
	
	var tween = get_tree().create_tween()
	tween.tween_property(tracer, "scale", Vector3(0.0, 0.0, 1.0), 0.05)
	tween.tween_callback(tracer.queue_free)
