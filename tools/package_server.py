"""Package only the explicit deploy files, without node_modules or credentials."""
from pathlib import Path
from zipfile import ZipFile, ZIP_DEFLATED
import argparse

parser = argparse.ArgumentParser()
parser.add_argument("--web", action="store_true", help="Include the built Flutter website")
args = parser.parse_args()

root = Path(__file__).resolve().parents[1]
output = root / "build" / "deploy" / ("jidiu-qishi-web-1panel.zip" if args.web else "jidiu-gomuku-1panel.zip")
web = root / "build" / "web"
if args.web and not (web / "index.html").is_file():
    parser.error("Run flutter build web --release --no-web-resources-cdn first")
output.parent.mkdir(parents=True, exist_ok=True)
files = ["index.js", "game_rules.js", "game_rules.test.js", "package.json",
         "package-lock.json", "Dockerfile", ".dockerignore", "compose.1panel.yaml",
         "DEPLOY_1PANEL.md"]
with ZipFile(output, "w", compression=ZIP_DEFLATED) as archive:
    for name in files:
        source = "Dockerfile.web" if args.web and name == "Dockerfile" else name
        archive.write(root / "server" / source, arcname="server/" + name)
    if args.web:
        archive.write(root / "server" / "DEPLOY_WEB_1PANEL.md", arcname="server/DEPLOY_WEB_1PANEL.md")
        for source in sorted(web.rglob("*")):
            if source.is_file():
                archive.write(source, arcname="server/web/" + source.relative_to(web).as_posix())
print(output)
