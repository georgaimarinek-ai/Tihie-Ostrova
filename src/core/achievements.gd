class_name Achievements
extends RefCounted
## Steam achievements from content/achievements.json (roadmap phase 10): an achievement is earned by the first
## world event that matches its "when" (the event's type and every other field given). No counters, no grind.


## The ids a world event earns (already earned ones included; the caller keeps what's new).
static func earned_by(db: ContentDB, e: Dictionary) -> Array[String]:
	var out: Array[String] = []
	for id: String in db.achievements:
		var when: Dictionary = db.achievements[id]["when"]
		if String(when["event"]) != String(e.get("type", "")):
			continue
		var ok := true
		for k: String in when:
			if k != "event" and String(e.get(k, "")) != String(when[k]):
				ok = false
				break
		if ok:
			out.append(id)
	return out
