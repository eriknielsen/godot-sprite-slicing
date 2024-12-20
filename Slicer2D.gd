# MIT License
# Copyright (c) 2019 Lupo Dharkael

extends Node2D

class_name Slicer2D

# Assign a Physics2DDirectSpaceState to use a custom one, null equals the default one.
var space_state : PhysicsDirectSpaceState2D = null
# Min area for the slice to be valid.
var min_area := 0.01
# This will multiply the impulse applied to the slices after the cut.
var impulse_intensity := 100.0


class SlicingData:
	var object : Sliceable2D
	var global_enter := Vector2()
	var global_out := Vector2()
	var cut_number := 0
	var slices : Array = []


func slice_world(start : Vector2, end : Vector2, collision_layer : int = 0x7FFFFFFF, destroy : bool = true) -> Array:
	return _slice(start, end, collision_layer, destroy)


func slice_one(item : Sliceable2D, start : Vector2, end : Vector2, collision_layer : int = 0x7FFFFFFF, destroy : bool = true) -> SlicingData:
	return _slice(start, end, collision_layer, destroy, item).front() as SlicingData

func _slice(start : Vector2, end : Vector2, collision_layer : int = 0x7FFFFFFF, destroy : bool = true, fixed_body : Sliceable2D = null) -> Array:
	var res := []
	var data_arr : Array = _query_slicing_data(start, end, collision_layer, fixed_body)
	if data_arr.is_empty():
		return res
	
	# After this point we assume the objects processed are valid (they require slicing)
	# data is a SlicingData, result of the raycast query
	for data in data_arr:
		
		# The unified arr is the list of points of all the shapes from each part of the cut
		var unified_arr_1 := PackedVector2Array() 
		var unified_arr_2 := PackedVector2Array()
		
		var object : Sliceable2D = data.object
		
		if not object.has_meta(STATE_META):
			object.set_meta(STATE_META, SliceState.new())
		var state : SliceState = object.get_meta(STATE_META)
		# Cut limit
		var cut_limit = object.get("cut_limit_val")
		if typeof(cut_limit) == TYPE_INT:
			if cut_limit <= 0 or state and cut_limit <= state.cut_number:
				continue
		
		var slices : Array = data.slices
		
		var local_enter : Vector2 = object.to_local(data.global_enter)
		var local_out : Vector2 = object.to_local(data.global_out)
		var local_start : Vector2 = object.to_local(start)
		var local_end : Vector2 = object.to_local(end)
		
		# Basis initialization to calculate determinant.
		# That way we can know if a point is in one side or the other of the cut.
		var b := Basis()
		b.x = Vector3(local_start.x, local_start.y, 1)
		b.y = Vector3(local_end.x, local_end.y, 1)
		
		var split_valid := false
		
		# register all the shapes for the children
		var shape_arr_1 := []
		var shape_arr_2 := []
		
		var shape_owners : Array = object.get_shape_owners()
		for shape_owner in shape_owners:
			
			if object.is_shape_owner_disabled(shape_owner):
				continue
			
			for shape_id in object.shape_owner_get_shape_count(shape_owner):
				
				var child_1_arr := PackedVector2Array()
				var child_2_arr := PackedVector2Array()
				
				var shape : Shape2D = object.shape_owner_get_shape(shape_owner, shape_id)
				
				var points : PackedVector2Array = _get_shape_points(shape)
				
				if points.size() == 0:
					continue
				
				# Split the points
				for p in points:
					b.z = Vector3(p.x, p.y, 1)
					if b.determinant() > 0:
						child_1_arr.append(p)
					else:
						child_2_arr.append(p)
				
				
				# one arr is empty, the shape is not affected by the cut
				if child_1_arr.size() == 0 or child_2_arr.size() == 0:
					unified_arr_1 += child_1_arr
					unified_arr_2 += child_2_arr
					
					if child_1_arr.size() == 0:
						shape_arr_2.push_back(shape)
					else:
						shape_arr_1.push_back(shape)
					
					continue
				
				if not _point_arr_is_valid(child_1_arr) or not _point_arr_is_valid(child_2_arr):
					continue
				
				split_valid = true
				
				child_1_arr.push_back(local_enter)
				child_1_arr.push_back(local_out)
				
				child_2_arr.push_back(local_enter)
				child_2_arr.push_back(local_out)
				
				var child_1_shape := ConvexPolygonShape2D.new()
				
				child_1_shape.points = Geometry2D.convex_hull(child_1_arr)
				shape_arr_1.push_back(child_1_shape)
				unified_arr_1 += child_1_shape.points
				
				var child_2_shape := ConvexPolygonShape2D.new()
				child_2_shape.points = Geometry2D.convex_hull(child_2_arr)
				shape_arr_2.push_back(child_2_shape)
				unified_arr_2 += child_2_shape.points
				# Shape id loop
			# Shape owner loop
		# data_arr loop
		if not split_valid:
			continue
		
		state.cut_number += 1
		data.cut_number = state.cut_number
		
		var sprite : Sprite2D = object.get_node(object.sprite_node) as Sprite2D
		if sprite:
			var orig := object.to_local(sprite.get_global_transform().origin)
			var rect := sprite.get_rect()
			
			var pos := orig + rect.position
			var size := rect.size
			
			if sprite.flip_h:
				pos.x += size.x
				size.x *= -1
			if sprite.flip_v:
				pos.y += size.y
				size.y *= -1
			
			state.texture_size = size
			state.texture_pos = pos
		var cut_dir := (end - start).normalized()
		
		var child_1 := _create_child(object, shape_arr_1)
		_init_sprite(object, child_1, unified_arr_1)
		child_1.apply_central_impulse(cut_dir * impulse_intensity + Vector2(-cut_dir.y, cut_dir.x))
		
		var child_2 := _create_child(object, shape_arr_2)
		_init_sprite(object, child_2, unified_arr_2)
		child_2.apply_central_impulse(cut_dir * impulse_intensity + Vector2(cut_dir.y, -cut_dir.x))
		
		var p = object.get_parent()
		p.add_child(child_1)
		p.add_child(child_2)
		
		slices.push_back(child_1)
		slices.push_back(child_2)
		
		if object.has_method("_on_sprite_sliced"):
			object.call("_on_sprite_sliced", data)
		
		res.append(data)
		
		if destroy:
			object.queue_free()
		
	return res


