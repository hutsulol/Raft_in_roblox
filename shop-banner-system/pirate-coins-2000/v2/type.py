"""Create portable vector lettering from the bundled OFL Nunito font."""
import json
from pathlib import Path
from fontTools.ttLib import TTFont
from fontTools.varLib.instancer import instantiateVariableFont
from fontTools.pens.svgPathPen import SVGPathPen

root = Path(__file__).resolve().parent
font = instantiateVariableFont(TTFont(root / 'Nunito.ttf'), {'wght': 900})
glyphs = font.getGlyphSet()
cmap = font.getBestCmap()
upm = font['head'].unitsPerEm
items = [
    ('title', 'Мешок Pirate', 321, 101, 35, 360, '#FFFFFF'),
    ('offer', 'ВЫГОДНЫЙ НАБОР', 324, 463, 34, 410, '#FFFFFF'),
    ('amount', '2 000', 324, 388, 43, 280, '#8A4B10'),
    ('price', '100', 823, 541, 47, 175, '#FFFFFF'),
]
result = []
for key, text, cx, baseline, size, maximum, color in items:
    names = [cmap[ord(ch)] for ch in text]
    advances = [font['hmtx'][n][0] for n in names]
    scale = min(size / upm, maximum / sum(advances))
    x = cx - sum(advances) * scale / 2
    paths = []
    for name, advance in zip(names, advances):
        pen = SVGPathPen(glyphs)
        glyphs[name].draw(pen)
        paths.append(f'<path transform="translate({x:.3f},{baseline}) scale({scale:.6f},-{scale:.6f})" d="{pen.getCommands()}"/>')
        x += advance * scale
    drawing = ''.join(paths)
    shadow = f'<g fill="#75420D" opacity=".2" transform="translate(0,2)">{drawing}</g>'
    result.append({'key':key,'text':text,'font':'Nunito Black','size':size,'width':sum(advances)*scale,'svg':shadow+f'<g fill="{color}">{drawing}</g>'})
(root / 'lettering.json').write_text(json.dumps(result, ensure_ascii=False), encoding='utf-8')
print('Vector lettering generated with measured widths.')
