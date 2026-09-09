@tool
class_name Building
extends Node3D

const _ROT_FRONT := 0
const _ROT_BACK := 10
const _ROT_LEFT := 16
const _ROT_RIGHT := 22

const _WALL_C := 2

const _DOCK_DOOR_SCENE := preload("res://parts/DockDoor.tscn")
const _CONTAINER_TRAILER_SCENE := preload("res://parts/ContainerTrailer.tscn")
const _DOOR_FALLBACK_WALL := 0

const _TRAILER_REAR_OFFSET := 6.16
const _TRAILER_Y_OFFSET := 1.62

const _ROOF_TRANSITION := 0
const _ROOF_TILE := 1
const _ROOF_HIDE_PITCH := 80.0

const SECTION_SIZE := 10.0
const FULL_WALL_HEIGHT := 12.0
const HALF_WALL_HEIGHT := 6.0

## Number of wall segments along the building width (each segment is 10 m).
@export_range(2, 50) var width_sections: int = 8:
	set(value):
		width_sections = value
		_generate_building()

## Number of wall segments along the building length (each segment is 10 m).
@export_range(2, 50) var length_sections: int = 5:
	set(value):
		length_sections = value
		_generate_building()

## Number of layers stacked vertically (each layer adds ~6 m of height).
@export_range(1, 10) var height_sections: int = 1:
	set(value):
		height_sections = value
		_generate_building()

@export_group("Wall Pattern")

## Wall used for every full-wall segment that no rule overrides.
@export var default_wall: BuildingWallRule.Wall = BuildingWallRule.Wall.A:
	set(value):
		default_wall = value
		_generate_building()

## Pattern rules painted over the default, in order. Later rules win where they overlap.
@export var rules: Array[BuildingWallRule] = []:
	set(value):
		_disconnect_rules()
		rules = value
		for i in rules.size():
			if rules[i] == null:
				rules[i] = BuildingWallRule.new()
		_connect_rules()
		_generate_building()

@export_group("Visibility")

## Show the floor sections.
@export var floor_visible: bool = true:
	set(value):
		floor_visible = value
		if is_node_ready():
			floor_grid.visible = value

## Show the wall sections.
@export var walls_visible: bool = true:
	set(value):
		walls_visible = value
		if is_node_ready():
			for grid in _wall_grids:
				grid.visible = value

## Show the roof sections. The roof may still auto-hide when the camera looks down from above.
@export var roof_visible: bool = true:
	set(value):
		roof_visible = value
		if is_node_ready():
			roof_grid.visible = value
			_apply_background()

@export_group("Lighting")

enum ShadowQuality { LOW, MEDIUM, HIGH, VERY_HIGH }
const _SHADOW_ATLAS_SIZE := {
	ShadowQuality.LOW: 2048,
	ShadowQuality.MEDIUM: 4096,
	ShadowQuality.HIGH: 8192,
	ShadowQuality.VERY_HIGH: 16384,
}
@export var shadow_quality: ShadowQuality = ShadowQuality.MEDIUM:
	set(value):
		shadow_quality = value
		if is_node_ready():
			_apply_shadow_quality()

## Solid background shown in place of the sky while the roof is hidden.
@export var background_color: Color = Color(0, 0, 0):
	set(value):
		background_color = value
		if is_node_ready():
			_apply_background()

## Overall lighting brightness. Scales the key, fill and ambient together (1.0 = authored).
@export_range(0.0, 3.0, 0.05) var brightness: float = 1.0:
	set(value):
		brightness = value
		if is_node_ready():
			_apply_brightness()

@onready var floor_grid: GridMap = $Floor
@onready var walls_a_grid: GridMap = $WallsA
@onready var walls_b_grid: GridMap = $WallsB
@onready var roof_grid: GridMap = $Roof
@onready var _door_holder: Node3D = $DockDoors
@onready var world_env: WorldEnvironment = $WorldEnvironment
@onready var key_light: DirectionalLight3D = $DirectionalLight3D
@onready var fill_light: DirectionalLight3D = $DirectionalFill
@onready var _wall_grids: Array[GridMap] = [walls_a_grid, walls_b_grid]
@onready var _wall_lights: Array[DirectionalLight3D] = [
	$DirectionalWallA, $DirectionalWallB,
]

var _base_key_energy: float
var _base_fill_energy: float
var _base_wall_energy: float
var _base_ambient_energy: float


