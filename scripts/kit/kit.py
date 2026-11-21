"""Pocket Weather low-poly world kit (Blender 5.3, headless via the bpy module).
1 unit = 1 stud, Z up in Blender (glTF exports Y up). Every asset is built around its own origin
(bottom centre), then shifted to a slot on a grid so the whole kit ships as ONE GLB.
Object names: <Asset>__<Part>, e.g. Fir_A__Body, Fir_A__Snow. kit_layout.json lists each asset's slot.
Parts:
  Body   main mesh (vertex colours, MeshPart.Color stays white)
  Snow   winter-only overlay that follows the shape below it (roofs, tiers, canopy tops)
  Glow   window / lamp glass (set Material = Neon in Studio)
  Top    plot island grass (white-ish vertex shading, tinted by MeshPart.Color = theme grass)
Run:  python3 kit.py <out_dir>
"""
import sys, os, math, random, json
import bpy, bmesh
from mathutils import Vector, Matrix, Euler

OUT = sys.argv[-1] if len(sys.argv) > 1 and not sys.argv[-1].endswith(".py") else "out"
os.makedirs(OUT, exist_ok=True)

for o in list(bpy.data.objects):
    bpy.data.objects.remove(o, do_unlink=True)
for m in list(bpy.data.meshes):
    bpy.data.meshes.remove(m)
scene = bpy.context.scene
scene.unit_settings.system = "NONE"


def hx(h):
    h = h.lstrip("#")
    return tuple(int(h[i:i + 2], 16) / 255 for i in (0, 2, 4))


def mix(a, b, t):
    return tuple(a[i] * (1 - t) + b[i] * t for i in range(3))


def jit(rng, c, a=0.05):
    k = 1 + rng.uniform(-a, a)
    return tuple(max(0.0, min(1.0, v * k)) for v in c)


# ---------------------------------------------------------------- palette (sRGB)
BARK = [hx("#7A4A2A"), hx("#6B3F23"), hx("#86553A")]
BARK_DARK = hx("#553219")
FIR = [hx("#1F6B4A"), hx("#2A8257"), hx("#3C9A62"), hx("#5BB56E")]   # dark .. light
FIR_TIP = hx("#79C97A")
OAK = [hx("#3E8E3A"), hx("#5DAE45"), hx("#86C957")]
OAK2 = [hx("#2F8A4E"), hx("#4CAB5C"), hx("#7FCB6E")]
BUSH = [hx("#3A8F45"), hx("#55AB52"), hx("#7AC461")]
SNOW = hx("#F5F8FD")
SNOW_SH = hx("#D7E3F3")
ROCK = [hx("#7D7896"), hx("#8F8AA8"), hx("#A6A2BE"), hx("#BAB6CF")]
MOSS = hx("#6FAF55")
STONE = [hx("#B7B2C8"), hx("#A39EB6"), hx("#C8C4D6")]
PLASTER = [hx("#F4EAD6"), hx("#EFE2C9")]
TIMBER = [hx("#7B4E2E"), hx("#6E4427")]
ROOF_RED = [hx("#C2513C"), hx("#AE4634"), hx("#D06048")]
ROOF_BLUE = [hx("#3E77A8"), hx("#356A98"), hx("#4C86B6")]
ROOF_GREEN = [hx("#5E9A48"), hx("#538B3F"), hx("#6DAA55")]
ROOF_ORANGE = [hx("#D98A35"), hx("#C77B2C"), hx("#E49845")]
TRIM = hx("#F7F1E6")
DOOR = [hx("#7A4826"), hx("#6E4021")]
SHUTTER_BLUE = hx("#3D6E8C")
SHUTTER_GREEN = hx("#4E7F4A")
GLOW = hx("#FFF2D0")
IRON = hx("#2E3459")
BRASS = hx("#D9A945")
DIRT = [hx("#8A6343"), hx("#7A5638"), hx("#946B48")]
CLIFF = [hx("#857F9E"), hx("#736E8E"), hx("#9893B0"), hx("#6A6585")]
GRASS_TOP = [hx("#FFFFFF"), hx("#EEF3EE"), hx("#F7FBF4")]  # tinted in Studio
FLOWER = [hx("#FF6FA8"), hx("#FFD23F"), hx("#FFFFFF"), hx("#B98CFF"), hx("#FF8A4A")]


class MB:
    """Mesh builder: closed shells with face-corner vertex colours ('Col', sRGB)."""

    def __init__(self, name):
        self.name = name
        self.bm = bmesh.new()
        self.col = self.bm.loops.layers.color.new("Col")

    def add(self, verts, faces, colfn):
        vs = [self.bm.verts.new(Vector(v)) for v in verts]
        out = []
        for f in faces:
            try:
                face = self.bm.faces.new([vs[i] for i in f])
            except ValueError:
                continue
            face.normal_update()
            c = face.calc_center_median()
            for lp in face.loops:
                col = colfn(c, face.normal, lp.vert.co) if callable(colfn) else colfn
                lp[self.col] = (col[0], col[1], col[2], 1.0)
            out.append(face)
        return out

    def add_bm(self, tbm, M, colfn):
        tbm.verts.ensure_lookup_table()
        idx = {v: i for i, v in enumerate(tbm.verts)}
        verts = [M @ v.co for v in tbm.verts]
        faces = [[idx[v] for v in f.verts] for f in tbm.faces]
        tbm.free()
        return self.add(verts, faces, colfn)

    def box(self, lo, hi, col):
        x0, y0, z0 = lo
        x1, y1, z1 = hi
        v = [(x0, y0, z0), (x1, y0, z0), (x1, y1, z0), (x0, y1, z0), (x0, y0, z1), (x1, y0, z1), (x1, y1, z1), (x0, y1, z1)]
        f = [(0, 3, 2, 1), (4, 5, 6, 7), (0, 1, 5, 4), (1, 2, 6, 5), (2, 3, 7, 6), (3, 0, 4, 7)]
        return self.add(v, f, col)

    def obox(self, centre, size, M3, col):
        c = Vector(centre)
        hx_, hy, hz = (s / 2 for s in size)
        loc = [(-hx_, -hy, -hz), (hx_, -hy, -hz), (hx_, hy, -hz), (-hx_, hy, -hz), (-hx_, -hy, hz), (hx_, -hy, hz), (hx_, hy, hz), (-hx_, hy, hz)]
        v = [c + M3 @ Vector(p) for p in loc]
        f = [(0, 3, 2, 1), (4, 5, 6, 7), (0, 1, 5, 4), (1, 2, 6, 5), (2, 3, 7, 6), (3, 0, 4, 7)]
        return self.add(v, f, col)

    def tube(self, rings, col, cap0=True, cap1=True):
        """rings: list of lists of points (same count). Quads between rings, fan caps."""
        n = len(rings[0])
        verts = [p for r in rings for p in r]
        faces = []
        for i in range(len(rings) - 1):
            for k in range(n):
                a, b = i * n + k, i * n + (k + 1) % n
                faces.append((a, b, b + n, a + n))
        if cap0:
            c0 = len(verts)
            verts.append(sum((Vector(p) for p in rings[0]), Vector()) / n)
            for k in range(n):
                faces.append((c0, (k + 1) % n, k))
        if cap1:
            c1 = len(verts)
            verts.append(sum((Vector(p) for p in rings[-1]), Vector()) / n)
            base = (len(rings) - 1) * n
            for k in range(n):
                faces.append((c1, base + k, base + (k + 1) % n))
        return self.add(verts, faces, col)

    def cyl(self, p0, p1, r0, r1, n, col, phase=0.0, caps=True):
        p0, p1 = Vector(p0), Vector(p1)
        ax = (p1 - p0).normalized()
        u = ax.orthogonal().normalized()
        w = ax.cross(u)
        rings = []
        for p, r in ((p0, r0), (p1, r1)):
            rings.append([p + (u * math.cos(phase + 2 * math.pi * i / n) + w * math.sin(phase + 2 * math.pi * i / n)) * r for i in range(n)])
        return self.tube(rings, col, caps, caps)

    def ico(self, centre, scale, col, subdiv=2, rng=None, jitter=0.0, flat_bottom=0.0):
        tbm = bmesh.new()
        bmesh.ops.create_icosphere(tbm, subdivisions=subdiv, radius=1.0)
        if rng:
            for v in tbm.verts:
                n = v.co.normalized()
                d = 1 + rng.uniform(-jitter, jitter)
                if n.z < -0.3:
                    d *= 1 - flat_bottom
                v.co = n * d
        M = Matrix.Translation(centre) @ Matrix.Diagonal((*scale, 1))
        return self.add_bm(tbm, M, col)

    def to_object(self, name=None, smooth=False):
        bmesh.ops.remove_doubles(self.bm, verts=self.bm.verts, dist=1e-5)
        bmesh.ops.recalc_face_normals(self.bm, faces=self.bm.faces)
        me = bpy.data.meshes.new(name or self.name)
        self.bm.to_mesh(me)
        self.bm.free()
        for p in me.polygons:
            p.use_smooth = smooth
        ob = bpy.data.objects.new(name or self.name, me)
        scene.collection.objects.link(ob)
        ca = me.color_attributes["Col"]
        me.color_attributes.active_color = ca
        me.color_attributes.render_color_index = me.color_attributes.active_color_index
        mat = bpy.data.materials.get("VC") or bpy.data.materials.new("VC")
        mat.use_backface_culling = True
        try:
            mat.use_nodes = True
            nt = mat.node_tree
            if not any(n.type == "VERTEX_COLOR" for n in nt.nodes):
                bsdf = next(n for n in nt.nodes if n.type == "BSDF_PRINCIPLED")
                vc = nt.nodes.new("ShaderNodeVertexColor")
                vc.layer_name = "Col"
                nt.links.new(vc.outputs["Color"], bsdf.inputs["Base Color"])
                bsdf.inputs["Roughness"].default_value = 0.8
        except Exception:
            pass
        me.materials.append(mat)
        return ob


