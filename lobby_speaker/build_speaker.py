# Деревянная пляжная колонка-ящик для лобби. Собирает модель и экспортирует FBX.
# Запуск: blender -b -P build_speaker.py
# 1 юнит Blender = 1 стад. Перед колонки смотрит в -Y, верх +Z.
import bpy, bmesh, math, os, random
import numpy as np
from mathutils import Vector, Matrix

OUT = os.path.dirname(os.path.abspath(__file__))
random.seed(7)
np.random.seed(7)

bpy.ops.wm.read_factory_settings(use_empty=True)

# ═══ Текстура-атлас 1024×1024 ═══
# [0..0.5]×[0..0.5]   — дерево (волокна идут вдоль U)
# [0.5..1]×[0..0.5]   — красная тряпка с пальмой
# [0..1]×[0.5..1]     — палитра 8×4 клеток по 128 px
PALETTE = {
    "METAL": (104, 104, 110), "METAL_D": (70, 70, 78), "RIVET": (150, 150, 156),
    "PANEL": (42, 40, 42), "HOLE": (14, 13, 15), "HORN": (82, 78, 78),
    "HORN_IN": (66, 62, 63), "CONE": (242, 172, 44), "CONE_D": (204, 132, 30),
    "CAP": (58, 52, 48), "SURROUND": (36, 34, 36), "BASKET": (62, 60, 62),
    "ROPE": (220, 180, 112), "ROPE_D": (168, 126, 70), "LEAF": (124, 184, 56),
    "LEAF_D": (72, 128, 36), "STAR": (248, 142, 42), "STAR_D": (212, 98, 28),
    "SHELL": (247, 178, 152), "SHELL_D": (222, 138, 116), "BLUE": (72, 124, 168),
    "JACK_W": (232, 230, 224), "JACK_R": (200, 40, 40), "CLOTH": (186, 48, 44),
    "WOOD_END": (120, 72, 36),
    "ROPE_GRAD": (0, 0, 0),   # градиент ROPE_D → ROPE по горизонтали, рисуется отдельно
}
NAMES = list(PALETTE)
SIZE = 1024

def smooth_noise(n, scale, rng):
    """1D гладкий шум длиной n."""
    k = max(2, int(n / scale) + 2)
    pts = rng.random(k)
    xs = np.linspace(0, k - 1, n)
    return np.interp(xs, np.arange(k), pts)

