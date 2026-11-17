class_name Biochemistry
extends RefCounted
## Chimie d'une créature : concentrations (0 à 1), demi-vies, réactions,
## émetteurs, récepteurs et organes, tous configurés par les gènes exprimés.
## Tout est stocké en tableaux compacts pour rester rapide sur mobile.

const LN2 := 0.6931472
const BODY := 0   # organe fictif « Corps », jamais malade

var conc := PackedFloat32Array()
var loci := Loci.new()
var organs: Array[Organ] = []

var _organ_index := {}
var _half_life := PackedFloat32Array()
var _decay_dt := -1.0
var _decay := PackedFloat32Array()
var _eff := PackedFloat32Array()

# Réactions : A + B -> C + D
var _ra := PackedInt32Array()
var _rb := PackedInt32Array()
var _rc := PackedInt32Array()
var _rd := PackedInt32Array()
var _rrate := PackedFloat32Array()
var _rorg := PackedInt32Array()
var _rcond := PackedInt32Array()
var _rlo := PackedFloat32Array()
var _rhi := PackedFloat32Array()
# Émetteurs : source (substance ou locus) -> substance
var _esrc := PackedInt32Array()
var _esrc_chem := PackedByteArray()
var _einv := PackedByteArray()
var _ethr := PackedFloat32Array()
var _egain := PackedFloat32Array()
var _echem := PackedInt32Array()
var _eorg := PackedInt32Array()
# Récepteurs : substance -> locus
var _cchem := PackedInt32Array()
var _cinv := PackedByteArray()
var _cthr := PackedFloat32Array()
var _cgain := PackedFloat32Array()
var _clocus := PackedInt32Array()
var _corg := PackedInt32Array()

var _proteins := -1


func _init() -> void:
	conc.resize(Chemicals.MAX)
	_half_life.resize(Chemicals.MAX)
	organs.append(Organ.new("Corps"))
	_organ_index["Corps"] = BODY
	_proteins = Chemicals.id_of("Protéines")


## (Re)construit le métabolisme à partir des gènes exprimés.
## first_time : naissance (valeurs initiales). Sinon (changement de stade),
## les concentrations et la santé des organes sont conservées.
func configure(genes: Array[Gene], first_time: bool) -> void:
	_half_life.fill(0.0)
	_decay_dt = -1.0
	for arr in [_ra, _rb, _rc, _rd, _rrate, _rorg, _rcond, _rlo, _rhi,
			_esrc, _esrc_chem, _einv, _ethr, _egain, _echem, _eorg,
			_cchem, _cinv, _cthr, _cgain, _clocus, _corg]:
		arr.clear()
	# Organes d'abord : les autres gènes s'y rattachent.
	for g in genes:
		if g.type == Gene.Type.ORGAN:
			var n := str(g.params.get("organ", ""))
			if not _organ_index.has(n):
				_organ_index[n] = organs.size()
				organs.append(Organ.new(n))
				organs[-1].configure(g.params, loci, true)
			else:
				organs[_organ_index[n]].configure(g.params, loci, first_time)
	for g in genes:
		var p := g.params
		match g.type:
			Gene.Type.SUBSTANCE:
				var c := Chemicals.id_of(str(p.get("chem", "")))
				if c >= 0:
					_half_life[c] = float(p.get("half_life", 0.0))
					if first_time:
						conc[c] = float(p.get("initial", 0.0))
			Gene.Type.REACTION:
				var a := Chemicals.id_of(str(p.get("a", "")))
				if a < 0:
					continue
				_ra.append(a)
				_rb.append(Chemicals.id_of(str(p.get("b", ""))))
				_rc.append(Chemicals.id_of(str(p.get("c", ""))))
				_rd.append(Chemicals.id_of(str(p.get("d", ""))))
				_rrate.append(float(p.get("rate", 0.0)))
				_rorg.append(_organ_id(str(p.get("organ", "Corps"))))
				_rcond.append(Chemicals.id_of(str(p.get("cond", ""))))
				_rlo.append(float(p.get("lo", 0.0)))
				_rhi.append(float(p.get("hi", 1.0)))
			Gene.Type.EMITTER:
				var target := Chemicals.id_of(str(p.get("chem", "")))
				if target < 0:
					continue
				var src := str(p.get("source", ""))
				if src.begins_with("chem:"):
					var sc := Chemicals.id_of(src.substr(5))
					if sc < 0:
						continue
					_esrc.append(sc)
					_esrc_chem.append(1)
				else:
					_esrc.append(loci.id_of(src))
					_esrc_chem.append(0)
				_einv.append(1 if p.get("invert", false) else 0)
				_ethr.append(float(p.get("threshold", 0.0)))
				_egain.append(float(p.get("gain", 0.0)))
				_echem.append(target)
				_eorg.append(_organ_id(str(p.get("organ", "Corps"))))
			Gene.Type.RECEPTOR:
				var c := Chemicals.id_of(str(p.get("chem", "")))
				if c < 0:
					continue
				_cchem.append(c)
				_cinv.append(1 if p.get("invert", false) else 0)
				_cthr.append(float(p.get("threshold", 0.0)))
				_cgain.append(float(p.get("gain", 0.0)))
				_clocus.append(loci.id_of(str(p.get("locus", ""))))
				_corg.append(_organ_id(str(p.get("organ", "Corps"))))
	_eff.resize(organs.size())


