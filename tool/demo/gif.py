"""Turns a recorded flow into a small looping GIF: phone-shaped frames on
warm paper, a caption line, a sage ripple where the finger taps, and short
cross-fades between steps."""
import json, os, sys
from PIL import Image, ImageDraw, ImageFont

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), '..', '..'))
FONT = ImageFont.truetype(f'{ROOT}/assets/fonts/Roboto-Bold.ttf', 17)
PAPER = (244, 241, 232)
SAGE = (85, 113, 90)
W, SCALE = 300, 300 / 1080          # phone width in the GIF
PH = round(2400 * SCALE)            # phone height
PAD, CAP = 18, 44
CW, CH = W + 2 * PAD, PH + 2 * PAD + CAP

def phone(path, crop_top=0):
    im = Image.open(path).convert('RGB').resize((W, PH), Image.LANCZOS)
    return im

def compose(im, caption, tap=None, ripple=0.0):
    c = Image.new('RGB', (CW, CH), PAPER)
    # soft shadow + rounded phone
    sh = Image.new('L', (CW, CH), 0)
    ImageDraw.Draw(sh).rounded_rectangle([PAD+2, PAD+5, PAD+W+2, PAD+PH+5], 26, fill=60)
    c.paste((205, 200, 188), (0, 0), sh)
    m = Image.new('L', (W, PH), 0)
    ImageDraw.Draw(m).rounded_rectangle([0, 0, W-1, PH-1], 26, fill=255)
    frame = im.copy()
    if tap is not None:
        x, y = tap[0] * SCALE, tap[1] * SCALE
        ov = Image.new('RGBA', (W, PH), (0, 0, 0, 0))
        d = ImageDraw.Draw(ov)
        r = 14 + 16 * ripple
        d.ellipse([x-r, y-r, x+r, y+r], fill=(*SAGE, int(110 * (1 - ripple) + 40)))
        d.ellipse([x-11, y-11, x+11, y+11], outline=(255, 255, 255, 230), width=3, fill=(*SAGE, 170))
        frame = Image.alpha_composite(frame.convert('RGBA'), ov).convert('RGB')
    c.paste(frame, (PAD, PAD), m)
    return with_caption(c, caption)

def with_caption(c, caption):
    if caption:
        c = c.copy()
        d = ImageDraw.Draw(c)
        tw = d.textlength(caption, font=FONT)
        d.text(((CW - tw) / 2, PAD + PH + 12), caption, font=FONT, fill=(52, 70, 56))
    return c

def build(name, out):
    frames = json.load(open(os.path.join(name, 'frames.json')))
    seq, durs = [], []
    caption = ''
    prev = None   # previous frame without its caption
    for fr in frames:
        caption = fr['caption'] or caption
        im = phone(fr['file'])
        base = compose(im, None)
        # Cross-fade the phone only; the caption switches crisply.
        if prev is not None:
            for t in (0.33, 0.66):
                seq.append(with_caption(Image.blend(prev, base, t), caption)); durs.append(50)
        if fr['tap']:
            for rp in (0.0, 0.5, 1.0):
                seq.append(compose(im, caption, fr['tap'], rp)); durs.append(int(fr['hold'] * 1000 / 3))
            prev = compose(im, None, fr['tap'], 1.0)
        else:
            seq.append(with_caption(base, caption)); durs.append(int(fr['hold'] * 1000))
            prev = base
    # Each frame gets its own palette: one shared palette can't hold every
    # colour a clip passes through (warm greys, sage, clay, highlighter
    # inks) and visibly shifted some of them.
    q = [f.quantize(colors=256, method=Image.Quantize.MEDIANCUT, dither=Image.Dither.NONE) for f in seq]
    q[0].save(out, save_all=True, append_images=q[1:], duration=durs, loop=0, optimize=True, disposal=1)
    return len(seq), os.path.getsize(out)

if __name__ == '__main__':
    print(build(sys.argv[1], sys.argv[2]))