def draw_atlas():
    rng = np.random.default_rng(3)
    img = np.zeros((SIZE, SIZE, 4), dtype=np.float32)
    img[..., 3] = 1

    # ─ дерево ─
    H = W_ = 512
    y = np.arange(H)[:, None].astype(np.float32)
    x = np.arange(W_)[None, :].astype(np.float32)
    warp = smooth_noise(W_, 70, rng)[None, :] * 9 + smooth_noise(H, 30, rng)[:, None] * 4
    grain = np.sin((y + warp) * 0.42)
    tone = smooth_noise(H, 26, rng)[:, None]                 # полосы разных досок
    fine = smooth_noise(W_ * 4, 3, rng)[: W_][None, :] * 0.06
    light = np.array([186, 118, 60]) / 255
    dark = np.array([118, 66, 30]) / 255
    t = np.clip(0.35 + 0.45 * tone + 0.12 * grain + fine, 0, 1)
    wood = dark[None, None, :] * (1 - t[..., None]) + light[None, None, :] * t[..., None]
    lines = (grain > 0.94)[..., None]
    wood = np.where(lines, wood * 0.72, wood)
    img[0:512, 0:512, :3] = wood

    # ─ тряпка с пальмой ─
    cy = (np.arange(512)[:, None] + 0.5) / 512
    cx = (np.arange(512)[None, :] + 0.5) / 512
    red = np.array(PALETTE["CLOTH"]) / 255
    fold = 0.9 + 0.1 * np.sin(cx * 38 + np.sin(cy * 9) * 1.5)
    cloth = red[None, None, :] * fold[..., None]

    def dist_poly(pts):
        pts = np.asarray(pts)
        d = np.full(cx.shape[1:] if False else (512, 512), 9.0, dtype=np.float32)
        for (x0, y0), (x1, y1) in zip(pts[:-1], pts[1:]):
            dx, dy = x1 - x0, y1 - y0
            L2 = dx * dx + dy * dy + 1e-9
            tt = np.clip(((cx - x0) * dx + (cy - y0) * dy) / L2, 0, 1)
            d = np.minimum(d, np.hypot(cx - (x0 + tt * dx), cy - (y0 + tt * dy)))
        return d

    mask = np.zeros((512, 512), dtype=bool)
    # ствол
    ts = np.linspace(0, 1, 24)
    trunk = [(0.47 + 0.06 * t_ + 0.035 * math.sin(t_ * math.pi), 0.17 + 0.23 * t_) for t_ in ts]
    for i, (px, py) in enumerate(trunk):
        r = 0.026 * (1 - 0.45 * ts[i])
        mask |= np.hypot(cx - px, cy - py) < r
    top = trunk[-1]
    # листья
    for ang, ln in ((168, 0.15), (128, 0.13), (88, 0.11), (48, 0.13), (10, 0.15)):
        a = math.radians(ang)
        pts = []
        for t_ in np.linspace(0, 1, 14):
            px = top[0] + math.cos(a) * ln * t_
            py = top[1] + math.sin(a) * ln * t_ - 0.06 * t_ * t_
            pts.append((px, py))
        for i, (px, py) in enumerate(pts):
            w = 0.034 * math.sin(math.pi * min(0.98, (i + 1) / len(pts)))
            mask |= np.hypot(cx - px, cy - py) < w
    # волны
    for y0, x0, x1 in ((0.135, 0.33, 0.69), (0.095, 0.38, 0.64)):
        xs = np.linspace(x0, x1, 40)
        mask |= dist_poly([(xx, y0 + 0.012 * math.sin(xx * 42)) for xx in xs]) < 0.011
    logo = np.array([238, 206, 192]) / 255
    cloth = np.where(mask[..., None], logo[None, None, :] * fold[..., None], cloth)
    img[0:512, 512:1024, :3] = cloth

    # ─ палитра ─
    for i, name in enumerate(NAMES):
        col, row = i % 8, i // 8
        y0 = 512 + row * 128
        if name == "ROPE_GRAD":
            k = np.linspace(0, 1, 128)[:, None]
            a, b = np.array(PALETTE["ROPE_D"]) / 255, np.array(PALETTE["ROPE"]) / 255
            img[y0:y0 + 128, col * 128:(col + 1) * 128, :3] = (a * (1 - k) + b * k)[None, :, :]
        else:
            img[y0:y0 + 128, col * 128:(col + 1) * 128, :3] = np.array(PALETTE[name]) / 255

    im = bpy.data.images.new("SpeakerAtlas", SIZE, SIZE, alpha=False)
    im.pixels.foreach_set(img.ravel())
    im.filepath_raw = os.path.join(OUT, "LobbySpeaker_atlas.png")
    im.file_format = "PNG"
    im.save()
    return im

def cell_uv(name):
    i = NAMES.index(name)
    col, row = i % 8, i // 8
    return ((col + 0.5) / 8, 0.5 + (row + 0.5) / 8)

# ═══ Помощники ═══
def ensure_uv(me):
    if not me.uv_layers:
        me.uv_layers.new(name="UVMap")
    return me.uv_layers.active

def paint(obj, name):
    uv = ensure_uv(obj.data)
    u, v = cell_uv(name)
    for lp in uv.data:
        lp.uv = (u, v)
    return obj

def wood(obj, tone=None):
    """Проекция дерева: волокна вдоль самой длинной оси детали."""
    me = obj.data
    uv = ensure_uv(me)
    co = np.array([v.co[:] for v in me.vertices])
    mn, mx = co.min(0), co.max(0)
    dims = np.maximum(mx - mn, 1e-3)
    L = int(np.argmax(dims))
    off = random.random() * 0.75 if tone is None else tone
    for p in me.polygons:
        nrm = [abs(c) for c in p.normal]
        dom = int(np.argmax(nrm))
        for li in p.loop_indices:
            c = co[me.loops[li].vertex_index]
            if dom != L:
                o = 3 - dom - L
                u = (c[L] - mn[L]) / dims[L]
                a = off + (c[o] - mn[o]) * 0.05
            else:
                a1, a2 = [k for k in range(3) if k != L]
                u = 0.1 + (c[a1] - mn[a1]) * 0.05
                a = off + (c[a2] - mn[a2]) * 0.05
            uv.data[li].uv = (0.01 + min(max(u, 0), 1) * 0.48, 0.01 + min(max(a, 0), 1) * 0.48)
    return obj

def finish(obj, angle=40):
    bpy.context.view_layer.objects.active = obj
    for m in list(obj.modifiers):
        bpy.ops.object.modifier_apply(modifier=m.name)
    bpy.ops.object.transform_apply(location=False, rotation=True, scale=True)
    for p in obj.data.polygons:
        p.use_smooth = True
    obj.data.set_sharp_from_angle(angle=math.radians(angle))
    return obj

def new_obj(name, bm):
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    o = bpy.data.objects.new(name, me)
    bpy.context.collection.objects.link(o)
    return o