func _ready() -> void:
	_apply_structure_shadows()
	floor_grid.visible = floor_visible
	for grid in _wall_grids:
		grid.visible = walls_visible
	roof_grid.visible = roof_visible
	_base_key_energy = key_light.light_energy
	_base_fill_energy = fill_light.light_energy
	_base_wall_energy = _wall_lights[0].light_energy
	if world_env.environment:
		_base_ambient_energy = world_env.environment.ambient_light_energy
	_apply_background()
	_apply_brightness()
	_apply_shadow_quality()
	_connect_rules()
	_generate_building()


func _connect_rules() -> void:
	for rule in rules:
		if rule and not rule.changed.is_connected(_generate_building):
			rule.changed.connect(_generate_building)


func _disconnect_rules() -> void:
	for rule in rules:
		if rule and rule.changed.is_connected(_generate_building):
			rule.changed.disconnect(_generate_building)


func _apply_shadow_quality() -> void:
	var atlas_size: int = _SHADOW_ATLAS_SIZE[shadow_quality]
	RenderingServer.directional_shadow_atlas_set_size(atlas_size, false)


func _apply_background() -> void:
	if world_env.environment == null:
		return
	world_env.environment.background_color = background_color
	world_env.environment.background_mode = \
		Environment.BG_SKY if roof_grid.visible else Environment.BG_COLOR


func _apply_brightness() -> void:
	key_light.light_energy = _base_key_energy * brightness
	fill_light.light_energy = _base_fill_energy * brightness
	for light in _wall_lights:
		light.light_energy = _base_wall_energy * brightness
	if world_env.environment:
		world_env.environment.ambient_light_energy = _base_ambient_energy * brightness


func _apply_structure_shadows() -> void:
	_set_grid_cast_shadow(floor_grid, RenderingServer.SHADOW_CASTING_SETTING_OFF)
	_set_grid_cast_shadow(roof_grid, RenderingServer.SHADOW_CASTING_SETTING_OFF)
	for grid in _wall_grids:
		_set_grid_cast_shadow(grid, RenderingServer.SHADOW_CASTING_SETTING_ON)


func _set_grid_cast_shadow(grid: GridMap, setting: RenderingServer.ShadowCastingSetting) -> void:
	var lib := grid.mesh_library
	if lib == null:
		return
	for id in lib.get_item_list():
		lib.set_item_mesh_cast_shadow(id, setting)


func _process(_delta: float) -> void:
	var cam: Camera3D = _active_camera()
	if cam == null:
		return
	var pitch_down: float = rad_to_deg(asin(clampf(cam.global_transform.basis.z.y, -1.0, 1.0)))
	var ceiling_y: float = roof_grid.to_global(Vector3(0.0, FULL_WALL_HEIGHT * height_sections + HALF_WALL_HEIGHT, 0.0)).y
	var auto_hide: bool = cam.global_position.y > ceiling_y and pitch_down >= _ROOF_HIDE_PITCH
	var should_show: bool = roof_visible and not auto_hide
	if should_show != roof_grid.visible:
		roof_grid.visible = should_show
		_apply_background()


func _active_camera() -> Camera3D:
	if Engine.is_editor_hint():
		var ed_viewport: SubViewport = EditorInterface.get_editor_viewport_3d(0)
		return ed_viewport.get_camera_3d() if ed_viewport else null
	return get_viewport().get_camera_3d()


func _get_wall_bounds() -> Array[int]:
	var x_min := -floori(width_sections / 2.0)
	var x_max := x_min + width_sections
	var z_min := -floori(length_sections / 2.0)
	var z_max := z_min + length_sections
	return [x_min, x_max, z_min, z_max]


func _structure_offset() -> Vector3:
	var ox := SECTION_SIZE * (floori(width_sections / 2.0) - width_sections / 2.0)
	var oz := SECTION_SIZE * (floori(length_sections / 2.0) - length_sections / 2.0)
	return Vector3(ox, 0.0, oz)


func _apply_structure_offset() -> void:
	var off := _structure_offset()
	floor_grid.position = off
	for grid in _wall_grids:
		grid.position = off
	roof_grid.position = off
	_door_holder.position = off


func _generate_building() -> void:
	if not is_node_ready():
		return
	_apply_structure_offset()
	_generate_floor()
	_generate_walls()
	_generate_roof()
	_apply_shadow_distance()


