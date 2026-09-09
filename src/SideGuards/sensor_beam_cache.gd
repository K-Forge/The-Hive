class_name SensorBeamCache

const MAX_BEAMS := 16
const BEAM_RADIUS := 0.05

static var _beams: Dictionary = {} # instance_id -> [start, end]


static func set_beam(id: int, start: Vector3, end: Vector3) -> void:
	var existing: Variant = _beams.get(id)
	if existing and existing[0] == start and existing[1] == end:
		return
	_beams[id] = [start, end]
	_apply()


static func clear_beam(id: int) -> void:
	if not _beams.erase(id):
		return
	_apply()


static func _apply() -> void:
	var mat: ShaderMaterial = SideGuardMesh.create_material()
	if mat == null:
		return
	var starts := PackedVector3Array()
	var ends := PackedVector3Array()
	starts.resize(MAX_BEAMS)
	ends.resize(MAX_BEAMS)
	var n: int = 0
	for id: int in _beams:
		if n >= MAX_BEAMS:
			break
		var beam: Array = _beams[id]
		starts[n] = beam[0]
		ends[n] = beam[1]
		n += 1
	mat.set_shader_parameter("beam_count", n)
	mat.set_shader_parameter("beam_starts", starts)
	mat.set_shader_parameter("beam_ends", ends)