def rbox(name, size, loc, bevel=0.12, seg=2, rot=(0, 0, 0)):
    bpy.ops.mesh.primitive_cube_add(size=1, location=loc, rotation=rot)
    o = bpy.context.object
    o.name = name
    o.scale = size
    bpy.ops.object.transform_apply(scale=True)
    if bevel:
        m = o.modifiers.new("bevel", "BEVEL")
        m.width = bevel
        m.segments = seg
        m.limit_method = "NONE"
    return finish(o)

def sphere(name, r, loc, seg=8, rings=5, scale=(1, 1, 1)):
    bpy.ops.mesh.primitive_uv_sphere_add(segments=seg, ring_count=rings, radius=r, location=loc)
    o = bpy.context.object
    o.name = name
    o.scale = scale
    return finish(o, 80)

def torus_y(name, major, minor, loc, seg=48, mseg=10):
    bpy.ops.mesh.primitive_torus_add(major_radius=major, minor_radius=minor,
                                     major_segments=seg, minor_segments=mseg,
                                     location=loc, rotation=(math.pi / 2, 0, 0))
    o = bpy.context.object
    o.name = name
    return finish(o, 80)

def cyl_y(name, r, depth, loc, verts=40):
    bpy.ops.mesh.primitive_cylinder_add(vertices=verts, radius=r, depth=depth,
                                        location=loc, rotation=(math.pi / 2, 0, 0))
    o = bpy.context.object
    o.name = name
    return finish(o)

def join(name, objs, origin=(0, 0, 0)):
    bpy.ops.object.select_all(action="DESELECT")
    for o in objs:
        o.select_set(True)
    bpy.context.view_layer.objects.active = objs[0]
    bpy.ops.object.join()
    o = bpy.context.object
    o.name = o.data.name = name
    bpy.context.scene.cursor.location = origin
    bpy.ops.object.origin_set(type="ORIGIN_CURSOR")
    return o

# ─── Верёвка: трубка с тремя скрученными прядями ───
def rope(name, pts, r, closed=False, hint=None, twist=3.2, ring=8):
    P = [Vector(p) for p in pts]
    n = len(P)
    T = []
    for i in range(n):
        if closed:
            a = P[(i + 1) % n] - P[i - 1]
        else:
            a = P[min(i + 1, n - 1)] - P[max(i - 1, 0)]
        T.append(a.normalized())
    N = []
    if hint is not None:
        h = Vector(hint)
        for t in T:
            N.append((h - t * h.dot(t)).normalized())
    else:
        up = Vector((0, 0, 1)) if abs(T[0].z) < 0.9 else Vector((1, 0, 0))
        N.append((up - T[0] * up.dot(T[0])).normalized())
        for i in range(1, n):
            v = N[-1] - T[i] * N[-1].dot(T[i])
            N.append(v.normalized())
    s = [0.0]
    for i in range(1, n):
        s.append(s[-1] + (P[i] - P[i - 1]).length)
    if closed:
        total = s[-1] + (P[0] - P[-1]).length
        k = max(1, round(total * twist / math.tau))
        twist = k * math.tau / total

    bm = bmesh.new()
    rings, vals = [], []
    for i in range(n):
        B = T[i].cross(N[i])
        rv, vv = [], []
        for j in range(ring):
            th = math.tau * j / ring
            c = math.cos(3 * th - s[i] * twist)
            rr = r * (1 + 0.2 * c)
            rv.append(bm.verts.new(P[i] + (N[i] * math.cos(th) + B * math.sin(th)) * rr))
            vv.append(c)
        rings.append(rv)
        vals.append(vv)
    uvl = bm.loops.layers.uv.new("UVMap")
    # цвет плавно: в ложбинах между прядями темнее (градиентная клетка)
    gu, gv = cell_uv("ROPE_GRAD")
    def grad(c):
        return (gu - 0.5 / 8 + (0.08 + 0.84 * (0.5 + 0.5 * c)) / 8, gv)
    segs = n if closed else n - 1
    for i in range(segs):
        i2 = (i + 1) % n
        for j in range(ring):
            j2 = (j + 1) % ring
            quad = ((i, j), (i, j2), (i2, j2), (i2, j))
            f = bm.faces.new([rings[a][b] for a, b in quad])
            for lp, (a, b) in zip(f.loops, quad):
                lp[uvl].uv = grad(vals[a][b])
    if not closed:
        for rv in (rings[0], rings[-1]):
            f = bm.faces.new(rv)
            for lp in f.loops:
                lp[uvl].uv = grad(-0.6)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces[:])
    o = new_obj(name, bm)
    return finish(o, 70)