# AUXILIAR --------------------------------------------------------------------

class SliceState:
	var texture_size : Vector2
	var texture_pos : Vector2
	var cut_number : int

const STATE_META := "STATE_META"

func _init_sprite(parent : Sliceable2D, child : Sliceable2D, polygon : PackedVector2Array) -> void:
	var mesh_inst : MeshInstance2D = child.get_node(child.sprite_node)
	var first_node = parent.get_node(parent.sprite_node) # TODO
	# valid for Sprite and MeshInstance2D
	mesh_inst.texture = first_node.texture
	
	# mesh creation
	polygon = Geometry2D.convex_hull(polygon)
	var indices = Geometry2D.triangulate_polygon(polygon)
	
	var state : SliceState = parent.get_meta(STATE_META)
	var uvs := PackedVector2Array()
	uvs.resize(polygon.size())
	var vec : Vector2
	for i in uvs.size():
		vec = (polygon[i] - state.texture_pos) / state.texture_size
		vec.x = clamp(vec.x, 0.0, 1.0)
		vec.y = clamp(vec.y, 0.0, 1.0)
		uvs[i] = vec
	
	var mesh_array = []
	mesh_array.resize(Mesh.ARRAY_MAX)
	mesh_array[Mesh.ARRAY_VERTEX] = polygon
	mesh_array[Mesh.ARRAY_INDEX] = indices
	mesh_array[Mesh.ARRAY_TEX_UV] = uvs
	
	
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, mesh_array)
	mesh_inst.mesh = m


func _create_child(object : Sliceable2D, shapes : Array) -> Sliceable2D:
	var child : Sliceable2D = object.duplicate() as Sliceable2D
	for i in child.get_shape_owners():
		child.remove_shape_owner(i)
	var mesh_inst := MeshInstance2D.new()
	var sprite_node := child.get_node(child.sprite_node)
	mesh_inst.name = sprite_node.name
	sprite_node.replace_by(mesh_inst)
	
	var shape_owner := child.create_shape_owner(child)
	for shape in shapes:
		child.shape_owner_add_shape(shape_owner, shape)
	return child


func _get_shape_points(shape : Shape2D) -> PackedVector2Array:
	var points := PackedVector2Array()
				
	if shape is ConvexPolygonShape2D:
		points = shape.points
		
