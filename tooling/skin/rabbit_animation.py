"""Render the original Fish Pocket rabbit's sprite sheets and an optional GIF preview."""
import argparse
import json
import math
from pathlib import Path

from PIL import Image, ImageChops, ImageColor, ImageDraw, ImageFilter

ASSETS = Path(__file__).resolve().parents[2] / 'app/DshIOS/Assets.xcassets'
FPS = 24
TILE = 264
SAMPLE = 4
INK = '#4C4260'
EAR_OUTER, EAR_INNER, EAR_OUTLINE = '#FFF1E6', '#E9B5C6', '#7C6880'
CLIPS = {'blink': 9, 'look': 39, 'hop': 25, 'code': 37, 'search': 49}


def track(t, *keys):
    """Join timed poses with zero slope at the ends of each interval."""
    if t <= keys[0][0]:
        return keys[0][1]
    for (start, a), (end, b) in zip(keys, keys[1:]):
        if t <= end:
            u = (t - start) / (end - start)
            return a + (b - a) * u * u * (3 - 2 * u)
    return keys[-1][1]


def pose(clip, t):
    p = dict(lift=0, squash=0, lean=0, nod=0, gaze=0, lid=0, smile=0,
             ear_l=0, ear_r=0, foot_l=0, foot_r=0, paw_l=0, paw_r=0, prop=0)
    if clip == 'blink':
        p.update(lid=track(t, (0, 0), (.28, 1), (.42, 1), (.84, 0)),
                 nod=track(t, (0, 0), (.44, .85), (1, 0)),
                 ear_l=track(t, (0, 0), (.46, -2.1), (.75, .8), (1, 0)),
                 ear_r=track(t, (0, 0), (.58, 3.2), (.83, -.8), (1, 0)))
    elif clip == 'look':
        p.update(gaze=track(t, (0, 0), (.18, -3.4), (.33, -3.2), (.61, 3.4), (.78, 3.1), (1, 0)),
                 lean=track(t, (0, 0), (.23, -5), (.36, -5), (.65, 5), (.81, 4.2), (1, 0)),
                 lid=track(t, (0, 0), (.39, 0), (.45, .82), (.52, 0), (1, 0)),
                 smile=track(t, (0, 0), (.27, .28), (.49, 0), (.72, .43), (1, 0)),
                 ear_l=track(t, (0, 0), (.29, -5), (.44, -3), (.70, 5), (.84, 1), (1, 0)),
                 ear_r=track(t, (0, 0), (.33, -4), (.45, -1), (.73, 6), (.87, 1), (1, 0)))
    elif clip == 'hop':
        if .20 <= t <= .68:
            u = (t - .20) / .48
            p['lift'] = 12.5 * 4 * u * (1 - u)
        p.update(squash=track(t, (0, 0), (.16, .14), (.29, -.11), (.47, -.02), (.62, -.07), (.73, .16), (.87, -.035), (1, 0)),
                 lean=track(t, (0, 0), (.17, -2.0), (.42, 2.5), (.74, -1.0), (1, 0)),
                 foot_l=track(t, (0, 0), (.22, 0), (.42, 4.5), (.67, 0), (1, 0)),
                 foot_r=track(t, (0, 0), (.24, 0), (.46, 5.3), (.68, 0), (1, 0)),
                 lid=track(t, (0, 0), (.16, .45), (.28, .08), (.46, .48), (.64, .06), (.75, .62), (1, 0)),
                 smile=track(t, (0, 0), (.17, .36), (.40, .94), (.59, .81), (.80, .36), (1, 0)),
                 ear_l=track(t, (0, 0), (.17, 2), (.34, -7), (.53, -5), (.75, 7), (.88, -2), (1, 0)),
                 ear_r=track(t, (0, 0), (.20, -2), (.38, 8), (.57, 5), (.79, -9), (.91, 2.5), (1, 0)))
    elif clip == 'code':
        p.update(nod=track(t, (0, 0), (.23, 1.6), (.50, 0), (.74, 1.9), (1, 0)),
                 gaze=track(t, (0, 0), (.36, -1.4), (.71, 1.0), (1, 0)),
                 lid=track(t, (0, 0), (.70, 0), (.78, .9), (.87, 0), (1, 0)),
                 smile=track(t, (0, 0), (.48, .35), (1, 0)),
                 paw_l=track(t, (0, 0), (.23, 2.7), (.42, 0), (.72, 2.2), (1, 0)),
                 paw_r=track(t, (0, 0), (.11, 2.3), (.33, 0), (.53, 2.7), (.81, 0), (1, 0)),
                 ear_l=track(t, (0, 0), (.33, -2.8), (.56, .9), (.82, -2.3), (1, 0)),
                 ear_r=track(t, (0, 0), (.40, 2.5), (.65, -.8), (.88, 2.8), (1, 0)))
    elif clip == 'search':
        p.update(gaze=track(t, (0, 0), (.23, 3.4), (.55, 2.8), (.68, 1.3), (.83, 1.9), (1, 0)),
                 lean=track(t, (0, 0), (.28, 4.2), (.61, 2.3), (.80, 3.1), (1, 0)),
                 lid=track(t, (0, 0), (.28, .25), (.58, .24), (.67, .85), (.77, .04), (1, 0)),
                 smile=track(t, (0, 0), (.39, .35), (.79, .48), (1, 0)),
                 prop=track(t, (0, 0), (.20, -3.0), (.48, -4.0), (.72, 1.0), (1, 0)),
                 ear_l=track(t, (0, 0), (.35, 3.3), (.66, -.8), (.88, 1.5), (1, 0)),
                 ear_r=track(t, (0, 0), (.41, 5.3), (.68, -1.8), (.91, 2.1), (1, 0)))
    return p


