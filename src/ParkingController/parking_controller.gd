extends Node3D

## Height above the pick/place point the tool travels at while carrying the car.
@export_custom(PROPERTY_HINT_NONE, "suffix:m") var hover_height: float = 1.0
## Pause between finishing one slot and starting the next.
@export_custom(PROPERTY_HINT_NONE, "suffix:s") var cycle_delay: float = 1.0
## Safety cap per move, so an unreachable target can never stall the cycle.
@export_custom(PROPERTY_HINT_NONE, "suffix:s") var max_move_time: float = 8.0
## Corner and size of the box the hive gets collision generated inside.
@export var collision_region_origin: Vector3 = Vector3(-45, -5, -5)
@export var collision_region_size: Vector3 = Vector3(55, 35, 55)

@onready var robot: SixAxisRobot = $Robot as SixAxisRobot
@onready var car: RigidBody3D = $Car/RigidBody3D as RigidBody3D
@onready var slots: Array[Node3D] = [$Slot1 as Node3D, $Slot2 as Node3D, $Slot3 as Node3D]

var _running := false
var _slot_index := 0


## The car is instanced from a scene that also carries several full copies of
## the hive model plus a gantry, all hidden. They are ~8000 mesh instances of
## dead weight, enough to stall the simulation, so drop them once at startup.
func _ready() -> void:
	for child in $Car.get_children():
		if child is Node3D and not (child as Node3D).visible:
			child.queue_free()
	_build_hive_collision()


## The hive is an imported mesh with no collision at all, so a released car
## would sink straight through its floor and walls. Generate trimesh bodies
## for the hive meshes around the parking bay only — doing the whole 450 m
## tower would be thousands of colliders for no benefit.
func _build_hive_collision() -> void:
	var hive := get_parent().get_node_or_null("Hive")
	if not hive:
		return
	var region := AABB(collision_region_origin, collision_region_size)
	for child in hive.find_children("*", "MeshInstance3D", true, false):
		var mesh_inst: MeshInstance3D = child
		if (mesh_inst.global_transform * mesh_inst.get_aabb()).intersects(region):
			mesh_inst.create_trimesh_collision()


func _enter_tree() -> void:
	Simulation.started.connect(_on_simulation_started)
	Simulation.stopped.connect(_on_simulation_stopped)


func _exit_tree() -> void:
	Simulation.started.disconnect(_on_simulation_started)
	Simulation.stopped.disconnect(_on_simulation_stopped)


func _on_simulation_started() -> void:
	if not robot or not car or slots.is_empty():
		push_warning("ParkingController: configure robot, car and slots before running")
		return
	_running = true
	_slot_index = 0
	_run_cycle()


func _on_simulation_stopped() -> void:
	_running = false


func _run_cycle() -> void:
	while _running:
		var target := slots[_slot_index]
		await _pick_and_place(target.global_position)
		if not _running:
			return
		_slot_index = (_slot_index + 1) % slots.size()
		await get_tree().create_timer(cycle_delay).timeout


func _pick_and_place(place_pos: Vector3) -> void:
	var pick_pos := car.global_position
	var up := Vector3.UP * hover_height

	await _move_tool_to(pick_pos + up)
	await _move_tool_to(pick_pos)
	robot.vacuum_on = true

	await _move_tool_to(pick_pos + up)
	await _move_tool_to(place_pos + up)
	await _move_tool_to(place_pos)
	robot.vacuum_on = false

	await _move_tool_to(place_pos + up)


## Moves the tool tip to a world position with a smooth, animated motion.
## solve_ik() snaps the joints instantly to the solution, so we snapshot the
## current pose first, jump to the solved pose to read it off, snap back
## (no frame is rendered in between), then tween to it for real.
func _move_tool_to(world_pos: Vector3) -> void:
	var start_angles := robot.get_joint_angles()
	robot.solve_ik(world_pos)
	var target_angles := robot.get_joint_angles()
	robot.move_to_position(start_angles, true)
	robot.move_to_position(target_angles, false)
	var elapsed := 0.0
	while robot.is_moving() and elapsed < max_move_time:
		await get_tree().process_frame
		elapsed += get_process_delta_time()
	if robot.is_moving():
		robot.stop_motion()
