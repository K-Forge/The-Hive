@tool
class_name RollerSpec
extends RefCounted

## Standard roller duty classes. Each pairs a realistic tube diameter with a
## matched roller pitch, so picking a class can't produce an implausible combo.

enum DutyClass {
	LIGHT,  ## 48 mm tube, 75 mm pitch — small cartons / totes.
	MEDIUM, ## 60 mm tube, 100 mm pitch — general cartons.
	HEAVY,  ## 80 mm tube, 130 mm pitch — large/heavy cartons, totes.
}

## Radius the roller and corner meshes are authored at; meshes are scaled down to the duty radius.
const MODEL_RADIUS: float = 0.12


static func radius(duty: DutyClass) -> float:
	match duty:
		DutyClass.LIGHT:
			return 0.024
		DutyClass.HEAVY:
			return 0.04
		_:
			return 0.03


static func pitch(duty: DutyClass) -> float:
	match duty:
		DutyClass.LIGHT:
			return 0.075
		DutyClass.HEAVY:
			return 0.13
		_:
			return 0.1


static func radial_scale(duty: DutyClass) -> float:
	return radius(duty) / MODEL_RADIUS
