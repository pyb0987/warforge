extends SceneTree
## Diagnostic runner entry point (thin wrapper).
## Delegates to diagnostic_game.gd after autoloads are registered.
##
## Usage:
##   godot --headless --path godot/ -s sim/diagnostic_runner.gd -- \
##     --strategy=hybrid --seed=42

func _init() -> void:
	process_frame.connect(_run, CONNECT_ONE_SHOT)


func _run() -> void:
	var DiagClass = load("res://sim/diagnostic_game.gd")
	var args := {}
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--strategy="):
			args["strategy"] = arg.substr(11)
		elif arg.begins_with("--seed="):
			args["seed"] = arg.substr(7).to_int()
		elif arg.begins_with("--genome="):
			args["genome"] = arg.substr(9)

	var diag = DiagClass.new()
	diag.run_game(args)
	quit(0)