ASSETS = {}  # name -> list of objects


def register(asset, ob, part):
    ob.name = f"{asset}__{part}"
    ob.data.name = ob.name
    ASSETS.setdefault(asset, []).append(ob)


def shell_on(src_faces, mb, push, colfn, min_up=0.3, drop=0.0, lip=0.22):
    """Snow blanket: the up-facing faces of a shape, kept connected (shared verts pushed along their
    averaged normal), plus a short skirt hanging from the open edge so the layer reads as thick."""
    faces = [f for f in src_faces if f.is_valid and f.normal.z >= min_up]
    if not faces:
        return
    vn = {}
    for f in faces:
        for v in f.verts:
            vn.setdefault(v, Vector())
            vn[v] += f.normal
    idx, pts = {}, []
    for v, n in vn.items():
        n = n.normalized()
        idx[v] = len(pts)
        pts.append(v.co + n * push + Vector((0, 0, push * 0.4)))
    flist = [[idx[v] for v in f.verts] for f in faces]
    # boundary edges -> skirt
    count = {}
    for f in faces:
        for e in f.edges:
            count[e] = count.get(e, 0) + 1
    for f in faces:
        loops = list(f.loops)
        for lp in loops:
            e = lp.edge
            if count.get(e, 0) != 1:
                continue
            a, b = lp.vert, lp.link_loop_next.vert
            ia, ib = idx[a], idx[b]
            pa, pb = pts[ia], pts[ib]
            da = pa - Vector((0, 0, lip)) + (Vector((pa.x, pa.y, 0)) - Vector((0, 0, 0))).normalized() * 0.0
            db = pb - Vector((0, 0, lip))
            pts.append(da)
            pts.append(db)
            flist.append([ib, ia, len(pts) - 2, len(pts) - 1])
    mb.add(pts, flist, colfn)


# ================================================================== FIRS
def fir(name, seed, tiers, trunk_h, trunk_r, sides=9):
    rng = random.Random(seed)
    body = MB(name)
    snow = MB(name + "S")
    # trunk with flare
    rings = []
    for i, (z, r) in enumerate(((0, trunk_r * 1.5), (0.5, trunk_r * 1.1), (trunk_h, trunk_r * 0.75))):
        rings.append([Vector((math.cos(2 * math.pi * k / 7) * r * (1.15 if (i == 0 and k % 2 == 0) else 1), math.sin(2 * math.pi * k / 7) * r, z - (0.25 if i == 0 else 0))) for k in range(7)])
    body.tube(rings, lambda c, n, co: jit(rng, BARK[int(abs(c.x * 7 + c.z * 3)) % 3], 0.04))
    nt = len(tiers)
    for ti, (z, r, h) in enumerate(tiers):
        tw = rng.uniform(0, 0.6)
        t_norm = ti / max(1, nt - 1)
        # rim with ragged skirt: alternating long/short points that droop
        rim = []
        for k in range(sides * 2):
            a = tw + math.pi * 2 * k / (sides * 2)
            long = k % 2 == 0
            rr = r * (1.0 if long else 0.78) * rng.uniform(0.94, 1.06)
            dz = -(0.45 if long else 0.1) * (r / 3) - rng.uniform(0, 0.15)
            rim.append(Vector((math.cos(a) * rr, math.sin(a) * rr, z + dz)))
        inner = [Vector((p.x * 0.55, p.y * 0.55, z + h * 0.12)) for p in rim]
        tip = Vector((rng.uniform(-0.08, 0.08), rng.uniform(-0.08, 0.08), z + h))
        verts = rim + inner + [tip]
        m = len(rim)
        faces = []
        for k in range(m):
            faces.append((k, (k + 1) % m, m + (k + 1) % m, m + k))  # underside to inner ring
        for k in range(m):
            faces.append((k, 2 * m, (k + 1) % m))  # slopes to the tip

        def colfn(c, nrm, co, t_norm=t_norm, z=z, h=h):
            if nrm.z < -0.2:
                return jit(rng, FIR[0], 0.05)
            up = (c.z - z) / h
            idx = 1 + min(2, int(t_norm * 1.2 + up * 1.6))
            col = FIR[idx]
            if up > 0.8 and ti == nt - 1:
                col = FIR_TIP
            return jit(rng, col, 0.06)
        fs = body.add(verts, faces, colfn)
        # snow cap: from the tip down ~55% of the slope, ragged lower edge, pushed off the surface
        cap_rim = []
        for k in range(m):
            p = rim[k]
            t = rng.uniform(0.5, 0.7) if k % 2 == 0 else rng.uniform(0.4, 0.55)
            q = tip.lerp(p, t)
            d = Vector((q.x, q.y, 0)).normalized() if (q.x or q.y) else Vector((1, 0, 0))
            cap_rim.append(q + d * 0.14 + Vector((0, 0, 0.1)))
        ctip = tip + Vector((0, 0, 0.12))
        sverts = cap_rim + [ctip]
        sfaces = [(k, m, (k + 1) % m) for k in range(m)]
        lip = [p + Vector((0, 0, -0.16)) - Vector((p.x, p.y, 0)).normalized() * 0.08 for p in cap_rim]
        sverts += lip
        sfaces += [(k, (k + 1) % m, m + 1 + (k + 1) % m, m + 1 + k) for k in range(m)]
        snow.add(sverts, sfaces, lambda c, nrm, co: SNOW if nrm.z > 0.35 else SNOW_SH)
    register(name, body.to_object(), "Body")
    register(name, snow.to_object(), "Snow")


