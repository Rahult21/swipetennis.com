"""Bake four metre-scaled tennis surfaces into the iOS asset catalog."""
import json
import math
import random
import struct
import zlib
from pathlib import Path

CATALOG = Path(__file__).resolve().parents[1] / "SwipeTennis" / "Assets.xcassets"
BASE = {"lawn": (52, 111, 79), "mesa": (179, 87, 54),
        "harbor": (46, 109, 155), "night": (44, 64, 135)}


def chunk(tag, data):
    return struct.pack(">I", len(data)) + tag + data + struct.pack(">I", zlib.crc32(tag + data))


def bake(venue, base):
    rng = random.Random(842)
    width, height = 384, 832
    scan = bytearray()
    for row in range(height):
        z = 23.77 * (row + 0.5) / height
        scan.append(0)
        for col in range(width):
            x = 10.97 * (col + 0.5) / width - 1.37
            speck = rng.uniform(-1, 1)
            if venue == "lawn":
                stripe = (int(z / (23.77 / 8)) % 2 - 0.5) * 11
                grain = speck * 8 + 2.5 * math.sin(2 * x + 3 * z)
                worn = math.exp(-((x - 4.115) / 3.1)**2 - (min(z, 23.77-z) / 0.82)**2)
                color = [base[0]+grain+stripe+31*worn, base[1]+grain+stripe-10*worn,
                         base[2]+grain+stripe-24*worn]
            elif venue == "mesa":
                # Local clusters of grit and broad, curved sweep marks in the clay.
                brush = math.cos(z * 3.7 + 0.03 * (x-4)**2)
                grain = speck * 11 + brush * 3 + 2 * math.sin(x * 3 + z * 2)
                color = [c + grain for c in base]
            else:
                # Fine acrylic aggregate. Keep the blue uniform at playing distance.
                grain = 5 * speck + 1.3 * math.sin(0.75*x + 0.47*z)
                color = [c + grain for c in base]
            scan.extend(max(0, min(255, round(c))) for c in color)
    png = b'\x89PNG\r\n\x1a\n' + chunk(b'IHDR', struct.pack('>2I5B', width, height, 8, 2, 0, 0, 0))
    png += chunk(b'IDAT', zlib.compress(scan, 9)) + chunk(b'IEND', b'')
    dest = CATALOG / ("court-" + venue + ".imageset")
    dest.mkdir(exist_ok=True)
    (dest / "surface.png").write_bytes(png)
    meta = {"images": [{"filename": "surface.png", "idiom": "universal"}],
            "info": {"author": "xcode", "version": 1}}
    (dest / "Contents.json").write_text(json.dumps(meta, indent=2) + "\n")


if __name__ == "__main__":
    for name, rgb in BASE.items():
        bake(name, rgb)


def ball_felt():
    rng = random.Random(3107)
    width,height = 384,192
    scan = bytearray()
    for row in range(height):
        scan.append(0)
        lat = math.pi*(0.5-(row+0.5)/height)
        for col in range(width):
            lon = math.tau*(col+0.5)/width
            curve = 0.72*math.sin(2*lon)
            slope = 1.44*math.cos(2*lon)/max(0.03,math.cos(lat))
            edge = abs(lat-curve)/math.sqrt(1+slope*slope)
            seam = min(1,max(0,(0.053-edge)/0.016)) if abs(lat-curve)<0.25 else 0
            groove = math.exp(-((edge-0.054)/0.014)**2) if abs(lat-curve)<0.25 else 0
            grain = rng.gauss(0,5)
            for felt,thread in zip((202,231,53),(244,244,209)):
                scan.append(max(0,min(255,int(felt+(thread-felt)*seam+grain-groove*17))))
    png = b'\x89PNG\r\n\x1a\n'+chunk(b'IHDR',struct.pack('>2I5B',width,height,8,2,0,0,0))
    dest = CATALOG/"match-ball.imageset"
    dest.mkdir(exist_ok=True)
    (dest/"felt.png").write_bytes(png+chunk(b'IDAT',zlib.compress(scan,9))+chunk(b'IEND',b''))
    meta = {"images":[{"filename":"felt.png","idiom":"universal"}],"info":{"author":"xcode","version":1}}
    (dest/"Contents.json").write_text(json.dumps(meta,indent=2)+"\n")


if __name__ == "__main__":
    ball_felt()
