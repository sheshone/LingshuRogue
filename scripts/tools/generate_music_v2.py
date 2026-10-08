"""Generate restrained xianxia prototype music and ceremonial UI sounds.

The cues use a bright major-pentatonic vocabulary, sparse plucked-string
phrases, bell partials and soft breath tones. Event tails wrap around the
buffer so Godot can loop the WAV without a hard seam.
"""
from array import array
import math, random, wave
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
RATE = 22050


def add_note(buf, start, duration, freq, amp, kind="qin"):
    frames = len(buf)
    count = int(duration * RATE)
    for i in range(count):
        t = i / RATE
        if kind == "bell":
            env = math.exp(-2.1 * t)
            value = (math.sin(math.tau*freq*t) + .42*math.sin(math.tau*freq*2.01*t)
                     + .21*math.sin(math.tau*freq*2.72*t) + .12*math.sin(math.tau*freq*4.15*t)) * env
        elif kind == "drum":
            env = math.exp(-8.5*t)
            value = (math.sin(math.tau*(freq*(1-.55*t))*t) + random.uniform(-.22,.22)) * env
        else:
            env = (1-math.exp(-32*t))*math.exp(-3.15*t)
            value = (math.sin(math.tau*freq*t)+.31*math.sin(math.tau*freq*2.005*t)
                     +.12*math.sin(math.tau*freq*3.98*t)) * env
        idx = (int(start*RATE)+i) % frames
        buf[idx] += value*amp


def write_wav(path, buf):
    peak = max(.001, max(abs(x) for x in buf))
    gain = .78/peak
    pcm = array('h', (max(-32767,min(32767,int(x*gain*32767))) for x in buf))
    path.parent.mkdir(parents=True, exist_ok=True)
    with wave.open(str(path), 'wb') as out:
        out.setparams((1,2,RATE,0,'NONE','not compressed'))
        out.writeframes(pcm.tobytes())


def music(name, root, duration, beat, melody, intensity=0):
    random.seed(hash(name)&0xffff)
    buf = array('f', [0.0])*int(duration*RATE)
    scale = [1.0, 9/8, 5/4, 3/2, 5/3, 2.0]
    for step in range(int(duration/beat)):
        note = melody[step % len(melody)]
        start = step*beat
        # Short, articulated notes leave clean silence between phrases; avoiding
        # long resonant tails is important here because they read as vocal moans.
        add_note(buf,start,1.35,root*scale[note],.23 if intensity==0 else .18,"qin")
        if step%4==0:
            add_note(buf,start+.08,2.0,root*2*scale[melody[(step+2)%len(melody)]],.05,"bell")
        if step%8 in (2,6):
            add_note(buf,start+.38,1.5,root*4*scale[melody[(step+4)%len(melody)]],.038,"qin")
        if intensity:
            add_note(buf,start,0.48,72 if step%4==0 else 94,.11 if intensity==1 else .16,"drum")
            if intensity>1 and step%2:
                add_note(buf,start+beat*.5,.35,132,.09,"drum")
    write_wav(ROOT/'assets/audio/music'/f'{name}.wav',buf)


def ceremonial_sound(name, notes, kind="bell"):
    duration=2.6
    buf=array('f',[0.0])*int(duration*RATE)
    for index,freq in enumerate(notes):
        add_note(buf,index*.24,duration-index*.18,freq,.22,kind if index%2==0 else "qin")
    write_wav(ROOT/'assets/audio/sfx'/f'{name}.wav',buf)


music('menu', 261.63, 88.0, 1.35, [0,2,4,5,4,3,2,4,5,4,2,3,4,5,3,2], 0)
music('map', 246.94, 88.0, 1.5, [0,1,3,4,5,4,3,2,4,5,3,4,2,3,4,5], 0)
music('battle', 246.94, 64.0, 1.0, [0,2,3,4,2,1,3,5,4,3,2,0,1,3,2,4], 1)
music('elite', 220.0, 64.0, .86, [0,3,2,4,1,3,5,4,2,3,1,4,3,2,0,3], 2)
music('boss', 196.0, 64.0, .75, [0,3,4,2,5,4,3,1,4,2,3,5,4,1,3,2], 2)
ceremonial_sound('victory',[392.0,493.88,587.33,783.99])
ceremonial_sound('relic_trigger',[523.25,659.25,783.99])
print('AUDIO_V2_OK')
