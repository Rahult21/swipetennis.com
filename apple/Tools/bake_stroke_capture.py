"""Create the editable CC BY-SA 3.0 stroke data described in MotionCredits.md.

The source capture faces +Z; anatomical right is -X. The exported axes are
player-right, vertical, and toward the net. Positions are shoulder-relative
and normalized by each original arm's segment length.
"""
import argparse
import csv
import math
from pathlib import Path
from retarget_tennis import read

CLIPS = [
    ("serve","lvargas_Servicio_21seg.bvh",413),
    ("smash","lvargas_Remate.bvh",2386),
    ("backhand","lvargas_Reves.bvh",910),
    ("forehand","lvargas_Derecha_7seg.bvh",299),
    ("volley","lvargas_VDerecha.bvh",1227),
]


def relative(a,b,scale=1.0):
    return [-(a[0]-b[0])*scale,(a[1]-b[1])*scale,(a[2]-b[2])*scale]


def sample(frame):
    def between(a,b):
        return relative(frame[a],frame[b])
    result = []
    for pair in [("RightHip","LeftHip"),("RightShoulder","LeftShoulder")]:
        dx,dy,dz = between(*pair)
        result += [math.atan2(dz,dx)]
    result += [(frame["LeftShoulder"][1]-frame["RightShoulder"][1])/200]
    for side in ["Right","Left"]:
        shoulder,elbow,wrist = [frame[side+n] for n in ["Shoulder","Elbow","Wrist"]]
        arm = math.dist(shoulder,elbow)+math.dist(elbow,wrist)
        # The pole determines which way the elbow bends around a wrist fixed by the ball.
        midpoint = [(s+w)/2 for s,w in zip(shoulder,wrist)]
        result += relative(wrist,shoulder,1/arm) + relative(elbow,midpoint,1/arm)
    result += relative(frame["RightAnkle"],frame["LeftAnkle"],0.01)
    return result


if __name__ == "__main__":
    cli = argparse.ArgumentParser(description=__doc__)
    cli.add_argument("directory",type=Path)
    cli.add_argument("output",type=Path)
    args = cli.parse_args()
    with args.output.open("w",newline="") as table:
        writer = csv.writer(table,lineterminator="\n")
        writer.writerow(["stroke","seconds","hipYaw","chestYaw","shoulderTilt"]+
                        [bone+axis for bone in ["rightWrist","rightPole","leftWrist","leftPole","rearFoot"] for axis in "XYZ"])
        for name,file,hit in CLIPS:
            sequence = read(args.directory/file)
            for offset in range(-82,71,2):
                writer.writerow([name,offset/100]+[round(v,5) for v in sample(sequence[hit+offset])])