#	elif shape is CapsuleShape2D:
#		for i in 24:
#			var ofs : Vector2 = Vector2(0, -shape.get_height() * 0.5 if (i > 6 and i <= 18) else shape.get_height() * 0.5)
#			points.push_back(Vector2(sin(i * PI * 2 / 24.0), cos(i * PI * 2 / 24.0)) * shape.get_radius() + ofs)
#			if i == 6 or i == 18:
#				points.push_back(Vector2(sin(i * PI * 2 / 24.0), cos(i * PI * 2 / 24.0)) * shape.get_radius() - ofs)
#
#	elif shape is CircleShape2D:
#		var elems := 24
#		points.resize(elems)
#		var step := (PI * 2) / elems
#
#		for i in elems:
#			var angle : float = step * i
#			points[i] = Vector2(sin(angle), cos(angle)) * shape.radius
#
#	elif shape is RectangleShape2D:
#		points.resize(4)
#		var extents : Vector2 = shape.extents
#
#		points[0] = Vector2(-extents.x, -extents.y)
#		points[1] = Vector2(extents.x, -extents.y)
#		points[2] = Vector2(extents.x, extents.y)
#		points[3] = Vector2(-extents.x, extents.y)
	else:
		print("Unsupported ", shape.get_class(), " type for collision slicing.")
	
	return points

func _point_arr_is_valid(points : PackedVector2Array) -> bool:
	# check area size
	var r : Rect2
	for p in points:
		r = r.expand(p)
	return (r.get_area()) >= min_area

func _line_cast(start : Vector2, end : Vector2, collision_layer : int = 0x7FFFFFFF) -> Array:
	var res := []
	
	var ss := space_state if space_state else get_world_2d().get_direct_space_state()
	var exceptions := []
	
	var intersect_ray_parameters: PhysicsRayQueryParameters2D = PhysicsRayQueryParameters2D.create(start, end)
	intersect_ray_parameters.exclude = exceptions
	intersect_ray_parameters.collision_mask = collision_layer
	while true:
		var query : Dictionary = ss.intersect_ray(intersect_ray_parameters)#ss.intersect_ray(start, end, exceptions, collision_layer)
		if query.is_empty():
			break
		var pos : Vector2 = query.position
		exceptions.append(query.collider.get_rid())
		intersect_ray_parameters.exclude = exceptions
		res.append(query)

	return res


func _query_slicing_data(start : Vector2, end : Vector2, collision_layer : int = 0x7FFFFFFF, fixed_body : Sliceable2D = null) -> Array:
	var res := []
	var query_forward : Array = _line_cast(start, end, collision_layer)
	var query_backwards : Array = _line_cast(end, start, collision_layer)

	if query_forward.size() != query_backwards.size():
		return res
	
	var ss = space_state if space_state else get_world_2d().get_direct_space_state()
	# We blacklist the colliders containing the beginning or end points of the cut
	var blacklisted_colliders : Array = []
	var intersect_point_parameters_start: PhysicsPointQueryParameters2D = PhysicsPointQueryParameters2D.new()
	intersect_point_parameters_start.position = start
	intersect_point_parameters_start.collision_mask = collision_layer
	var start_inside : Array = ss.intersect_point(intersect_point_parameters_start)#ss.intersect_point(start, 32, [], collision_layer)
	var intersect_point_parameters_end: PhysicsPointQueryParameters2D = PhysicsPointQueryParameters2D.new()
	intersect_point_parameters_end.position = end
	intersect_point_parameters_end.collision_mask = collision_layer
	var end_inside : Array = ss.intersect_point(intersect_point_parameters_end)#ss.intersect_point(end, 32, [], collision_layer)
	for i in start_inside:
		blacklisted_colliders.push_back(i.collider)
	for i in end_inside:
		blacklisted_colliders.push_back(i.collider)
	
	query_backwards.reverse()
	
	for i in query_forward.size():
		# Both need to be the same
		if query_forward[i].collider != query_backwards[i].collider:
			return []
		# Require rigid body in rigid mode
		var collider : Sliceable2D = query_forward[i].collider as Sliceable2D
		if collider == null or collider.freeze or blacklisted_colliders.has(collider):
			continue
		# Check for forced body
		if fixed_body and fixed_body != collider:
			continue
		# Validate sprite
		var first_node = collider.get_node(collider.sprite_node)
		var sprite = first_node as Sprite2D
		if not sprite and not first_node is MeshInstance2D:
			continue
		elif sprite and (sprite.hframes > 1 or sprite.vframes > 1):
			continue
		var data := SlicingData.new()
		data.global_enter = query_forward[i].position
		data.global_out = query_backwards[i].position
		data.object = query_forward[i].collider
		res.push_back(data)
	
	return res
