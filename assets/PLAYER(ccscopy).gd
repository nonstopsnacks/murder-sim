extends CharacterBody3D


@export var mouse_sens := 0.003
@export var gravity := 12
@export var jump_speed := 4.0

@export var walk_speed := 3.8
@export var sprint_speed := 5.4

# Stamina
@export var use_stamina := true
@export var stamina_max := 3.0
@export var stamina_drain := 1.2
@export var stamina_regen := 0.9
var stamina := 3.0
var is_sprinting := false

@export var footstep_interval := 0.38

var yaw := 0.0
var pitch := 0.0
var footstep_timer := 0.0

var carrying_pizza: Node3D = null

@onready var head: Node3D   = $Head
@onready var cam:  Camera3D = $Head/Camera
@onready var footsteps: AudioStreamPlayer3D = $PlayerFootsteps

# --- NEW FOR FLOATING LABELS ---
@onready var look_ray: RayCast3D = $Head/Camera/LookRay
var last_interactable: Node = null

# --- new pizza carry-
@onready var held_anchor: Node3D = $Head/Camera/HeldPizzaAnchor
var held_pizza_mesh: MeshInstance3D = null
var _held_last_topping: StringName = &""

func _ready() -> void:
	if head == null or cam == null:
		push_error("Player: expected nodes at $Head and $Head/Camera.")
		return

	# ---- NEW: sync yaw/pitch to whatever rotation we spawned with ----
	yaw = rotation.y
	pitch = head.rotation.x
	# ------------------------------------------------------------------

	cam.current = true
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	randomize()

	stamina = stamina_max


func _unhandled_input(event: InputEvent) -> void:
	# Mouse look
	if event is InputEventMouseMotion and cam and head:
		yaw   -= event.relative.x * mouse_sens
		pitch  = clamp(pitch - event.relative.y * mouse_sens, -1.2, 1.2)
		rotation.y      = yaw
		head.rotation.x = pitch

	# Escape unlocks mouse
	if event.is_action_pressed("ui_cancel"):
		var m := Input.get_mouse_mode()
		Input.set_mouse_mode(
			Input.MOUSE_MODE_CAPTURED if m == Input.MOUSE_MODE_VISIBLE
			else Input.MOUSE_MODE_VISIBLE
		)

	# --- INTERACTION ---
	if cam and event.is_action_pressed("interact"):
		var from := cam.global_transform.origin
		var to   := from - cam.global_transform.basis.z * 3.0

		var q := PhysicsRayQueryParameters3D.create(from, to)
		q.collide_with_areas  = true
		q.collide_with_bodies = true
		q.hit_from_inside     = true
		q.exclude             = [self]

		var hit := get_world_3d().direct_space_state.intersect_ray(q)
		if hit.is_empty():
			print("Ray not colliding.")
			return

		var n: Node = hit["collider"]
		print("Ray hit:", n)

		# =========================================================
		# FIRST PRIORITY: OVEN INTERACTION — SKIP PIZZA PICKUP
		# =========================================================

		var oven_check := n
		while oven_check and not oven_check.has_method("try_use"):
			oven_check = oven_check.get_parent()

		if oven_check and oven_check.name.to_lower().find("oven") != -1:
			print("Interacting with oven.")
			oven_check.try_use(self)
			return

		# =========================================================
		# SECOND PRIORITY: PICKING UP PIZZA
		# =========================================================

		var temp := n
		while temp and not temp.is_in_group("pizzas"):
			temp = temp.get_parent()

		if temp and temp.is_in_group("pizzas"):

			if temp.get_meta("on_buffet") == true:
				print("Can't pick up buffet pizza.")
				return

			if temp.get_meta("in_oven") == true:
				print("Can't pick up oven pizza (use oven instead).")
				return

			var allowed = ["cheese", "pepperoni", "cheese_baked", "pepperoni_baked"]
			if temp.topping not in allowed:
				print("Pizza not ready to pick up yet!")
				return

			if carrying_pizza != null:
				print("Already carrying a pizza.")
				return

			pick_up_pizza(temp)
			return

		# =========================================================
		# FALLBACK: try_use()
		# =========================================================

		while n and not n.has_method("try_use"):
			n = n.get_parent()

		if n and n.has_method("try_use"):
			print("Calling try_use on:", n)
			n.try_use(self)
		else:
			print("No try_use() on collider or its parents.")


func pick_up_pizza(pizza: Node3D) -> void:
	carrying_pizza = pizza
	pizza.visible = false
	print("Picked up pizza.")

	pizza.set_meta("being_carried", true)
	pizza.set_meta("in_oven", false)
	pizza.set_meta("on_buffet", false)

	_sync_held_visual_from(pizza)
	_held_last_topping = pizza.topping


func drop_pizza_at(pos: Vector3) -> void:
	if carrying_pizza == null:
		return

	carrying_pizza.visible = true
	carrying_pizza.global_transform.origin = pos
	carrying_pizza.set_meta("being_carried", false)
	carrying_pizza = null

	if held_pizza_mesh:
		held_pizza_mesh.visible = false

	print("Dropped pizza.")


