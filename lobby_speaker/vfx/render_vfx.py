# Текстуры частиц для колонки: ноты и кольцо басовой волны.
# Запуск: blender -b -P render_vfx.py
# Ноты белые с тёмной обводкой: ParticleEmitter.Color красит белое, обводка остаётся тёмной.
import bpy, math, os
import numpy as np

OUT = os.path.dirname(os.path.abspath(__file__))
FONT = "C:/Windows/Fonts/seguisym.ttf"
NOTES = {"note_eighth": "\u266A", "note_beamed": "\u266B", "note_sixteenth": "\u266C", "note_quarter": "\u2669"}
RES = 256

bpy.ops.wm.read_factory_settings(use_empty=True)
scene = bpy.context.scene
for eng in ("BLENDER_EEVEE_NEXT", "BLENDER_EEVEE"):
    try:
        scene.render.engine = eng
        break
    except TypeError:
        pass
scene.render.resolution_x = scene.render.resolution_y = RES
scene.render.film_transparent = True
scene.render.image_settings.file_format = "PNG"
scene.render.image_settings.color_mode = "RGBA"
scene.view_settings.view_transform = "Standard"

font = bpy.data.fonts.load(FONT)

def emit_mat(name, rgb):
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    nt = m.node_tree
    nt.nodes.clear()
    em = nt.nodes.new("ShaderNodeEmission")
    em.inputs["Color"].default_value = (*rgb, 1)
    out = nt.nodes.new("ShaderNodeOutputMaterial")
    nt.links.new(em.outputs[0], out.inputs[0])
    return m

white = emit_mat("White", (1, 1, 1))
outline = emit_mat("Outline", (0.09, 0.06, 0.05))

bpy.ops.object.camera_add(location=(0, 0, 10))
cam = bpy.context.object
cam.data.type = "ORTHO"
scene.camera = cam

def text_obj(ch, mat, z, offset):
    bpy.ops.object.text_add(location=(0, 0, z))
    t = bpy.context.object
    t.data.body = ch
    t.data.font = font
    t.data.align_x = "CENTER"
    t.data.align_y = "CENTER"
    t.data.offset = offset          # утолщение контура = обводка
    t.data.materials.append(mat)
    return t

for name, ch in NOTES.items():
    for o in [o for o in bpy.data.objects if o.type == "FONT"]:
        bpy.data.objects.remove(o)
    front = text_obj(ch, white, 0.01, 0.0)
    back = text_obj(ch, outline, 0.0, 0.028)
    bpy.context.view_layer.update()
    # кадрируем по габаритам обводки
    xs, ys = [], []
    for c in back.bound_box:
        xs.append(c[0]); ys.append(c[1])
    cx, cy = (min(xs) + max(xs)) / 2, (min(ys) + max(ys)) / 2
    size = max(max(xs) - min(xs), max(ys) - min(ys)) * 1.12
    for o in (front, back):
        o.location.x -= cx
        o.location.y -= cy
    cam.data.ortho_scale = size
    scene.render.filepath = os.path.join(OUT, name + ".png")
    bpy.ops.render.render(write_still=True)

# Кольцо волны: белое, мягкие края, чуть светлее внутренняя кромка
n = 512
y, x = np.mgrid[0:n, 0:n].astype(np.float32)
r = np.hypot(x - n / 2 + 0.5, y - n / 2 + 0.5) / (n / 2)
band = np.exp(-((r - 0.84) / 0.06) ** 2)
inner = np.clip((r - 0.45) / 0.39, 0, 1) ** 3 * 0.35 * (r < 0.84)
alpha = np.clip(band + inner, 0, 1)
img = np.ones((n, n, 4), dtype=np.float32)
img[..., 3] = alpha
im = bpy.data.images.new("wave_ring", n, n, alpha=True)
im.pixels.foreach_set(img.ravel())
im.filepath_raw = os.path.join(OUT, "wave_ring.png")
im.file_format = "PNG"
im.save()

# Контрольный лист: всё на тёмном фоне, ноты подкрашены, как в игре
tints = [(1.0, 0.84, 0.35), (0.25, 0.9, 0.82), (1.0, 0.55, 0.47), (0.72, 0.55, 1.0)]
sheet = np.zeros((RES, RES * 5, 4), dtype=np.float32)
sheet[..., :3] = (0.16, 0.17, 0.22)
sheet[..., 3] = 1
for i, name in enumerate(NOTES):
    src = bpy.data.images.load(os.path.join(OUT, name + ".png"))
    px = np.array(src.pixels[:], dtype=np.float32).reshape(RES, RES, 4)
    a = px[..., 3:4]
    col = px[..., :3] * np.array(tints[i])
    sheet[:, i * RES:(i + 1) * RES, :3] = sheet[:, i * RES:(i + 1) * RES, :3] * (1 - a) + col * a
ring = img[::2, ::2]
a = ring[..., 3:4]
sheet[:, 4 * RES:, :3] = sheet[:, 4 * RES:, :3] * (1 - a) + np.array((0.6, 1.0, 0.95)) * a
sh = bpy.data.images.new("sheet", RES * 5, RES, alpha=False)
sh.pixels.foreach_set(sheet.ravel())
sh.filepath_raw = os.path.join(OUT, "_preview_sheet.png")
sh.file_format = "PNG"
sh.save()
print("VFX DONE")
