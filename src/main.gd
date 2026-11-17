extends Node2D
## Point d'entrée : assemble simulation, affichage, caméra et interface.
## Toucher la créature = la caresser. Toucher ailleurs = faire tomber un fruit.
## Glisser = déplacer la caméra.

## Pas fixe de simulation (5 par seconde de jeu), découplé de l'affichage.
const STEP := 0.2
const MAX_STEPS_PER_FRAME := 60
const SPEEDS: Array[float] = [1.0, 2.0, 4.0, 16.0]
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
var _accumulator := 0.0


func _ready() -> void:
	RenderingServer.set_default_clear_color(Color(0.62, 0.82, 0.95))
	world = WorldSim.new()

	var world_view := WorldView.new()
	world_view.world = world
	add_child(world_view)

	creature_view = CreatureView.new()
	creature_view.creature = _creature()
	creature_view.z_index = 1
	add_child(creature_view)

	camera = Camera2D.new()
	camera.position = Vector2(_creature().x, -180.0)
	camera.zoom = Vector2(1.0, 1.0)
	camera.limit_left = 0
	camera.limit_right = int(world.width)
	camera.limit_bottom = 200
	camera.limit_top = -560
	add_child(camera)
	camera.make_current()
	world_view.camera = camera

	hud = Hud.new()
	add_child(hud)
	hud.caress_pressed.connect(func() -> void: _creature().caress())
	hud.scold_pressed.connect(func() -> void: _creature().scold())
	hud.fruit_pressed.connect(func() -> void: world.drop_food(_creature().x + _creature().facing * 160.0))
	hud.speed_pressed.connect(func() -> void: _speed_index = (_speed_index + 1) % SPEEDS.size())
	hud.follow_pressed.connect(func() -> void: _follow = true)
	hud.new_creature_pressed.connect(_on_new_creature)


func _creature() -> CreatureSim:
	return world.creatures[0]


func _on_new_creature() -> void:
	world.replace_dead()
	creature_view.creature = _creature()
	_follow = true


func _process(delta: float) -> void:
	var speed := SPEEDS[_speed_index]
	_accumulator += minf(delta, 0.1) * speed
	var steps := 0
	while _accumulator >= STEP and steps < MAX_STEPS_PER_FRAME:
		world.tick(STEP)
		_accumulator -= STEP
		steps += 1
	if steps == MAX_STEPS_PER_FRAME:
		_accumulator = 0.0   # appareil trop lent : on ralentit plutôt que de figer

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
	if world_pos.distance_to(creature_view.body_center()) < 80.0 * c.body_size():
		c.caress()
	else:
		world.drop_food(world_pos.x)