def face_colored(name, verts, faces, colors, solid=0.0):
    bm = bmesh.new()
    bv = [bm.verts.new(v) for v in verts]
    uvl = bm.loops.layers.uv.new("UVMap")
    for f, col in zip(faces, colors):
        bf = bm.faces.new([bv[i] for i in f])
        for lp in bf.loops:
            lp[uvl].uv = cell_uv(col)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces[:])
    o = new_obj(name, bm)
    if solid:
        m = o.modifiers.new("solid", "SOLIDIFY")
        m.thickness = solid
        m.offset = 0
    return o

# ═══ Размеры ═══
W, D = 10.0, 8.0
FEET = 1.2
TOP = 16.0
ZMID = (FEET + TOP) / 2

body, ropes, decor, cone_parts = [], [], [], []

# ─── Деревянный каркас ───
for sx in (-1, 1):
    for sy in (-1, 1):
        body.append(wood(rbox("Post", (1.5, 1.5, TOP - FEET), (sx * 4.25, sy * 3.25, ZMID), 0.14)))
        body.append(wood(rbox("Foot", (1.7, 1.7, FEET + 0.05), (sx * 4.15, sy * 3.15, FEET / 2), 0.12)))

for z in (FEET + 0.8, TOP - 0.8):
    for sy in (-1, 1):
        body.append(wood(rbox("BeamFB", (W - 0.2, 1.4, 1.6), (0, sy * 3.2, z), 0.14)))
    for sx in (-1, 1):
        body.append(wood(rbox("BeamLR", (1.4, D - 0.2, 1.6), (sx * 4.2, 0, z), 0.14)))

PANEL_Z0, PANEL_Z1 = FEET + 1.6, TOP - 1.6
PH = PANEL_Z1 - PANEL_Z0
# доски по бокам, сзади и сверху
for sx in (-1, 1):
    for y in (-1.7, 0, 1.7):
        body.append(wood(rbox("SidePlank", (0.4, 1.62, PH + 0.1), (sx * 4.6, y, ZMID), 0.1)))
for x in (-2.7, -0.9, 0.9, 2.7):
    body.append(wood(rbox("BackPlank", (1.72, 0.4, PH + 0.1), (x, 3.6, ZMID), 0.1)))
    body.append(wood(rbox("TopPlank", (1.72, 5.2, 0.4), (x, 0, TOP - 0.25), 0.1)))
# тёмная начинка, чтобы щели между досками были чёрными
body.append(paint(rbox("Inner", (8.9, 6.9, TOP - FEET - 0.6), (0, 0, ZMID), 0), "HOLE"))
# передняя панель
FRONT = -3.6
body.append(paint(rbox("Panel", (7.2, 0.4, PH + 0.1), (0, FRONT + 0.2, ZMID), 0.06), "PANEL"))

# ─── Железные уголки ───
def rivet(loc):
    body.append(paint(sphere("Rivet", 0.17, loc, 8, 5, (1, 1, 1)), "RIVET"))

for sx in (-1, 1):
    for sy in (-1, 1):
        for top in (False, True):
            zc = TOP - 0.95 if top else FEET + 0.95
            fx, fy = sx * (5 - 0.85), sy * (4 - 0.85)
            body.append(paint(rbox("Bracket", (1.75, 0.14, 1.95), (fx, sy * 4.07, zc), 0.05), "METAL"))
            body.append(paint(rbox("Bracket", (0.14, 1.75, 1.95), (sx * 5.07, fy, zc), 0.05), "METAL"))
            rivet((fx - sx * 0.35, sy * 4.16, zc + 0.45))
            rivet((fx + sx * 0.3, sy * 4.16, zc - 0.45))
            rivet((sx * 5.16, fy - sy * 0.35, zc + 0.45))
            rivet((sx * 5.16, fy + sy * 0.3, zc - 0.45))
            if top:
                body.append(paint(rbox("Bracket", (1.75, 1.75, 0.14), (fx, fy, TOP + 0.07), 0.05), "METAL"))
                rivet((fx, fy, TOP + 0.16))

