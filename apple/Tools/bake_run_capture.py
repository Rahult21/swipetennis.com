"""Extract one runner's arm swing and torso motion from CMU trial 16_55.c3d."""
import argparse
import csv
import math
import struct
from pathlib import Path


def markers(path):
    data = path.read_bytes()
    parameters = (data[0] - 1) * 512
    processor = data[parameters + 3]
    point_count, analog, first, last = struct.unpack_from("<4H", data, 2)
    if processor != 85 or analog:
        raise ValueError("Expected the original DEC C3D point recording")
    # VAX F-float stores its two 16-bit words in reverse IEEE order.
    scale = struct.unpack("<f", data[14:16] + data[12:14])[0] / 4
    base = (struct.unpack_from("<H", data, 16)[0] - 1) * 512
    p = parameters + 4
    names = []
    while p + 4 < base:
        n, group = struct.unpack_from("bb", data, p)
        if not n or not group:
            break
        key = data[p + 2:p + 2 + abs(n)]
        p += 2 + abs(n)
        offset = struct.unpack_from("<H", data, p)[0]
        if group == 3 and key == b"LABELS":
            width, count = data[p + 4:p + 6]
            text = data[p + 6:p + 6 + width * count]
            names = [text[i:i + width].decode().strip().split(":")[-1]
                     for i in range(0, len(text), width)]
        if not offset:
            break
        p += offset
    frames = []
    for frame in range(last - first + 1):
        points = {}
        for i, name in enumerate(names[:41]):
            x, y, z, confidence = struct.unpack_from("<hhhh", data, base + 8 * (frame * point_count + i))
            if confidence >= 0:
                points[name] = (x * scale / 1000, y * scale / 1000, z * scale / 1000)
        frames.append(points)
    return frames


def midpoint(a, b):
    return [(x + y) / 2 for x, y in zip(a, b)]


def offset(a, b):
    # Subject runs along lab +X. Export right, up, forward.
    return [b[1] - a[1], a[2] - b[2], a[0] - b[0]]


def extract(frame):
    result = []
    for side in ["R", "L"]:
        shoulder = frame[side + "SHO"]
        elbow = frame[side + "ELB"]
        wrist = midpoint(frame[side + "WRA"], frame[side + "WRB"])
        reach = math.dist(shoulder, elbow) + math.dist(elbow, wrist)
        for v in [offset(wrist, shoulder), offset(elbow, midpoint(wrist, shoulder))]:
            result.extend(x / reach for x in v)
    waist = midpoint(midpoint(frame["RFWT"],frame["RBWT"]),midpoint(frame["LFWT"],frame["LBWT"]))
    for tag in ["FWT","SHO"]:
        x, _, z = offset(frame["R"+tag],frame["L"+tag])
        result.append(math.atan2(z,x))
    result.append(waist[2])
    return result


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("source", type=Path)
    parser.add_argument("destination", type=Path)
    args = parser.parse_args()
    frames = markers(args.source)
    # A left foot strike to the following left foot strike, captured at 120 Hz.
    rows = [extract(frames[i]) for i in range(106, 179, 2)]
    average_height = sum(r[-1] for r in rows) / len(rows)
    for r in rows:
        r[-1] -= average_height
    # Take out the small drift between the two ends as the runner accelerates.
    # Distribute it across the full cycle instead of jumping at the loop seam.
    drift = [b-a for a,b in zip(rows[0], rows[-1])]
    with args.destination.open("w", newline="") as out:
        table = csv.writer(out, lineterminator="\n")
        table.writerow([bone+axis for bone in ("rightHand","rightPole","leftHand","leftPole") for axis in "XYZ"] +
                       ["hipYaw","shoulderYaw","pelvisY"])
        for i,row in enumerate(rows[:-1]):
            table.writerow([round(v-d*i/(len(rows)-1),5) for v,d in zip(row,drift)])
