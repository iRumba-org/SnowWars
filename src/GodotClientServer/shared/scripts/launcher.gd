extends Control
class_name Launcher

func _ready() -> void:
	%ServerButton.pressed.connect(_on_server_pressed)
	%ClientButton.pressed.connect(_on_client_pressed)
	%LocalButton.pressed.connect(_on_local_pressed)

func _on_server_pressed() -> void:
	var port := Net.DEFAULT_PORT
	if not %PortLineEdit.text.is_empty():
		port = %PortLineEdit.text.to_int()
	var err := Net.start_server(port)
	if err != OK:
		push_error("Net: failed to start server (error %d)" % err)

func _on_client_pressed() -> void:
	var host: String = %HostLineEdit.text
	var port := Net.DEFAULT_PORT
	if not %ClientPortLineEdit.text.is_empty():
		port = %ClientPortLineEdit.text.to_int()
	var err := Net.start_client(host, port)
	if err != OK:
		push_error("Net: failed to start client (error %d)" % err)

func _on_local_pressed() -> void:
	Net.start_local()
