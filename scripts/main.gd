extends Node

@onready var chase_camera: Camera3D = $Marker3D_Chase/chase_camera
@onready var tpp_camera: Camera3D = $Marker3D_TPP/tpp_camera

func _ready() -> void:
	# Set the chase camera as the default when the game starts
	if chase_camera:
		chase_camera.make_current()

func _process(_delta: float) -> void:
	# Make sure you have "switch_camera" mapped in Project Settings -> Input Map
	if Input.is_action_just_pressed("switch_camera"):
		toggle_cameras()

func toggle_cameras() -> void:
	if not chase_camera or not tpp_camera:
		push_warning("Main: Cameras are not assigned in the Inspector!")
		return
		
	if chase_camera.current:
		tpp_camera.make_current()
	else:
		chase_camera.make_current()
