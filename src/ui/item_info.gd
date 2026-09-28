class_name ItemInfo
extends RefCounted
## Words about an item for the bag and the crafting card, written from content data (what it is for,
## which beacons burn it, what a tool gathers, what a dish gives), so every item has a description
## without a separate text file.


static func kind(db: ContentDB, id: String) -> String:
	return Loc.t("kind." + String(db.items[id]["kind"]))


static func describe(db: ContentDB, id: String) -> String:
	var it: Dictionary = db.items[id]
	var lines: PackedStringArray = []
	if it.has("beacon_fuel"):
		var uses: PackedStringArray = []
		for bid in db.beacon_order:
			var fuel: Dictionary = db.beacons[bid]["fuel"]
			if fuel.has(id):
				uses.append("%s — %d" % [Loc.beacon(db, bid), int(fuel[id])])
		lines.append(Loc.t("info.fuel") % ", ".join(uses))
	if it.has("tool"):
		var gathers: PackedStringArray = []
		for other: Dictionary in db.items.values():
			if other.has("gather") and other["gather"]["tool"] == it["tool"]["type"] and int(other["gather"].get("tool_tier", 1)) <= int(it["tool"]["tier"]):
				gathers.append(Loc.name_of(other["name"]).to_lower())
		lines.append(Loc.t("info.tool") % [int(it["tool"]["tier"]), ", ".join(gathers)])
	if it.has("food"):
		var f: Dictionary = it["food"]
		lines.append(Loc.t("info.food") % [int(f["hp"]), int(f["stamina"]), int(f["minutes"])])
	if it.has("light"):
		var l: Dictionary = it["light"]
		if l.has("fuel"):
			lines.append(Loc.t("info.lantern") % [int(l["fog_radius"]), Loc.item(db, l["fuel"]).to_lower(), int(l["minutes_per_fuel"])])
		elif float(l.get("minutes", 0.0)) > 0.0:
			lines.append(Loc.t("info.torch") % [int(l["fog_radius"]), int(l["minutes"])])
		else:
			lines.append(Loc.t("info.eternal") % int(l["fog_radius"]))
	if it.has("weapon"):
		lines.append(Loc.t("info.weapon") % [int(it["weapon"]["damage"]), int(it["weapon"]["stamina"])])
	if it.has("gather"):
		var g: Dictionary = it["gather"]
		var tool := Loc.t("tool." + String(g["tool"]))
		lines.append(Loc.t("info.gather") % [tool, Loc.region(db, g["region"])])
	var used: PackedStringArray = []
	for r: Dictionary in db.recipes.values():
		if (r["inputs"] as Dictionary).has(id):
			for out: String in r["output"]:
				if not Loc.item(db, out) in used:
					used.append(Loc.item(db, out))
	if not used.is_empty():
		var shown := used.slice(0, 5)
		lines.append(Loc.t("info.used_for") % ", ".join(shown).to_lower() + ("…" if used.size() > 5 else ""))
	return "\n".join(lines)


## "Древесина 4 · Живица 2"
static func bag_text(db: ContentDB, bag: Dictionary) -> String:
	var parts: PackedStringArray = []
	for k: String in bag:
		parts.append("%s %d" % [Loc.item(db, k), int(bag[k])])
	return " · ".join(parts)


## " Как сделать «Смольё»: Древесина 4 · Живица 2, у станции «Верстак» (строится через B)." for every
## crafted item of a bag ("" when all of it is gathered as is), so the fuel line tells where the fuel comes from.
static func how_made(db: ContentDB, bag: Dictionary) -> String:
	var out := ""
	for id: String in bag:
		var made := db.recipes_producing(id)
		if made.is_empty():
			continue
		var r: Dictionary = made[0]
		var inputs := bag_text(db, ContentDB.bag(r["inputs"]))
		var station := String(r["station"])
		if station == "hand":
			out += " " + Loc.t("info.made_hand") % [Loc.item(db, id), inputs]
		else:
			out += " " + Loc.t("info.made_at") % [Loc.item(db, id), inputs, Loc.name_of(db.pieces[station]["name"])]
	return out


## "04:05" for minutes.
static func clock(minutes: float) -> String:
	var s := maxi(0, int(minutes * 60.0))
	return "%02d:%02d" % [s / 60, s % 60]
