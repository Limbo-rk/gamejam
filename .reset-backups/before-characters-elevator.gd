extends Node3D

@export_range(0.0, 60.0, 0.1) var start_delay: float = 5.0
@onready var elevator_animation: AnimationPlayer = $ElevatorAnimation

func _ready() -> void:
    # Hold the authored starting pose during the delay, then play once.
    elevator_animation.play("ElevatorRise")
    elevator_animation.seek(0.0, true)
    elevator_animation.pause()
    await get_tree().create_timer(start_delay, false).timeout
    elevator_animation.play("ElevatorRise")
