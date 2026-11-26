"""Build short shoe textures and the muffled defensive block from the bundled impact recording."""
import array
import math
import random
import wave
from pathlib import Path

root = Path(__file__).resolve().parents[1] / 'SwipeTennis'
rate = 22050
def write(name, samples, sample_rate):
    with wave.open(str(root / (name+'.wav')),'wb') as out:
        out.setparams((1,2,sample_rate,0,'NONE','not compressed'))
        out.writeframes(array.array('h',(round(min(1,max(-1,x))*32767) for x in samples)).tobytes())

for surface, duration in [('clay',0.22),('grass',0.105),('hard',0.12)]:
    rng = random.Random(17)
    slow = fast = 0
    samples = []
    for i in range(int(duration*rate)):
        t = i/rate
        noise = rng.uniform(-1,1)
        slow += 0.045*(noise-slow)
        fast += 0.42*(noise-fast)
        impact = math.sin(2*math.pi*78*t)*math.exp(-t*62)
        envelope = min(1,t/0.006)*max(0,1-t/duration)**1.8
        if surface == 'clay':
            grain = (fast-slow)*(0.40 + 0.45*math.sin(2*math.pi*(38*t+58*t*t))**2)
            sound = 0.17*impact + grain
        elif surface == 'grass':
            sound = 0.44*impact + 0.9*slow
        else:
            sound = 0.36*impact + 0.37*fast + 0.05*math.sin(2*math.pi*(540*t+850*t*t))
        samples.append(sound*envelope)
    write('shoe-'+surface,samples,rate)

with wave.open(str(root/'hit.wav'),'rb') as src:
    assert src.getnchannels()==1 and src.getsampwidth()==2
    rate = src.getframerate()
    source = array.array('h',src.readframes(src.getnframes()))
lp = 0
blocked = []
for i, value in enumerate(source):
    lp += (1-math.exp(-2*math.pi*1800/rate))*(value/32768-lp)
    blocked.append(lp*math.exp(-i/rate*9))
write('block',blocked,rate)
