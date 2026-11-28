"""Bake two fully clothed, GPU-skinned USD athletes from CC0 MakeHuman assets.

Usage: build_athletes.py SOURCE_DIR SYSTEM_ASSETS_ZIP OUTPUT_DIR.
SOURCE_DIR holds base.obj, default.mhskel, default_weights.mhw and the targets
listed in athlete_targets(). The converter only reads the supplied assets.
"""
import argparse
from collections import defaultdict
from dataclasses import dataclass
import json
import math
from pathlib import Path
import subprocess
import shutil
from tempfile import TemporaryDirectory
from zipfile import ZipFile


def lerp(a, b, t):
    return tuple(x + (y-x)*t for x, y in zip(a, b))


def average(points):
    return tuple(sum(axis)/len(points) for axis in zip(*points))


def world(point):
    x, y, z = point
    return (-0.1*x, 0.1*y+0.88, -0.1*z)


def fmt(value):
    return format(value, ".6g")


def vector(point):
    return "(" + ", ".join(fmt(v) for v in point) + ")"


def array(items):
    return "[" + ", ".join(items) + "]"


class Obj:
    def __init__(self, text):
        self.points, self.uv, self.faces = [], [], []
        group = ""
        for line in text.splitlines():
            row = line.split()
            if not row:
                continue
            if row[0] == "v":
                self.points.append(tuple(map(float, row[1:4])))
            elif row[0] == "vt":
                self.uv.append(tuple(map(float, row[1:3])))
            elif row[0] == "g":
                group = row[1]
            elif row[0] == "f":
                face = []
                for token in row[1:]:
                    v, t, *_ = (token + "//").split("/")
                    face.append((int(v)-1, int(t)-1 if t else 0))
                self.faces.append((group, face))


def source_bone(name):
    side = name[-1] if name.endswith((".L", ".R")) else ""
    stem = name.split(".")[0]
    if stem.startswith("upperarm"):
        return "upperArm" + side
    if stem == "lowerarm02":
        return "twist" + side
    if stem.startswith("lowerarm"):
        return "forearm" + side
    if stem.startswith("finger"):
        return "digit" + stem[6:].replace("-","") + side
    if stem.startswith(("wrist", "metacarpal")):
        return "hand" + side
    if stem.startswith("upperleg"):
        return "thigh" + side
    if stem.startswith("lowerleg"):
        return "shin" + side
    if stem.startswith(("toe", "foot")):
        return "foot" + side
    if stem.startswith(("shoulder", "clavicle", "scapula")):
        return "clav" + side
    if stem in ["spine02","spine03"]:
        return "waist"
    if stem.startswith("breast") or stem == "spine01":
        return "chest"
    if stem.startswith("neck"):
        return "neck"
    if stem.startswith(("spine","pelvis","root")):
        return "pelvis"
    if stem == "oculi01": return "brow"+side
    if stem in ("risorius03", "levator05"): return "cheek"+side
    if stem == "orbicularis03": return "lidTop"+side
    if stem == "orbicularis04": return "lidBottom"+side
    if stem.startswith("tongue") or stem in ("jaw", "special04", "oris01", "oris02", "oris07") or (stem == "oris06" and side):
        return "jaw"
    if stem in ("oris03", "oris04", "oris05", "oris06"):
        return "upperLip"
    return "head"


def combined(terms):
    result = defaultdict(float)
    for mix, values in terms:
        for name, value in values.items():
            result[name] += mix * value
    best = sorted(((w, n) for n, w in result.items() if w > 0.0001),reverse=True)[:4]
    weight = sum(w for w, _ in best)
    return {n:w/weight for w,n in best} if best else {"pelvis":1.0}


def joint_volume_weights(weights):
    """Use adjacent quarter-turn frames on the articulation arc. With linear
    GPU skinning this bounds the chord error even at a deeply bent knee."""
    values = dict(weights)
    for side in "LR":
        seams = [("deltoid", ("clav"+side, "chest"), "upperArm"+side),
                 ("elbowCap", ("upperArm"+side,), "forearm"+side),
                 ("hipCap", ("pelvis", "waist"), "thigh"+side),
                 ("kneeCap", ("thigh"+side,), "shin"+side)]
        for joint, proximal, distal in seams:
            upstream = sum(values.get(key, 0) for key in proximal)
            downstream = values.get(distal, 0)
            if min(upstream, downstream) < 0.0001:
                continue
            total = upstream + downstream
            step = 4 * downstream / total
            for key in proximal:
                if key in values:
                    values[key] *= total * max(0, 1-step) / upstream
            values[distal] = total * max(0, step-3)
            for n, suffix in enumerate(("Inner", "", "Outer"), start=1):
                values[joint+suffix+side] = total * max(0, 1-abs(step-n))

    return combined([(1,values)])


@dataclass
class Vertex:
    position: tuple
    uv: tuple
    weights: dict

    def between(self, other, t):
        return Vertex(lerp(self.position,other.position,t),lerp(self.uv,other.uv,t),
                      combined([(1-t,self.weights),(t,other.weights)]))


def clip_height(vertices, height):
    output = []
    prev = vertices[-1]
    for curr in vertices:
        a, b = prev.position[1] - height, curr.position[1] - height
        if (a < 0) != (b < 0):
            output.append(prev.between(curr,a/(a-b)))
        if b >= 0:
            output.append(curr)
        prev = curr
    return output


