"""Tiny emulator driver: every step saves a frame and remembers where the
finger went, so the GIF builder can draw a tap marker."""
import json, os, subprocess, sys, time
A = os.path.expanduser('~/Library/Android/sdk/platform-tools/adb')
OUT = os.path.dirname(os.path.abspath(__file__))

def sh(*args):
    return subprocess.run([A, *args], capture_output=True)

class Flow:
    def __init__(self, name):
        self.name = name
        self.dir = os.path.join(OUT, name)
        os.makedirs(self.dir, exist_ok=True)
        for f in os.listdir(self.dir): os.remove(os.path.join(self.dir, f))
        self.frames = []

    def shot(self, hold=1.2, tap=None, caption=None, wait=0.6):
        time.sleep(wait)
        path = os.path.join(self.dir, f'{len(self.frames):02d}.png')
        with open(path, 'wb') as f:
            f.write(sh('exec-out', 'screencap', '-p').stdout)
        self.frames.append({'file': path, 'hold': hold, 'tap': tap, 'caption': caption})
        self.save()
        return path

    def tap(self, x, y, wait=0.8, caption=None, hold=0.9):
        # Frame showing where we're about to tap, then the tap itself.
        self.shot(hold=hold, tap=[x, y], caption=caption, wait=0.2)
        sh('shell', 'input', 'tap', str(x), str(y))
        time.sleep(wait)

    def type(self, text, wait=0.4):
        sh('shell', 'input', 'text', text.replace(' ', '%s').replace("'", "\\'"))
        time.sleep(wait)

    def key(self, code, wait=0.5):
        sh('shell', 'input', 'keyevent', str(code)); time.sleep(wait)

    def save(self):
        json.dump(self.frames, open(os.path.join(self.dir, 'frames.json'), 'w'), indent=1)

def raw_shot(path):
    with open(path, 'wb') as f:
        f.write(sh('exec-out', 'screencap', '-p').stdout)

def fresh():
    sh('shell', 'pm', 'clear', 'com.corplex.corplex')
    sh('shell', 'am', 'start', '-n', 'com.corplex.corplex/.MainActivity')
    time.sleep(5.5)

def P(x, y):
    """Screenshot-preview coordinates (900-wide) to device pixels."""
    return round(x * 1.2), round(y * 1.2)

def setup_paper():
    """Fresh app with the Transformer paper imported and looked up; leaves
    the paper screen open, scrolled to the top."""
    fresh()
    sh('shell','input','tap',*map(str,P(675,1870))); time.sleep(1.2)
    sh('shell','input','tap',*map(str,P(724,1702))); time.sleep(2.5)
    sh('shell','input','tap',*map(str,P(380,530))); time.sleep(2.0)
    sh('shell','input','swipe','540','1500','540','1000','300'); time.sleep(0.8)
    sh('shell','input','tap',*map(str,P(450,1030))); time.sleep(1.0)
    sh('shell','input','text','1706.03762'); time.sleep(0.8)
    # "Look up" sits above the keyboard; no back key (if the keyboard is
    # already down, back navigates instead and everything after misfires).
    sh('shell','input','tap',*map(str,P(740,893))); time.sleep(5.0)
    # The app's own back arrow to the Library, then reopen the paper so its
    # screen starts at the top.
    sh('shell','input','tap',*map(str,P(60,170))); time.sleep(1.5)
    sh('shell','input','tap',*map(str,P(450,495))); time.sleep(1.5)

def _press(self, x, y, ms=900, wait=1.0, caption=None, hold=0.9):
    self.shot(hold=hold, tap=[x, y], caption=caption, wait=0.2)
    sh('shell', 'input', 'swipe', str(x), str(y), str(x), str(y), str(ms))
    time.sleep(wait)

def _drag(self, x1, y1, x2, y2, ms=1200, wait=1.0, caption=None, steps=3):
    self.shot(hold=0.7, tap=[x1, y1], caption=caption, wait=0.2)
    # Break the drag into legs so the GIF shows it moving.
    for i in range(1, steps + 1):
        ax = x1 + (x2 - x1) * (i - 1) / steps; ay = y1 + (y2 - y1) * (i - 1) / steps
        bx = x1 + (x2 - x1) * i / steps; by = y1 + (y2 - y1) * i / steps
        sh('shell', 'input', 'swipe', str(int(ax)), str(int(ay)), str(int(bx)), str(int(by)), str(ms // steps))
    time.sleep(wait)

Flow.press = _press
Flow.drag = _drag

def setup_quoted_note():
    """setup_paper, then quote a passage into a new note; leaves the note open."""
    setup_paper()
    sh('shell','input','tap',*map(str,P(450,521))); time.sleep(7.0)
    x, y = P(162, 399)
    sh('shell','input','swipe',str(x),str(y),str(x),str(y),'900'); time.sleep(1.0)
    sh('shell','input','swipe','235','520','527','537','1200'); time.sleep(1.2)
    sh('shell','input','tap','432','665'); time.sleep(1.5)
    sh('shell','input','tap',*map(str,P(200,1845))); time.sleep(2.5)

import math

def stroke(points):
    """One stylus stroke through the given device-pixel points."""
    (x, y), rest = points[0], points[1:]
    sh('shell', 'input', 'stylus', 'motionevent', 'DOWN', str(int(x)), str(int(y)))
    for x, y in rest:
        sh('shell', 'input', 'stylus', 'motionevent', 'MOVE', str(int(x)), str(int(y)))
    sh('shell', 'input', 'stylus', 'motionevent', 'UP', str(int(x)), str(int(y)))

def circle(cx, cy, r, n=28):
    return [(cx + r * math.cos(2 * math.pi * i / n - 1.4),
             cy + r * 0.92 * math.sin(2 * math.pi * i / n - 1.4)) for i in range(n + 2)]

def line(x1, y1, x2, y2, n=8):
    return [(x1 + (x2 - x1) * i / n, y1 + (y2 - y1) * i / n) for i in range(n + 1)]

def wave(x1, x2, y, amp=14, n=24):
    return [(x1 + (x2 - x1) * i / n, y + amp * math.sin(i / n * 4 * math.pi)) for i in range(n + 1)]