func _organ_id(n: String) -> int:
	return _organ_index.get(n, BODY)


func add(c: int, amount: float) -> void:
	if c >= 0:
		conc[c] = clampf(conc[c] + amount, 0.0, 1.0)


func get_level(c: int) -> float:
	return conc[c] if c >= 0 else 0.0


func organ(organ_name: String) -> Organ:
	return organs[_organ_index[organ_name]] if _organ_index.has(organ_name) else null


## Un pas de métabolisme. age_s sert au vieillissement des organes.
func step(dt: float, age_s: float) -> void:
	for i in organs.size():
		_eff[i] = 1.0 if i == BODY else organs[i].efficiency()

	# Émetteurs
	for i in _esrc.size():
		var s: float = conc[_esrc[i]] if _esrc_chem[i] else loci.values[_esrc[i]]
		if _einv[i]:
			s = 1.0 - s
		var v := s - _ethr[i]
		if v > 0.0:
			var c := _echem[i]
			conc[c] = clampf(conc[c] + _egain[i] * v * dt * _eff[_eorg[i]], 0.0, 1.0)

	# Réactions
	for i in _ra.size():
		var cond := _rcond[i]
		if cond >= 0 and (conc[cond] < _rlo[i] or conc[cond] > _rhi[i]):
			continue
		var amount := conc[_ra[i]]
		if _rb[i] >= 0:
			amount = minf(amount, conc[_rb[i]])
		amount *= 1.0 - exp(-_rrate[i] * _eff[_rorg[i]] * dt)
		if amount <= 0.0:
			continue
		conc[_ra[i]] -= amount
		if _rb[i] >= 0:
			conc[_rb[i]] -= amount
		if _rc[i] >= 0:
			conc[_rc[i]] = minf(1.0, conc[_rc[i]] + amount)
		if _rd[i] >= 0:
			conc[_rd[i]] = minf(1.0, conc[_rd[i]] + amount)

	# Demi-vies
	if dt != _decay_dt:
		_decay_dt = dt
		_decay.resize(Chemicals.MAX)
		for c in Chemicals.MAX:
			_decay[c] = exp(-LN2 * dt / _half_life[c]) if _half_life[c] > 0.0 else 1.0
	for c in Chemicals.MAX:
		conc[c] *= _decay[c]

	# Récepteurs : chaque locus cible reçoit la somme de ses récepteurs
	for i in _clocus.size():
		loci.values[_clocus[i]] = 0.0
	for i in _cchem.size():
		var s := conc[_cchem[i]]
		if _cinv[i]:
			s = 1.0 - s
		var v := s - _cthr[i]
		if v > 0.0:
			loci.values[_clocus[i]] += _cgain[i] * v * _eff[_corg[i]]

	# Organes
	for i in range(1, organs.size()):
		var o := organs[i]
		var used := o.step(dt, age_s, loci.values[o.damage_locus], conc[_proteins])
		conc[_proteins] = maxf(0.0, conc[_proteins] - used)