func _apply_shadow_distance() -> void:
	var width := width_sections * SECTION_SIZE
	var length := length_sections * SECTION_SIZE
	var height := FULL_WALL_HEIGHT * height_sections + HALF_WALL_HEIGHT
	var diagonal := sqrt(width * width + length * length + height * height)
	key_light.directional_shadow_max_distance = diagonal
	fill_light.directional_shadow_max_distance = diagonal
	var wall_distance := maxf(width, length)
	for light in _wall_lights:
		light.directional_shadow_max_distance = wall_distance


func _generate_floor() -> void:
	floor_grid.clear()
	var b := _get_wall_bounds()
	var x0: int = b[0]
	var x1: int = b[1]
	var z0: int = b[2]
	var z1: int = b[3]

	for x in range(x0, x1):
		for z in range(z0, z1):
			floor_grid.set_cell_item(Vector3i(x, 0, z), 0)


func _place_wall(pos: Vector3i, item: int, rot: int) -> void:
	match rot:
		_ROT_FRONT, _ROT_RIGHT:
			walls_a_grid.set_cell_item(pos, item, rot)
		_ROT_BACK, _ROT_LEFT:
			walls_b_grid.set_cell_item(pos, item, rot)


func _generate_walls() -> void:
	for grid in _wall_grids:
		grid.clear()
	_clear_doors()
	var b := _get_wall_bounds()
	var x0: int = b[0]
	var x1: int = b[1]
	var z0: int = b[2]
	var z1: int = b[3]

	# Full wall layers: each full wall uses every other 6 m row
	for h in range(height_sections):
		var full_wall_y := h * 2
		_place_full_wall_ring_mixed(x0, x1, z0, z1, full_wall_y)

	# Top half-wall ring above the last full wall layer
	var top_half_wall_y := height_sections * 2
	_place_wall_ring(x0, x1, z0, z1, top_half_wall_y, _WALL_C)

func _place_wall_ring(x0: int, x1: int, z0: int, z1: int, y: int, item: int) -> void:
	# -Z side
	for x in range(x0, x1):
		_place_wall(Vector3i(x, y, z0), item, _ROT_FRONT)

	# +Z side
	for x in range(x0 + 1, x1 + 1):
		_place_wall(Vector3i(x, y, z1), item, _ROT_BACK)

	# -X side
	for z in range(z0 + 1, z1 + 1):
		_place_wall(Vector3i(x0, y, z), item, _ROT_LEFT)

	# +X side
	for z in range(z0, z1):
		_place_wall(Vector3i(x1, y, z), item, _ROT_RIGHT)

func _get_matching_rule(perimeter_index: int, perimeter_length: int) -> BuildingWallRule:
	var matched: BuildingWallRule = null
	for rule in rules:
		if rule and rule.matches(perimeter_index, perimeter_length):
			matched = rule
	return matched

func _place_full_wall_ring_mixed(x0: int, x1: int, z0: int, z1: int, y: int) -> void:
	var side_neg_z := x1 - x0
	var side_pos_z := x1 - x0
	var side_neg_x := z1 - z0
	var side_pos_x := z1 - z0
	var perimeter_length := side_neg_z + side_pos_z + side_neg_x + side_pos_x

	var perimeter_index := 0

	# -Z side
	for x in range(x0, x1):
		var rule := _get_matching_rule(perimeter_index, perimeter_length)
		_place_full_wall(Vector3i(x, y, z0), rule, _ROT_FRONT)
		perimeter_index += 1

	# +Z side
	for x in range(x0 + 1, x1 + 1):
		var rule := _get_matching_rule(perimeter_index, perimeter_length)
		_place_full_wall(Vector3i(x, y, z1), rule, _ROT_BACK)
		perimeter_index += 1

	# -X side
	for z in range(z0 + 1, z1 + 1):
		var rule := _get_matching_rule(perimeter_index, perimeter_length)
		_place_full_wall(Vector3i(x0, y, z), rule, _ROT_LEFT)
		perimeter_index += 1

	# +X side
	for z in range(z0, z1):
		var rule := _get_matching_rule(perimeter_index, perimeter_length)
		_place_full_wall(Vector3i(x1, y, z), rule, _ROT_RIGHT)
		perimeter_index += 1


