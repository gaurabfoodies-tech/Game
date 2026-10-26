extends Node3D

# Shadow Quest 3D - original code-only mobile prototype.
# No external assets required.
const SPEED: float = 5.0
const JUMP: float = 6.0
const GRAVITY: float = 16.0
const TOUCH_SENS: float = 0.006
var hero: CharacterBody3D
var hero_visual: Node3D
var pivot: Node3D
var camera: Camera3D
var hud: CanvasLayer
var health_label: Label
var mission_label: Label
var coins_label: Label
var message_label: Label
var hp: int = 100
var coins: int = 0
var kills: int = 0
var attack_timer: float = 0.0
var hurt_timer: float = 0.0
var enemies: Array[CharacterBody3D] = []
var enemy_hp: Dictionary = {}
var enemy_origins: Dictionary = {}
var touch_move_id: int = -1
var touch_look_id: int = -1
var touch_origin: Vector2 = Vector2.ZERO
var touch_move: Vector2 = Vector2.ZERO
var look_last: Vector2 = Vector2.ZERO
var attack_requested: bool = false
var jump_requested: bool = false
var joystick_base: ColorRect
var joystick_knob: ColorRect
var mission_stage: int = 0

func _ready() -> void:
    _build_world()
    _build_hero()
    _build_hud()
    _update_hud()

func _mat(color: Color) -> StandardMaterial3D:
    var m := StandardMaterial3D.new()
    m.albedo_color = color
    m.roughness = 0.9
    return m

func _box(parent: Node3D, pos: Vector3, size: Vector3, color: Color) -> MeshInstance3D:
    var node := MeshInstance3D.new()
    var mesh := BoxMesh.new()
    mesh.size = size
    node.mesh = mesh
    node.position = pos
    node.material_override = _mat(color)
    parent.add_child(node)
    return node

func _sphere(parent: Node3D, pos: Vector3, radius: float, color: Color) -> MeshInstance3D:
    var node := MeshInstance3D.new()
    var mesh := SphereMesh.new()
    mesh.radius = radius
    mesh.height = radius * 2.0
    node.mesh = mesh
    node.position = pos
    node.material_override = _mat(color)
    parent.add_child(node)
    return node

func _solid_box(pos: Vector3, size: Vector3, color: Color) -> void:
    var body := StaticBody3D.new()
    body.position = pos
    add_child(body)
    _box(body, Vector3.ZERO, size, color)
    var collider := CollisionShape3D.new()
    var shape := BoxShape3D.new()
    shape.size = size
    collider.shape = shape
    body.add_child(collider)

func _build_world() -> void:
    var env := WorldEnvironment.new()
    var settings := Environment.new()
    settings.background_mode = Environment.BG_COLOR
    settings.background_color = Color(0.55, 0.75, 0.88)
    settings.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
    settings.ambient_light_color = Color(0.85, 0.9, 1.0)
    settings.ambient_light_energy = 0.65
    env.environment = settings
    add_child(env)
    var sun := DirectionalLight3D.new()
    sun.rotation_degrees = Vector3(-48, -32, 0)
    sun.light_energy = 1.5
    sun.shadow_enabled = true
    add_child(sun)
    _solid_box(Vector3(0, -0.5, 0), Vector3(95, 1, 95), Color(0.27, 0.44, 0.24))
    _solid_box(Vector3(0, -0.43, -9), Vector3(6, 0.15, 67), Color(0.48, 0.39, 0.27))
    var rng := RandomNumberGenerator.new()
    rng.seed = 41327
    for i in range(55):
        var x := rng.randf_range(-43, 43)
        var z := rng.randf_range(-43, 43)
        if absf(x) < 5.0:
            continue
        _box(self, Vector3(x, 1.2, z), Vector3(0.55, 2.4, 0.55), Color(0.36, 0.23, 0.12))
        _sphere(self, Vector3(x, 3.0, z), rng.randf_range(1.2, 2.1), Color(0.10, rng.randf_range(0.30, 0.5), 0.17))
    for i in range(8):
        var x := -16.0 if i % 2 == 0 else 16.0
        var z := -31.0 + float(i) * 8.0
        _solid_box(Vector3(x, 1.0, z), Vector3(4, 2, 4), Color(0.52, 0.48, 0.4))
        _box(self, Vector3(x, 2.35, z), Vector3(4.8, 0.65, 4.8), Color(0.35, 0.19, 0.13))
    for i in range(6):
        var angle := float(i) * TAU / 6.0
        var p := Vector3(sin(angle) * 7.0, 0, -24.0 + cos(angle) * 7.0)
        _solid_box(p + Vector3(0, 1.2, 0), Vector3(1.4, 2.4, 1.4), Color(0.48, 0.46, 0.4))
    for i in range(7):
        _spawn_enemy(Vector3(rng.randf_range(-12, 12), 0.2, rng.randf_range(-34, -13)))
    for i in range(12):
        var c := Area3D.new()
        c.position = Vector3(rng.randf_range(-18, 18), 0.7, rng.randf_range(-37, 10))
        c.add_to_group("coins")
        add_child(c)
        _sphere(c, Vector3.ZERO, 0.35, Color(1, 0.78, 0.08))
        var collision := CollisionShape3D.new()
        var shape := SphereShape3D.new()
        shape.radius = 0.65
        collision.shape = shape
        c.add_child(collision)
        c.body_entered.connect(_collect_coin.bind(c))

