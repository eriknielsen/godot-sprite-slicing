# MIT License
# Copyright (c) 2019 Lupo Dharkael

extends Node2D

var begin := Vector2.ZERO
var end := Vector2.ZERO
var draw_enabled := false


func _ready():
	pass


func _input(event : InputEvent):
	if event is InputEventMouseButton:
		if event.pressed:
			print("begin")
			begin = event.position
			end = event.position
			draw_enabled = true
		else:
			draw_enabled = false
			end = event.position
			print("end")
			# redraw
			queue_redraw()
			$Slicer2D.slice_world(begin, end)
	elif event is InputEventMouseMotion and draw_enabled:
		queue_redraw()
		end = event.position
		print("end with draw enabled")

func _draw():
	print(draw_enabled)
	if draw_enabled:
		print("drawing")
		draw_line(begin, end, Color.RED)
