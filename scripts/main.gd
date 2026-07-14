extends Node

@onready var chase_camera: Camera3D = $Marker3D_Chase/chase_camera
@onready var tpp_camera: Camera3D = $Marker3D_TPP/tpp_camera
@onready var label: Label = $CanvasLayer/Label

# --- NEW: Add this export variable so you can reference the car ---
@onready var car: RigidBody3D = $armed_mod_jeep
# ------------------------------------------------------------------

@export var display_text: String = "Hello 3D World!" 
	
func _ready() -> void:
	label.text = display_text
	
	# Set the chase camera as the default when the game starts
	if chase_camera:
		chase_camera.make_current()

func _process(_delta: float) -> void:
	# Make sure you have "switch_camera" mapped in Project Settings -> Input Map
	if Input.is_action_just_pressed("switch_camera"):
		toggle_cameras()

	# --- NEW: Update the speedometer display every single frame ---
	if car:
		var display_speed = round(car.current_speed_display)
		label.text = str(display_speed) + " KM/H"
	# --------------------------------------------------------------

func toggle_cameras() -> void:
	if not chase_camera or not tpp_camera:
		push_warning("Main: Cameras are not assigned in the Inspector!")
		return
		
	if chase_camera.current:
		tpp_camera.make_current()
	else:
		chase_camera.make_current()
