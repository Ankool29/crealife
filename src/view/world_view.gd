class_name WorldView
extends Node2D
## Dessine le décor et les fruits. Le sol est à y = 0, le ciel vers les y négatifs.

const GROUND_DEPTH := 600.0

var world: WorldSim


func _process(_delta: float) -> void:
	queue_redraw()


func _draw() -> void:
	if world == null:
		return
	var w := world.width
	# Collines lointaines
	for i in 8:
		var hx := w * (i + 0.5) / 8.0
		draw_circle(Vector2(hx, 60.0), 260.0 + (i % 3) * 40.0, Color(0.55, 0.75, 0.55))
	# Sol
	draw_rect(Rect2(-400.0, 0.0, w + 800.0, GROUND_DEPTH), Color(0.45, 0.32, 0.2))
	draw_rect(Rect2(-400.0, 0.0, w + 800.0, 18.0), Color(0.36, 0.66, 0.3))
	# Arbres
	for tx in world.trees:
		draw_rect(Rect2(tx - 16.0, -170.0, 32.0, 172.0), Color(0.42, 0.27, 0.15))
		draw_circle(Vector2(tx, -210.0), 95.0, Color(0.2, 0.52, 0.24))
		draw_circle(Vector2(tx - 70.0, -175.0), 60.0, Color(0.23, 0.56, 0.26))
		draw_circle(Vector2(tx + 70.0, -180.0), 65.0, Color(0.22, 0.55, 0.25))
	# Objets (formes provisoires, remplacées par les sprites 3D)
	for o in world.objects:
		var p := Vector2(o.x, -o.h - 10.0)
		match o.type_name:
			"fruit":
				draw_circle(p, 11.0, Color(0.85, 0.15, 0.15))
				draw_line(p + Vector2(0, -10), p + Vector2(3, -17), Color(0.3, 0.2, 0.1), 3.0)
			"graine":
				draw_circle(p + Vector2(0, 4), 6.0, Color(0.8, 0.65, 0.3))
			"baie":
				draw_circle(p + Vector2(0, 2), 8.0, Color(0.45, 0.15, 0.6))
			"balle":
				draw_circle(p + Vector2(0, -4), 16.0, Color(0.95, 0.8, 0.2))
			"pierre":
				draw_circle(p + Vector2(0, 4), 14.0, Color(0.5, 0.5, 0.5))
			"distributeur":
				draw_rect(Rect2(o.x - 30, -110, 60, 110), Color(0.35, 0.4, 0.5))
				draw_circle(Vector2(o.x, -80), 16.0, Color(0.3, 0.8, 0.7) if o.cooldown <= 0.0 else Color(0.3, 0.3, 0.3))
	for bx in world.bushes:
		draw_circle(Vector2(bx, -30), 50.0, Color(0.18, 0.4, 0.2, 0.9))
