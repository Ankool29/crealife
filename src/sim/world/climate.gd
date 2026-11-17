class_name Climate
extends RefCounted
## Climat (phase 5) : jour et nuit, saisons, météo et température.
##
## - Une journée dure DAY secondes de jeu (24 min), une saison SEASON (1 h) :
##   une année de 4 h, une créature en vit deux et demie.
## - La météo change toutes les 5 à 15 min selon la saison : beau, nuageux,
##   pluie (neige s'il gèle).
## - La température dehors dépend de la saison, de l'heure et de la météo ;
##   dedans (salle d'apprentissage), elle reste douce.

const DAY := 1440.0
const SEASON := 3600.0
const SEASONS: Array[String] = ["Printemps", "Été", "Automne", "Hiver"]
const SEASON_TEMP: Array[float] = [14.0, 25.0, 11.0, -1.0]
## Fruits produits par les arbres selon la saison (multiplicateur).
const SEASON_FRUIT: Array[float] = [1.0, 1.2, 0.8, 0.3]
const WEATHERS: Array[String] = ["beau", "nuageux", "pluie"]
## Probabilités de beau / nuageux / pluie selon la saison.
const WEATHER_ODDS := [[0.45, 0.3, 0.25], [0.65, 0.25, 0.1], [0.3, 0.35, 0.35], [0.35, 0.35, 0.3]]
const INDOOR_TEMP := 19.0
const START_HOUR := 8.0          # une partie commence le matin

var weather := 0                 # indice dans WEATHERS
var _weather_left := 600.0
var _wobble := 0.0               # petite variation lente de température


## Heure de la journée (0..24).
func hour(time: float) -> float:
	return fposmod(time / DAY * 24.0 + START_HOUR, 24.0)


func day_number(time: float) -> int:
	return int((time / DAY * 24.0 + START_HOUR) / 24.0) + 1


func season(time: float) -> int:
	return int(time / SEASON) % 4


## Lumière du jour dehors : 1 en plein jour, 0 la nuit, transitions à l'aube
## (6 h - 8 h) et au crépuscule (19 h - 21 h).
func daylight(time: float) -> float:
	var h := hour(time)
	return clampf(minf((h - 6.0) / 2.0, (21.0 - h) / 2.0), 0.0, 1.0)


func is_raining() -> bool:
	return weather == 2


## Neige : précipitations par temps de gel.
func is_snowing(time: float) -> bool:
	return is_raining() and outdoor_temp(time) < 2.0


## Température extérieure en °C.
func outdoor_temp(time: float) -> float:
	var s := season(time)
	# transition douce entre deux saisons
	var into := fposmod(time, SEASON) / SEASON
	var base := SEASON_TEMP[s]
	if into > 0.8:
		base = lerpf(base, SEASON_TEMP[(s + 1) % 4], (into - 0.8) / 0.2)
	var daily := 5.0 * sin((hour(time) - 9.0) / 24.0 * TAU)      # plus chaud vers 15 h
	var w: float = [0.0, -1.5, -3.5][weather]
	return base + daily + w + _wobble


func tick(dt: float, rng: RandomNumberGenerator, time: float) -> void:
	_weather_left -= dt
	_wobble = clampf(_wobble + rng.randfn(0.0, 0.05) * sqrt(dt), -2.0, 2.0)
	if _weather_left <= 0.0:
		_weather_left = rng.randf_range(300.0, 900.0)
		var odds: Array = WEATHER_ODDS[season(time)]
		var r := rng.randf()
		weather = 0 if r < odds[0] else (1 if r < odds[0] + odds[1] else 2)


func describe(time: float) -> String:
	var w := "neige" if is_snowing(time) else WEATHERS[weather]
	return "%s, jour %d, %d h · %d °C, %s" % [SEASONS[season(time)], day_number(time), int(hour(time)),
		int(round(outdoor_temp(time))), w]


func to_dict() -> Dictionary:
	return {"weather": weather, "weather_left": _weather_left, "wobble": _wobble}


func load_dict(d: Dictionary) -> void:
	weather = int(d.get("weather", 0))
	_weather_left = float(d.get("weather_left", 600.0))
	_wobble = float(d.get("wobble", 0.0))