def rotate(x, y, cx, cy, degrees):
    angle = math.radians(degrees)
    dx, dy = x - cx, y - cy
    return cx + math.cos(angle)*dx - math.sin(angle)*dy, cy + math.sin(angle)*dx + math.cos(angle)*dy


def render(clip, t):
    p = pose(clip, t)
    image = Image.new('RGBA', (112*SAMPLE, 112*SAMPLE))
    shadow = Image.new('RGBA', image.size)
    width = 27 - .57 * p['lift']
    ImageDraw.Draw(shadow).ellipse(tuple(round(v*SAMPLE) for v in (56-width, 93, 56+width, 99)),
                                   fill=(76, 66, 96, round(52 - p['lift']*1.9)))
    image.alpha_composite(shadow.filter(ImageFilter.GaussianBlur(1.7*SAMPLE)))
    draw = ImageDraw.Draw(image)

    def ground(x, y):
        return 56 + (x-56)*(1+p['squash']*.42), 94 + (y-94)*(1-p['squash']) - p['lift']

    def head(x, y):
        x, y = rotate(x, y, 56, 74, p['lean'])
        return ground(x, y+p['nod'])

    def ear_left(x, y):
        return head(*rotate(x, y, 40, 51, p['ear_l']))

    def ear_right(x, y):
        return head(*rotate(x, y, 70, 51, p['ear_r']))

    def path(start, curves, fill=None, outline=None, width=1, move=ground):
        points = [start]
        x, y = start
        for a, b, c, d, e, f in curves:
            for i in range(1, 25):
                v = i/24
                u = 1-v
                points.append((u**3*x+3*u*u*v*a+3*u*v*v*c+v**3*e,
                               u**3*y+3*u*u*v*b+3*u*v*v*d+v**3*f))
            x, y = e, f
        polygon(points, fill, outline, width, move)

    def polygon(points, fill, outline, width, move):
        # Scale around the floor line so stretched ears have room at the jump's apex.
        pixels = [(round((56 + (a-56)*.90)*SAMPLE), round((96 + (b-96)*.90)*SAMPLE))
                  for a, b in (move(x, y) for x, y in points)]
        if fill:
            draw.polygon(pixels, fill=fill)
        if outline:
            draw.line(pixels, fill=outline, width=round(width*SAMPLE), joint='curve')
            radius = width*SAMPLE/2
            for x, y in (pixels[0], pixels[-1]):
                draw.ellipse((x-radius, y-radius, x+radius, y+radius), fill=outline)

    def ellipse(bounds, fill, move=ground):
        l, t, r, b = bounds
        points = [((l+r+(r-l)*math.cos(a))/2, (t+b+(b-t)*math.sin(a))/2)
                  for a in (i*math.tau/48 for i in range(48))]
        polygon(points, fill, None, 0, move)

    path((35,55), [(29,45,24,23,32,16),(40,8,49,26,47,47),(46,54,42,57,35,55)], EAR_OUTER, EAR_OUTLINE, 1.6, ear_left)
    path((36,46), [(32,37,30,23,35,22),(41,21,44,37,42,49),(40,50,38,48,36,46)], EAR_INNER, move=ear_left)
    path((63,48), [(65,35,69,19,82,19),(92,19,94,28,89,35),(84,41,82,52,74,57),(68,56,64,52,63,48)], EAR_OUTER, EAR_OUTLINE, 1.6, ear_right)
    path((71,48), [(73,42,76,31,81,28),(86,25,88,28,85,32),(80,37,78,49,73,51),(71,51,70,50,71,48)], EAR_INNER, move=ear_right)
    path((33,69), [(32,62,35,59,43,58),(55,54,70,57,77,66),(88,80,82,93,69,94),(54,97,29,94,28,86),(25,80,28,73,33,69)], '#DCC5EB', '#847087', 1.6)
    ellipse((43,71,70,92), '#FFF1E6')
    for left, right, rise in [(27,47,p['foot_l']), (64,85,p['foot_r'])]:
        ellipse((left,82-rise,right,94-rise), '#F5E2F4')
    path((23,65), [(20,52,31,42,48,40),(63,37,83,42,88,53),(95,68,85,81,67,83),(48,88,25,82,23,65)], '#FFF4E9', '#7C6880', 1.6, head)
    path((30,55), [(34,48,46,44,55,44),(62,44,66,46,65,48),(64,49,57,47,48,49),(39,50,35,54,30,55)], '#FFFEF7', move=head)
    smile = p['smile']
    cheeks = (246, round(202 - smile*9), round(210 - smile*5))
    ellipse((31,65-smile,45,72), cheeks, head)
    ellipse((68,65-smile,82,72), cheeks, head)
    half = 5 - 4.6*p['lid']
    for origin in (43,68):
        x = origin + p['gaze']*(1-p['lid']*.38)
        y = 60 + p['lid']*.8
        # The curve starts nearly round and narrows to an eyelid, keeping the same center.
        arch = p['lid'] * (1.1 - 3.2*smile)
        path((x-3.4,y), [(x-3.4,y-half+arch,x+3.4,y-half+arch,x+3.4,y),
                         (x+3.4,y+half+arch,x-3.4,y+half+arch,x-3.4,y)],
             INK, INK, .9+p['lid']*.55, head)
        if half > 1.3:
            glint = min(1, (half-1.3)/2.5)
            ellipse((x-1.65,y-half*.64,x-1.65+2.2*glint,y-half*.64+2.5*glint), '#FFFFFF', head)
    path((53,65), [(54,63.5,58,63.5,59,65),(58,67,54,67,53,65)], '#B67890', move=head)
    path((51+2*smile,68), [(53,71,55,71,56,68+smile),(58,71,60,71,62-2*smile,68)], outline=INK, width=1.15, move=head)
    if smile > .34:
        ellipse((54,69,58,69+(smile-.34)*6.8), '#AD6D89', head)
    if clip == 'code':
        path((35,77), [(41,75,49,78,56,78),(63,78,71,75,77,77),(76,82,73,87,71,91),(60,94,48,94,40,91),(36,87,34,81,35,77)], '#8F91C4', '#665883', 1.3)
        path((39,79), [(48,80,57,82,73,79)], outline='#DEDCF6', width=1.3)
        ellipse((53,84,60,88), '#FFF0D8')
        ellipse((38,76-p['paw_l'],45,81-p['paw_l']), '#FFF1E6')
        ellipse((67,76-p['paw_r'],74,81-p['paw_r']), '#FFF1E6')
    if clip == 'search':
        def glass(x, y):
            x, y = rotate(x, y, 81, 74, p['prop']*2)
            return ground(x+p['prop']*.25, y+p['prop'])
        path((81,74), [(86,69,90,64,94,60)], outline='#665883', width=4, move=glass)
        ellipse((86,47,102,63), '#665883', glass)
        ellipse((89,50,99,60), '#D9EBFA', glass)
        ellipse((91,51,95,54), '#FFFFFF', glass)
    return image.resize((TILE,TILE), Image.Resampling.LANCZOS)


