"""Generate three coherent, seamless xianxia prototype cues.

The arrangement deliberately avoids low sustained oscillators.  Guqin/pipa-like
plucks carry the harmony, bright bells mark phrases, and battle uses dry frame
drums.  Every cue is an exact number of bars so Godot can loop it cleanly.
"""
from pathlib import Path
import math, wave
import numpy as np

ROOT = Path(__file__).resolve().parents[2]
RATE = 22050
PENTA = np.array([0, 2, 4, 7, 9, 12, 14, 16], dtype=float)


def hz(root, degree):
    return root * 2.0 ** (PENTA[degree] / 12.0)


def pluck(length, freq, amp=.18, bright=1.0):
    n = max(1, int(length * RATE)); t = np.arange(n) / RATE
    attack = np.minimum(1.0, t * 85.0)
    env = attack * np.exp(-t * (3.0 + .5 * bright))
    sig = (np.sin(2*np.pi*freq*t) + .34*bright*np.sin(2*np.pi*freq*2.01*t)
           + .14*bright*np.sin(2*np.pi*freq*3.98*t))
    return sig * env * amp


def bell(length, freq, amp=.08):
    n = max(1, int(length * RATE)); t = np.arange(n) / RATE
    env = np.exp(-2.3*t)
    sig = np.sin(2*np.pi*freq*t) + .34*np.sin(2*np.pi*freq*2.73*t)
    return sig * env * amp


def drum(length, amp=.13, high=False):
    n=max(1,int(length*RATE)); t=np.arange(n)/RATE
    rng=np.random.default_rng(n + int(amp*1000) + int(high))
    f=118 if high else 68
    body=np.sin(2*np.pi*(f*(1-.35*np.minimum(t,1)))*t)
    noise=rng.normal(0,.16,n)
    return (body+noise)*np.exp(-10*t)*amp


def place(buf, sound, start):
    i=int(start*RATE); end=min(len(buf),i+len(sound))
    if i < len(buf): buf[i:end] += sound[:end-i]


def soften(buf):
    # Short musical-room echoes bind individual plucks into one phrase without
    # creating the vocal, ghostly tail of the previous prototype.
    dry=buf.copy()
    for delay,gain in ((.115,.16),(.228,.09),(.347,.045)):
        d=int(delay*RATE); buf[d:] += dry[:-d]*gain
    # tiny fade only at the absolute edges; composition itself resolves to root
    f=int(.08*RATE); ramp=np.linspace(0,1,f)
    buf[:f]*=ramp; buf[-f:]*=ramp[::-1]
    peak=max(.001,float(np.max(np.abs(buf))))
    return np.tanh(buf*(.82/peak)*1.12)*.82


def write(name, buf):
    out=(soften(buf)*32767).astype('<i2')
    path=ROOT/'assets/audio/music'/f'{name}.wav'; path.parent.mkdir(parents=True,exist_ok=True)
    with wave.open(str(path),'wb') as f:
        f.setparams((1,2,RATE,0,'NONE','not compressed')); f.writeframes(out.tobytes())


def compose(name, bpm, beats, root, melody, progression, battle=False):
    beat=60.0/bpm; duration=beats*beat
    buf=np.zeros(int(duration*RATE),dtype=np.float64)
    for b in range(beats):
        chord=progression[(b//8)%len(progression)]
        # Continuous two-note pipa/guqin figure gives the track a steady pulse.
        for half,degree in enumerate((chord, min(7,chord+2))):
            place(buf,pluck(beat*.82,hz(root,degree),.105 if not battle else .09,1.05), (b+half*.5)*beat)
        if b%2==0:
            place(buf,pluck(beat*1.55,hz(root*.5,chord),.085,.55),b*beat)
        # Melody is phrased: three active beats followed by breathing space.
        phrase=b%8
        if phrase in (0,1,2,4,5,6):
            degree=melody[b%len(melody)]
            place(buf,pluck(beat*1.45,hz(root*2,degree),.13,1.2),b*beat+.07)
        if b%16==0:
            place(buf,bell(beat*3.2,hz(root*2,4),.065),b*beat+.04)
        if battle:
            if b%4==0: place(buf,drum(.42,.16),b*beat)
            elif b%2==0: place(buf,drum(.26,.085,True),b*beat)
            place(buf,pluck(beat*.48,hz(root, progression[(b//8)%len(progression)]+1),.065,1.35),b*beat+beat*.5)
    write(name,buf)


compose('menu', 75, 80, 220.0,
        [0,2,4,5,4,2,1,0, 2,3,5,6,5,4,2,1], [0,2,1,3,2], False)
compose('map', 90, 96, 220.0,
        [0,1,3,4,3,2,1,2, 3,4,6,5,4,3,2,1], [0,1,3,2,0,4], False)
compose('battle', 120, 128, 196.0,
        [0,2,3,5,4,3,2,1, 2,4,5,6,5,3,2,0], [0,3,1,4,2,3,1,0], True)
print('AUDIO_V3_OK')
