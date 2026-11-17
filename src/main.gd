extends Node2D
## Point d'entrée : assemble simulation, affichage, caméra, interface et sauvegarde.
## Toucher une créature = la sélectionner (si elle l'est déjà : la caresser).
## Toucher ailleurs = faire tomber un fruit. Glisser = déplacer la caméra.

## Pas fixe de simulation (5 par seconde de jeu), découplé de l'affichage.
const STEP := 0.2
const MAX_STEPS_PER_FRAME := 60
const SPEEDS: Array[float] = [1.0, 2.0, 4.0, 16.0]
const TAP_SLOP := 16.0
const SAVE_PATH := "user://crealife_sauvegarde.json"
const AUTOSAVE_PERIOD := 120.0     # secondes réelles
const EVENT_DURATION := 6.0

var world: WorldSim
var camera: Camera2D
var hud: Hud
var world_view: WorldView

var _views := {}                   # uid -> CreatureView
var _selected_uid := 0
var _speed_index := 0
var _follow := true
var _pressing := false
var _dragged := false
var _press_pos := Vector2.ZERO
var _accumulator := 0.0
var _autosave := 0.0
var _event_text := ""
var _event_timer := 0.0
var _last_world_event := ""


func _ready() -> void:
	RenderingServer.set_default_clear_color(Color(0.62, 0.82, 0.95))
	world = _load_game()
	if world == null:
		world = WorldSim.new(randi(), "normal", 2)

	world_view = WorldView.new()
	world_view.world = world
	add_child(world_view)

	camera = Camera2D.new()
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
	hud.caress_pressed.connect(func() -> void: if _selected(): _selected().caress())
	hud.scold_pressed.connect(func() -> void: if _selected(): _selected().scold())
	hud.fruit_pressed.connect(func() -> void:
		var c := _selected()
		world.drop_food(c.x + c.facing * 160.0 if c else camera.position.x))
	hud.speed_pressed.connect(func() -> void: _speed_index = (_speed_index + 1) % SPEEDS.size())
	hud.follow_pressed.connect(func() -> void: _follow = true)
	hud.next_creature_pressed.connect(_select_next)
	hud.new_game_confirmed.connect(new_game)
	hud.say_pressed.connect(func(text: String) -> void:
		var c := _selected()
		if c == null:
			return
		var found := world.say(text, c)
		if not c.alive or c.is_asleep():
			c.last_event = "%s dort et ne vous entend pas." % c.creature_name
		elif found.is_empty():
			c.last_event = "%s ne reconnaît aucun mot dans « %s »." % [c.creature_name, text]
		_event_text = c.last_event
		_event_timer = 0.0)
	hud.new_creature_pressed.connect(func() -> void:
		world.restart_lineage()
		_select_next())
	_select_next()
	var c := _selected()
	camera.position = Vector2(c.x if c else world.width * 0.5, -180.0)


func _selected() -> CreatureSim:
	for c in world.creatures:
		if c.uid == _selected_uid:
			return c
	return null


## Sélectionne la créature vivante suivante (dans l'ordre de naissance).
func _select_next() -> void:
	var alive := world.creatures.filter(func(c): return c.alive)
	if alive.is_empty():
		return
	var i := 0
	for k in alive.size():
		if alive[k].uid == _selected_uid:
			i = (k + 1) % alive.size()
	_selected_uid = alive[i].uid
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

	_sync_views()
	var c := _selected()
	if c == null:
		_select_next()
		c = _selected()
	for uid in _views:
		_views[uid].selected = uid == _selected_uid
	if _follow and c:
		camera.position.x = lerpf(camera.position.x, c.x, 1.0 - exp(-3.0 * delta))

	# Message : les grands événements du monde (naissances...) passent en priorité
	if world.last_event != _last_world_event:
		_last_world_event = world.last_event
		_event_text = world.last_event
		_event_timer = EVENT_DURATION
	_event_timer -= delta
	if _event_timer <= 0.0 and c:
		_event_text = c.last_event
	hud.update_from(c, world, _event_text, speed, _follow)

	_autosave += delta
	if _autosave >= AUTOSAVE_PERIOD:
		save_game()