fir("Fir_A", 11, [(2.6, 4.4, 4.2), (4.9, 3.7, 3.9), (7.0, 3.0, 3.6), (8.9, 2.3, 3.3), (10.6, 1.5, 3.0)], 3.2, 0.7)
fir("Fir_B", 12, [(2.0, 5.0, 4.0), (4.3, 4.0, 3.8), (6.4, 2.9, 3.6), (8.2, 1.8, 3.2)], 2.6, 0.8)
fir("Fir_C", 13, [(3.2, 3.6, 3.6), (5.2, 3.2, 3.4), (7.0, 2.8, 3.2), (8.7, 2.3, 3.1), (10.3, 1.8, 2.9), (11.8, 1.2, 2.7)], 3.8, 0.6, sides=8)
fir("Fir_D", 14, [(1.4, 2.6, 2.6), (2.9, 2.0, 2.4), (4.2, 1.3, 2.2)], 1.8, 0.4, sides=8)


# ================================================================== ROUND TREES
def oak(name, seed, clumps, trunk_top, branches, palette, trunk_r=0.9):
    rng = random.Random(seed)
    body = MB(name)
    snow = MB(name + "S")
    # flared trunk, slight lean
    lean = Vector((rng.uniform(-0.4, 0.4), rng.uniform(-0.4, 0.4), 0))
    rings = []
    for i in range(5):
        t = i / 4
        c = Vector((0, 0, trunk_top * t)) + lean * t * t
        r = trunk_r * (1.6 - 0.75 * t) if i == 0 else trunk_r * (1.05 - 0.45 * t)
        rings.append([c + Vector((math.cos(2 * math.pi * k / 7 + i * 0.25) * r * (1.25 if (i == 0 and k % 2 == 0) else 1), math.sin(2 * math.pi * k / 7 + i * 0.25) * r, -0.25 if i == 0 else 0)) for k in range(7)])
    body.tube(rings, lambda c, n, co: jit(rng, BARK[int(abs(c.z * 2.3)) % 3], 0.04))
    for (h, d, L) in branches:
        p0 = Vector((0, 0, h)) + lean * (h / trunk_top) ** 2
        p1 = p0 + Vector(d).normalized() * L
        body.cyl(p0, p1, trunk_r * 0.42, trunk_r * 0.2, 6, BARK_DARK)
    zs = [c[0][2] for c in clumps]
    zlo, zhi = min(zs) - 2.5, max(zs) + 2.5
    for i, (c, r) in enumerate(clumps):
        cc = Vector(c) + lean

        def colfn(fc, nrm, co):
            t = (fc.z - zlo) / (zhi - zlo)
            if nrm.z < -0.35 or t < 0.3:
                return jit(rng, palette[0], 0.05)
            if t > 0.68 and nrm.z > 0.2:
                return jit(rng, palette[2], 0.05)
            return jit(rng, palette[1], 0.05)
        fs = body.ico(cc, r, colfn, subdiv=2, rng=rng, jitter=0.13, flat_bottom=0.18)
        shell_on(fs, snow, 0.14, lambda fc, nrm, co: SNOW if nrm.z > 0.6 else SNOW_SH, min_up=0.5)
    register(name, body.to_object(), "Body")
    register(name, snow.to_object(), "Snow")


oak("Oak_A", 21, [((0, 0, 9.0), (3.8, 3.6, 3.0)), ((2.8, 0.9, 7.6), (2.6, 2.4, 2.2)), ((-2.7, -0.8, 7.9), (2.5, 2.5, 2.2)),
                  ((0.7, -2.4, 8.2), (2.3, 2.2, 2.0)), ((-0.4, 2.1, 10.2), (2.3, 2.1, 1.9))], 6.8,
    [(4.0, (1, 0.3, 0.9), 2.7), (4.8, (-0.9, -0.4, 1.0), 2.3)], OAK)
oak("Oak_B", 22, [((0, 0, 7.4), (3.2, 3.0, 2.6)), ((2.2, -0.6, 6.2), (2.2, 2.1, 1.9)), ((-2.0, 0.8, 6.5), (2.2, 2.0, 1.9)),
                  ((0.2, 1.2, 8.8), (2.0, 1.9, 1.7))], 5.4, [(3.5, (1, -0.4, 0.8), 2.2)], OAK2, trunk_r=0.75)
oak("Oak_C", 23, [((0, 0, 11.0), (3.0, 2.9, 3.6)), ((0.3, 0.2, 13.6), (2.2, 2.1, 2.3)), ((1.6, -0.9, 9.6), (2.0, 1.9, 1.8)),
                  ((-1.6, 0.9, 9.9), (2.0, 1.9, 1.8))], 8.6, [(5.5, (1, 0.6, 1.2), 2.0), (6.5, (-1, -0.3, 1.0), 1.8)], OAK, trunk_r=0.7)


# ================================================================== PALM
def palm(name, seed, h=10.0):
    rng = random.Random(seed)
    body = MB(name)
    bend = Vector((2.2, 0.4, 0))
    segs = 7
    prev = None
    for i in range(segs):
        t0, t1 = i / segs, (i + 1) / segs
        p0 = Vector((0, 0, h * t0)) + bend * t0 * t0
        p1 = Vector((0, 0, h * t1)) + bend * t1 * t1
        r0, r1 = 0.62 - 0.22 * t0, 0.56 - 0.22 * t1
        body.cyl(p0, p1 + (p1 - p0).normalized() * 0.12, r0 * 1.12, r1, 7, jit(rng, BARK[i % 3] if i % 2 else hx("#9A6A44"), 0.03), phase=i * 0.3)
        prev = p1
    top = prev
    for k in range(8):
        a = k * math.pi * 2 / 8 + rng.uniform(-0.15, 0.15)
        d = Vector((math.cos(a), math.sin(a), 0))
        side = d.cross(Vector((0, 0, 1)))
        L = rng.uniform(4.6, 5.6)
        pts = []
        for j in range(6):
            t = j / 5
            p = top + d * L * t + Vector((0, 0, 1.1 * math.sin(t * 2.4) - 1.9 * t * t))
            w = 0.95 * math.sin(math.pi * min(1, t * 1.15 + 0.12))
            pts.append((p, w))
        # frond = thin strip with a raised spine (two triangles per segment each side), closed with thickness
        verts, faces = [], []
        for j, (p, w) in enumerate(pts):
            verts += [p + side * w - Vector((0, 0, 0.12)), p + Vector((0, 0, 0.12)), p - side * w - Vector((0, 0, 0.12)), p - Vector((0, 0, 0.06))]
        for j in range(len(pts) - 1):
            a0, b0 = j * 4, (j + 1) * 4
            faces += [(a0, b0, b0 + 1, a0 + 1), (a0 + 1, b0 + 1, b0 + 2, a0 + 2), (a0 + 2, b0 + 2, b0 + 3, a0 + 3), (a0 + 3, b0 + 3, b0, a0)]
        body.add(verts, faces, lambda c, nrm, co: jit(rng, OAK[2] if nrm.z > 0.3 else OAK[1], 0.06))
    for k in range(3):
        a = k * 2.1
        body.ico(top + Vector((math.cos(a) * 0.45, math.sin(a) * 0.45, -0.45)), (0.42, 0.42, 0.46), hx("#6B4A2B"), subdiv=1)
    register(name, body.to_object(), "Body")


palm("Palm_A", 31)
palm("Palm_B", 32, h=8.0)


# ================================================================== BUSHES, FLOWERS, GRASS
def bush(name, seed, blobs, palette, berries=None):
    rng = random.Random(seed)
    body = MB(name)
    snow = MB(name + "S")
    zhi = max(c[2] + r[2] for c, r in blobs)
    for c, r in blobs:
        def colfn(fc, nrm, co):
            t = fc.z / zhi
            if nrm.z < -0.3 or t < 0.3:
                return jit(rng, palette[0], 0.05)
            return jit(rng, palette[2] if (t > 0.7 and nrm.z > 0.3) else palette[1], 0.05)
        fs = body.ico(Vector(c), r, colfn, subdiv=2, rng=rng, jitter=0.12, flat_bottom=0.3)
        shell_on(fs, snow, 0.1, lambda fc, nrm, co: SNOW if nrm.z > 0.6 else SNOW_SH, min_up=0.55)
    if berries:
        for _ in range(berries[1]):
            c, r = rng.choice(blobs)
            a = rng.uniform(0, math.tau)
            el = rng.uniform(0.15, 0.9)
            p = Vector(c) + Vector((math.cos(a) * r[0] * math.cos(el), math.sin(a) * r[1] * math.cos(el), r[2] * math.sin(el))) * 1.02
            body.ico(p, (0.22, 0.22, 0.22), berries[0], subdiv=1)
    register(name, body.to_object(), "Body")
    register(name, snow.to_object(), "Snow")