# =====================================================
# FLOATING LABEL DETECTION (runs every frame)
# =====================================================
func _process(delta: float) -> void:
	
	# --- new pizza carry-
	if carrying_pizza == null:
		if held_pizza_mesh:
			held_pizza_mesh.visible = false
	else:
		# if something placed it (oven/counter) it should no longer be "being_carried"
		if carrying_pizza.has_meta("being_carried") and carrying_pizza.get_meta("being_carried") == false:
			carrying_pizza = null
			if held_pizza_mesh:
				held_pizza_mesh.visible = false
	# --- new pizza carry-
	


func _physics_process(delta: float) -> void:
	if not is_on_floor():
		velocity.y -= gravity * delta
	else:
		velocity.y = 0.0

	if is_on_floor() and Input.is_action_just_pressed("jump"):
		velocity.y = jump_speed

	var dir := Vector3.ZERO
	var b := global_transform.basis
	if Input.is_action_pressed("move_forward"): dir -= b.z
	if Input.is_action_pressed("move_back"):    dir += b.z
	if Input.is_action_pressed("move_left"):    dir -= b.x
	if Input.is_action_pressed("move_right"):   dir += b.x

	dir.y = 0.0
	var move_dir := dir.normalized()



# --- sprint logic ---
	var wants_sprint := Input.is_action_pressed("sprint")
	var moving := move_dir.length() > 0.01
	
	
	if Input.is_action_just_pressed("sprint"):
		print("[SPRINT] pressed")

	if is_sprinting:
		print("[SPRINT] draining stamina=", stamina)
	

	var target_speed := walk_speed
	is_sprinting = false

	if wants_sprint and moving:
		if not use_stamina:
			target_speed = sprint_speed
			is_sprinting = true
		else:
			if stamina > 0.0:
				target_speed = sprint_speed
				is_sprinting = true
				stamina = max(0.0, stamina - stamina_drain * delta)
	else:
	# regen when not sprinting
		if use_stamina:
			stamina = min(stamina_max, stamina + stamina_regen * delta)

	dir = move_dir * target_speed
	velocity.x = dir.x
	velocity.z = dir.z




	footstep_timer += delta
	var horizontal_speed := Vector2(velocity.x, velocity.z).length()
	var is_moving := horizontal_speed > 0.1
	var is_grounded := is_on_floor()

	var step_interval := footstep_interval
	if is_sprinting:
		step_interval *= 0.65

	if is_moving and is_grounded and footstep_timer >= step_interval:
		_play_footstep()
		footstep_timer = 0.0

	move_and_slide()


func _play_footstep() -> void:
	if not footsteps:
		return

	footsteps.pitch_scale = randf_range(0.95, 1.05)

	if footsteps.playing:
		footsteps.stop()

	footsteps.play()


func set_spawn_transform(t: Transform3D) -> void:
	global_transform = t
	# After changing transform, sync yaw to new body rotation
	yaw = rotation.y
	# If you ever give your spawns vertical tilt, you can also do:
	# pitch = head.rotation.x


# --- new pizza carry-
func _find_mesh(n: Node) -> MeshInstance3D:
	if n is MeshInstance3D:
		return n
	for c in n.get_children():
		var m := _find_mesh(c)
		if m: return m
	return null

func _ensure_held_mesh() -> void:
	if held_pizza_mesh: return
	held_pizza_mesh = MeshInstance3D.new()
	held_anchor.add_child(held_pizza_mesh)
	held_pizza_mesh.visible = false

func _sync_held_visual_from(pizza: Node3D) -> void:
	_ensure_held_mesh()

	var src := _find_mesh(pizza)
	if src == null:
		push_warning("Couldn't find MeshInstance3D on pizza to mirror.")
		return


	held_pizza_mesh.mesh = src.mesh
	held_pizza_mesh.material_override = _as_viewmodel_material(src.material_override)

	var sc := src.get_surface_override_material_count()
	for i in range(sc):
		held_pizza_mesh.set_surface_override_material(i,
			_as_viewmodel_material(src.get_surface_override_material(i))
		)

	held_pizza_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

# --- copy correct size from the original ---
	held_pizza_mesh.scale = src.global_transform.basis.get_scale()
	# Carry pose (tweak to taste)
	held_pizza_mesh.position = Vector3.ZERO
	held_pizza_mesh.rotation = Vector3.ZERO
	
	held_anchor.position = Vector3(0.25, -0.35, -0.7)
	held_anchor.rotation = Vector3(deg_to_rad(-10), deg_to_rad(20), 0)

	held_pizza_mesh.visible = true


func _as_viewmodel_material(mat: Material) -> Material:
	if mat == null:
		return null
	var m := mat.duplicate() as Material

	if m is BaseMaterial3D:
		var bm := m as BaseMaterial3D
		bm.no_depth_test = true
		bm.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
		# optional: makes it feel more like an FPS prop
		# bm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	return m