## Une vue par créature : ajoute les nouvelles, retire celles qui ont disparu.
func _sync_views() -> void:
	var present := {}
	for c in world.creatures:
		present[c.uid] = true
		if not _views.has(c.uid):
			var v := CreatureView.new()
			v.creature = c
			v.z_index = 1
			add_child(v)
			_views[c.uid] = v
	for uid in _views.keys():
		if not present.has(uid):
			_views[uid].queue_free()
			_views.erase(uid)


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
	var best: CreatureView = null
	var best_d := INF
	for v in _views.values():
		var d: float = world_pos.distance_to(v.body_center())
		if d < 110.0 * v.creature.body_size() and d < best_d:
			best_d = d
			best = v
	# Panneau « Parler » ouvert : toucher un objet ou une autre créature la lui montre
	if hud.speech_open() and _selected():
		var thing := _thing_at(world_pos, best)
		if thing != null:
			_selected().show_thing(thing)
			_event_text = _selected().last_event
			_event_timer = 0.0
			return
	# Toucher l'écran d'apprentissage change ce qu'il montre
	var scr := world._first("ecran")
	if best == null and scr and Rect2(scr.x - 75.0, -scr.h - 200.0, 150.0, 110.0).has_point(world_pos):
		world.next_screen_mode()
		_event_text = "L'écran montre maintenant les %s." % WorldSim.SCREEN_MODES[world.screen.mode]
		_event_timer = EVENT_DURATION
		return
	if best == null:
		world.drop_food(world_pos.x)
	elif best.creature.uid == _selected_uid:
		best.creature.caress()
	else:
		_selected_uid = best.creature.uid
		_follow = true


## Objet ou créature (autre que la sélectionnée) le plus proche du doigt.
func _thing_at(world_pos: Vector2, _unused: CreatureView) -> Object:
	var best: Object = null
	var best_d := 90.0
	for o in world.objects:
		if o.holder != null:
			continue
		var d := world_pos.distance_to(Vector2(o.x, -o.h - 25.0))
		if d < best_d:
			best_d = d
			best = o
	for v in _views.values():
		if v.creature.uid == _selected_uid or not v.creature.alive:
			continue
		var d: float = world_pos.distance_to(v.body_center()) * 1.3   # les objets, plus petits, passent avant
		if d < best_d:
			best_d = d
			best = v.creature
	return best


# ---------------------------------------------------------- sauvegarde --

## Efface la sauvegarde et recommence avec deux nouveaux fondateurs.
func new_game() -> void:
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE_PATH))
	world = WorldSim.new(randi(), "normal", 2)
	world_view.world = world
	for v in _views.values():
		v.queue_free()
	_views.clear()
	_selected_uid = 0
	_speed_index = 0
	_accumulator = 0.0
	_last_world_event = ""
	_select_next()
	var c := _selected()
	camera.position.x = c.x if c else world.width * 0.5
	_follow = true
	_event_text = "Nouvelle partie : %s et %s viennent de naître." % [world.creatures[0].creature_name, world.creatures[1].creature_name]
	_event_timer = EVENT_DURATION
	save_game()


func save_game() -> void:
	_autosave = 0.0
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(world.to_dict()))


func _load_game() -> WorldSim:
	if not FileAccess.file_exists(SAVE_PATH):
		return null
	var data = JSON.parse_string(FileAccess.get_file_as_string(SAVE_PATH))
	if typeof(data) != TYPE_DICTIONARY:
		return null
	var w := WorldSim.from_dict(data)
	return w if not w.creatures.is_empty() else null


## Le jeu se met en pause quand l'appli passe en arrière-plan (décision D3) :
## on sauvegarde à ce moment-là, et à la fermeture.
func _notification(what: int) -> void:
	if world == null:
		return
	if what in [NOTIFICATION_APPLICATION_PAUSED, NOTIFICATION_APPLICATION_FOCUS_OUT, NOTIFICATION_WM_CLOSE_REQUEST]:
		save_game()