bush("Bush_A", 41, [((0, 0, 1.0), (1.8, 1.6, 1.3)), ((1.3, 0.5, 0.8), (1.2, 1.1, 1.0)), ((-1.2, -0.3, 0.8), (1.2, 1.2, 1.0))], BUSH, (hx("#FF5C8A"), 9))
bush("Bush_B", 42, [((0, 0, 0.9), (1.5, 1.4, 1.1)), ((0.9, -0.8, 0.7), (1.0, 1.0, 0.9))], OAK2)
bush("Bush_C", 43, [((0, 0, 1.3), (2.2, 2.0, 1.6)), ((1.9, 0.4, 0.9), (1.4, 1.3, 1.1)), ((-1.6, 0.6, 1.0), (1.4, 1.4, 1.2)), ((0.2, -1.6, 0.9), (1.3, 1.2, 1.0))], BUSH, (hx("#FFE14A"), 7))


def flowers(name, seed, n, colours):
    rng = random.Random(seed)
    body = MB(name)
    for i in range(n):
        a = rng.uniform(0, math.tau)
        r = rng.uniform(0, 1.2)
        base = Vector((math.cos(a) * r, math.sin(a) * r, 0))
        h = rng.uniform(0.9, 1.6)
        top = base + Vector((rng.uniform(-0.15, 0.15), rng.uniform(-0.15, 0.15), h))
        body.cyl(base - Vector((0, 0, 0.1)), top, 0.07, 0.05, 4, hx("#3E8E3A"))
        # two leaves
        for s in (-1, 1):
            lp = base.lerp(top, 0.35)
            d = Vector((math.cos(a + s * 1.4), math.sin(a + s * 1.4), 0.35))
            body.add([lp, lp + d * 0.55 + Vector((0, 0, 0.12)), lp + d * 0.25 + Vector((0, 0, 0.28))], [(0, 1, 2), (0, 2, 1)], hx("#4CAB5C"))
        col = colours[i % len(colours)]
        petals = 5
        ring = []
        for k in range(petals):
            pa = k * math.tau / petals + rng.uniform(0, 0.3)
            ring.append(top + Vector((math.cos(pa) * 0.34, math.sin(pa) * 0.34, 0.06)))
        mid = []
        for k in range(petals):
            pa = (k + 0.5) * math.tau / petals
            mid.append(top + Vector((math.cos(pa) * 0.16, math.sin(pa) * 0.16, 0.1)))
        # star-shaped head (closed thin disc)
        verts = []
        for k in range(petals):
            verts += [ring[k], mid[k]]
        topc = top + Vector((0, 0, 0.14))
        botc = top - Vector((0, 0, 0.02))
        verts += [topc, botc]
        m = len(verts) - 2
        faces = [(m, k, (k + 1) % m) for k in range(m)] + [(m + 1, (k + 1) % m, k) for k in range(m)]
        body.add(verts, faces, lambda c, nrm, co, col=col: col if nrm.z > -0.2 else mix(col, (0.3, 0.3, 0.3), 0.3))
        body.ico(topc, (0.11, 0.11, 0.07), hx("#FFC23A") if col != hx("#FFD23F") else hx("#FF8A4A"), subdiv=1)
    register(name, body.to_object(), "Body")


flowers("Flowers_A", 51, 9, [FLOWER[0], FLOWER[2], FLOWER[1]])
flowers("Flowers_B", 52, 8, [FLOWER[3], FLOWER[4], FLOWER[2]])


def grass(name, seed, n=11):
    rng = random.Random(seed)
    body = MB(name)
    for i in range(n):
        a = rng.uniform(0, math.tau)
        r = rng.uniform(0, 0.5)
        base = Vector((math.cos(a) * r, math.sin(a) * r, -0.05))
        h = rng.uniform(0.8, 1.6)
        lean = Vector((math.cos(a), math.sin(a), 0)) * rng.uniform(0.2, 0.5)
        side = Vector((-math.sin(a), math.cos(a), 0)) * 0.14
        tip = base + lean + Vector((0, 0, h))
        body.add([base - side, base + side, tip, base + Vector((math.cos(a), math.sin(a), 0)) * 0.06], [(0, 1, 2), (1, 3, 2), (3, 0, 2)],
                 lambda c, nrm, co: mix(hx("#3E8E3A"), hx("#8ED16A"), max(0, min(1, co.z / 1.4))))
    register(name, body.to_object(), "Body")


grass("Grass_A", 61)


# ================================================================== ROCKS
def rock(name, seed, scale, moss=False, subdiv=1):
    rng = random.Random(seed)
    body = MB(name)
    snow = MB(name + "S")
    tbm = bmesh.new()
    bmesh.ops.create_icosphere(tbm, subdivisions=subdiv, radius=1.0)
    for v in tbm.verts:
        n = v.co.normalized()
        d = rng.uniform(0.86, 1.08)
        p = n * d
        if p.z < -0.2:
            p.z = -0.2 + (p.z + 0.2) * 0.25
        v.co = p
    # a couple of planar cuts for chiselled faces
    for _ in range(5):
        pn = Vector((rng.uniform(-1, 1), rng.uniform(-1, 1), rng.uniform(-0.2, 1))).normalized()
        cut = rng.uniform(0.72, 0.86)
        for v in tbm.verts:
            dist = v.co.dot(pn)
            if dist > cut:
                v.co -= pn * (dist - cut)
    M = Matrix.Diagonal((*scale, 1)) @ Matrix.Translation((0, 0, 0.2))

    def colfn(c, nrm, co):
        if moss and nrm.z > 0.6:
            return jit(rng, MOSS, 0.05)
        t = max(0, min(3, int((nrm.z + 0.6) * 2.2)))
        return jit(rng, ROCK[t], 0.04)
    fs = body.add_bm(tbm, M, colfn)
    shell_on(fs, snow, 0.1, lambda c, nrm, co: SNOW if nrm.z > 0.6 else SNOW_SH, min_up=0.5)
    register(name, body.to_object(), "Body")
    register(name, snow.to_object(), "Snow")


rock("Rock_A", 71, (2.2, 1.7, 1.5), subdiv=2)
rock("Rock_B", 72, (1.4, 1.2, 1.6), moss=True, subdiv=2)
rock("Rock_C", 73, (3.4, 2.6, 2.0), subdiv=2)
rock("Rock_D", 74, (1.0, 0.9, 0.7), subdiv=2)


