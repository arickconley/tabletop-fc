extends Node

var muted = false:
	set(value):
		muted = value
		if muted:
			for player in players.values():
				player.stop()
var players = {}

func _ready() -> void:
	for cue in ["select", "kick", "dice", "whistle", "goal"]:
		var player = AudioStreamPlayer.new()
		player.stream = load("res://assets/audio/" + cue + ".wav")
		player.volume_db = -8
		player.max_polyphony = 2
		add_child(player)
		players[cue] = player

func play(cue: String) -> void:
	if not muted and players.has(cue):
		players[cue].play()
