class_name Loc
extends RefCounted
## Language helpers. Interface strings: keys in i18n/ru.po and i18n/en.po, looked up with tr() in nodes or
## Loc.t() in static code (tests/test_i18n.gd checks every key exists in both files). Content names come
## from content/*.json ({"ru": ..., "en": ...}).


static func lang() -> String:
	return "ru" if TranslationServer.get_locale().begins_with("ru") else "en"


static func t(key: String) -> String:
	return String(TranslationServer.translate(key))


## A {"ru": ..., "en": ...} name from content.
static func name_of(d: Variant) -> String:
	if d is Dictionary:
		return String((d as Dictionary).get(lang(), (d as Dictionary).get("en", "")))
	return str(d)


static func item(db: ContentDB, id: String) -> String:
	return name_of(db.items.get(id, {}).get("name", id))


static func beacon(db: ContentDB, bid: String) -> String:
	return name_of(db.beacons[bid]["name"])


static func region(db: ContentDB, rid: String) -> String:
	return name_of(db.regions[rid]["name"])


static func chapter(db: ContentDB, rid: String) -> String:
	return name_of(db.regions[rid]["chapter"]["name"])


## "186 м" / "186 m"
static func meters(m: float) -> String:
	return "%d %s" % [roundi(m), t("unit.m")]


## A compass direction for a vector on the map (north = -z): "on the north-east".
static func direction(v: Vector2) -> String:
	var a := fposmod(rad_to_deg(atan2(v.x, -v.y)) + 22.5, 360.0)
	var keys := ["dir.n", "dir.ne", "dir.e", "dir.se", "dir.s", "dir.sw", "dir.w", "dir.nw"]
	return t(keys[int(a / 45.0) % 8])