# ================================================================== HOUSES
def gable_house(name, seed, W, D, H, pitch, roof_pal, shutter, two_storey=False, porch=False, dormer=False):
    """Timber-frame cottage. Footprint W (x) by D (y), eave height H, ridge along X. Front = -Y."""
    rng = random.Random(seed)
    body = MB(name)
    glow = MB(name + "G")
    snow = MB(name + "S")
    hx_, hy = W / 2, D / 2
    base_h = 1.0
    # stone base: course of chunky blocks
    x = -hx_ - 0.3
    while x < hx_ + 0.3:
        L = min(rng.uniform(1.4, 2.4), hx_ + 0.3 - x)
        for y0, y1 in ((-hy - 0.3, -hy + 0.4), (hy - 0.4, hy + 0.3)):
            body.box((x + 0.05, y0, 0), (x + L - 0.05, y1, base_h + rng.uniform(-0.08, 0.08)), jit(rng, rng.choice(STONE), 0.04))
        x += L
    y = -hy + 0.4
    while y < hy - 0.4:
        L = min(rng.uniform(1.4, 2.4), hy - 0.4 - y)
        for x0, x1 in ((-hx_ - 0.3, -hx_ + 0.4), (hx_ - 0.4, hx_ + 0.3)):
            body.box((x0, y + 0.05, 0), (x1, y + L - 0.05, base_h + rng.uniform(-0.08, 0.08)), jit(rng, rng.choice(STONE), 0.04))
        y += L
    # walls (plaster) inset slightly, timber frame proud
    body.box((-hx_ + 0.1, -hy + 0.1, base_h), (hx_ - 0.1, hy - 0.1, H), PLASTER[0])
    rise = math.tan(math.radians(pitch)) * (hy + 0.1)
    # gable wall triangles (x faces)
    for sx in (-1, 1):
        xx = sx * (hx_ - 0.1)
        v = [(xx, -hy + 0.1, H), (xx, hy - 0.1, H), (xx, 0, H + rise - 0.2)]
        v2 = [(xx - sx * 0.3, -hy + 0.1, H), (xx - sx * 0.3, hy - 0.1, H), (xx - sx * 0.3, 0, H + rise - 0.2)]
        body.add(v + v2, [(0, 1, 2) if sx > 0 else (0, 2, 1), (3, 5, 4) if sx > 0 else (3, 4, 5)], PLASTER[1])
    tw = 0.45
    # corner posts, sill and head beams
    for sx in (-1, 1):
        for sy in (-1, 1):
            body.box((sx * hx_ - tw / 2 - 0.05 * sx, sy * hy - tw / 2, base_h), (sx * hx_ + tw / 2 - 0.05 * sx, sy * hy + tw / 2, H), TIMBER[0])
    for sy in (-1, 1):
        body.box((-hx_, sy * hy - tw / 2, H - tw), (hx_, sy * hy + tw / 2, H), TIMBER[1])
        body.box((-hx_, sy * hy - tw / 2, base_h), (hx_, sy * hy + tw / 2, base_h + tw * 0.8), TIMBER[1])
        if two_storey:
            body.box((-hx_, sy * hy - tw / 2, (base_h + H) / 2 - tw / 2), (hx_, sy * hy + tw / 2, (base_h + H) / 2 + tw / 2), TIMBER[0])
    for sx in (-1, 1):
        body.box((sx * hx_ - tw / 2, -hy, H - tw), (sx * hx_ + tw / 2, hy, H), TIMBER[1])
        # gable diagonal braces
        xx = sx * (hx_ + 0.12)
        body.obox((xx, -hy / 2, H + rise / 2 - 0.1), (0.3, math.hypot(hy, rise), 0.35), Matrix.Rotation(math.atan2(rise, hy), 3, "X"), TIMBER[0])
        body.obox((xx, hy / 2, H + rise / 2 - 0.1), (0.3, math.hypot(hy, rise), 0.35), Matrix.Rotation(-math.atan2(rise, hy), 3, "X"), TIMBER[0])

    # windows: frame, glass (glow), sill (+ snow), shutters, flower box on the front
    def window(cx, cz, face_y, w=2.2, h=2.4, flower_box=False):
        s = 1 if face_y > 0 else -1
        fy = face_y + s * 0.18
        body.box((cx - w / 2 - 0.25, fy - 0.1, cz - h / 2 - 0.25), (cx + w / 2 + 0.25, fy + 0.1, cz + h / 2 + 0.25), TRIM)
        glow.box((cx - w / 2, fy + s * 0.05 - 0.05, cz - h / 2), (cx + w / 2, fy + s * 0.05 + 0.05, cz + h / 2), GLOW)
        body.box((cx - 0.08, fy + s * 0.12 - 0.06, cz - h / 2), (cx + 0.08, fy + s * 0.12 + 0.06, cz + h / 2), TRIM)
        body.box((cx - w / 2, fy + s * 0.12 - 0.06, cz - 0.08), (cx + w / 2, fy + s * 0.12 + 0.06, cz + 0.08), TRIM)
        sill_y0, sill_y1 = sorted((fy, fy + s * 0.55))
        body.box((cx - w / 2 - 0.45, sill_y0, cz - h / 2 - 0.42), (cx + w / 2 + 0.45, sill_y1, cz - h / 2 - 0.2), TRIM)
        snow.box((cx - w / 2 - 0.4, sill_y0 + 0.03, cz - h / 2 - 0.2), (cx + w / 2 + 0.4, sill_y1 - 0.03 * s, cz - h / 2 - 0.02), SNOW)
        for sx in (-1, 1):
            body.box((cx + sx * (w / 2 + 0.3) - 0.55 + (0.55 if sx > 0 else 0), fy - 0.08 + s * 0.06, cz - h / 2 - 0.1),
                     (cx + sx * (w / 2 + 0.3) + (0.55 if sx > 0 else 0), fy + 0.08 + s * 0.06, cz + h / 2 + 0.1), shutter)
        if flower_box:
            by0, by1 = sorted((fy + s * 0.1, fy + s * 0.75))
            body.box((cx - w / 2 - 0.2, by0, cz - h / 2 - 1.05), (cx + w / 2 + 0.2, by1, cz - h / 2 - 0.45), TIMBER[1])
            for k in range(5):
                px = cx - w / 2 + k * w / 4
                body.ico((px, (by0 + by1) / 2, cz - h / 2 - 0.35), (0.32, 0.32, 0.28), BUSH[1], subdiv=1)
                body.ico((px + 0.12, (by0 + by1) / 2, cz - h / 2 - 0.12), (0.16, 0.16, 0.14), FLOWER[k % 3], subdiv=1)
    wz = base_h + (H - base_h) * (0.45 if not two_storey else 0.27)
    door_w, door_h = 2.4, 4.4
    window(-W * 0.3, wz, -hy, flower_box=True)
    window(W * 0.3, wz, -hy, flower_box=True)
    window(-W * 0.25, wz, hy)
    window(W * 0.25, wz, hy)
    if two_storey:
        wz2 = base_h + (H - base_h) * 0.75
        window(-W * 0.3, wz2, -hy, w=1.8, h=2.0)
        window(0, wz2, -hy, w=1.8, h=2.0)
        window(W * 0.3, wz2, -hy, w=1.8, h=2.0)
    # door: frame, planks, knob, lamp, steps, small canopy
    fy = -hy - 0.15
    body.box((-door_w / 2 - 0.35, fy - 0.12, base_h - 0.1), (door_w / 2 + 0.35, fy + 0.1, base_h + door_h + 0.35), TRIM)
    for k in range(4):
        x0 = -door_w / 2 + k * door_w / 4
        body.box((x0 + 0.03, fy - 0.2, base_h), (x0 + door_w / 4 - 0.03, fy - 0.08, base_h + door_h), DOOR[k % 2])
    body.ico((door_w / 2 - 0.4, fy - 0.3, base_h + door_h * 0.48), (0.14, 0.14, 0.14), BRASS, subdiv=1)
    for i in range(2):
        body.box((-door_w / 2 - 0.5 - i * 0.3, fy - 0.9 - i * 0.8, 0), (door_w / 2 + 0.5 + i * 0.3, fy - i * 0.8, base_h - i * 0.5), jit(rng, STONE[i], 0.03))
    # door canopy (small gable) + its snow
    cz = base_h + door_h + 0.55
    cr = 0.9
    body.add([(-door_w / 2 - 0.7, fy, cz), (door_w / 2 + 0.7, fy, cz), (door_w / 2 + 0.7, fy - 1.6, cz - 0.6), (-door_w / 2 - 0.7, fy - 1.6, cz - 0.6),
              (-door_w / 2 - 0.7, fy, cz + 0.25), (door_w / 2 + 0.7, fy, cz + 0.25), (door_w / 2 + 0.7, fy - 1.6, cz - 0.35), (-door_w / 2 - 0.7, fy - 1.6, cz - 0.35)],
             [(0, 3, 2, 1), (4, 5, 6, 7), (0, 1, 5, 4), (1, 2, 6, 5), (2, 3, 7, 6), (3, 0, 4, 7)], roof_pal[1])
    snow.add([(-door_w / 2 - 0.65, fy, cz + 0.27), (door_w / 2 + 0.65, fy, cz + 0.27), (door_w / 2 + 0.65, fy - 1.62, cz - 0.32), (-door_w / 2 - 0.65, fy - 1.62, cz - 0.32),
              (-door_w / 2 - 0.65, fy, cz + 0.52), (door_w / 2 + 0.65, fy, cz + 0.52), (door_w / 2 + 0.65, fy - 1.66, cz - 0.1), (-door_w / 2 - 0.65, fy - 1.66, cz - 0.1)],
             [(0, 3, 2, 1), (4, 5, 6, 7), (0, 1, 5, 4), (1, 2, 6, 5), (2, 3, 7, 6), (3, 0, 4, 7)], SNOW)
    _ = cr
    # wall lamp
    body.box((door_w / 2 + 0.7, fy - 0.15, base_h + door_h - 0.3), (door_w / 2 + 0.9, fy - 0.6, base_h + door_h - 0.1), IRON)
    glow.box((door_w / 2 + 0.55, fy - 0.85, base_h + door_h - 0.9), (door_w / 2 + 1.05, fy - 0.45, base_h + door_h - 0.25), hx("#FFD27A"))
    body.box((door_w / 2 + 0.5, fy - 0.9, base_h + door_h - 0.25), (door_w / 2 + 1.1, fy - 0.4, base_h + door_h - 0.12), IRON)
    # ---- roof: two thick slabs with overhang + shingle rows + ridge cap; snow layer follows each slope
    ox, oy, th = 0.9, 1.1, 0.5
    ang = math.radians(pitch)
    slope_len = (hy + oy) / math.cos(ang)
    ridge_z = H + rise

    def slab(sy, z_off, thick, length_pad, col, mb, inset=0.0, lip=0.0):
        # slab whose top surface runs from the ridge (y=0) down to the eave on side sy
        nrm = Vector((0, sy * math.sin(ang), math.cos(ang)))
        down = Vector((0, sy * math.cos(ang), -math.sin(ang)))
        top0 = Vector((0, 0, ridge_z + th * 0.6 + z_off))
        x0, x1 = -hx_ - ox - length_pad + inset, hx_ + ox + length_pad - inset
        L = slope_len + lip
        a = Vector((x0, 0, 0)) + top0
        b = Vector((x1, 0, 0)) + top0
        c = b + down * L
        d = a + down * L
        v = [a, b, c, d, a - nrm * thick, b - nrm * thick, c - nrm * thick, d - nrm * thick]
        f = [(0, 1, 2, 3), (4, 7, 6, 5), (0, 4, 5, 1), (1, 5, 6, 2), (2, 6, 7, 3), (3, 7, 4, 0)]
        if sy < 0:
            f = [tuple(reversed(q)) for q in f]
        return mb.add(v, f, col)
    for sy in (-1, 1):
        slab(sy, 0, th, 0, lambda c, nrm, co: jit(rng, roof_pal[0] if nrm.z > 0.2 else hx("#5A3A26"), 0.03), body)
        # shingle rows: thin stepped strips on top of the slab
        rows = 6
        for r_ in range(rows):
            t0 = (r_ + 0.15) / rows
            nrm = Vector((0, sy * math.sin(ang), math.cos(ang)))
            down = Vector((0, sy * math.cos(ang), -math.sin(ang)))
            base_p = Vector((0, 0, ridge_z + th * 0.6)) + down * (slope_len * t0)
            seg = 0
            x = -hx_ - ox
            while x < hx_ + ox - 0.1:
                L = min(rng.uniform(1.6, 2.6), hx_ + ox - x)
                p0 = base_p + Vector((x + 0.04, 0, 0))
                M3 = Matrix((Vector((1, 0, 0)), down, nrm)).transposed()
                ctr = p0 + Vector((L / 2 - 0.04, 0, 0)) + down * (slope_len / rows * 0.5) + nrm * 0.1
                body.obox(ctr, (L - 0.08, slope_len / rows * 0.98, 0.2), M3, jit(rng, roof_pal[seg % 3], 0.05))
                x += L
                seg += 1
        # snow: one slab following the slope, thinner at the ridge, with a rounded lip over the eave
        slab(sy, 0.32, 0.36, 0.05, lambda c, nrm, co: SNOW if nrm.z > 0.3 else SNOW_SH, snow, inset=0.0, lip=0.25)
        # snow lumps along the eave
        down = Vector((0, sy * math.cos(ang), -math.sin(ang)))
        eave = Vector((0, 0, ridge_z + th * 0.6 + 0.32)) + down * (slope_len + 0.25)
        x = -hx_ - ox + 0.4
        while x < hx_ + ox - 0.3:
            snow.ico(eave + Vector((x, 0, -0.05)), (rng.uniform(0.55, 0.85), 0.32, 0.26), SNOW_SH, subdiv=1)
            x += rng.uniform(0.9, 1.4)
    # ridge cap
    body.obox((0, 0, ridge_z + th * 0.6 + 0.12), (W + 2 * ox + 0.2, 0.7, 0.45), Matrix.Rotation(math.radians(45), 3, "X"), hx("#6A3B26"))
    snow.obox((0, 0, ridge_z + th * 0.6 + 0.5), (W + 2 * ox + 0.1, 0.75, 0.55), Matrix.Rotation(math.radians(45), 3, "X"), SNOW)
    # chimney (brick courses) + snow cap
    cx, cy = W * 0.28, D * 0.18
    ch_top = ridge_z + 2.4
    z = H
    k = 0
    while z < ch_top:
        hh = 0.5
        body.box((cx - 0.9 - (0.06 if k % 2 else 0), cy - 0.9, z), (cx + 0.9 + (0.06 if k % 2 else 0), cy + 0.9, z + hh), jit(rng, [hx("#B65A47"), hx("#A84E3D"), hx("#C46852")][k % 3], 0.03))
        z += hh
        k += 1
    body.box((cx - 1.05, cy - 1.05, ch_top), (cx + 1.05, cy + 1.05, ch_top + 0.35), hx("#7E7A8E"))
    body.box((cx - 0.5, cy - 0.5, ch_top + 0.35), (cx + 0.5, cy + 0.5, ch_top + 0.5), hx("#2E2A2A"))
    snow.box((cx - 1.0, cy - 1.0, ch_top + 0.36), (cx + 1.0, cy + 1.0, ch_top + 0.7), SNOW)
    if porch:
        # side porch deck with posts and a lean-to roof
        px0, px1 = hx_ + 0.3, hx_ + 4.2
        for i in range(6):
            yy = -hy + i * (D / 6)
            body.box((px0, yy + 0.05, base_h - 0.3), (px1, yy + D / 6 - 0.05, base_h), jit(rng, TIMBER[i % 2], 0.04))
        for sy in (-1, 1):
            body.box((px1 - 0.45, sy * (hy - 0.4) - 0.22, base_h), (px1 - 0.05, sy * (hy - 0.4) + 0.22, H - 0.6), TIMBER[0])
        body.add([(px0 - 0.2, -hy - 0.3, H + 0.3), (px1 + 0.6, -hy - 0.3, H - 1.0), (px1 + 0.6, hy + 0.3, H - 1.0), (px0 - 0.2, hy + 0.3, H + 0.3),
                  (px0 - 0.2, -hy - 0.3, H + 0.6), (px1 + 0.6, -hy - 0.3, H - 0.7), (px1 + 0.6, hy + 0.3, H - 0.7), (px0 - 0.2, hy + 0.3, H + 0.6)],
                 [(0, 1, 2, 3), (4, 7, 6, 5), (0, 4, 5, 1), (1, 5, 6, 2), (2, 6, 7, 3), (3, 7, 4, 0)], roof_pal[2])
        snow.add([(px0 - 0.15, -hy - 0.25, H + 0.62), (px1 + 0.65, -hy - 0.25, H - 0.68), (px1 + 0.65, hy + 0.25, H - 0.68), (px0 - 0.15, hy + 0.25, H + 0.62),
                  (px0 - 0.15, -hy - 0.25, H + 0.92), (px1 + 0.7, -hy - 0.25, H - 0.42), (px1 + 0.7, hy + 0.25, H - 0.42), (px0 - 0.15, hy + 0.25, H + 0.92)],
                 [(0, 1, 2, 3), (4, 7, 6, 5), (0, 4, 5, 1), (1, 5, 6, 2), (2, 6, 7, 3), (3, 7, 4, 0)], SNOW)
        for k in range(3):
            body.ico((px1 - 1.0 - k * 1.2, hy - 0.9, base_h + 0.5), (0.45, 0.45, 0.5), hx("#B65A47"), subdiv=1)
            body.ico((px1 - 1.0 - k * 1.2, hy - 0.9, base_h + 1.05), (0.5, 0.5, 0.42), BUSH[1], subdiv=1)
    if dormer:
        # dormer on the front slope
        dz = H + rise * 0.45
        dy = -hy * 0.45
        body.box((-1.4, dy - 1.4, dz - 1.0), (1.4, dy + 0.4, dz + 1.6), PLASTER[0])
        glow.box((-0.8, dy - 1.47, dz - 0.4), (0.8, dy - 1.4, dz + 1.0), GLOW)
        body.box((-1.0, dy - 1.52, dz - 0.6), (1.0, dy - 1.42, dz + 1.2), TRIM)
        for sx in (-1, 1):
            body.obox((sx * 0.95, dy - 0.5, dz + 2.1), (2.2, 2.6, 0.35), Matrix.Rotation(-sx * math.radians(38), 3, "Y"), roof_pal[0])
            snow.obox((sx * 0.95, dy - 0.5, dz + 2.42), (2.1, 2.62, 0.3), Matrix.Rotation(-sx * math.radians(38), 3, "Y"), SNOW)
    register(name, body.to_object(), "Body")
    register(name, glow.to_object(), "Glow")
    register(name, snow.to_object(), "Snow")