class Part:
    def __init__(self, name):
        self.name = name
        self.vertices, self.faces, self.lookup = [], [], {}

    def add(self, vertices):
        if len(vertices) < 3:
            return
        face = []
        for v in vertices:
            key = (v.position,v.uv)
            if key not in self.lookup:
                self.lookup[key] = len(self.vertices)
                self.vertices.append(v)
            face.append(self.lookup[key])
        for i in range(1,len(face)-1):
            triangle = [face[0],face[i],face[i+1]]
            if len(set(triangle)) == 3:
                self.faces.append(triangle)

    def usd(self, bones):
        positions = [world(v.position) for v in self.vertices]
        # Accumulate area-weighted normals across UV seams.
        normals = defaultdict(lambda:[0.,0.,0.])
        for tri in self.faces:
            a,b,c = [positions[i] for i in tri]
            u = [b[i]-a[i] for i in range(3)]
            v = [c[i]-a[i] for i in range(3)]
            norm = [u[1]*v[2]-u[2]*v[1],u[2]*v[0]-u[0]*v[2],u[0]*v[1]-u[1]*v[0]]
            for index in tri:
                accum = normals[positions[index]]
                for k in range(3):
                    accum[k] += norm[k]
        def unit(n):
            length = math.sqrt(sum(x*x for x in n)) or 1
            return tuple(x/length for x in n)
        indices, weights = [], []
        for vert in self.vertices:
            items = [(bones.index(n),w) for n,w in joint_volume_weights(vert.weights).items()]
            items += [(0,0.)]*(4-len(items))
            for i, w in items:
                indices.append(str(i)); weights.append(fmt(w))
        return f'''
    def Mesh "{self.name}" (prepend apiSchemas = ["SkelBindingAPI", "MaterialBindingAPI"]) {{
      uniform token subdivisionScheme = "none"
      uniform bool doubleSided = true
      rel material:binding = </Athlete/Looks/{self.name}>
      rel skel:skeleton = </Athlete/Rig>
      point3f[] points = {array(map(vector,positions))}
      normal3f[] normals = {array(vector(unit(normals[p])) for p in positions)} (interpolation = "vertex")
      texCoord2f[] primvars:st = {array(vector(v.uv) for v in self.vertices)} (interpolation = "vertex")
      int[] faceVertexCounts = {array("3" for _ in self.faces)}
      int[] faceVertexIndices = {array(str(i) for tri in self.faces for i in tri)}
      int[] primvars:skel:jointIndices = {array(indices)} (elementSize = 4
        interpolation = "vertex")
      float[] primvars:skel:jointWeights = {array(weights)} (elementSize = 4
        interpolation = "vertex")
    }}
'''


def athlete_targets(model):
    """Model-space, additive shapes in the pinned MakeHuman targets directory."""
    woman = model == "female"
    targets = [(f"macrodetails/{origin}-{model}-young", 1/3) for origin in ("african", "asian", "caucasian")]
    targets += [
        (f"macrodetails/universal-{model}-young-maxmuscle-averageweight", 0.70 if woman else 0.96),
        ("torso/torso-muscle-dorsi-incr", 0.21 if woman else 0.52),
        ("pelvis/pelvis-tone-incr", 0.32),
        ("hip/hip-scale-horiz-incr", 0.16 if woman else 0.06),
        ("chin/chin-width-decr", 0.30 if woman else 0.05),
        ("chin/chin-prominent-incr", 0.09 if woman else 0.26),
        ("eyebrows/eyebrows-angle-up", 0.19 if woman else 0.08),
    ]
    for side in ("l", "r"):
        targets += [
            (f"cheek/{side}-cheek-bones-incr", 0.37 if woman else 0.22),
            (f"armslegs/{side}-upperleg-muscle-incr", 0.44 if woman else 0.34),
            (f"armslegs/{side}-lowerleg-muscle-incr", 0.28 if woman else 0.36),
        ]
    return targets


