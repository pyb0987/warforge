class_name AITracer
extends RefCounted
## Minimal JSONL trace writer for AI decisions.
## No-op when enabled=false (default) — near-zero cost in production sims.
## Events collected in-memory during a run, flushed once at end.

var enabled: bool = false
var events: Array = []


func emit(event: Dictionary) -> void:
	if not enabled:
		return
	events.append(event)


func flush_to_file(path: String) -> Error:
	if events.is_empty():
		return OK
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return FileAccess.get_open_error()
	for ev in events:
		f.store_line(JSON.stringify(ev))
	f.close()
	events.clear()
	return OK