gable_house("House_A", 81, 13, 10, 8.0, 38, ROOF_RED, SHUTTER_BLUE)
gable_house("House_B", 82, 11, 9, 11.0, 42, ROOF_BLUE, SHUTTER_GREEN, two_storey=True)
gable_house("House_C", 83, 15, 10, 8.0, 34, ROOF_GREEN, SHUTTER_BLUE, porch=True)
gable_house("House_D", 84, 12, 9, 8.5, 40, ROOF_ORANGE, SHUTTER_GREEN)


# ================================================================== STREET LAMP
def street_lamp(name):
    body = MB(name)
    glow = MB(name + "G")
    snow = MB(name + "S")
    body.cyl((0, 0, 0), (0, 0, 0.5), 0.9, 0.8, 8, IRON, phase=0.2)
    body.cyl((0, 0, 0.5), (0, 0, 1.2), 0.55, 0.42, 8, IRON, phase=0.2)
    body.cyl((0, 0, 1.2), (0, 0, 8.4), 0.26, 0.2, 8, IRON, phase=0.2)
    for z in (2.6, 6.2):
        body.cyl((0, 0, z), (0, 0, z + 0.25), 0.36, 0.36, 8, BRASS)
    # lantern: base plate, 4 corner posts, glass, roof, finial
    body.cyl((0, 0, 8.4), (0, 0, 8.65), 0.75, 0.75, 8, IRON, phase=math.pi / 8)
    for k in range(4):
        a = math.pi / 4 + k * math.pi / 2
        body.box((math.cos(a) * 0.62 - 0.08, math.sin(a) * 0.62 - 0.08, 8.65), (math.cos(a) * 0.62 + 0.08, math.sin(a) * 0.62 + 0.08, 10.0), IRON)
    glow.cyl((0, 0, 8.7), (0, 0, 9.95), 0.55, 0.62, 8, hx("#FFE7A8"), phase=math.pi / 8)
    body.cyl((0, 0, 10.0), (0, 0, 10.25), 0.95, 0.95, 8, IRON, phase=math.pi / 8)
    body.cyl((0, 0, 10.25), (0, 0, 10.95), 0.85, 0.15, 8, IRON, phase=math.pi / 8)
    body.ico((0, 0, 11.05), (0.18, 0.18, 0.18), BRASS, subdiv=1)
    snow.cyl((0, 0, 10.26), (0, 0, 10.75), 0.98, 0.3, 8, SNOW, phase=math.pi / 8)
    register(name, body.to_object(), "Body")
    register(name, glow.to_object(), "Glow")
    register(name, snow.to_object(), "Snow")


