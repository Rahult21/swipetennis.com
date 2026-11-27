"""Bake two fully clothed, GPU-skinned USD athletes from CC0 MakeHuman assets.

Usage: build_athletes.py SOURCE_DIR SYSTEM_ASSETS_ZIP OUTPUT_DIR.
SOURCE_DIR holds base.obj, default.mhskel, default_weights.mhw and the six
adult *-young.target files. The converter only reads the supplied assets.
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
    if stem.startswith(("wrist", "finger", "metacarpal")):
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
    return "head"


def combined(terms):
    result = defaultdict(float)
    for mix, values in terms:
        for name, value in values.items():
            result[name] += mix * value
    best = sorted(((w, n) for n, w in result.items() if w > 0.0001),reverse=True)[:4]
    weight = sum(w for w, _ in best)
    return {n:w/weight for w,n in best} if best else {"pelvis":1.0}


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
            items = [(bones.index(n),w) for n,w in vert.weights.items()]
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


class Athlete:
    def __init__(self, source, archive, model):
        self.base = Obj((source / "base.obj").read_text())
        self.original = self.base.points
        self.points = list(self.original)
        targets = [(f"{origin}-{model}-young.target",1/3) for origin in ("african","asian","caucasian")]
        targets.append((f"universal-{model}-young-maxmuscle-averageweight.target",0.38))
        for filename, blend in targets:
            target = source / filename
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
                        "neck":pivot("neck01"),"head":pivot("head")}
        for side in "LR":
            for key, bone in [("upperArm","upperarm01"),("forearm","lowerarm01"),("twist","lowerarm02"),("hand","wrist"),
                              ("clav","clavicle"),
                              ("thigh","upperleg01"),("shin","lowerleg01"),("foot","foot")]:
                self.anchors[key+side] = pivot(bone+"."+side)
        self.curl_fingers(rig,weights["weights"])
        for side in "LR":
            palm = average([pivot(f"finger{n}.{side}") for n in ["1-3","3-1","3-3"]])
            knuckles = [pivot(f"finger{n}-1.{side}") for n in [2,5]]
            self.anchors["palm"+side] = palm
            self.anchors["gripAxis"+side] = tuple(p+a-b for p,a,b in zip(palm,*knuckles))
        self.parts = {}
        self.archive = archive
        self.model = model
        self.hidden = set()

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
            strength = 1 if side=="R" else -0.37
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
        hair = "short01" if self.model=="male" else "ponytail01"
        prefix = "Man" if self.model=="male" else "Woman"
        sources = [(skin,prefix+"Skin.jpg",1024),(f"hair/{hair}/{hair}_diffuse.png",prefix+"Hair.png",512)]
        if self.model=="male":
            sources += [("eyes/materials/brown_eye.png","AthleteEyes.jpg",256),
                        ("clothes/shoes05/shoes05_diffuse.png","CourtShoes.jpg",512),
                        ("clothes/male_casualsuit06/male_casualsuit06_ao.png","CourtKit.jpg",512),
                        ("clothes/male_casualsuit06/male_casualsuit06_normal.png","CourtKitNormal.jpg",512)]
        with TemporaryDirectory() as tmp:
            tmp = Path(tmp)
            for asset,name,size in sources:
                image = tmp/"input.png"
                image.write_bytes(self.archive.read(asset))
                args = [str(tool),str(image),str(folder/name),str(size)]
                if asset==skin:
                    mesh = self.parts["Skin"]
                    mask = tmp/"skin-uv.json"
                    mask.write_text(json.dumps([[mesh.vertices[i].uv for i in face] for face in mesh.faces]))
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
            self.anchors["tailBase"] = (0.,head[1]+.033,head[2]+.102)
            self.anchors["tailTip"] = (0.,head[1]-.077,head[2]+.121)
            skinning = []
            for point in mapped:
                _,y,z = world(point)
                falls = min(1,max(0,(self.anchors["tailBase"][1]-y)/.066))
                rear = min(1,max(0,(z-head[2]-.061)/.035))
                hangs = falls*rear if self.model=="female" else 0
                tip = min(1,max(0,(self.anchors["tailTip"][1]+.031-y)/.081))
                skinning.append({"head":1-hangs,"tailBase":hangs*(1-tip),"tailTip":hangs*tip})
        if kind == "Eyes":
            eye = ["eyeR" if world(p)[0]>0 else "eyeL" for p in mapped]
            for name in ["eyeL","eyeR"]:
                cloud = [world(p) for p,bone in zip(mapped,eye) if bone==name]
                center = tuple((max(axis)+min(axis))*0.5 for axis in zip(*cloud))
                self.anchors[name] = (center[0],center[1],center[2]+0.004)
            skinning = [{bone:1.0} for bone in eye]
        if kind == "Shoe":
            # Hide the enclosed toes, not just the surfaces with the strongest foot weights.
            deleted = fitting.index("delete_verts")+1
            tokens = " ".join(fitting[deleted:]).split()
            for i,t in enumerate(tokens):
                if t.isdigit():
                    self.hidden.add(int(t))
                elif t == "-" and i and i+1 < len(tokens):
                    self.hidden.update(range(int(tokens[i-1]),int(tokens[i+1])+1))
        # The source suit has two connected islands: exclude the lower trouser leg.
        groups = components(mesh) if kind == "Kit" else {}
        for _,face in mesh.faces:
            vs = [Vertex(mapped[i],mesh.uv[t],skinning[i]) for i,t in face]
            if kind != "Kit":
                self.emit(kind,vs); continue
            if groups[face[0][0]] == "top":
                arm = sum(sum(w for bone,w in v.weights.items() if bone.startswith(("upperArm","forearm"))) for v in vs)/len(vs)
                self.emit("Sleeves" if arm > 0.50 else "Shirt",vs)
            else:
                hem = (self.anchors["thighL"][1]-0.25-0.88)*10
                self.emit("Shorts",clip_height(vs,hem))

    def accessories(self):
        """Build optional, weighted kit pieces after fitting the common sportswear."""
        def vertex(p,uv,bones):
            return Vertex((-p[0]*10,(p[1]-.88)*10,-p[2]*10),uv,bones)
        def strip(name,rows,wrap=True):
            for a,b in zip(rows,rows[1:]):
                for i in range(len(a) if wrap else len(a)-1):
                    j=(i+1)%len(a)
                    self.emit(name,[a[i],b[i],b[j],a[j]])
        for side in "LR":
            foot = self.anchors["foot"+side]
            shoe = [world(v.position) for v in self.parts["Shoe"].vertices if (world(v.position)[0]<0)==(side=="L")]
            floor = min(p[1] for p in shoe)
            sole = [p for p in shoe if p[1]<floor+0.008]
            self.anchors["toe"+side] = (foot[0],floor,min(p[2] for p in sole))
            self.anchors["heel"+side] = (foot[0],floor,max(p[2] for p in sole))
            wrist = self.anchors["hand"+side]
            elbow = self.anchors["forearm"+side]
            def normalize(q):
                length = math.sqrt(sum(v*v for v in q))
                return tuple(v/length for v in q)
            axis = normalize([e-w for e,w in zip(elbow,wrist)])
            x = normalize((axis[2],0,-axis[0]))
            z = (axis[1]*x[2]-axis[2]*x[1],axis[2]*x[0]-axis[0]*x[2],axis[0]*x[1]-axis[1]*x[0])
            skin = [world(v.position) for v in self.parts["Skin"].vertices if sum(v.weights.get(b+side,0) for b in ["hand","forearm","twist"])>0.82]
            rows = []
            for distance,extra in [(0.034,.0007),(.037,.003),(.043,.003),(.048,.0024),(.066,.0024),(.073,.003),(.078,.0007)]:
                section = []
                for pos in skin:
                    delta = [p-w for p,w in zip(pos,wrist)]
                    dot = lambda vec:sum(a*b for a,b in zip(delta,vec))
                    if abs(dot(axis)-distance)<.013: section.append((dot(x),dot(z)))
                axes = list(zip(*section))
                if len(axes)!=2: axes = [[-.033,.033],[-.029,.029]]
                cx,cz = [(max(q)+min(q))/2 for q in axes]
                rx,rz = [(max(q)-min(q))/2+extra+.0025 for q in axes]
                ring = []
                for i in range(40):
                    t = i*math.tau/40
                    p = tuple(w+d*distance+a*(cx+rx*math.cos(t))+b*(cz+rz*math.sin(t)) for w,d,a,b in zip(wrist,axis,x,z))
                    ring.append(vertex(p,(i/40,distance),{"twist"+side:1}))
                rows.append(ring)
            strip("Wristband",rows)
        head = self.anchors["head"]
        # A fitted ribbed sock follows calf and ankle weights and overlaps the shoe.
        # Each ring fits the body mesh at that height instead of wrapping a cylinder.
        for side in "LR":
            foot = self.anchors["foot"+side]; sign = -1 if side=="L" else 1
            lower = [world(v.position) for name in ["Skin","Shoe"] for v in self.parts[name].vertices
                     if world(v.position)[0]*sign>0 and 0.10<world(v.position)[1]<0.36]
            rows = []
            for height,extra in [(0.128,.0008),(.152,.0014),(.187,.0015),(.22,.0015),(.247,.0019),
                                 (.253,.003),(.261,.002),(.266,.0034),(.273,.0014)]:
                ring = []
                section = [p for p in lower if abs(p[1]-height)<0.014]
                if not section: section = sorted(lower,key=lambda p:abs(p[1]-height))[:16]
                xs,_,zs = list(zip(*section)); cx,cz=(min(xs)+max(xs))/2,(min(zs)+max(zs))/2
                for i in range(48):
                    a=math.tau*i/48; dx,dz=math.cos(a),math.sin(a)
                    radius=max((p[0]-cx)*dx+(p[2]-cz)*dz for p in section)+extra+0.0008*(i%2)
                    shin=min(1,max(0,(height-0.128)/0.052))
                    bones={"shin"+side:shin,"foot"+side:1-shin}
                    ring.append(vertex((cx+dx*radius,height,cz+dz*radius),(i/48,(height-.128)*6),bones))
                rows.append(ring)
            strip("Sock",rows)
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
        waist = self.anchors["thighR"][1] + .062
        pants = [world(v.position) for v in self.parts["Shorts"].vertices]
        rows = []
        for depth in [0,.017,.061,.12,.195,.239,.244]:
            row = []
            section = [p for p in pants if abs(p[1]-(waist-depth))<.037] or pants
            width = max(abs(p[0]) for p in section)+.010
            front,back = min(p[2] for p in section)-.017,max(p[2] for p in section)+.017
            cz,rz = (front+back)/2,(back-front)/2
            for i in range(64):
                t = i*math.tau/64; left = math.sin(t)<0
                flare = max(0.,depth-.052)*(.089+.032*math.cos(t*16))
                thigh = min(.56,depth*2.25)*abs(math.sin(t))
                weights = {"pelvis":1-thigh,("thighL" if left else "thighR"):thigh}
                row.append(vertex(((width+flare)*math.sin(t),waist-depth,cz-(rz+flare)*math.cos(t)),(i/64,depth),weights))
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
            points = [(0.009,.005,-.068),(.066,.008,-.015),(.088,-.018,-.045),(.041,-.061,-.088)]
            self.emit("Collar",[vertex((x*sign,neck[1]+y,neck[2]+z),(x,y),{"chest":.65,"neck":.35}) for x,y,z in points])

    def build(self):
        self.proxy("clothes","male_casualsuit06","Kit")
        self.proxy("clothes","shoes05","Shoe")
        self.proxy("hair","short01" if self.model == "male" else "ponytail01","Hair")
        self.proxy("eyes","low-poly","Eyes")
        for group, face in self.base.faces:
            if group != "body" or all(i in self.hidden for i,_ in face):
                continue
            ids = [i for i,_ in face]
            center = average([self.points[i] for i in ids])
            # Only skin exposed by the shortest kit is retained. This also prevents
            # buried body faces from emerging through the waistband while running.
            if -1.2 < center[1] < 4.7 and abs(center[0]) < 1.55:
                continue
            if -1.1 < center[1] < 0.7 and abs(center[0]) < 1.9:
                continue
            self.emit("Skin",[Vertex(self.points[i],self.base.uv[t],self.weights[i]) for i,t in face])

        self.accessories()

    def save(self, output):
        bones = list(self.anchors)
        def bind(name,p):
            # Align local +Y along each limb. At runtime the long axis alone
            # can adapt to the target reach without inflating arms or legs.
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
        paths = array(json.dumps("root" if n=="root" else "root/"+n) for n in bones)
        colors = {"Skin":(0.78,0.54,0.43),"Shirt":(0.08,0.49,0.46),"Sleeves":(0.08,0.49,0.46),
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
    uniform matrix4d[] restTransforms = {local}
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


def components(mesh):
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
        tag = "top" if max(mesh.points[i][1] for i in island)>4 else "bottom"
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
