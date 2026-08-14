class_name TutorialOpponent extends Actor
## 教学用受控对手：不寻路、不抢先出手，手中任务品只在倒地时掉落。

var protect_held_until_downed := true

func setup(title := "训练黄牛") -> void:
	build_body(Color(0.9, 0.28, 0.22), title)

func _physics_process(delta: float) -> void:
	actor_tick(delta)
	if not downed:
		apply_motion(delta, Vector3.ZERO, 0.0)

func drop_one_held(scatter := true) -> Item:
	if protect_held_until_downed and not downed:
		return null
	return super.drop_one_held(scatter)