# ─── Рупор-пищалка ───
HORN_X, HORN_Z = 0.9, 12.35
def horn():
    rings = [
        (4.3, 3.3, -3.95, "HORN"),     # внешний край рамки
        (3.6, 2.6, -3.95, "HORN"),     # внутренний край рамки
        (3.5, 2.5, -3.75, "HORN_IN"),
        (1.1, 0.8, -2.6, "HORN_IN"),   # горло
    ]
    verts, faces, cols = [], [], []
    for w, h, y, _ in rings:
        for (a, b) in ((-1, -1), (1, -1), (1, 1), (-1, 1)):
            verts.append((HORN_X + a * w / 2, y, HORN_Z + b * h / 2))
    # задняя стенка рамки
    w, h = 4.3, 3.3
    for (a, b) in ((-1, -1), (1, -1), (1, 1), (-1, 1)):
        verts.append((HORN_X + a * w / 2, -3.55, HORN_Z + b * h / 2))
    back = 16
    for r in range(3):
        for k in range(4):
            k2 = (k + 1) % 4
            faces.append((r * 4 + k, r * 4 + k2, (r + 1) * 4 + k2, (r + 1) * 4 + k))
            cols.append(rings[r][3] if r == 0 else "HORN_IN")
    for k in range(4):
        k2 = (k + 1) % 4
        faces.append((back + k, back + k2, k2, k))
        cols.append("HORN")
    faces.append((12, 13, 14, 15))
    cols.append("HOLE")
    o = face_colored("Horn", verts, faces, cols)
    m = o.modifiers.new("bevel", "BEVEL")
    m.width = 0.06
    m.segments = 2
    m.limit_method = "ANGLE"
    return finish(o, 35)

body.append(horn())
for a, b in ((-1, -1), (1, -1), (1, 1), (-1, 1)):
    rivet((HORN_X + a * 1.95, -4.02, HORN_Z + b * 1.45))

# ─── Динамик ───
# Динамик целиком стоит ПЕРЕД панелью (её лицо на y=-3.6), иначе конус тонет в ней.
WC = Vector((0, -4.3, 6.4))    # центр, по переднему краю конуса
CONE_DEPTH = 0.6
body.append(paint(cyl_y("Hole", 2.95, 0.12, (0, -3.66, WC.z)), "HOLE"))
body.append(paint(torus_y("Basket", 2.78, 0.32, (0, -4.15, WC.z)), "BASKET"))

def cone_y(name, r_front, r_back, depth, y_front, z):
    # чаша без крышек; нормали внутрь, чтобы её было видно спереди
    # (Roblox не рисует обратные стороны)
    bpy.ops.mesh.primitive_cone_add(vertices=48, radius1=r_front, radius2=r_back, depth=depth,
                                    end_fill_type="NOTHING",
                                    location=(0, y_front + depth / 2, z), rotation=(-math.pi / 2, 0, 0))
    o = bpy.context.object
    o.name = name
    bm = bmesh.new()
    bm.from_mesh(o.data)
    bmesh.ops.reverse_faces(bm, faces=bm.faces[:])
    bm.to_mesh(o.data)
    bm.free()
    return finish(o, 50)

cone_parts.append(paint(torus_y("Surround", 2.45, 0.26, (0, WC.y, WC.z)), "SURROUND"))
cone_parts.append(paint(cone_y("Cone", 2.3, 0.8, CONE_DEPTH, WC.y, WC.z), "CONE"))
for rr in (1.25, 1.75):
    yy = WC.y + (2.3 - rr) / 1.5 * CONE_DEPTH
    cone_parts.append(paint(torus_y("ConeLine", rr, 0.045, (0, yy - 0.03, WC.z), 48, 6), "CONE_D"))
cone_parts.append(paint(sphere("DustCap", 0.88, (0, WC.y + CONE_DEPTH - 0.02, WC.z), 24, 12, (1, 0.62, 1)), "CAP"))

# верёвочное кольцо и скобы
RING_R = 3.25
pts = [(math.cos(a) * RING_R, -4.45, WC.z + math.sin(a) * RING_R)
       for a in np.linspace(0, math.tau, 150, endpoint=False)]
ropes.append(rope("WooferRope", pts, 0.3, closed=True, hint=(0, -1, 0)))
for k in range(4):
    a = math.radians(45 + 90 * k)
    c = (math.cos(a) * RING_R, -4.62, WC.z + math.sin(a) * RING_R)
    body.append(paint(rbox("Clamp", (1.05, 0.45, 0.6), c, 0.08, 2, (0, -a, 0)), "METAL_D"))
    rivet((c[0], -4.87, c[2]))

