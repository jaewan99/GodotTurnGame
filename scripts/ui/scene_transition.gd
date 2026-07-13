## SceneTransition
## Autoload. Plays a luminance-mask wipe over the whole screen while swapping
## between big scenes (menu ↔ map ↔ battlefield). Route scene changes through
## `SceneTransition.change_scene(path)` instead of get_tree().change_scene_to_file().
extends CanvasLayer

const SHADER := preload("res://shaders/luminance_transition.gdshader")

## How long the cover (and the uncover) each take.
const _COVER_TIME := 0.45
const _UNCOVER_TIME := 0.45
## Cutoff sweeps slightly past [0,1] so the screen fully covers / fully clears.
const _CUTOFF_HIDDEN := 1.05    # overlay fully transparent
const _CUTOFF_COVERED := -0.05  # overlay fully opaque

var _rect: ColorRect
var _mat: ShaderMaterial
var _busy := false


func _ready() -> void:
	layer = 128                                   # above every other CanvasLayer
	process_mode = Node.PROCESS_MODE_ALWAYS       # works even while the tree is paused

	_mat = ShaderMaterial.new()
	_mat.shader = SHADER
	_mat.set_shader_parameter("cover_color", Color.BLACK)
	_mat.set_shader_parameter("mask_texture", _make_mask())
	_mat.set_shader_parameter("cutoff", _CUTOFF_HIDDEN)

	_rect = ColorRect.new()
	_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	# STOP so the overlay swallows clicks while the wipe is on screen — prevents
	# interacting with (or re-triggering) the scene underneath mid-transition.
	_rect.mouse_filter = Control.MOUSE_FILTER_STOP
	_rect.material = _mat
	_rect.visible = false
	add_child(_rect)


## A soft organic noise mask so the wipe dissolves in blobs rather than a hard line.
func _make_mask() -> Texture2D:
	var noise := FastNoiseLite.new()
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise.frequency = 0.012
	var tex := NoiseTexture2D.new()
	tex.width = 512
	tex.height = 512
	tex.noise = noise
	return tex


## Cover the screen, swap to `path`, then uncover. Safe to call once at a time.
func change_scene(path: String) -> void:
	if _busy:
		return
	_busy = true
	_rect.visible = true

	await _sweep(_CUTOFF_HIDDEN, _CUTOFF_COVERED, _COVER_TIME)

	get_tree().change_scene_to_file(path)
	# Let the new scene instantiate and run _ready before revealing it.
	await get_tree().process_frame
	await get_tree().process_frame

	await _sweep(_CUTOFF_COVERED, _CUTOFF_HIDDEN, _UNCOVER_TIME)

	_rect.visible = false
	_busy = false


func _sweep(from: float, to: float, time: float) -> void:
	_mat.set_shader_parameter("cutoff", from)
	var tween := create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tween.tween_method(
		func(v: float): _mat.set_shader_parameter("cutoff", v),
		from, to, time)
	await tween.finished