func _build_hero() -> void:
    hero = CharacterBody3D.new()
    hero.position = Vector3(0, 0.4, 8)
    add_child(hero)
    var collider := CollisionShape3D.new()
    var capsule := CapsuleShape3D.new()
    capsule.radius = 0.42
    capsule.height = 1.8
    collider.shape = capsule
    collider.position.y = 0.9
    hero.add_child(collider)
    hero_visual = Node3D.new()
    hero.add_child(hero_visual)
    _box(hero_visual, Vector3(0, 1.05, 0), Vector3(0.8, 1.1, 0.45), Color(0.17, 0.24, 0.45))
    _sphere(hero_visual, Vector3(0, 1.82, 0), 0.33, Color(0.85, 0.62, 0.43))
    _box(hero_visual, Vector3(-0.24, 0.37, 0), Vector3(0.25, 0.75, 0.3), Color(0.18, 0.18, 0.2))
    _box(hero_visual, Vector3(0.24, 0.37, 0), Vector3(0.25, 0.75, 0.3), Color(0.18, 0.18, 0.2))
    _box(hero_visual, Vector3(0.65, 1.0, -0.15), Vector3(0.14, 1.4, 0.12), Color(0.75, 0.8, 0.85))
    pivot = Node3D.new()
    pivot.position.y = 1.55
    hero.add_child(pivot)
    camera = Camera3D.new()
    camera.position = Vector3(0, 1.1, 5.8)
    camera.rotation_degrees.x = -10
    camera.current = true
    pivot.add_child(camera)

func _spawn_enemy(pos: Vector3) -> void:
    var enemy := CharacterBody3D.new()
    enemy.position = pos
    add_child(enemy)
    var collider := CollisionShape3D.new()
    var shape := CapsuleShape3D.new()
    shape.radius = 0.45
    shape.height = 1.7
    collider.shape = shape
    collider.position.y = 0.85
    enemy.add_child(collider)
    _box(enemy, Vector3(0, 0.95, 0), Vector3(0.85, 1.1, 0.55), Color(0.5, 0.13, 0.12))
    _sphere(enemy, Vector3(0, 1.65, 0), 0.3, Color(0.34, 0.31, 0.28))
    enemies.append(enemy)
    enemy_hp[enemy] = 3
    enemy_origins[enemy] = pos