# ─── Верёвка вокруг корпуса ───
def body_loop(z0, slope, n=320):
    ax, ay, cr = 5.25, 4.25, 0.55
    # скруглённый прямоугольник по периметру
    path = []
    straight = [(ax - cr, ay), (ay - cr, ax)]
    per = 4 * (2 * (ax - cr) + 0) + 2 * math.pi * cr
    corners = [((ax - cr), (ay - cr), 0), (-(ax - cr), (ay - cr), 90),
               (-(ax - cr), -(ay - cr), 180), ((ax - cr), -(ay - cr), 270)]
    segs = []
    for cx_, cy_, start in corners:
        for t in np.linspace(0, 90, 10, endpoint=False):
            a = math.radians(start + t)
            segs.append((cx_ + cr * math.cos(a), cy_ + cr * math.sin(a)))
        # прямой участок до следующего угла
        a = math.radians(start + 90)
        p0 = (cx_ + cr * math.cos(a), cy_ + cr * math.sin(a))
        nxt = corners[(corners.index((cx_, cy_, start)) + 1) % 4]
        p1 = (nxt[0] + cr * math.cos(a), nxt[1] + cr * math.sin(a))
        L = math.hypot(p1[0] - p0[0], p1[1] - p0[1])
        for t in np.linspace(0, 1, max(2, int(L / 0.2)), endpoint=False):
            segs.append((p0[0] + (p1[0] - p0[0]) * t, p0[1] + (p1[1] - p0[1]) * t))
    for x, y in segs:
        if y < -4 and abs(x) < 3.8:
            k = min(1, max(0, (3.8 - abs(x)) / 0.8))
            k = k * k * (3 - 2 * k)
            y = -4.25 + 0.35 * k   # спереди прижимаем к панели
        path.append((x, y, z0 - slope * y))
    return path

ropes.append(rope("BodyRope", body_loop(9.0, 0.29), 0.3, closed=True, hint=(0, 0, 1)))

# ─── Ручка ───
for sx in (-1, 1):
    body.append(wood(rbox("HandlePost", (1.0, 1.2, 3.2), (sx * 3.0, 0, TOP + 1.5), 0.14)))
body.append(wood(rbox("HandleBar", (7.0, 1.2, 1.1), (0, 0, TOP + 3.2), 0.16)))
hz = TOP + 3.2
helix = []
for t in np.linspace(0, 1, 300):
    x = -2.2 + 4.4 * t
    a = t * math.tau * 8.5
    helix.append((x, math.cos(a) * 0.82, hz + math.sin(a) * 0.78))
ropes.append(rope("HandleRope", helix, 0.24, twist=4.0))

# ─── Задняя стенка: прорези и разъёмы ───
for z in (10.3, 11.0, 11.7):
    body.append(paint(rbox("Vent", (3.2, 0.2, 0.36), (0, 3.85, z), 0.1), "HOLE"))
body.append(paint(rbox("JackPlate", (2.4, 0.2, 1.3), (0, 3.85, 6.0), 0.08), "PANEL"))
for x, col in ((-0.5, "JACK_W"), (0.5, "JACK_R")):
    body.append(paint(cyl_y("Jack", 0.3, 0.2, (x, 3.98, 6.0), 20), col))
    body.append(paint(cyl_y("JackHole", 0.12, 0.05, (x, 4.08, 6.0), 12), "HOLE"))

# ─── Облезлая голубая краска ───
def paint_patch(name, center, axis_u, axis_v, w, h, jag=0.25):
    cu = Vector(center)
    U, V = Vector(axis_u), Vector(axis_v)
    # мазок сухой кистью: прямоугольник с рваными верхним и нижним краями
    outline = []
    k = 14
    for i in range(k + 1):                      # верх, слева направо
        x = -w / 2 + w * i / k
        outline.append(cu + U * x + V * (h / 2 - jag * h * random.random()))
    for i in range(k + 1):                      # низ, справа налево
        x = w / 2 - w * i / k
        outline.append(cu + U * x + V * (-h / 2 + jag * h * random.random()))
    n = len(outline)
    verts = [cu] + outline
    faces = [(0, i + 1, (i + 1) % n + 1) for i in range(n)]
    return finish(face_colored(name, verts, faces, ["BLUE"] * n), 80)

decor.append(paint_patch("PaintSide", (-4.82, 0.1, 5.2), (0, 1, 0), (0, 0, 1), 4.9, 1.0, 0.35))
decor.append(paint_patch("PaintSide2", (-4.82, -0.4, 6.15), (0, 1, 0), (0, 0, 1), 3.6, 0.55, 0.45))
decor.append(paint_patch("PaintPost", (-4.25, -4.01, 5.4), (0, 0, 1), (1, 0, 0), 2.6, 1.2, 0.3))

