extends Node2D
## Point d'entrée : assemble simulation, affichage, caméra et interface.
## Toucher la créature = la caresser. Toucher ailleurs = faire tomber un fruit.
## Glisser = déplacer la caméra.

const SPEEDS: Array[float] = [1.0, 2.0, 4.0]
const TAP_SLOP := 16.0

var world: WorldSim
var camera: Camera2D
var hud: Hud
var creature_view: CreatureView

var _speed_index := 0
var _follow := true
var _pressing := false
var _dragged := false
var _press_pos := Vector2.ZERO


func _ready() -> void:
	RenderingServer.set_default_clear_color(Color(0.62, 0.82, 0.95))
	world = WorldSim.new()

	var world_view := WorldView.new()
	world_view.world = world
	add_child(world_view)

	creature_view = CreatureView.new()
	creature_view.creature = _creature()
	add_child(creature_view)

	camera = Camera2D.new()
	camera.position = Vector2(_creature().x, -150.0)
	camera.zoom = Vector2(1.3, 1.3)
	camera.limit_left = 0
	camera.limit_right = int(world.width)
	camera.limit_bottom = 200
	add_child(camera)
	camera.make_current()

	hud = Hud.new()
	add_child(hud)
	hud.caress_pressed.connect(func() -> void: _creature().caress())
	hud.scold_pressed.connect(func() -> void: _creature().scold())
	hud.fruit_pressed.connect(func() -> void: world.drop_food(_creature().x + _creature().facing * 160.0))
	hud.speed_pressed.connect(func() -> void: _speed_index = (_speed_index + 1) % SPEEDS.size())
	hud.follow_pressed.connect(func() -> void: _follow = true)


func _creature() -> CreatureSim:
	return world.creatures[0]


func _process(delta: float) -> void:
	var speed := SPEEDS[_speed_index]
	# Sous-pas : la simulation reste stable même en accéléré.
	var steps := int(ceil(speed))
	var dt := minf(delta, 0.1) * speed / steps
	for i in steps:
		world.tick(dt)

	if _follow:
		camera.position.x = lerpf(camera.position.x, _creature().x, 1.0 - exp(-3.0 * delta))
	hud.update_from(_creature(), speed, _follow)


func _unhandled_input(event: InputEvent) -> void:
	# Les événements souris sont aussi produits par le tactile sur Android.
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_pressing = true
			_dragged = false
			_press_pos = event.position
		else:
			if _pressing and not _dragged:
				_on_tap(event.position)
			_pressing = false
	elif event is InputEventMouseMotion and _pressing:
		if not _dragged and event.position.distance_to(_press_pos) > TAP_SLOP:
			_dragged = true
			_follow = false
		if _dragged:
			camera.position.x = clampf(camera.position.x - event.relative.x / camera.zoom.x, 0.0, world.width)


func _on_tap(screen_pos: Vector2) -> void:
	var world_pos := get_canvas_transform().affine_inverse() * screen_pos
	var c := _creature()
	if world_pos.distance_to(creature_view.body_center()) < 80.0 * c.size:
		c.caress()
	else:
		world.drop_food(world_pos.x)