func _build_hud() -> void:
    hud = CanvasLayer.new()
    add_child(hud)
    var root := Control.new()
    root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    root.mouse_filter = Control.MOUSE_FILTER_IGNORE
    hud.add_child(root)
    health_label = _label(root, Vector2(18, 12), "HP: 100")
    coins_label = _label(root, Vector2(18, 48), "Coins: 0")
    mission_label = _label(root, Vector2(18, 84), "Mission")
    message_label = _label(root, Vector2(18, 120), "")
    joystick_base = _pad(root, Vector2(28, -170), Vector2(130, 130), Color(0.1, 0.1, 0.1, 0.3), false)
    joystick_knob = _pad(joystick_base, Vector2(42, 42), Vector2(46, 46), Color(0.85, 0.85, 0.9, 0.65), true)
    var attack := _button(root, "ATTACK", Vector2(-145, -155), Vector2(112, 65))
    attack.pressed.connect(func() -> void: attack_requested = true)
    var jump := _button(root, "JUMP", Vector2(-265, -100), Vector2(104, 60))
    jump.pressed.connect(func() -> void: jump_requested = true)
    var pause := _button(root, "PAUSE", Vector2(-120, 14), Vector2(100, 48))
    pause.pressed.connect(func() -> void: get_tree().paused = not get_tree().paused)
    pause.process_mode = Node.PROCESS_MODE_ALWAYS
    root.resized.connect(_layout_controls.bind(root, attack, jump, pause))
    _layout_controls(root, attack, jump, pause)

func _label(root: Control, pos: Vector2, value: String) -> Label:
    var label := Label.new()
    label.text = value
    label.position = pos
    label.add_theme_font_size_override("font_size", 24)
    label.mouse_filter = Control.MOUSE_FILTER_IGNORE
    root.add_child(label)
    return label

func _pad(root: Control, pos: Vector2, size: Vector2, color: Color, ignore_mouse: bool) -> ColorRect:
    var rect := ColorRect.new()
    rect.color = color
    rect.position = pos
    rect.size = size
    rect.mouse_filter = Control.MOUSE_FILTER_IGNORE if ignore_mouse else Control.MOUSE_FILTER_STOP
    root.add_child(rect)
    return rect

func _button(root: Control, caption: String, pos: Vector2, size: Vector2) -> Button:
    var b := Button.new()
    b.text = caption
    b.position = pos
    b.size = size
    root.add_child(b)
    return b

func _layout_controls(root: Control, attack: Button, jump: Button, pause: Button) -> void:
    var s := root.size
    joystick_base.position = Vector2(35, s.y - 165)
    attack.position = Vector2(s.x - 145, s.y - 135)
    jump.position = Vector2(s.x - 265, s.y - 100)
    pause.position = Vector2(s.x - 120, 15)

func _update_hud() -> void:
    health_label.text = "HP: %d" % hp
    coins_label.text = "Coins: %d" % coins
    if mission_stage == 0:
        mission_label.text = "Mission 1: Collect 5 coins (%d/5)" % mini(coins, 5)
    elif mission_stage == 1:
        mission_label.text = "Mission 2: Defeat 3 enemies (%d/3)" % mini(kills, 3)
    elif mission_stage == 2:
        mission_label.text = "Mission 3: Reach the ancient ruins"
    else:
        mission_label.text = "All missions complete!"

func _collect_coin(body: Node3D, coin: Area3D) -> void:
    if body != hero or not is_instance_valid(coin):
        return
    coins += 1
    coin.queue_free()
    if mission_stage == 0 and coins >= 5:
        mission_stage = 1
        message_label.text = "Mission 1 complete!"
    _update_hud()

func _input(event: InputEvent) -> void:
    if event is InputEventScreenTouch:
        var e := event as InputEventScreenTouch
        var half := get_viewport().get_visible_rect().size.x * 0.5
        if e.pressed:
            if e.position.x < half and touch_move_id == -1:
                touch_move_id = e.index
                touch_origin = e.position
            elif e.position.x >= half and touch_look_id == -1:
                touch_look_id = e.index
                look_last = e.position
        else:
            if e.index == touch_move_id:
                touch_move_id = -1
                touch_move = Vector2.ZERO
                joystick_knob.position = Vector2(42, 42)
            if e.index == touch_look_id:
                touch_look_id = -1
    elif event is InputEventScreenDrag:
        var e := event as InputEventScreenDrag
        if e.index == touch_move_id:
            touch_move = (e.position - touch_origin) / 65.0
            touch_move = touch_move.limit_length(1.0)
            joystick_knob.position = Vector2(42, 42) + touch_move * 35.0
        elif e.index == touch_look_id:
            _rotate_camera(e.relative)
            look_last = e.position
    elif event is InputEventMouseMotion and Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT):
        _rotate_camera((event as InputEventMouseMotion).relative)

