"""Retarget the two Tennis-MoCap BVH recordings listed in apple/MotionCredits.md.
Usage: python3 apple/Tools/retarget_tennis.py forehand.bvh volley.bvh destination.csv
The output is a separate, editable CC BY-SA 3.0 animation asset.
"""
import csv
import math
import sys


def multiply(a, b):
    return [[sum(a[i][k]*b[k][j] for k in range(3)) for j in range(3)] for i in range(3)]


def turn(axis, degrees):
    c, s = math.cos(math.radians(degrees)), math.sin(math.radians(degrees))
    return {'X': [[1,0,0],[0,c,-s],[0,s,c]], 'Y': [[c,0,s],[0,1,0],[-s,0,c]],
            'Z': [[c,-s,0],[s,c,0],[0,0,1]]}[axis]


def read(path):
    header, motion = open(path).read().split('MOTION')
    stack, joints, index = [], {}, 0
    for line in header.splitlines():
        w = line.split()
        if not w:
            continue
        if w[0] in ('ROOT', 'JOINT', 'End'):
            name = w[1] if w[0] != 'End' else None
            if name:
                joints[name] = {'parent': stack[-1] if stack else None}
            stack.append(name)
        elif w[0] == '}':
            stack.pop()
        elif w[0] == 'OFFSET' and stack[-1]:
            joints[stack[-1]]['offset'] = list(map(float, w[1:]))
        elif w[0] == 'CHANNELS':
            joints[stack[-1]]['channels'] = list(enumerate(w[2:], index))
            index += int(w[1])
    frames = []
    for line in motion.strip().splitlines()[2:]:
        values = list(map(float, line.split()))
        positions, rotations = {}, {}
        for name, joint in joints.items():
            parent = joint['parent']
            rotation = rotations[parent] if parent else [[1,0,0],[0,1,0],[0,0,1]]
            origin = positions[parent] if parent else [0,0,0]
            offset = joint['offset']
            position = [origin[i]+sum(rotation[i][j]*offset[j] for j in range(3)) for i in range(3)]
            for k, channel in joint['channels']:
                if channel.endswith('position'):
                    position['XYZ'.index(channel[0])] += values[k]
                else:
                    rotation = multiply(rotation, turn(channel[0],values[k]))
            positions[name], rotations[name] = position, rotation
        frames.append(positions)
    return frames


def sample(frames, index):
    f = frames[index]
    hip, shoulder, wrist = (f[name] for name in ['Hips','RightShoulder','RightWrist'])
    left, right = f['LeftAnkle'], f['RightAnkle']
    # Project each joint into the player's transverse plane; retain vertical translations in metres.
    dx, dz = shoulder[0]-f['LeftShoulder'][0], shoulder[2]-f['LeftShoulder'][2]
    length = math.hypot(dx,dz)
    def lateral(a,b):
        return ((a[0]-b[0])*dx+(a[2]-b[2])*dz)/length/100
    return [hip[1]/100, left[1]/100, right[1]/100, lateral(left,hip), lateral(right,hip),
            lateral(wrist,shoulder), (wrist[1]-shoulder[1])/100]


def extract(writer, name, frames, first, last):
    base = sample(frames,first)
    for i in range(first,last+1,2):
        writer.writerow([name] + [round(a-b,5) for a,b in zip(sample(frames,i),base)])


if __name__ == '__main__':
    drive, volley = read(sys.argv[1]), read(sys.argv[2])
    def fastest(frames):
        # Use a complete interior stroke; the dominant wrist-speed peak anchors its contact transition.
        return max(range(90,min(len(frames)-110,650)),key=lambda i: math.dist(frames[i-2]['RightWrist'],frames[i+2]['RightWrist']))
    hit, block = fastest(drive), fastest(volley)
    with open(sys.argv[3],'w',newline='') as output:
        writer = csv.writer(output,lineterminator='\n')
        writer.writerow(['clip','pelvisY','leftY','rightY','leftX','rightX','handX','handY'])
        extract(writer,'plant',drive,hit-38,hit)
        extract(writer,'recover',drive,hit+10,hit+82)
        extract(writer,'volley',volley,block-52,block)
    print('Contact anchors (100 Hz)',hit,block)
