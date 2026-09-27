extends Node
## Autoload "Content": the loaded game data. Scenes use Content.db; core code takes a ContentDB argument.

var db: ContentDB


func _ready() -> void:
	db = ContentDB.shared()
	var problems := db.validate()
	for p in problems:
		push_error("content: " + p)