func _rotate_camera(delta: Vector2) -> void:
    pivot.rotation.y -= delta.x * TOUCH_SENS
    pivot.rotation.x = clampf(pivot.rotation.x - delta.y * TOUCH_SENS, -0.6, 0.45)

func _physics_process(delta: float) -> void:
    if hp <= 0:
        if Input.is_key_pressed(KEY_R):
            hp = 100
            hero.position = Vector3(0, 0.4, 8)
            message_label.text = ""
            _update_hud()
        return
    attack_timer = maxf(0.0, attack_timer - delta)
    hurt_timer = maxf(0.0, hurt_timer - delta)
    var key_dir := Input.get_vector("ui_left", "ui_right", "ui_up", "ui_down")
    var move_input := touch_move if touch_move.length() > 0.05 else key_dir
    var dir := pivot.global_basis.x * move_input.x + pivot.global_basis.z * move_input.y
    dir.y = 0.0
    dir = dir.normalized()
    hero.velocity.x = dir.x * SPEED
    hero.velocity.z = dir.z * SPEED
    if dir.length() > 0.1:
        hero_visual.rotation.y = lerp_angle(hero_visual.rotation.y, atan2(-dir.x, -dir.z), delta * 12.0)
    if not hero.is_on_floor():
        hero.velocity.y -= GRAVITY * delta
    elif jump_requested or Input.is_key_pressed(KEY_SPACE):
        hero.velocity.y = JUMP
    jump_requested = false
    hero.move_and_slide()
    if attack_requested or Input.is_key_pressed(KEY_F):
        _attack()
    attack_requested = false
    _update_enemies(delta)
    if mission_stage == 2 and hero.global_position.distance_to(Vector3(0, 0, -24)) < 7.0:
        mission_stage = 3
        message_label.text = "You completed Shadow Quest!"
        _update_hud()

func _attack() -> void:
    if attack_timer > 0.0:
        return
    attack_timer = 0.55
    message_label.text = "Sword attack!"
    for enemy in enemies.duplicate():
        if not is_instance_valid(enemy):
            continue
        if enemy.global_position.distance_to(hero.global_position) < 2.7:
            var remaining: int = int(enemy_hp[enemy]) - 1
            enemy_hp[enemy] = remaining
            if remaining <= 0:
                enemies.erase(enemy)
                enemy_hp.erase(enemy)
                enemy_origins.erase(enemy)
                enemy.queue_free()
                kills += 1
                if mission_stage == 1 and kills >= 3:
                    mission_stage = 2
                    message_label.text = "Mission 2 complete!"
                _update_hud()

func _update_enemies(delta: float) -> void:
    for enemy in enemies:
        if not is_instance_valid(enemy):
            continue
        var diff := hero.global_position - enemy.global_position
        diff.y = 0.0
        var dist := diff.length()
        if dist < 11.0 and dist > 1.4:
            var dir := diff.normalized()
            enemy.velocity.x = dir.x * 2.0
            enemy.velocity.z = dir.z * 2.0
            enemy.rotation.y = atan2(-dir.x, -dir.z)
        else:
            enemy.velocity.x = 0.0
            enemy.velocity.z = 0.0
        if not enemy.is_on_floor():
            enemy.velocity.y -= GRAVITY * delta
        enemy.move_and_slide()
        if dist < 1.7 and hurt_timer <= 0.0:
            hp = maxi(0, hp - 10)
            hurt_timer = 1.2
            message_label.text = "You were hit! Press R to restart if defeated."
            _update_hud()