class Athlete:
    def __init__(self, source, archive, model):
        self.base = Obj((source / "base.obj").read_text())
        self.original = self.base.points
        self.points = list(self.original)
        for shape, blend in athlete_targets(model):
            target = source / (Path(shape).name + ".target")
            for line in target.read_text().splitlines():
                t = line.split()
                if t and t[0].isdigit():
                    i = int(t[0])
                    self.points[i] = tuple(self.points[i][k]+float(t[k+1])*blend for k in range(3))
        weights = json.loads((source/"default_weights.mhw").read_text())
        assert weights["license"] == "CC0"
        self.weights = [defaultdict(float) for _ in self.points]
        for name, values in weights["weights"].items():
            for index, value in values:
                self.weights[index][source_bone(name)] += value
        self.weights = [combined([(1,w)]) for w in self.weights]
        rig = json.loads((source/"default.mhskel").read_text())
        def pivot(name):
            return world(average([self.points[i] for i in rig["joints"][rig["bones"][name]["head"]]]))
        self.anchors = {"root":(0.,0.,0.), "pelvis":pivot("root"),"chest":pivot("spine01"),"waist":pivot("spine03"),
                        "neck":pivot("neck01"),"head":pivot("head"), "jaw":pivot("jaw"), "upperLip":pivot("oris05")}
        for side in "LR":
            for key, bone in [("upperArm","upperarm01"),("forearm","lowerarm01"),("twist","lowerarm02"),("hand","wrist"),
                              ("clav","clavicle"),
                              ("thigh","upperleg01"),("shin","lowerleg01"),("foot","foot")]:
                self.anchors[key+side] = pivot(bone+"."+side)
        # Locate the handle inside a closed palm, then skin the open source hand
        # to a real finger hierarchy so live play can release and re-grip it.
        open_hand = list(self.points)
        digit_anchors = {
            f"digit{finger}{joint}{side}": pivot(f"finger{finger}-{joint}.{side}")
            for side in "LR" for finger in range(1,6) for joint in range(1,4)
        }
        self.curl_fingers(rig,weights["weights"])
        for side in "LR":
            palm = average([pivot(f"finger{n}.{side}") for n in ["1-3","3-1","3-3"]])
            knuckles = [pivot(f"finger{n}-1.{side}") for n in [2,5]]
            self.anchors["palm"+side] = palm
            self.anchors["gripAxis"+side] = tuple(p+a-b for p,a,b in zip(palm,*knuckles))
        self.points = open_hand
        for side in "LR":
            self.anchors["brow"+side] = pivot("oculi01."+side)
            self.anchors["cheek"+side] = pivot("risorius03."+side)
            self.anchors["lidTop"+side] = pivot("orbicularis03."+side)
            self.anchors["lidBottom"+side] = pivot("orbicularis04."+side)
            for seam, joint in [("deltoid","upperArm"),("elbowCap","forearm"),("hipCap","thigh"),("kneeCap","shin")]:
                for suffix in ("Inner", "", "Outer"):
                    self.anchors[seam+suffix+side] = self.anchors[joint+side]
        self.anchors.update(digit_anchors)
        self.shorts_length = .185 if model == "female" else .215
        self.hair = "ponytail01" if model == "female" else "short01"
        self.brow = "eyebrow005" if model == "female" else "eyebrow009"
        self.parts = {}
        self.archive = archive
        self.model = model
        self.hidden = set()
        self.under_kit = set()

    def curl_fingers(self, rig, weights):
        """Close the playing hand around the grip; soften the free fingers."""
        def pivot(bone):
            return average([self.points[i] for i in rig["joints"][rig["bones"][bone]["head"]]])
        def cross(a,b):
            return (a[1]*b[2]-a[2]*b[1],a[2]*b[0]-a[0]*b[2],a[0]*b[1]-a[1]*b[0])
        def rotate(p,origin,axis,angle):
            q = [x-y for x,y in zip(p,origin)]
            perpendicular = cross(axis,q)
            dot = sum(a*b for a,b in zip(q,axis))
            return tuple(v + x*math.cos(angle) + t*math.sin(angle) + a*dot*(1-math.cos(angle))
                         for v,x,t,a in zip(origin,q,perpendicular,axis))
        offsets = defaultdict(lambda:[0.,0.,0.])
        for side in "LR":
            index, little = [pivot(f"finger{n}-1.{side}") for n in [2,5]]
            axis = [x-y for x,y in zip(index,little)]
            axis = tuple(a/math.sqrt(sum(t*t for t in axis)) for a in axis)
            strength = 1 if side=="R" else -0.93
            for finger in range(1,6):
                chain = []
                for phalanx,angle in enumerate([40,62,44],1):
                    name = f"finger{finger}-{phalanx}.{side}"
                    chain.append((pivot(name),math.radians(angle)*strength*(0.30 if finger==1 else 1)))
                    for i,weight in weights.get(name,[]):
                        point = self.points[i]
                        for origin,radians in reversed(chain):
                            point = rotate(point,origin,axis,radians)
                        for k in range(3):
                            offsets[i][k] += weight*(point[k]-self.points[i][k])
        for i,delta in offsets.items():
            self.points[i] = tuple(p+d for p,d in zip(self.points[i],delta))

    def textures(self, folder, tool):
        skin = f"skins/young_caucasian_{self.model}/young_lightskinned_{self.model}_diffuse.png"
        hair = self.hair
        prefix = "Man" if self.model=="male" else "Woman"
        sources = [(skin,prefix+"Skin.jpg",2048),(f"hair/{hair}/{hair}_diffuse.png",prefix+"Hair.png",512)]
        sources.append((f"eyebrows/{self.brow}/{self.brow}.png",prefix+"Brows.png",256))
        if self.model=="male":
            sources += [("eyelashes/eyelashes03/eyelashes03.png","CourtLashes.png",256)]
            sources += [("eyes/materials/brown_eye.png","AthleteEyes.jpg",256),
                        ("clothes/shoes05/shoes05_diffuse.png","CourtShoes.jpg",512),
                        ("teeth/teeth_base/teeth.png","CourtTeeth.jpg",256),
                        ("clothes/male_casualsuit06/male_casualsuit06_ao.png","CourtKit.jpg",512),
                        ("clothes/male_casualsuit06/male_casualsuit06_normal.png","CourtKitNormal.jpg",512)]
        with TemporaryDirectory() as tmp:
            tmp = Path(tmp)
            for asset,name,size in sources:
                image = tmp/"input.png"
                image.write_bytes(self.archive.read(asset))
                args = [str(tool),str(image),str(folder/name),str(size)]
                if asset==skin:
                    mask = tmp/"skin-uv.json"
                    mask.write_text(json.dumps([[part.vertices[i].uv for i in face]
                        for name,part in self.parts.items() if name in ("Skin","TankSkin","CrewSkin","Wristband") for face in part.faces]))
                    args.append(str(mask))
                subprocess.run(args,check=True)

    def emit(self, name, vertices):
        if name not in self.parts:
            self.parts[name] = Part(name)
        self.parts[name].add(vertices)

    def proxy(self, folder, name, kind):
        path = f"{folder}/{name}/{name}"
        mesh = Obj(self.archive.read(path+".obj").decode())
        fitting = self.archive.read(path+".mhclo").decode().splitlines()
        assert any("CC0" in line for line in fitting)
        start = fitting.index("verts 0")+1
        rows = []
        for line in fitting[start:]:
            fields = line.split()
            if fields and fields[0].isdigit():
                rows.append(fields)
            if len(rows) == len(mesh.points):
                break
        assert len(rows) == len(mesh.points)
        scale = [1.,1.,1.]
        for line in fitting:
            v = line.split()
            if len(v)==4 and v[0] in ("x_scale","y_scale","z_scale"):
                k = "xyz".index(v[0][0])
                scale[k] = abs(self.points[int(v[1])][k]-self.points[int(v[2])][k])/float(v[3])
        mapped, skinning = [], []
        for row in rows:
            count = 1 if len(row) == 1 else 3
            sources = [int(v) for v in row[:count]]
            factors = [1] if count == 1 else [float(v) for v in row[3:6]]
            offset = [0]*3 if count==1 else [float(v) for v in row[6:9]]
            mapped.append(tuple(sum(w*self.points[i][k] for w,i in zip(factors,sources)) + offset[k]*scale[k] for k in range(3)))
            skinning.append(combined([(w,self.weights[i]) for w,i in zip(factors,sources)]))
        if kind == "Hair":
            head = self.anchors["head"]
            # The braid hangs behind the collar and upper back. Give it
            # clearance in bind space and anchor its lower length to the kit.
            self.anchors["tailBase"] = (0.,head[1]-.060,head[2]+.092)
            self.anchors["tailTip"] = (0.,head[1]-.200,head[2]+.170)
            skinning = []
            for i, point in enumerate(mapped):
                x,y,z = world(point)
                hangs = min(1,max(0,(head[1]-.047-y)/.054)) if self.model=="female" else 0.
                rear = min(1,max(0,(z-head[2]-.025)/.030))
                hangs *= rear
                tip = min(1,max(0,(head[1]-.105-y)/.160))
                clearance = hangs*(.020+.044*tip)
                mapped[i] = (point[0],point[1],point[2]-clearance*10)
                skinning.append({"head":1-hangs,"tailBase":hangs*(1-tip),
                                 "tailTip":hangs*tip*.55,"chest":hangs*tip*.45})
        if kind == "Teeth":
            weights = [sum(w for key,w in v.items() if key == "jaw") for v in skinning]
            adjacency = defaultdict(set)
            for _,face in mesh.faces:
                ids = [i for i,_ in face]
                for i,j in zip(ids,ids[1:]+ids[:1]):
                    adjacency[i].add(j); adjacency[j].add(i)
            pending = set(adjacency)
            while pending:
                island = {pending.pop()}; queue = list(island)
                while queue:
                    fresh = adjacency[queue.pop()] & pending
                    pending.difference_update(fresh); island.update(fresh); queue.extend(fresh)
                bone = "jaw" if sum(weights[i] for i in island) > len(island)*0.5 else "head"
                for i in island: skinning[i] = {bone:1.0}
        if kind == "Eyes":
            eye = ["eyeR" if world(p)[0]>0 else "eyeL" for p in mapped]
            for name in ["eyeL","eyeR"]:
                cloud = [world(p) for p,bone in zip(mapped,eye) if bone==name]
                center = tuple((max(axis)+min(axis))*0.5 for axis in zip(*cloud))
                self.anchors[name] = (center[0],center[1],center[2]+0.004)
            skinning = [{bone:1.0} for bone in eye]
        if kind in ("Kit","Shoe"):
            # The clothing author supplied the exact underlying body vertices.
            covered = self.hidden if kind == "Shoe" else self.under_kit
            deleted = fitting.index("delete_verts")+1
            tokens = " ".join(fitting[deleted:]).split()
            for i,t in enumerate(tokens):
                if t.isdigit():
                    covered.add(int(t))
                elif t == "-" and i and i+1 < len(tokens):
                    covered.update(range(int(tokens[i-1]),int(tokens[i+1])+1))
        # The source suit has two connected islands: exclude the lower trouser leg.
        groups = components(mesh, -6.8 if kind == "Shoe" else 4.0) if kind in ("Kit","Shoe") else {}
        if kind == "Kit":
            # Shape the trunk once per vertex so sleeves and shirt share seams.
            # Taper at the waist and lift the tail, preserving waistband overlap.
            waist = self.anchors["waist"][1]
            hip = self.anchors["thighL"][1]
            # The original cut determines the sleeve hem for every kit style.
            sleeve_weights = [sum(w for bone,w in weights.items() if bone.startswith(("upperArm","forearm")))
                              for weights in skinning]
            self.fit_kit_weights(mesh, mapped, skinning, groups)
            for i, (x,y,z) in enumerate(mapped):
                if groups.get(i) != "top":
                    continue
                height = world(mapped[i])[1]
                taper = math.exp(-((height-waist)/.115)**2)
                fit = .095 if self.model == "female" else .060
                hem_lift = max(0, min(1, (waist-height)/(waist-hip)))
                mapped[i] = (x*(1-fit*taper), y+(.42 if self.model=="female" else .25)*hem_lift,
                             z*(1-fit*.6*taper))
        for _,face in mesh.faces:
            vs = [Vertex(mapped[i],mesh.uv[t],skinning[i]) for i,t in face]
            if kind == "Shoe":
                # Shoes05 already includes a separate, fitted sock in each shoe.
                # Keep its original cuff, collar overlap and ankle weights.
                self.emit("Sock" if groups[face[0][0]] == "top" else "Shoe",vs)
                continue
            if kind != "Kit":
                self.emit(kind,vs); continue
            if groups[face[0][0]] == "top":
                arm = sum(sleeve_weights[i] for i, _ in face)/len(face)
                if arm > 0.50:
                    self.emit("Sleeves",vs)
                else:
                    shirt, insert = self.split_side_panel(vs)
                    self.emit("Shirt",shirt)
                    self.emit("SidePanel",insert)
            else:
                hem = (self.anchors["thighL"][1]-self.shorts_length-0.88)*10
                self.emit("Shorts",clip_height(vs,hem))
                liner = clip_height(vs,hem+.42)
                if not liner:
                    continue
                liner, _ = self.split_face(liner, lambda v: world(v.position)[1]-self.anchors["thighR"][1]-.032)
                self.emit("Liner",[Vertex((v.position[0]*.96,v.position[1],v.position[2]*.94),
                                          v.uv,v.weights) for v in liner])

    def fit_kit_weights(self, mesh, mapped, weights, groups):
        """Keep the fabric continuous between the legs and across the shoulder cap."""
        hip = self.anchors["thighL"][1]
        shoulder = self.anchors["upperArmL"]
        neighbours = defaultdict(set)
        for _, face in mesh.faces:
            for (a, _), (b, _) in zip(face, face[1:]+face[:1]):
                neighbours[a].add(b)
                neighbours[b].add(a)
        sleeves = []
        for i, point in enumerate(mapped):
            x, y, _ = world(point)
            if groups.get(i) == "top":
                across = abs(x)-abs(shoulder[0])
                if -.11 < across < .15 and shoulder[1]-.21 < y < shoulder[1]+.08:
                    sleeves.append(i)
            else:
                # The two leg openings move independently. The seam joining
                # them is supported by the pelvis, with a graded transition
                # into each thigh instead of opposite bones on adjacent vertices.
                side = max(0,min(1,(abs(x)-.013)/.108))
                height = max(0,min(1,(y-hip+.197)/.068))
                panel = (1-side*side*(3-2*side))*height*height*(3-2*height)
                if panel > 0:
                    weights[i] = combined([(1-panel,weights[i]),(panel,{"pelvis":1})])
        # Fair the shoulder weights along the actual surface. Running this
        # before the sleeve and shirt are cut gives both sides of a seam
        # exactly the same bend when the player raises the racket.
        for _ in range(3):
            previous = list(weights)
            for i in sleeves:
                ring = neighbours[i]
                if ring:
                    mix = .55/len(ring)
                    weights[i] = combined([(.45,previous[i])]+[(mix,previous[j]) for j in sorted(ring)])

    def split_side_panel(self, face):
        """Cut the inset along a curved seam shared by all shirt styles."""
        def distance(v):
            x,y,_ = world(v.position)
            rise = min(1,max(0,(y-self.anchors["waist"][1])/.29))
            edge = .122 if self.model=="female" else .141
            return abs(x) - (edge + .028*rise - .015*math.sin(math.pi*rise))
        return self.split_face(face, distance)

    @staticmethod
    def split_face(face, distance):
        inside, outside = [], []
        prev = face[-1]
        a = distance(prev)
        for curr in face:
            b = distance(curr)
            if (a>0) != (b>0):
                edge = prev.between(curr,a/(a-b))
                inside.append(edge)
                outside.append(edge)
            (outside if b > 0 else inside).append(curr)
            prev, a = curr, b
        return inside, outside

    def tank_face(self, face):
        # Skin and bodice are cut from one surface. Their cut vertices carry
        # identical weights, so an exposed shoulder cannot separate from a strap.
        shoulder = self.anchors["upperArmR"]
        neck = self.anchors["neck"]
        hip = self.anchors["thighR"][1]
        def edge(v):
            x,y,z = world(v.position)
            back = min(1,max(0,(z-neck[2]+.027)/.060))
            rise = min(1,max(0,(y-shoulder[1]+.137)/.15))
            outer = shoulder[0]+.055-(.086+.034*back)*math.sin(rise*math.pi/2)
            neck_height = neck[1]+.034-(.096-.020*back)*math.exp(-(x/.078)**2)
            arm = sum(w for b,w in v.weights.items() if b.startswith(("upperArm","forearm","twist")))
            return max(abs(x)-outer, y-neck_height, (arm-.27)*.11)
        panel, skin = self.split_face(face, edge)
        self.emit("TankSkin",skin)
        if not panel:
            return
        field, binding = self.split_face(panel, lambda v: edge(v)+.005)
        # Stretch the knit across the chest. Round out local detail with a
        # smooth elliptical section, feathering to the untouched bound edges.
        def fabric(v):
            x,y,z = world(v.position)
            t = min(1,max(0,(shoulder[1]-y)/.26))
            bust = math.sin(math.pi*t)
            radius = shoulder[0]*(.91+.08*bust)
            depth = .095+.023*bust
            mid = -.031 if self.model == "female" else -.014
            front = mid-depth*math.sqrt(max(0,1-(x/radius)**2))
            ease = min(1,max(0,-edge(v)/.034))
            blend = ease*ease*(3-2*ease)
            if z < mid:
                z = z + (min(z-.002,front)-z)*blend
            u = math.atan2(x,mid-z)/math.tau+.5
            return Vertex((-10*x,10*(y-.88),-10*z),(u,(y-hip)*2),v.weights)
        self.emit("Tank",[fabric(v) for v in field])
        self.emit("TankBinding",[fabric(v) for v in binding])

    def accessories(self):
        """Build optional, weighted kit pieces after fitting the common sportswear."""
        def vertex(p,uv,bones):
            return Vertex((-p[0]*10,(p[1]-.88)*10,-p[2]*10),uv,bones)
        def strip(name,rows,wrap=True):
            for a,b in zip(rows,rows[1:]):
                for i in range(len(a) if wrap else len(a)-1):
                    j=(i+1)%len(a)
                    self.emit(name,[a[i],b[i],b[j],a[j]])
        def normalize(q):
            length = math.sqrt(sum(v*v for v in q))
            return tuple(v/length for v in q)
        for side in "LR":
            foot = self.anchors["foot"+side]
            shoe = [world(v.position) for v in self.parts["Shoe"].vertices if (world(v.position)[0]<0)==(side=="L")]
            floor = min(p[1] for p in shoe)
            sole = [p for p in shoe if p[1]<floor+0.008]
            self.anchors["toe"+side] = (foot[0],floor,min(p[2] for p in sole))
            self.anchors["heel"+side] = (foot[0],floor,max(p[2] for p in sole))
        head = self.anchors["head"]
        skin = [world(v.position) for v in self.parts["Skin"].vertices]
        h = head[1]+0.073
        brow = [p for p in skin if abs(p[1]-h)<0.012 and abs(p[0])<0.12]
        rx = max(p[0] for p in brow)+0.006
        za,zb = min(p[2] for p in brow)-0.005,max(p[2] for p in brow)+0.008
        rz,cz = (zb-za)/2,(za+zb)/2
        rows = []
        for y,extra in [(h-0.013,0),(h-0.010,0.002),(h+0.009,0.002),(h+0.013,0)]:
            ring = []
            for i in range(48):
                t = i*math.tau/48
                ring.append(vertex(((rx+extra)*math.sin(t),y+0.006*math.cos(t),cz-(rz+extra)*math.cos(t)),(i/48,y-h),{"head":1}))
            rows.append(ring)
        strip("Headband",rows)
        rows = []
        for v in [0,.5,1]:
            row = []
            for i in range(33):
                t = (i/32-.5)*2.78
                span = math.cos(t)**1.5
                row.append(vertex((rx*math.sin(t)*(1+.22*v),h-0.004-0.012*v+0.005*span,cz-rz*math.cos(t)-.073*v*span),
                                  (i/32,v),{"head":1}))
            rows.append(row)
        strip("Visor",rows,False)
        # Follow the actual bodice at the waist. Cross-sections taken from
        # the shorts include open space above the hips when the trunk turns.
        waist = self.anchors["thighR"][1] + .107
        pants = [world(v.position) for v in self.parts["Shorts"].vertices]
        torso = self.parts["Tank"]
        section = []
        for face in torso.faces:
            vs = [torso.vertices[n] for n in face]
            for a,b in zip(vs,vs[1:]+vs[:1]):
                ay,by = world(a.position)[1],world(b.position)[1]
                if (ay < waist) != (by < waist):
                    section.append(a.between(b,(waist-ay)/(by-ay)))
        center_z = (min(world(v.position)[2] for v in section)+max(world(v.position)[2] for v in section))/2
        def bearing(v):
            x,_,z = world(v.position)
            return math.atan2(x,center_z-z)%math.tau
        rim = sorted(section,key=bearing)
        def waistband(t):
            hi = next((i for i,v in enumerate(rim) if bearing(v)>t),0)
            a,b = rim[hi-1],rim[hi]
            span = (bearing(b)-bearing(a))%math.tau
            return a.between(b,((t-bearing(a))%math.tau)/max(.000001,span))
        ring = [waistband(i*math.tau/64) for i in range(64)]
        rows = []
        for depth in [0,.002,.009,.023,.046,.083,.13,.185,.255,.291,.297]:
            row = []
            section = [p for p in pants if abs(p[1]-(waist-depth))<.037] or pants
            width = max(abs(p[0]) for p in section)+.016
            front,back = min(p[2] for p in section)-.025,max(p[2] for p in section)+.023
            cz,rz = (front+back)/2,(back-front)/2
            drape = min(1,depth/.10)
            drape *= drape*(3-2*drape)
            for i,seam in enumerate(ring):
                t = i*math.tau/64
                flare = max(0.,depth-.096)*(.17+.042*math.cos(t*12))
                thigh = max(0,min(.97,(depth-.043)*4.7))
                blend = .5+.5*math.tanh(4.0*math.sin(t))
                leg = combined([(mix,joint_volume_weights({"pelvis":1-thigh,"thigh"+side:thigh}))
                                for side,mix in (("R",blend),("L",1-blend))])
                x,_,z = world(seam.position)
                lip = -.003 if depth == 0 else .003
                x = (x+lip*math.sin(t))*(1-drape) + (width+flare)*math.sin(t)*drape
                z = (z-lip*math.cos(t))*(1-drape) + (cz-(rz+flare)*math.cos(t))*drape
                weights = combined([(1-drape,seam.weights),(drape,leg)])
                row.append(vertex((x,waist-depth,z),(i/64,depth),weights))
            rows.append(row)
        strip("Skort",rows)
        # Bind the piping directly to the actual open sleeve hem. Ignore UV
        # boundaries inside the cloth and the edges where it meets the shirt.
        sleeve = self.parts["Sleeves"]
        edges = defaultdict(list)
        for face in sleeve.faces:
            for a,b in zip(face,face[1:]+face[:1]):
                va,vb = sleeve.vertices[a],sleeve.vertices[b]
                edges[tuple(sorted((va.position,vb.position)))].append((va,vb))
        for pairs in edges.values():
            if len(pairs)!=1: continue
            a,b = pairs[0]
            mid = world(average([a.position,b.position]))
            side = "L" if mid[0]<0 else "R"
            shoulder,elbow = [self.anchors[key+side] for key in ["upperArm","forearm"]]
            axis = normalize([q-p for p,q in zip(shoulder,elbow)])
            reach = sum((p-q)*d for p,q,d in zip(mid,shoulder,axis))
            if reach<.105: continue
            def hem(v,span):
                pos = world(v.position)
                near = tuple(s+t*reach for s,t in zip(shoulder,axis))
                outward = normalize([p-n for p,n in zip(pos,near)])
                return vertex(tuple(p+n*.0018-d*span for p,n,d in zip(pos,outward,axis)),v.uv,v.weights)
            self.emit("SleeveEdge",[hem(a,0),hem(b,0),hem(b,.009),hem(a,.009)])
        neck = self.anchors["neck"]
        rows = []
        for rise,radius in [(-.007,1.08),(.005,1.06),(.017,.99),(.024,.95)]:
            ring=[]
            for i in range(48):
                a = math.tau*i/48
                ring.append(vertex((neck[0]+math.sin(a)*.067*radius,neck[1]+rise+.014*math.cos(a),
                                    neck[2]+math.cos(a)*.064*radius),(i/48,rise*4),{"chest":.62,"neck":.38}))
            rows.append(ring)
        strip("CollarEdge",rows)
        # The two collar leaves fold forward and taper toward the placket.
        for sign in [-1,1]:
            points = [(0.008,-.009,-.072),(.058,-.007,-.027),(.073,-.024,-.050),(.037,-.046,-.079)]
            self.emit("Collar",[vertex((x*sign,neck[1]+y,neck[2]+z),(x,y),{"chest":.65,"neck":.35}) for x,y,z in points])

    def wristband(self, face, side):
        # Cut the sweatband into the forearm surface so the skin and band
        # share the same silhouette as the wrist pronates around the handle.
        wrist = self.anchors["hand"+side]
        elbow = self.anchors["forearm"+side]
        length = math.dist(wrist,elbow)
        axis = [(a-b)/length for a,b in zip(elbow,wrist)]
        def along(v):
            return sum((p-b)*d for p,b,d in zip(world(v.position),wrist,axis))
        hand, above = self.split_face(face,lambda v: along(v)-.031)
        self.emit("Skin",hand)
        if above:
            band, arm = self.split_face(above,lambda v: along(v)-.073)
            self.emit("Wristband",band)
            self.emit("Skin",arm)

    def build(self):
        self.proxy("clothes","male_casualsuit06","Kit")
        self.proxy("clothes","shoes05","Shoe")
        self.proxy("hair",self.hair,"Hair")
        self.proxy("eyes","low-poly","Eyes")
        self.proxy("eyebrows",self.brow,"Brows")
        self.proxy("eyelashes","eyelashes03","Lashes")
        self.proxy("teeth","teeth_base","Teeth")
        arm_axes = {}
        for side in "LR":
            shoulder, elbow = (self.anchors[joint+side] for joint in ("upperArm", "forearm"))
            direction = [b-a for a,b in zip(shoulder,elbow)]
            length = math.sqrt(sum(d*d for d in direction))
            arm_axes[side] = [d/length for d in direction]
        for group, face in self.base.faces:
            if group != "body":
                continue
            ids = [i for i,_ in face]
            center = average([self.points[i] for i in ids])
            position = world(center)
            x,y,_ = position
            hip = self.anchors["thighR"][1]
            shoulder = self.anchors["upperArmR"][1]
            # Leave a generous continuous underlap at the neckline, armholes
            # and shorts. Only the centre, enclosed by *every* kit, is omitted.
            vs = [Vertex(self.points[i],self.base.uv[t],self.weights[i]) for i,t in face]
            upper_kit = hip < y < self.anchors["neck"][1]+.05 and abs(x)<.33
            if upper_kit:
                self.tank_face(vs)
            if y < .228 and all(i in self.hidden for i in ids):
                continue
            if hip-self.shorts_length+.065 < y < shoulder-.163 and abs(x)<.205:
                continue
            side = "L" if x < 0 else "R"
            socket = self.anchors["upperArm"+side]
            along = sum((p-s)*d for p,s,d in zip(position,socket,arm_axes[side]))
            covered = all(i in self.under_kit for i in ids)
            name = "CrewSkin" if upper_kit else "Skin"
            if y > shoulder-.18 and y < self.anchors["neck"][1]+.025 and along < .080 and covered:
                continue
            # Taper hidden thigh skin into the leg opening to give the cloth
            # room on a planted bend without shortening the exposed thigh.
            if y < hip and abs(x) < .28:
                def tuck(v):
                    px,py,pz = world(v.position)
                    inset = .22*max(0,min(1,(py-hip+self.shorts_length+.012)/.055))
                    joint = self.anchors["thigh"+side]
                    return Vertex((-(px+(joint[0]-px)*inset)*10,v.position[1],
                                   -(pz+(joint[2]-pz)*inset)*10),v.uv,v.weights)
                vs = [tuck(v) for v in vs]
            if name == "Skin" and math.dist(position,self.anchors["hand"+side]) < .14:
                self.wristband(vs,side)
            else:
                self.emit(name,vs)

        self.accessories()
        # Sock and shorts enclose these faces for every selectable outfit. Cut
        # the underlying leg inside the overlapping cloth.
        skin = self.parts["Skin"]
        hem = self.anchors["thighL"][1] - self.shorts_length
        def visible(triangle):
            vertices = [skin.vertices[i] for i in triangle]
            heights = [world(v.position)[1] for v in vertices]
            if max(heights) < 0.22:
                return False
            thigh = min(sum(w for bone,w in v.weights.items() if bone.startswith("thigh")) for v in vertices)
            return thigh < 0.65 or min(heights) <= hem+0.065
        skin.faces = [tri for tri in skin.faces if visible(tri)]

    def save(self, output):
        bones = list(self.anchors)
        def bind(name,p):
            # Align local +Y with the limb in its rigid bind frame.
            segments = {"upperArm":"forearm","forearm":"hand","thigh":"shin","shin":"foot"}
            side = name[-1:]
            child = segments.get(name[:-1]) if side in ("L","R") else None
            x,y,z = (1,0,0),(0,1,0),(0,0,1)
            if child:
                def unit(q):
                    d = math.sqrt(sum(v*v for v in q))
                    return tuple(v/d for v in q)
                def cross(a,b):
                    return (a[1]*b[2]-a[2]*b[1],a[2]*b[0]-a[0]*b[2],a[0]*b[1]-a[1]*b[0])
                y = unit(tuple(b-a for a,b in zip(p,self.anchors[child+side])))
                x = unit(cross(y,(0,0,1)))
                z = cross(x,y)
            return "("+",".join("("+",".join(map(fmt,(*row,w)))+")" for row,w in [(x,0),(y,0),(z,0),(p,1)])+")"
        local = array(bind(name,pos) for name,pos in self.anchors.items())
        def parent(name):
            if name.startswith("digit"):
                finger, segment, side = name[5:]
                return "hand"+side if segment == "1" else "digit"+finger+str(int(segment)-1)+side
            return "root"
        def path(name):
            return "root" if name=="root" else path(parent(name))+"/"+name
        paths = array(json.dumps(path(n)) for n in bones)
        relative = array(bind(name, tuple(a-b for a,b in zip(pos,self.anchors[parent(name)])))
                         if name.startswith("digit") else bind(name,pos) for name,pos in self.anchors.items())
        colors = {"Skin":(0.78,0.54,0.43),"SleeveSkin":(0.78,0.54,0.43),"Shirt":(0.08,0.49,0.46),"Sleeves":(0.08,0.49,0.46),
                  "Shorts":(0.12,0.16,0.18),"Hair":(0.13,0.08,0.06),"Eyes":(0.5,0.4,0.3),"Shoe":(0.89,0.9,0.92)}
        look = []
        for name in self.parts:
            look.append(f'''def Material "{name}" {{
                token outputs:surface.connect = </Athlete/Looks/{name}/PBR.outputs:surface>
                def Shader "PBR" {{
                  uniform token info:id = "UsdPreviewSurface"
                  color3f inputs:diffuseColor = {vector(colors.get(name,(.88,.88,.88)))}
                  float inputs:roughness = 0.82
                  token outputs:surface
                }}
              }}''')
        text = f'''#usda 1.0
(
  defaultPrim = "Athlete"
  metersPerUnit = 1
  upAxis = "Y"
)
def SkelRoot "Athlete" (prepend apiSchemas = ["SkelBindingAPI"]) {{
  rel skel:skeleton = </Athlete/Rig>
  def Skeleton "Rig" {{
    uniform token[] joints = {paths}
    uniform matrix4d[] bindTransforms = {local}
    uniform matrix4d[] restTransforms = {relative}
  }}
  def Scope "Looks" {{
    {chr(10).join(look)}
  }}
  {''.join(part.usd(bones) for part in self.parts.values())}
}}
'''
        with TemporaryDirectory() as tmp:
            folder = Path(tmp)
            (folder/"athlete.usda").write_text(text)
            subprocess.run(["usdcat","athlete.usda","-o","athlete.usdc"],cwd=folder,check=True)
            subprocess.run(["usdzip","athlete.usdz","athlete.usdc"],cwd=folder,check=True)
            shutil.copyfile(folder/"athlete.usdz",output)
        print(output.name, {name:len(part.faces) for name,part in self.parts.items()})


