@tool
class_name AGVWaypoint
extends Resource

@export var position: Vector3 = Vector3.ZERO
@export_range(-180.0, 180.0, 0.1, "suffix:°") var yaw_deg: float = 0.0
