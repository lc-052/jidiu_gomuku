"""Package only the explicit deploy files, without node_modules or credentials."""
from pathlib import Path
from zipfile import ZipFile, ZIP_DEFLATED
import argparse
import subprocess

parser = argparse.ArgumentParser()
parser.add_argument("--web", action="store_true", help="Include the built Flutter website")
parser.add_argument("--web-dir", type=Path, help="Use a separately built Flutter website directory")
parser.add_argument("--output", type=Path, help="Write the archive to a versioned release path")
args = parser.parse_args()

root = Path(__file__).resolve().parents[1]
output = args.output.resolve() if args.output else root / "build" / "deploy" / ("jidiu-qishi-web-1panel.zip" if args.web else "jidiu-gomuku-1panel.zip")
web = args.web_dir.resolve() if args.web_dir else root / "build" / "web"
if args.web and not (web / "index.html").is_file():
    parser.error("Run flutter build web --release --no-web-resources-cdn first")
if args.web:
    subprocess.run(["node", str(root / "server" / "prepare_web.js"), str(web)], check=True)
output.parent.mkdir(parents=True, exist_ok=True)
files = ["index.js", "game_rules.js", "game_rules.test.js", "web_assets.js", "web_assets.test.js", "prepare_web.js", "package.json",
         "package-lock.json", "Dockerfile", ".dockerignore", "compose.1panel.yaml",
         "DEPLOY_1PANEL.md"]
with ZipFile(output, "w", compression=ZIP_DEFLATED) as archive:
    for name in files:
        source = "Dockerfile.web" if args.web and name == "Dockerfile" else name
        archive.write(root / "server" / source, arcname="server/" + name)
    if args.web:
        archive.write(root / "server" / "DEPLOY_WEB_1PANEL.md", arcname="server/DEPLOY_WEB_1PANEL.md")
        for source in sorted(web.rglob("*")):
            # Docker regenerates sidecars; do not triple the upload archive size.
            if source.is_file() and source.suffix not in {".gz", ".br"}:
                archive.write(source, arcname="server/web/" + source.relative_to(web).as_posix())
print(output)