def components(mesh, dividing_height):
    adjacent = defaultdict(set)
    for _,face in mesh.faces:
        ids = [i for i,_ in face]
        for i,j in zip(ids,ids[1:]+ids[:1]):
            adjacent[i].add(j);adjacent[j].add(i)
    pending = set(adjacent)
    result = {}
    while pending:
        q = [pending.pop()]; island = list(q)
        while q:
            root = q.pop()
            for i in adjacent[root].intersection(pending):
                q.append(i);island.append(i);pending.remove(i)
        tag = "top" if max(mesh.points[i][1] for i in island)>dividing_height else "bottom"
        result.update((i,tag) for i in island)
    return result


if __name__ == "__main__":
    cli = argparse.ArgumentParser(description=__doc__)
    cli.add_argument("source",type=Path);cli.add_argument("archive",type=Path);cli.add_argument("output",type=Path)
    args = cli.parse_args()
    args.output.mkdir(exist_ok=True,parents=True)
    with ZipFile(args.archive) as package, TemporaryDirectory() as scratch:
        tool = Path(scratch)/"texture"
        subprocess.run(["swiftc",str(Path(__file__).with_name("BakePlayerTexture.swift")),"-o",str(tool)],check=True)
        for model, name in [("male","CourtMan"),("female","CourtWoman")]:
            athlete = Athlete(args.source,package,model)
            athlete.build()
            athlete.save(args.output/(name+".usdz"))
            athlete.textures(args.output,tool)