street_lamp("Lamp_A")


# ================================================================== PLOT ISLAND
def plot_island(name, seed, rx=18.0, ry=24.0):
    """Floating mini island: grass top (flat at z=0, tinted in Studio), dirt rim, layered cliff tapering to
    a rocky point. Front (bridge side) = +Y in Blender = -Z in Roblox... handled in Studio by rotation."""
    rng = random.Random(seed)
    top = MB(name + "T")
    cliff = MB(name + "C")
    n = 40
    outline = []
    for k in range(n):
        a = k * math.tau / n
        wob = 1 + 0.06 * math.sin(a * 3 + 1.3) + 0.04 * math.sin(a * 7) + rng.uniform(-0.025, 0.025)
        outline.append(Vector((math.cos(a) * rx * wob, math.sin(a) * ry * wob, 0)))
    centre = Vector((0, 0, 0))
    # grass top: fan with a second ring for gentle shading variation, plus a bevelled lip
    inner = [p * 0.6 for p in outline]
    verts = outline + inner + [centre]
    faces = [(k, (k + 1) % n, n + (k + 1) % n, n + k) for k in range(n)] + [(n + k, n + (k + 1) % n, 2 * n) for k in range(n)]
    top.add(verts, faces, lambda c, nrm, co: jit(rng, GRASS_TOP[rng.randrange(3)], 0.02))
    lip = [p * 1.015 + Vector((0, 0, -0.6)) for p in outline]
    top.add(outline + lip, [(k, n + k, n + (k + 1) % n, (k + 1) % n) for k in range(n)], lambda c, nrm, co: GRASS_TOP[1])
    # dirt band + strata rings tapering to a point
    layers = [(-0.6, 1.015, DIRT), (-1.8, 0.99, DIRT), (-3.2, 0.93, CLIFF), (-5.5, 0.84, CLIFF), (-8.0, 0.70, CLIFF), (-11.0, 0.52, CLIFF), (-14.5, 0.33, CLIFF), (-18.5, 0.16, CLIFF)]
    rings = []
    for li, (z, s, pal) in enumerate(layers):
        ring = []
        for k, p in enumerate(outline):
            j = rng.uniform(0.9, 1.08) if li > 1 else rng.uniform(0.98, 1.02)
            ring.append(Vector((p.x * s * j, p.y * s * j, z + rng.uniform(-0.5, 0.5) * (li > 1))))
        rings.append(ring)
    tipv = Vector((rng.uniform(-1, 1), rng.uniform(-1, 1), -22.5))
    for li in range(len(rings) - 1):
        pal = layers[li + 1][2]
        a, b = rings[li], rings[li + 1]
        for k in range(n):
            col = jit(rng, pal[(li + k // 3) % len(pal)], 0.05)
            cliff.add([a[k], a[(k + 1) % n], b[(k + 1) % n], b[k]], [(0, 3, 2, 1)], col)
    last = rings[-1]
    for k in range(n):
        cliff.add([last[k], last[(k + 1) % n], tipv], [(0, 2, 1)], jit(rng, CLIFF[3], 0.05))
    # hanging rocks + roots
    for _ in range(9):
        k = rng.randrange(n)
        p = rings[3][k]
        cliff.ico(p * 0.96 + Vector((0, 0, -rng.uniform(0.5, 2.5))), (rng.uniform(1.2, 2.2), rng.uniform(1.2, 2.2), rng.uniform(1.0, 1.8)), jit(rng, CLIFF[2], 0.05), subdiv=1)
    for _ in range(7):
        k = rng.randrange(n)
        p = rings[1][k]
        d = Vector((p.x, p.y, 0)).normalized()
        cliff.cyl(p + d * 0.1, p + d * 0.6 + Vector((0, 0, -rng.uniform(2, 3.5))), 0.16, 0.05, 5, BARK[1])
    register(name, top.to_object(), "Top")
    register(name, cliff.to_object(), "Cliff")


plot_island("PlotIsland", 91)


# ================================================================== WEATHER SYMBOLS (tower globe)
def extrude_poly(mb, pts2d, depth, col):
    """Flat polygon in XZ (y = depth / 2 both sides), fan triangulated from its centroid (convex-ish shapes)."""
    n = len(pts2d)
    cx = sum(p[0] for p in pts2d) / n
    cz = sum(p[1] for p in pts2d) / n
    front = [Vector((p[0], -depth / 2, p[1])) for p in pts2d]
    back = [Vector((p[0], depth / 2, p[1])) for p in pts2d]
    verts = front + back + [Vector((cx, -depth / 2, cz)), Vector((cx, depth / 2, cz))]
    f = []
    for k in range(n):
        j = (k + 1) % n
        f.append((2 * n, j, k))
        f.append((2 * n + 1, n + k, n + j))
        f.append((k, j, n + j, n + k))
    return mb.add(verts, f, col)


def symbols():
    sun = MB("Sym_Sun")
    ring = []
    for k in range(16):
        a = k * math.tau / 16
        ring.append((math.cos(a) * 2.2, math.sin(a) * 2.2))
    extrude_poly(sun, ring, 0.8, hx("#FFE27A"))
    for k in range(10):
        a = k * math.tau / 10
        d = Vector((math.cos(a), 0, math.sin(a)))
        s = Vector((-math.sin(a), 0, math.cos(a)))
        b0, b1, t = d * 2.7 + s * 0.55, d * 2.7 - s * 0.55, d * 4.0
        sun.add([b0 + Vector((0, -0.3, 0)), b1 + Vector((0, -0.3, 0)), t + Vector((0, -0.15, 0)), b0 + Vector((0, 0.3, 0)), b1 + Vector((0, 0.3, 0)), t + Vector((0, 0.15, 0))],
                [(0, 2, 1), (3, 4, 5), (0, 1, 4, 3), (1, 2, 5, 4), (2, 0, 3, 5)], hx("#FFC23A"))
    register("Sym_Sun", sun.to_object(), "Body")

    flake = MB("Sym_Snowflake")
    for k in range(6):
        a = k * math.pi / 3
        d = Vector((math.cos(a), 0, math.sin(a)))
        s = Vector((-math.sin(a), 0, math.cos(a)))
        flake.obox(d * 1.9, (0.0001 + 3.8 if False else 3.8, 0.6, 0.55), Matrix((d, Vector((0, 1, 0)), s)).transposed(), hx("#BFF4FF"))
        for t, L in ((2.1, 1.3), (3.0, 0.9)):
            for sg in (-1, 1):
                bd = (d * math.cos(math.radians(45)) + s * sg * math.sin(math.radians(45))).normalized()
                bs = Vector((-bd.z, 0, bd.x))
                flake.obox(d * t + bd * L / 2, (L, 0.5, 0.42), Matrix((bd, Vector((0, 1, 0)), bs)).transposed(), hx("#9FEAFF"))
    flake.ico((0, 0, 0), (0.9, 0.5, 0.9), hx("#E6FCFF"), subdiv=1)
    register("Sym_Snowflake", flake.to_object(), "Body")

    bolt = MB("Sym_Bolt")
    pts = [(0.9, 4.2), (-1.9, -0.3), (-0.1, -0.3), (-1.1, -4.2), (2.1, 0.8), (0.3, 0.8)]
    # bolt as two convex quads so the fan triangulation stays clean
    extrude_poly(bolt, [(0.9, 4.2), (-1.9, -0.3), (-0.1, -0.3), (0.3, 0.8)], 0.8, hx("#D9B8FF"))
    extrude_poly(bolt, [(-0.1, -0.3), (-1.1, -4.2), (2.1, 0.8), (0.3, 0.8)], 0.8, hx("#C79BFF"))
    _ = pts
    register("Sym_Bolt", bolt.to_object(), "Body")

    wind = MB("Sym_Wind")
    # three swooshes: thin swept tubes curling at the end
    for i, (y0, L, curl) in enumerate(((1.7, 5.0, 0.6), (0.0, 6.4, 0.75), (-1.7, 4.2, 0.55))):
        pts3 = []
        for j in range(18):
            t = j / 17
            if t < 0.7:
                p = Vector((-L / 2 + L * t / 0.7 * 0.85, 0, y0))
            else:
                u = (t - 0.7) / 0.3 * math.pi * 1.3
                cxp = -L / 2 + L * 0.85
                rr = curl * (1 - 0.35 * u / (math.pi * 1.3))
                p = Vector((cxp + math.sin(u) * rr, 0, y0 + curl - math.cos(u) * rr))
            pts3.append(p)
        rings = []
        for j, p in enumerate(pts3):
            r = 0.32 * (1 - 0.5 * (j / 17))
            rings.append([p + Vector((0, math.cos(a) * r, math.sin(a) * r)) for a in (0, math.pi / 2, math.pi, 3 * math.pi / 2)])
        wind.tube(rings, hx("#FFC27A") if i != 1 else hx("#FFB04A"))
    register("Sym_Wind", wind.to_object(), "Body")

    # thin torus ring for the animated rings around the globe
    rg = MB("GlobeRing")
    R, r, n, m = 13.0, 0.35, 48, 6
    rings = []
    for k in range(n + 1):
        a = k * math.tau / n
        c = Vector((math.cos(a) * R, math.sin(a) * R, 0))
        d = Vector((math.cos(a), math.sin(a), 0))
        rings.append([c + d * math.cos(b) * r + Vector((0, 0, math.sin(b) * r)) for b in (j * math.tau / m for j in range(m))])
    rg.tube(rings, hx("#8FE8FF"), cap0=False, cap1=False)
    register("GlobeRing", rg.to_object(), "Body")


symbols()

# ================================================================== layout + export
layout = {}
names = list(ASSETS.keys())
SLOT = 60
for i, name in enumerate(names):
    ox, oy = (i % 8) * SLOT, (i // 8) * SLOT
    layout[name] = {"x": ox, "y": oy, "parts": [o.name.split("__")[1] for o in ASSETS[name]]}
    for o in ASSETS[name]:
        o.location = (ox, oy, 0)
tris = {}
for name, obs in ASSETS.items():
    t = 0
    for o in obs:
        o.data.calc_loop_triangles()
        t += len(o.data.loop_triangles)
    tris[name] = t
json.dump({"slot": SLOT, "assets": layout, "tris": tris}, open(os.path.join(OUT, "kit_layout.json"), "w"), indent=1)
bpy.ops.object.select_all(action="DESELECT")
for obs in ASSETS.values():
    for o in obs:
        o.select_set(True)
bpy.context.view_layer.objects.active = next(iter(ASSETS.values()))[0]
bpy.ops.export_scene.gltf(filepath=os.path.join(OUT, "PocketWeatherKit.glb"), export_format="GLB", use_selection=True,
                          export_apply=True, export_yup=True, export_normals=True, export_vertex_color="ACTIVE",
                          export_draco_mesh_compression_enable=False)
bpy.ops.wm.save_as_mainfile(filepath=os.path.join(OUT, "kit.blend"))
print("TRIS", json.dumps(tris))
print("DONE", len(ASSETS))
