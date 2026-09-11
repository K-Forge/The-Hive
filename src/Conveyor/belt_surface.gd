@tool
class_name BeltSurface
extends RefCounted

## Shared belt-surface helpers (material, velocity, scroll). Pure static.

const BELT_SHADER: Shader = preload("res://src/Conveyor/belt_surface_shader.gdshader")
const BELT_TEXTURE: Texture2D = preload("res://assets/3DModels/Textures/4K-fabric_39-diffuse.jpg")
const BELT_TEXTURE_ALT: Texture2D = preload("res://assets/3DModels/Textures/ConvBox_Conv_text__arrows_1024.png")

## Caller must still set `Scale` (loop length) and tick `BeltPosition`.
static func create_material(color: Color, texture_style: int) -> ShaderMaterial:
	var material := ShaderMaterial.new()
	material.shader = BELT_SHADER
	material.set_shader_parameter("belt_texture", BELT_TEXTURE)
	material.set_shader_parameter("belt_texture_alt", BELT_TEXTURE_ALT)
	material.set_shader_parameter("use_alternate_texture", texture_style == BeltConveyor.BeltTexture.ALTERNATE)
	material.set_shader_parameter("ColorMix", color)
	material.set_shader_parameter("BeltPosition", 0.0)
	return material


static func apply_velocity(body: StaticBody3D, speed: float) -> void:
	if not is_instance_valid(body):
		return
	if speed == 0.0:
		body.constant_linear_velocity = Vector3.ZERO
	else:
		body.constant_linear_velocity = body.global_transform.basis.x.normalized() * speed


## Returns the new belt position wrapped to [0, 1).
static func advance_belt_position(material: ShaderMaterial,
		speed: float, delta: float, belt_position: float) -> float:
	if speed == 0.0:
		return belt_position
	var new_position: float = fmod(belt_position + speed * delta, 1.0)
	if material:
		material.set_shader_parameter("BeltPosition", new_position)
	return new_position


static func step_belt(body: StaticBody3D, material: ShaderMaterial,
		speed: float, delta: float, belt_position: float) -> float:
	apply_velocity(body, speed)
	return advance_belt_position(material, speed, delta, belt_position)