def write_asset(name, image):
    directory = ASSETS / f'DeskRabbit-{name}.imageset'
    directory.mkdir(exist_ok=True)
    image.save(directory / 'sprite.png', optimize=True)
    contents = {'images': [{'filename': 'sprite.png', 'idiom': 'universal'}],
                'info': {'author': 'xcode', 'version': 1}}
    (directory / 'Contents.json').write_text(json.dumps(contents, indent=2)+'\n', encoding='utf-8')


def draw_preview(image):
    canvas = Image.new('RGB', (350,300), '#EAEDFE')
    ImageDraw.Draw(canvas).rounded_rectangle((29,21,321,279), radius=36, fill='#F8F8FF')
    image = image.resize((230,230), Image.Resampling.LANCZOS)
    canvas.paste(image, (60,34), image)
    return canvas


def save_gif(pictures, delays, output):
    # Reserve the original ear colors in a palette shared by all frames.
    width, height = pictures[0].size
    columns = 12
    sample = Image.new('RGB', (columns*width, math.ceil(len(pictures)/columns)*height), '#EAEDFE')
    for i, picture in enumerate(pictures):
        sample.paste(picture, ((i%columns)*width, (i//columns)*height))
    colors = sample.quantize(colors=253).getpalette()[:253*3]
    ear_colors = [component for color in (EAR_OUTER, EAR_INNER, EAR_OUTLINE)
                  for component in ImageColor.getrgb(color)]
    palette = Image.new('P', (1, 1))
    palette.putpalette(ear_colors + colors)
    indexed = []
    for picture in pictures:
        frame = picture.quantize(palette=palette, dither=Image.Dither.NONE)
        channels = picture.split()
        for index, color in enumerate((EAR_OUTER, EAR_INNER, EAR_OUTLINE)):
            red, green, blue = (channel.point([255 if value == target else 0 for value in range(256)])
                                for channel, target in zip(channels, ImageColor.getrgb(color)))
            mask = ImageChops.multiply(ImageChops.multiply(red, green), blue)
            # The quantizer may map exact matches to a nearby palette entry.
            frame.paste(index, mask=mask)
        indexed.append(frame)
    indexed[0].save(output, save_all=True, append_images=indexed[1:], duration=delays,
                    loop=0, disposal=1, optimize=False)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--preview', type=Path)
    parser.add_argument('--still-preview', type=Path)
    args = parser.parse_args()
    frames = {name: [render(name, i/(count-1)) for i in range(count)] for name, count in CLIPS.items()}
    # The rest image is also the first and last frame of every idle clip.
    neutral = render('rest', 0)
    write_asset('rest', neutral)
    for name in ('hop', 'code', 'search'):
        write_asset(name, frames[name][len(frames[name])//2])
    # Refresh the original standalone poses from the same color palette.
    write_asset('blink', render('blink', .35))
    write_asset('left', render('look', .27))
    write_asset('right', render('look', .72))
    if args.still_preview:
        draw_preview(neutral).save(args.still_preview)
    for name, sequence in frames.items():
        columns = math.ceil(math.sqrt(len(sequence)))
        rows = math.ceil(len(sequence)/columns)
        sheet = Image.new('RGBA', (columns*TILE, rows*TILE))
        for i, frame in enumerate(sequence):
            sheet.paste(frame, ((i%columns)*TILE, (i//columns)*TILE))
        write_asset(f'motion-{name}', sheet)
    if args.preview:
        pictures, delays = [], []
        plan = [('rest', 700), ('blink', None), ('rest', 440), ('look', None), ('rest', 510),
                ('hop', None), ('rest', 560), ('code', None), ('rest', 340), ('search', None), ('rest', 560)]
        for name, delay in plan:
            if delay is None:
                pictures.extend(map(draw_preview, frames[name]))
                delays.extend(round((i+1)*100/FPS)*10-round(i*100/FPS)*10 for i in range(len(frames[name])))
            else:
                pictures.append(draw_preview(neutral))
                delays.append(delay)
        save_gif(pictures, delays, args.preview)


if __name__ == '__main__':
    main()