# ─── Красная тряпка с пальмой ───
def cloth():
    ns, nt = 26, 40
    S0, S1 = 0.0, 5.6
    verts, uvs, idx = [], [], {}
    jag = [8.4 + 0.7 * ((i % 3) / 2.0) + 0.4 * random.random() for i in range(ns + 1)]
    for i in range(ns + 1):
        s = S0 + (S1 - S0) * i / ns
        tend = jag[i] - 0.9 * (i / ns) ** 1.5      # правый край короче
        for j in range(nt + 1):
            t = tend * j / nt
            X = -5.7 + s
            Y = 0.6 - t
            drop_x = max(0.0, -5.0 - X)
            drop_y = max(0.0, -4.05 - Y)
            x = max(X, -5.12)
            y = max(Y, -4.17)
            z = TOP + 0.24 - drop_x - drop_y
            wave = 0.1 * math.sin(s * 2.3 + t * 0.6) + 0.05 * math.sin(s * 5.1)
            if drop_y > 0:
                y -= wave + 0.02 * drop_y
            elif drop_x > 0:
                x -= wave
            else:
                z += wave * 0.6 + 0.08
            idx[(i, j)] = len(verts)
            verts.append(Vector((x, y, z)))
            uvs.append((0.5 + 0.5 * (s / S1) * 0.98 + 0.004, (1 - t / 9.0) * 0.5 * 0.98 + 0.004))
    bm = bmesh.new()
    bv = [bm.verts.new(v) for v in verts]
    uvl = bm.loops.layers.uv.new("UVMap")
    for i in range(ns):
        for j in range(nt):
            q = [idx[(i, j)], idx[(i + 1, j)], idx[(i + 1, j + 1)], idx[(i, j + 1)]]
            f = bm.faces.new([bv[k] for k in q])
            for lp, k in zip(f.loops, q):
                lp[uvl].uv = uvs[k]
    o = new_obj("Cloth", bm)
    m = o.modifiers.new("solid", "SOLIDIFY")
    m.thickness = 0.07
    m.offset = 1
    return finish(o, 60)

decor.append(cloth())

# ─── Пальмовые листья ───
def frond(name, base, yaw, length, lift, droop, width, K=18):
    d = Vector((math.cos(yaw), math.sin(yaw), 0))
    side = Vector((-d.y, d.x, 0))
    verts, faces, cols = [], [], []
    for i in range(K + 1):
        t = i / K
        p = Vector(base) + d * length * t + Vector((0, 0, lift * t * (1 - t) * 4 - droop * t * t))
        w = width * math.sin(math.pi * min(t, 0.97)) ** 0.6 * (1.0 if i % 2 == 0 else 0.6)
        verts += [p, p + side * w - Vector((0, 0, 0.18 * w)), p - side * w - Vector((0, 0, 0.18 * w))]
    for i in range(K):
        a, b = i * 3, (i + 1) * 3
        faces.append((a, b, b + 1, a + 1)); cols.append("LEAF")
        faces.append((a, a + 2, b + 2, b)); cols.append("LEAF_D")
    o = face_colored(name, verts, faces, cols, solid=0.06)
    return finish(o, 70)

LB = (-3.6, 0.6, TOP + 0.45)
for yaw, ln, lift, droop, w in ((180, 6.2, 1.0, 3.0, 1.35), (212, 6.4, 1.1, 2.6, 1.4),
                                (152, 5.6, 1.2, 2.8, 1.3), (118, 4.8, 1.3, 2.2, 1.2),
                                (240, 5.4, 1.0, 2.2, 1.25), (85, 4.2, 1.4, 2.0, 1.1)):
    decor.append(frond("Frond", LB, math.radians(yaw), ln, lift, droop, w))

# ─── Морская звезда ───
def starfish(name, loc, rot, R=1.25, r=0.5, h=0.42):
    verts = [(0, 0, h)]
    n = 10
    for i in range(n):
        a = math.tau * i / n + math.pi / 2
        rr = R if i % 2 == 0 else r
        verts.append((math.cos(a) * rr, math.sin(a) * rr, 0.14 if i % 2 == 0 else 0.2))
    for i in range(n):
        a = math.tau * i / n + math.pi / 2
        rr = R if i % 2 == 0 else r
        verts.append((math.cos(a) * rr, math.sin(a) * rr, 0.0))
    verts.append((0, 0, 0))
    faces, cols = [], []
    for i in range(n):
        i2 = (i + 1) % n
        faces.append((0, 1 + i, 1 + i2)); cols.append("STAR")
        faces.append((1 + i, 1 + n + i, 1 + n + i2, 1 + i2)); cols.append("STAR_D")
        faces.append((2 * n + 1, 1 + n + i2, 1 + n + i)); cols.append("STAR_D")
    o = face_colored(name, verts, faces, cols)
    o.rotation_euler = rot
    o.location = loc
    m = o.modifiers.new("sub", "SUBSURF")
    m.levels = 1
    return finish(o, 80)

decor.append(starfish("Starfish", (3.0, -3.3, TOP + 0.3), (0.3, 0.0, 0.4), R=1.75, r=0.62, h=0.6))

