"""Subset OFL Noto Sans SC into renamed JidiuSans; requires fonttools.

Source: https://github.com/notofonts/noto-cjk/tree/main/Sans/SubsetOTF/SC
Usage: python tools/subset_font.py path/to/NotoSansSC-Regular.otf
Keeps GB2312, app text, Latin and punctuation. License: assets/fonts/OFL.txt.
"""
from pathlib import Path
import sys
from fontTools import subset
from fontTools.ttLib import TTFont

root = Path(__file__).resolve().parents[1]
characters = set(chr(i) for i in range(32, 127))
for lead in range(0xA1, 0xF8):
    for trail in range(0xA1, 0xFF):
        try:
            characters.update(bytes([lead, trail]).decode('gb2312'))
        except UnicodeDecodeError:
            pass
for source in (root / 'lib').rglob('*.dart'):
    characters.update(source.read_text(encoding='utf-8'))
characters.update(chr(i) for i in range(0x2000, 0x2070))
font = TTFont(sys.argv[1])
options = subset.Options()
options.name_IDs = ['*']
options.name_legacy = True
options.name_languages = ['*']
subsetter = subset.Subsetter(options=options)
subsetter.populate(unicodes=[ord(c) for c in characters])
subsetter.subset(font)
names = {1: 'JidiuSans', 2: 'Regular', 3: 'JidiuSans Regular 1.0',
         4: 'JidiuSans Regular', 6: 'JidiuSans-Regular', 16: 'JidiuSans', 17: 'Regular'}
for record in font['name'].names:
    if record.nameID in names:
        record.string = names[record.nameID].encode(record.getEncoding())
destination = root / 'assets/fonts/JidiuSans-Regular.otf'
font.save(destination)
print(f'{destination}: {destination.stat().st_size} bytes')
