class_name SaveStore
extends RefCounted
## Sauvegarde sûre :
## - écriture dans un fichier temporaire, puis remplacement (jamais de fichier
##   à moitié écrit si l'appli est tuée pendant l'enregistrement) ;
## - la sauvegarde précédente est gardée en copie de secours (.bak) ;
## - au chargement : la sauvegarde, sinon la copie de secours ; si aucune
##   n'est lisible, le fichier abîmé est mis de côté (.abimee), jamais écrasé ;
## - l'écriture (texte JSON + disque) se fait en arrière-plan.

const PATH := "user://crealife_sauvegarde.json"

var _busy := false
var _mutex := Mutex.new()


## Photographie le monde maintenant (fil principal), écrit en arrière-plan.
func save_async(world: WorldSim, path: String = PATH) -> void:
	_mutex.lock()
	var busy := _busy
	_busy = true
	_mutex.unlock()
	if busy:
		return                       # une écriture est déjà en cours : la suivante suffira
	var data := world.to_dict()
	WorkerThreadPool.add_task(func() -> void:
		write_text(path, JSON.stringify(data))
		_mutex.lock()
		_busy = false
		_mutex.unlock())


## Écriture immédiate (fermeture de l'appli, tests).
static func save_now(world: WorldSim, path: String = PATH) -> bool:
	return write_text(path, JSON.stringify(world.to_dict()))


static func write_text(path: String, text: String) -> bool:
	var tmp := path + ".tmp"
	var f := FileAccess.open(tmp, FileAccess.WRITE)
	if f == null:
		return false
	f.store_string(text)
	f.close()
	# relu pour vérifier que tout est bien sur le disque avant de remplacer
	if FileAccess.get_file_as_string(tmp).length() != text.length():
		return false
	var dir := DirAccess.open(path.get_base_dir())
	if dir == null:
		return false
	var name := path.get_file()
	if dir.file_exists(name):
		if dir.file_exists(name + ".bak"):
			dir.remove(name + ".bak")
		dir.rename(name, name + ".bak")
	return dir.rename(tmp.get_file(), name) == OK


## Rend [monde ou null, message]. Le message explique un éventuel problème.
static func load_world(path: String = PATH) -> Array:
	var tried := 0
	for p in [path, path + ".bak", path + ".tmp"]:
		if not FileAccess.file_exists(p):
			continue
		tried += 1
		var w := _read(p)
		if w != null:
			var msg := "" if p == path else "La sauvegarde était abîmée : partie reprise depuis la copie de secours."
			return [w, msg]
	if tried == 0:
		return [null, ""]
	# rien de lisible : on met le fichier de côté au lieu de l'écraser
	var dir := DirAccess.open(path.get_base_dir())
	if dir and dir.file_exists(path.get_file()):
		dir.rename(path.get_file(), path.get_file() + ".abimee")
	return [null, "La sauvegarde était illisible : elle est gardée à part (fichier .abimee), nouvelle partie."]


static func _read(p: String) -> WorldSim:
	var data = JSON.parse_string(FileAccess.get_file_as_string(p))
	if typeof(data) != TYPE_DICTIONARY or not valid(data):
		return null
	var w = WorldSim.from_dict(data)
	if w == null or w.creatures.is_empty():
		return null
	return w


## Vérifie la forme générale d'une sauvegarde avant de la charger (sinon une
## clé manquante interromprait le chargement au milieu).
static func valid(d: Dictionary) -> bool:
	for k in ["time", "creatures", "objects", "history", "next_id"]:
		if not d.has(k):
			return false
	if typeof(d.creatures) != TYPE_ARRAY or typeof(d.objects) != TYPE_ARRAY:
		return false
	for c in d.creatures:
		if typeof(c) != TYPE_DICTIONARY:
			return false
		for k in ["uid", "name", "sex", "x", "age", "genome", "biochem", "brain", "alive"]:
			if not c.has(k):
				return false
	for o in d.objects:
		if typeof(o) != TYPE_DICTIONARY or not (o.has("id") and o.has("type") and o.has("x")):
			return false
	return true