func _place_full_wall(pos: Vector3i, rule: BuildingWallRule, rot: int) -> void:
	var item := (rule.wall if rule else default_wall) as int
	if item == BuildingWallRule.Wall.DOCK_DOOR:
		if pos.y == 0:
			_spawn_dock_door(pos, rot, rule)
		else:
			_place_wall(pos, _DOOR_FALLBACK_WALL, rot)
		return
	_place_wall(pos, item, rot)


func _spawn_dock_door(pos: Vector3i, rot: int, rule: BuildingWallRule) -> void:
	var door := _DOCK_DOOR_SCENE.instantiate() as DockDoor
	if rule:
		door.door_count = rule.door_count
		door.door_width = rule.opening_width
		door.travel_height = rule.opening_height
	_door_holder.add_child(door)
	var cell_basis := walls_a_grid.get_basis_with_orthogonal_index(rot)
	door.transform = Transform3D(cell_basis, walls_a_grid.map_to_local(pos))
	var layers := 2 if rot == _ROT_FRONT or rot == _ROT_RIGHT else 4
	door.set_render_layer(layers)

	if rule == null or rule.trailer:
		_spawn_trailers(door.transform, door.door_count, layers)


func _spawn_trailers(door_transform: Transform3D, door_count: int, layers: int) -> void:
	var opening_centers: PackedFloat32Array = [5.0] if door_count == 1 else [2.75, 7.25]
	var backed := Basis(Vector3.UP, PI)
	for cx in opening_centers:
		var trailer := _CONTAINER_TRAILER_SCENE.instantiate() as Node3D
		var local := Transform3D(backed, Vector3(cx, -_TRAILER_Y_OFFSET, -_TRAILER_REAR_OFFSET))
		trailer.transform = door_transform * local
		_door_holder.add_child(trailer)
		for mesh in trailer.find_children("*", "MeshInstance3D", true):
			(mesh as MeshInstance3D).layers = layers


func _clear_doors() -> void:
	if _door_holder == null:
		return
	for child in _door_holder.get_children():
		_door_holder.remove_child(child)
		child.queue_free()

func _get_matching_wall_y_for_roof(roof_y: int) -> int:
	var roof_local_y := roof_grid.map_to_local(Vector3i(0, roof_y, 0)).y
	var wall_cell_h := walls_a_grid.cell_size.y

	if is_zero_approx(wall_cell_h):
		return roof_y
	return roundi(roof_local_y / wall_cell_h)

func _generate_roof() -> void:
	roof_grid.clear()

	var b := _get_wall_bounds()
	var x0: int = b[0]
	var x1: int = b[1]
	var z0: int = b[2]
	var z1: int = b[3]

	# Walls now step in 6 m increments, so the top half wall is at height_sections * 2.
	# Roof grid still uses its own vertical spacing, so keep its own simpler level index.
	var lower_half_wall_y := height_sections * 2
	var upper_half_wall_y := lower_half_wall_y + 1
	var roof_y := height_sections + 1

	# Roof transitions on -Z and +Z
	for x in range(x0, x1):
		roof_grid.set_cell_item(Vector3i(x, roof_y, z0), _ROOF_TRANSITION, _ROT_FRONT)

	for x in range(x0 + 1, x1 + 1):
		roof_grid.set_cell_item(Vector3i(x, roof_y, z1), _ROOF_TRANSITION, _ROT_BACK)

	# Flat roof tiles between them
	for x in range(x0, x1):
		for z in range(z0 + 1, z1 - 1):
			roof_grid.set_cell_item(Vector3i(x, roof_y, z), _ROOF_TILE)

	# Side half walls on the ends that do not have roof transitions
	# Lower 6 m band
	for z in range(z0 + 1, z1 + 1):
		_place_wall(Vector3i(x0, lower_half_wall_y, z), _WALL_C, _ROT_LEFT)

	for z in range(z0, z1):
		_place_wall(Vector3i(x1, lower_half_wall_y, z), _WALL_C, _ROT_RIGHT)

	# Upper 6 m band
	for z in range(z0 + 1, z1 + 1):
		_place_wall(Vector3i(x0, upper_half_wall_y, z), _WALL_C, _ROT_LEFT)

	for z in range(z0, z1):
		_place_wall(Vector3i(x1, upper_half_wall_y, z), _WALL_C, _ROT_RIGHT)
