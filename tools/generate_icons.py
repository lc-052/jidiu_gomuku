from pathlib import Path
from PIL import Image
root=Path(__file__).resolve().parents[1]
image=Image.open(root/'assets/icon/app_icon.png').convert('RGB')
image.resize((192,192),Image.Resampling.LANCZOS).save(root/'assets/icon/app_logo.png',optimize=True)
for base in ['android/app/src/main/res','ios/Runner/Assets.xcassets/AppIcon.appiconset','macos/Runner/Assets.xcassets/AppIcon.appiconset','web']:
    for p in (root/base).rglob('*.png'):
        if p.name.startswith(('ic_launcher','Icon-','app_icon')) or p.name=='favicon.png':
            with Image.open(p) as old: size=old.size
            canvas=Image.new('RGB',size,'#fffdf3')
            ratio=.68 if 'foreground' in p.name else .8 if 'maskable' in p.name else 1
            art=image.resize((round(size[0]*ratio),round(size[1]*ratio)),Image.Resampling.LANCZOS)
            canvas.paste(art,((size[0]-art.width)//2,(size[1]-art.height)//2))
            canvas.save(p)
image.resize((256,256),Image.Resampling.LANCZOS).save(root/'windows/runner/resources/app_icon.ico',sizes=[(16,16),(32,32),(48,48),(64,64),(128,128),(256,256)])
foreground=Image.new('RGB',(1024,1024),'#fffdf3')
art=image.resize((696,696),Image.Resampling.LANCZOS)
foreground.paste(art,(164,164));foreground.save(root/'assets/icon/app_icon_fg.png')
