@tool
extends Node

## Compatibility shim for the "Simulation" global used throughout Open Industry
## Project's part scripts (SixAxisRobot, Box, Pallet, conveyors, spawners, ...).
##
## The official OIP release bundles a custom Godot fork where "Simulation" is a
## native engine singleton; that fork is Windows-only today, so this autoload
## reimplements its documented signal/method surface in plain GDScript to run
## the project on stock Godot. Starts automatically shortly after the scene
## tree is ready, matching "press Play and the simulation runs".

signal started
signal stopped
signal pause_toggled(paused: bool)

var _running := false
var _paused := false


func _ready() -> void:
	# @tool is needed so this autoload is a real instance (not a placeholder)
	# while just editing, but the simulation itself should only auto-start
	# when actually playing a scene, not while idling in the bare editor.
	if not Engine.is_editor_hint():
		call_deferred("start")


func is_running() -> bool:
	return _running


func is_paused() -> bool:
	return _paused


func start() -> void:
	if _running:
		return
	_running = true
	_paused = false
	started.emit()


func stop() -> void:
	if not _running:
		return
	_running = false
	_paused = false
	stopped.emit()


func toggle_pause() -> void:
	if not _running:
		return
	_paused = not _paused
	pause_toggled.emit(_paused)