# ─── Ракушка ───
def shell(name, loc, rot):
    ni, nj = 22, 9
    verts, faces, cols = [], [], []
    for i in range(ni + 1):
        ph = math.radians(-72 + 144 * i / ni)
        for j in range(nj + 1):
            rho = 0.08 + 1.05 * j / nj
            rib = 0.06 * rho * abs(math.sin(ph * 9))
            bulge = 0.38 * (1 - (rho / 1.13) ** 2) * math.cos(ph * 0.8)
            verts.append((rho * math.sin(ph) * 1.1, -(bulge + rib), rho * math.cos(ph)))
    for i in range(ni):
        for j in range(nj):
            a = i * (nj + 1) + j
            faces.append((a, a + nj + 1, a + nj + 2, a + 1))
            cols.append("SHELL" if (i // 2) % 2 == 0 else "SHELL_D")
    o = face_colored(name, verts, faces, cols, solid=0.08)
    o.rotation_euler = rot
    o.location = loc
    o.scale = (1.6, 1.6, 1.6)
    return finish(o, 70)

decor.append(shell("Shell", (-3.1, -4.25, FEET + 0.35), (math.radians(-12), 0, math.radians(10))))

# ═══ Сборка в 4 меша ═══
body_o = join("Speaker_Body", body)
rope_o = join("Speaker_Rope", ropes)
decor_o = join("Speaker_Decor", decor)
cone_o = join("Speaker_WooferCone", cone_parts, origin=(0, WC.y, WC.z))

atlas = draw_atlas()
mat = bpy.data.materials.new("SpeakerAtlas")
mat.use_nodes = True
nt_ = mat.node_tree
bsdf = nt_.nodes["Principled BSDF"]
tex = nt_.nodes.new("ShaderNodeTexImage")
tex.image = atlas
nt_.links.new(tex.outputs["Color"], bsdf.inputs["Base Color"])
bsdf.inputs["Roughness"].default_value = 0.7

meshes = [body_o, rope_o, decor_o, cone_o]
for o in meshes:
    o.data.materials.clear()
    o.data.materials.append(mat)

def tris(o):
    return sum(len(p.vertices) - 2 for p in o.data.polygons)
print("TRIS", {o.name: tris(o) for o in meshes})
bb = [o.matrix_world @ Vector(c) for o in meshes for c in o.bound_box]
print("BBOX", [round(min(v[i] for v in bb), 2) for i in range(3)], [round(max(v[i] for v in bb), 2) for i in range(3)])

bpy.ops.wm.save_as_mainfile(filepath=os.path.join(OUT, "LobbySpeaker.blend"))

bpy.ops.object.select_all(action="DESELECT")
for o in meshes:
    o.select_set(True)
bpy.ops.export_scene.fbx(
    filepath=os.path.join(OUT, "LobbySpeaker.fbx"),
    use_selection=True, object_types={"MESH"},
    apply_unit_scale=True, apply_scale_options="FBX_SCALE_ALL",
    mesh_smooth_type="FACE", use_mesh_modifiers=True,
    path_mode="COPY", embed_textures=True,
    axis_forward="-Z", axis_up="Y",
)

# ═══ Превью ═══
scene = bpy.context.scene
for eng in ("BLENDER_EEVEE_NEXT", "BLENDER_EEVEE"):
    try:
        scene.render.engine = eng
        break
    except TypeError:
        pass
scene.render.resolution_x = 1100
scene.render.resolution_y = 1100
scene.view_settings.view_transform = "Standard"
world = bpy.data.worlds.new("World")
scene.world = world
world.use_nodes = True
world.node_tree.nodes["Background"].inputs["Color"].default_value = (0.16, 0.17, 0.22, 1)
world.node_tree.nodes["Background"].inputs["Strength"].default_value = 1.6
bpy.ops.object.light_add(type="SUN", rotation=(math.radians(50), math.radians(10), math.radians(-40)))
bpy.context.object.data.energy = 3.4
bpy.context.object.data.color = (1.0, 0.93, 0.84)

def shot(name, loc, target=(0, 0, 9.5), lens=50):
    bpy.ops.object.camera_add(location=loc)
    cam = bpy.context.object
    cam.data.lens = lens
    cam.rotation_euler = (Vector(target) - cam.location).to_track_quat("-Z", "Y").to_euler()
    scene.camera = cam
    scene.render.filepath = os.path.join(OUT, name)
    bpy.ops.render.render(write_still=True)

shot("preview_front34.png", (-20, -32, 15))
shot("preview_front.png", (0, -42, 10))
shot("preview_back34.png", (24, 30, 15))
print("DONE")
