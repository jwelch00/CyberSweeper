#!/usr/bin/env python3
"""Builds the CyberSweeper downloads. Works on Windows, macOS and Linux.

    python tools/build.py --install-templates   # once: Godot's export templates
    python tools/build.py                       # all three, into dist/
    python tools/build.py --only windows,linux

Writes dist/CyberSweeper-windows.zip, CyberSweeper-macos.zip,
CyberSweeper-linux.tar.gz, SHA256SUMS (for `sha256sum -c`) and index.html,
the download page (site/index.html with everything inline and this release's
sizes and checksums; --page-only rewrites just the page). Each archive
holds one CyberSweeper/ folder: the game, README.txt and LICENSES/ (the font
licenses and Godot's, which must travel with the game).

Every build is checked before it's reported done: what went into the game
data (no tests/, sim/ or dev/), each archive's layout and executable bits, the
Mac app's signature and Info.plist, the Windows icon and version, and, on a
Linux host, a headless test launch of the Linux build.

Godot is found like tools/run_tests.py finds it. The export templates must
match its exact version; --install-templates downloads Godot's official
template file from its GitHub release (1.3 GB), checks it against the SHA-512
list published with that release, and keeps only the templates used here.
--templates-file FILE installs from a .tpz you already downloaded. This is the
only part of CyberSweeper that goes online; the game makes no network calls.
"""
from __future__ import annotations

import argparse
import base64
import hashlib
import html
import json
import io
import os
import platform
import plistlib
import re
import shutil
import stat
import subprocess
import sys
import tarfile
import tempfile
import time
import urllib.request
import zipfile
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import run_tests as rt  # noqa: E402

ROOT = rt.ROOT
GAME = rt.GAME
BUILD = ROOT / "build"   # raw exports (gitignored)
DIST = ROOT / "dist"
NAME = "CyberSweeper"
# The downloads and this public repo name no person, account or server.
BUNDLE_ID = "com.cybersweeper.game"
GODOT_RELEASES = "https://github.com/godotengine/godot/releases/download"

# Each target: its preset in game/export_presets.cfg, the file Godot writes,
# and the archive it becomes.
TARGETS = {
    "windows": {"preset": "Windows", "file": f"{NAME}.exe", "archive": f"{NAME}-windows.zip"},
    "macos": {"preset": "macOS", "file": f"{NAME}.zip", "archive": f"{NAME}-macos.zip"},
    "linux": {"preset": "Linux", "file": f"{NAME}.x86_64", "archive": f"{NAME}-linux.tar.gz"},
}
# The templates those presets need, from the .tpz's templates/ folder.
TEMPLATES = ["version.txt", "windows_release_x86_64.exe", "macos.zip", "linux_release.x86_64"]
FONT_LICENSES = ["OFL-ChakraPetch.txt", "OFL-MartianMono.txt", "OFL-NotoSansCJK.txt"]
# Never in a download: tests, the simulator, dev-only tools (screenshots).
FORBIDDEN = ("tests/", "sim/", "dev/")
# Must be in the game data (paths as the exported pack lists them).
REQUIRED = ["project.binary", "data/rivals.json", "data/bots.json", "data/unlocks.json", "data/tuning.json",
            "assets/tokens/palettes.json"]


def fail(msg: str) -> None:
    sys.exit("build failed: " + msg)


def step(msg: str) -> None:
    print("== " + msg, flush=True)


# --- Godot and its templates --------------------------------------------------------

def godot_version(godot: str) -> tuple[str, str]:
    """('4.7.2.stable', '4.7.2-stable'): the template folder name and the release tag."""
    out = subprocess.run([godot, "--version"], capture_output=True, text=True).stdout.strip().splitlines()
    m = re.match(r"(\d+\.\d+(?:\.\d+)?)\.([a-z]+\d*)", out[-1] if out else "")
    if not m:
        fail(f"can't read the Godot version from {godot}")
    return f"{m[1]}.{m[2]}", f"{m[1]}-{m[2]}"


def templates_dir(godot: str, folder: str) -> Path:
    # Where the Godot editor itself looks (and installs from its export
    # templates manager). A self-contained editor (a ._sc_ or _sc_ file next
    # to it) keeps them in editor_data/ beside it instead.
    exe = Path(godot).resolve()
    if (exe.parent / "._sc_").exists() or (exe.parent / "_sc_").exists():
        return exe.parent / "editor_data" / "export_templates" / folder
    system = platform.system()
    if system == "Windows":
        base = Path(os.environ["APPDATA"]) / "Godot"
    elif system == "Darwin":
        base = Path.home() / "Library" / "Application Support" / "Godot"
    else:
        base = Path(os.environ.get("XDG_DATA_HOME") or Path.home() / ".local" / "share") / "godot"
    return base / "export_templates" / folder


def missing_templates(tdir: Path) -> list[str]:
    return [t for t in TEMPLATES if not (tdir / t).is_file()]


def published_sha512(tag: str, filename: str) -> str:
    url = f"{GODOT_RELEASES}/{tag}/SHA512-SUMS.txt"
    with urllib.request.urlopen(url, timeout=60) as r:
        for line in r.read().decode().splitlines():
            parts = line.split()
            if len(parts) == 2 and parts[1] == filename:
                return parts[0].lower()
    fail(f"{filename} isn't in Godot's checksum list ({url})")
    return ""


def sha512_of(path: Path) -> str:
    h = hashlib.sha512()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


def download(url: str, dest: Path) -> None:
    with urllib.request.urlopen(url, timeout=60) as r, open(dest, "wb") as f:
        total = int(r.headers.get("Content-Length") or 0)
        done, shown = 0, -10
        for chunk in iter(lambda: r.read(1 << 20), b""):
            f.write(chunk)
            done += len(chunk)
            pct = done * 100 // total if total else 0
            if pct >= shown + 10:
                print(f"  {pct}% of {total / 1e9:.2f} GB", flush=True)
                shown = pct


def install_templates(godot: str, from_file: str | None) -> None:
    folder, tag = godot_version(godot)
    tdir = templates_dir(godot, folder)
    filename = f"Godot_v{tag}_export_templates.tpz"
    step(f"installing Godot {tag} export templates into {tdir}")
    want = published_sha512(tag, filename)
    tmp: Path | None = None
    if from_file:
        tpz = Path(from_file)
    else:
        BUILD.mkdir(exist_ok=True)
        tmp = BUILD / filename
        print(f"  downloading {filename} from Godot's GitHub release")
        download(f"{GODOT_RELEASES}/{tag}/{filename}", tmp)
        tpz = tmp
    try:
        if sha512_of(tpz) != want:
            fail(f"{tpz.name} doesn't match the SHA-512 Godot published for it; not installing")
        print("  SHA-512 matches Godot's published checksum")
        tdir.mkdir(parents=True, exist_ok=True)
        with zipfile.ZipFile(tpz) as z:
            for t in TEMPLATES:
                with z.open("templates/" + t) as src, open(tdir / t, "wb") as dst:
                    shutil.copyfileobj(src, dst)
                if not t.endswith(".txt"):
                    os.chmod(tdir / t, 0o755)
                print(f"  {t}")
        if (tdir / "version.txt").read_text().strip() != folder:
            fail(f"the templates are for Godot {(tdir / 'version.txt').read_text().strip()}, not {folder}")
    finally:
        if tmp is not None and tmp.exists():
            tmp.unlink()


# --- exporting --------------------------------------------------------------------

def godot_ok(code: int, out: str, what: str) -> None:
    errors = [l for l in out.splitlines() if l.lstrip().startswith("ERROR") or any(m in l for m in rt.ERROR_MARKERS)]
    if code != 0 or errors:
        print(out[-4000:])
        fail(f"{what} (exit {code})")


def export(godot: str, target: str) -> Path:
    t = TARGETS[target]
    out_dir = BUILD / target
    if out_dir.exists():
        shutil.rmtree(out_dir)
    out_dir.mkdir(parents=True)
    out = out_dir / t["file"]
    code, log = rt.run_godot(godot, ["--export-release", t["preset"], str(out)], 1200)
    godot_ok(code, log, f"exporting {t['preset']}")
    if not out.is_file():
        fail(f"Godot didn't write {out}")
    return out_dir


def pack_listing(godot: str) -> list[str]:
    """The game data's file list, from exporting it on its own as a zip."""
    out = BUILD / "pack-check.zip"
    out.parent.mkdir(exist_ok=True)
    code, log = rt.run_godot(godot, ["--export-pack", TARGETS["linux"]["preset"], str(out)], 600)
    godot_ok(code, log, "exporting the game data for checking")
    with zipfile.ZipFile(out) as z:
        names = z.namelist()
    out.unlink()
    return names


def godot_licenses(godot: str) -> str:
    out = BUILD / "Godot.txt"
    code, log = rt.run_godot(godot, ["-s", "res://dev/licenses.gd", "--", "--out", str(out)], 120)
    godot_ok(code, log, "writing Godot's license notices")
    return out.read_text(encoding="utf-8")


# --- the archive contents -----------------------------------------------------------

def version() -> str:
    m = re.search(r'config/version="([^"]+)"', (GAME / "project.godot").read_text(encoding="utf-8"))
    if not m:
        fail("no config/version in game/project.godot")
    return m[1]


def readme(target: str, ver: str) -> str:
    start = {
        "windows": [
            "Double-click CyberSweeper.exe.",
            "",
            "The game isn't signed, so Windows SmartScreen may say it protected your",
            "PC. Click \"More info\", then \"Run anyway\". You only need to do this once.",
        ],
        "macos": [
            "Double-click CyberSweeper.app (you can move it to Applications first).",
            "It needs macOS 11 or later on Intel Macs, 13 or later on Apple silicon.",
            "",
            "The game isn't notarized by Apple, so the first launch is blocked. On",
            "macOS 15 or later, open System Settings > Privacy & Security, scroll",
            "down and click \"Open Anyway\". On older versions, right-click the app,",
            "choose Open, then Open again. You only need to do this once.",
        ],
        "linux": [
            "Run ./CyberSweeper.x86_64 from this folder (or double-click it).",
            "",
            "If it won't start, make it executable first:",
            "    chmod +x CyberSweeper.x86_64",
        ],
    }[target]
    saves = {
        "windows": r"%APPDATA%\CyberSweeper",
        "macos": "~/Library/Application Support/CyberSweeper",
        "linux": "~/.local/share/CyberSweeper",
    }[target]
    lines = [
        f"CyberSweeper {ver}",
        "Infinite Minesweeper. Three links. Never a coin flip.",
        "",
        "STARTING IT",
        *start,
        "",
        "YOUR SAVES",
        f"Settings, unlocks and leaderboards are kept in {saves}.",
        "Delete that folder to start over.",
        "",
        "The game never goes online: no accounts, no telemetry, no update checks.",
        "",
        "Licenses for the fonts and the Godot Engine are in the LICENSES folder.",
        "",
    ]
    return ("\r\n" if target == "windows" else "\n").join(lines)


def extras(target: str, ver: str, godot_text: str) -> dict[str, bytes]:
    """README.txt and LICENSES/, keyed by their path inside CyberSweeper/."""
    files = {"README.txt": readme(target, ver).encode("utf-8"),
             "LICENSES/Godot.txt": godot_text.encode("utf-8")}
    for f in FONT_LICENSES:
        files["LICENSES/" + f] = (GAME / "assets" / "fonts" / f).read_bytes()
    return files


FILE_MODE = 0o644
EXEC_MODE = 0o755


def _zip_info(name: str, mode: int) -> zipfile.ZipInfo:
    zi = zipfile.ZipInfo(name, time.localtime()[:6])
    zi.create_system = 3   # unix, so unzip and Archive Utility keep the mode
    zi.external_attr = ((stat.S_IFDIR if name.endswith("/") else stat.S_IFREG) | mode) << 16
    zi.compress_type = zipfile.ZIP_DEFLATED
    return zi


def pack_windows(exported: Path, files: dict[str, bytes], dest: Path) -> None:
    with zipfile.ZipFile(dest, "w") as z:
        for p in sorted(exported.iterdir()):
            z.writestr(_zip_info(f"{NAME}/{p.name}", EXEC_MODE if p.suffix == ".exe" else FILE_MODE), p.read_bytes())
        for name, data in files.items():
            z.writestr(_zip_info(f"{NAME}/{name}", FILE_MODE), data)


def pack_macos(exported: Path, files: dict[str, bytes], dest: Path) -> None:
    # Godot writes the signed CyberSweeper.app into a zip with its modes set;
    # copy those entries as they are, under CyberSweeper/, and add the extras.
    with zipfile.ZipFile(exported / TARGETS["macos"]["file"]) as src, zipfile.ZipFile(dest, "w") as z:
        for zi in src.infolist():
            data = src.read(zi)
            zi.filename = f"{NAME}/{zi.filename}"
            z.writestr(zi, data, compress_type=zipfile.ZIP_DEFLATED)
        for name, data in files.items():
            z.writestr(_zip_info(f"{NAME}/{name}", FILE_MODE), data)


def pack_linux(exported: Path, files: dict[str, bytes], dest: Path) -> None:
    def info(name: str, size: int, mode: int, kind=tarfile.REGTYPE) -> tarfile.TarInfo:
        ti = tarfile.TarInfo(name)
        ti.size, ti.mode, ti.type, ti.mtime = size, mode, kind, int(time.time())
        ti.uid = ti.gid = 0
        ti.uname = ti.gname = ""
        return ti
    with tarfile.open(dest, "w:gz") as tar:
        for d in (NAME, f"{NAME}/LICENSES"):
            tar.addfile(info(d, 0, EXEC_MODE, tarfile.DIRTYPE))
        binary = exported / TARGETS["linux"]["file"]
        with open(binary, "rb") as f:
            tar.addfile(info(f"{NAME}/{binary.name}", binary.stat().st_size, EXEC_MODE), f)
        for name, data in files.items():
            tar.addfile(info(f"{NAME}/{name}", len(data), FILE_MODE), io.BytesIO(data))


PACK = {"windows": pack_windows, "macos": pack_macos, "linux": pack_linux}


# --- checks -----------------------------------------------------------------------

def check_pack(names: list[str]) -> None:
    bad = [n for n in names if n.startswith(FORBIDDEN)]
    if bad:
        fail("the game data includes files that must stay out: " + ", ".join(bad[:8]))
    missing = [n for n in REQUIRED if n not in names]
    if missing:
        fail("the game data is missing " + ", ".join(missing))
    print(f"  game data: {len(names)} files, no tests/, sim/ or dev/")


def _check_extras(names: set[str]) -> None:
    for n in ["README.txt", "LICENSES/Godot.txt"] + ["LICENSES/" + f for f in FONT_LICENSES]:
        if f"{NAME}/{n}" not in names:
            fail(f"{n} is missing from the archive")


def check_windows(archive: Path, ver: str) -> None:
    with zipfile.ZipFile(archive) as z:
        names = set(z.namelist())
        _check_extras(names)
        exe = z.read(f"{NAME}/{NAME}.exe")
    if exe[:2] != b"MZ":
        fail("CyberSweeper.exe isn't a Windows program")
    # Godot copies each image of the .ico into the exe's icon resources.
    ico = (GAME / "assets" / "icon" / "icon.ico").read_bytes()
    count = int.from_bytes(ico[4:6], "little")
    for i in range(count):
        e = ico[6 + 16 * i: 22 + 16 * i]
        size, off = int.from_bytes(e[8:12], "little"), int.from_bytes(e[12:16], "little")
        if ico[off:off + size] not in exe:
            fail(f"icon image {i + 1} of {count} isn't in CyberSweeper.exe")
    for s in (NAME, ver):
        if s.encode("utf-16-le") not in exe:
            fail(f"CyberSweeper.exe's file properties don't say {s!r}")
    print(f"  windows: {len(names)} files; the exe carries all {count} icon sizes and version {ver}")


def check_macos(archive: Path, ver: str) -> None:
    app = f"{NAME}/{NAME}.app/Contents/"
    with zipfile.ZipFile(archive) as z:
        names = set(z.namelist())
        _check_extras(names)
        for need in ("Info.plist", f"MacOS/{NAME}", "_CodeSignature/CodeResources"):
            if app + need not in names:
                fail(f"the Mac app has no {need}")
        main = z.getinfo(app + f"MacOS/{NAME}")
        if not (main.external_attr >> 16) & 0o111:
            fail("the Mac app's program isn't executable in the zip")
        head = z.read(main)[:4]
        plist = plistlib.loads(z.read(app + "Info.plist"))
        icon = app + "Resources/" + plist.get("CFBundleIconFile", "")
        if not icon.endswith(".icns"):
            icon += ".icns"
        if icon not in names or z.read(icon) != (GAME / "assets" / "icon" / "icon.icns").read_bytes():
            fail("the Mac app's icon isn't CyberSweeper's icon.icns")
    if head != b"\xca\xfe\xba\xbe":
        fail("the Mac program isn't a universal (Intel + Apple silicon) binary")
    want = {"CFBundleIdentifier": BUNDLE_ID, "CFBundleShortVersionString": ver, "CFBundleName": NAME}
    for k, v in want.items():
        if plist.get(k) != v:
            fail(f"the Mac app's {k} is {plist.get(k)!r}, not {v!r}")
    print(f"  macos: universal, ad-hoc signed, {BUNDLE_ID} {ver}, icon in place")


def check_linux(archive: Path) -> None:
    with tarfile.open(archive) as tar:
        names = set(tar.getnames())
        _check_extras(names)
        binary = tar.getmember(f"{NAME}/{NAME}.x86_64")
        if binary.mode & 0o111 != 0o111:
            fail("the Linux binary isn't executable in the archive")
        head = tar.extractfile(binary).read(4)
    if head != b"\x7fELF":
        fail("the Linux binary isn't a Linux program")
    print("  linux: the binary is executable")


def test_launch(exported: Path) -> None:
    """Runs the Linux release build headless with dev flags: it must start and
    quit cleanly, say it's ignoring the flags, and write no screenshot. Its user
    folder (saves, Godot's log) goes in a scratch XDG_DATA_HOME, never the real
    one."""
    binary = exported / TARGETS["linux"]["file"]
    with tempfile.TemporaryDirectory() as tmp:
        shot = Path(tmp) / "shot.png"
        env = dict(os.environ, XDG_DATA_HOME=tmp)
        cmd = [str(binary), "--headless", "--quit-after", "600", "--", "--seed", "7", "--shot", str(shot)]
        try:
            p = subprocess.run(cmd, capture_output=True, text=True, timeout=120, env=env,
                               encoding="utf-8", errors="replace")
        except subprocess.TimeoutExpired:
            fail("the Linux build didn't quit within 2 minutes")
        out = p.stdout + p.stderr
        if p.returncode != 0 or any(m in out for m in rt.ERROR_MARKERS):
            print(out[-4000:])
            fail(f"the Linux build's test launch failed (exit {p.returncode})")
        if "ignoring development flags" not in out or "--seed" not in out:
            print(out[-2000:])
            fail("the release build didn't report ignoring the dev flags")
        if shot.exists():
            fail("the release build wrote a screenshot; dev flags must do nothing there")
        if not (Path(tmp) / NAME).is_dir():
            fail("the release build didn't use the CyberSweeper user folder")
    print("  linux: test launch ran 600 frames clean, ignored the dev flags, used the CyberSweeper folder")


def sha256_of(path: Path) -> str:
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


# --- the download page --------------------------------------------------------------

SITE = ROOT / "site"
DESIGN = ROOT / "design"
PAGE_MAX = 1_000_000
LABELS = {"windows": "Windows", "macos": "macOS", "linux": "Linux"}
# The fonts the page uses (cs.css also declares the Japanese subset; the page has no Japanese).
PAGE_FONTS = [f"ChakraPetch-{w}.woff2" for w in (400, 500, 600, 700)] + \
             [f"MartianMono-{w}.woff2" for w in (300, 400, 600, 800)]


def _data_uri(path: Path, mime: str) -> str:
    return f"data:{mime};base64,{base64.b64encode(path.read_bytes()).decode()}"


def _json(path: Path) -> dict:
    return json.loads(path.read_text(encoding="utf-8"))


def palette_css() -> str:
    """Signal's colors as CSS variables, from palettes.json (the way
    design/tokens/gen_palettes.py names them: tileEdge -> --tile-edge)."""
    pal = next(p for p in _json(GAME / "assets" / "tokens" / "palettes.json")["palettes"] if p["id"] == "signal")
    name = lambda k: re.sub(r"[A-Z]", lambda m: "-" + m[0].lower(), k)  # noqa: E731
    lines = [f"  --{name(k)}: {v};" for k, v in pal["colors"].items()]
    lines += [f"  --n{i + 1}: {v};" for i, v in enumerate(pal["numbers"])]
    return ":root {\n" + "\n".join(lines) + "\n}"


def design_css() -> str:
    """design/shared/cs.css with its palette import dropped (palette_css
    replaces it) and the fonts embedded."""
    css = (DESIGN / "shared" / "cs.css").read_text(encoding="utf-8")
    css = re.sub(r'@import url\("../tokens/palettes.css"\);\n?', "", css)
    css = re.sub(r'@font-face \{[^}]*NotoSansJP[^}]*\}\n?', "", css)
    for f in PAGE_FONTS:
        css = css.replace(f'url("../fonts/{f}")', f'url("{_data_uri(DESIGN / "fonts" / f, "font/woff2")}")')
    if re.search(r'url\(\s*["\']?\.\./', css):
        fail("design/shared/cs.css refers to a file the page can't embed")
    return css


def webp_size(path: Path) -> tuple[int, int]:
    d = path.read_bytes()
    if d[:4] != b"RIFF" or d[8:12] != b"WEBP":
        fail(f"{path} isn't a WebP image")
    kind = d[12:16]
    if kind == b"VP8X":
        return 1 + int.from_bytes(d[24:27], "little"), 1 + int.from_bytes(d[27:30], "little")
    if kind == b"VP8 ":
        return int.from_bytes(d[26:28], "little") & 0x3FFF, int.from_bytes(d[28:30], "little") & 0x3FFF
    if kind == b"VP8L":
        b = int.from_bytes(d[21:25], "little")
        return (b & 0x3FFF) + 1, ((b >> 14) & 0x3FFF) + 1
    fail(f"{path}: unknown WebP format")
    return 0, 0


def archive_version(path: Path) -> str:
    """The version on the first line of the README.txt inside an archive."""
    member = f"{NAME}/README.txt"
    if path.name.endswith(".tar.gz"):
        with tarfile.open(path) as tar:
            text = tar.extractfile(member).read().decode()
    else:
        with zipfile.ZipFile(path) as z:
            text = z.read(member).decode()
    return text.split()[1]


def macos_minimum(path: Path) -> str:
    with zipfile.ZipFile(path) as z:
        plist = plistlib.loads(z.read(f"{NAME}/{NAME}.app/Contents/Info.plist"))
    mins = plist.get("LSMinimumSystemVersionByArchitecture", {})
    v = lambda a: re.sub(r"\.0+$", "", mins.get(a, "?"))  # noqa: E731
    return f"macOS {v('x86_64')} or later on Intel, {v('arm64')} or later on Apple silicon"


def rivals_html() -> str:
    rivals = _json(GAME / "data" / "rivals.json")["rivals"]
    names = {p["id"]: p["name"] for p in _json(GAME / "assets" / "tokens" / "palettes.json")["palettes"]}
    prize = {rule["rival"]: names[pid] for pid, rule in _json(GAME / "data" / "unlocks.json")["palettes"].items()
             if rule and rule.get("type") == "beat_rival"}
    rows = []
    for i, r in enumerate(rivals):
        top = " top" if i == len(rivals) - 1 else ""
        won = f"Unlocks <b>{html.escape(prize[r['id']])}</b>" if r["id"] in prize else ""
        rows.append(f'      <div class="rv{top}"><span class="tier">{html.escape(r["label"])}</span>'
                    f'<span class="who">{html.escape(r["name"])}</span><span class="pts num">{int(r["score"]):,}</span>'
                    f'<span class="prize">{won}</span></div>')
    return "\n".join(rows)


def write_page(ver: str) -> Path:
    """dist/index.html from site/index.html: everything inline, with this
    release's sizes and checksums. Every archive must be from this version."""
    files = {}
    for t, info in TARGETS.items():
        path = DIST / info["archive"]
        if not path.exists():
            fail(f"the page needs all three downloads; {info['archive']} isn't in dist/")
        av = archive_version(path)
        if av != ver:
            fail(f"{info['archive']} is from {av}, not {ver}; rebuild it before writing the page")
        sha = sha256_of(path)
        files[t] = {"label": LABELS[t], "file": info["archive"], "size": f"{path.stat().st_size / 1e6:.0f} MB",
                    "href": f"{info['archive']}?v={sha[:12]}", "sha": sha}
    shot = SITE / "screenshot.webp"
    w, h = webp_size(shot)
    pad = max(len(f["file"]) for f in files.values()) + 4
    values = {
        "PALETTE_CSS": palette_css(),
        "CS_CSS": design_css(),
        "BOARD_JS": (DESIGN / "shared" / "board.js").read_text(encoding="utf-8"),
        "FAVICON": _data_uri(DESIGN / "icon" / "icon-small.svg", "image/svg+xml"),
        "ICON": _data_uri(DESIGN / "icon" / "icon.svg", "image/svg+xml"),
        "SCREENSHOT": _data_uri(shot, "image/webp"), "SCREENSHOT_W": str(w), "SCREENSHOT_H": str(h),
        "VERSION": html.escape(ver),
        "MACOS_MIN": macos_minimum(DIST / TARGETS["macos"]["archive"]),
        "RIVALS": rivals_html(),
        "SUMS": "\n".join(f"<b>{f['file']}</b>{' ' * (pad - len(f['file']))}{f['sha']}" for f in files.values()),
        "FILES_JSON": json.dumps({"version": ver, **{t: {k: f[k] for k in ("label", "file", "size", "href")}
                                                    for t, f in files.items()}}),
    }
    for t, f in files.items():
        values[f"{t.upper()}_HREF"] = html.escape(f["href"])
        values[f"{t.upper()}_FILE"] = f["file"]
        values[f"{t.upper()}_SIZE"] = f["size"]
    template = (SITE / "index.html").read_text(encoding="utf-8")
    wanted = set(re.findall(r"\{\{([A-Z_]+)\}\}", template))
    if wanted - values.keys():
        fail("site/index.html has unknown slots: " + ", ".join(sorted(wanted - values.keys())))
    page = re.sub(r"\{\{([A-Z_]+)\}\}", lambda m: values[m[1]], template)
    check_page(page, files)
    out = DIST / "index.html"
    out.write_text(page, encoding="utf-8", newline="\n")
    return out


def check_page(page: str, files: dict) -> None:
    for f in files.values():
        if f["sha"] not in page:
            fail(f"the page doesn't show {f['file']}'s checksum")
    allowed = {f["href"] for f in files.values()} | {"SHA256SUMS"}
    for attr, val in re.findall(r'\b(href|src)="([^"]*)"', page):
        v = html.unescape(val)
        if not (v.startswith("#") or v.startswith("data:") or v in allowed or v.startswith("${")):
            fail(f"the page links to {v[:80]!r}, which isn't in the release")
    loads = re.findall(r'(?:src|href)\s*=\s*["\']?https?:|url\(\s*["\']?https?:|@import|\bfetch\(|XMLHttpRequest', page)
    if loads:
        fail("the page loads something from outside: " + ", ".join(sorted(set(loads))))
    if len(page.encode()) > PAGE_MAX:
        fail(f"the page is {len(page.encode()) / 1e6:.2f} MB; keep it under {PAGE_MAX / 1e6:.0f} MB")
    print(f"  page: {len(page.encode()) / 1e3:.0f} KB, checksums and links match the release, loads nothing from outside")


# --- main -------------------------------------------------------------------------

def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--godot")
    ap.add_argument("--only", help="comma-separated: " + ",".join(TARGETS))
    ap.add_argument("--install-templates", action="store_true", help="download and install the export templates")
    ap.add_argument("--templates-file", help="install the templates from this .tpz instead of downloading")
    ap.add_argument("--page-only", action="store_true", help="rewrite dist/index.html from the archives already there")
    args = ap.parse_args()
    if args.page_only:
        step("the download page")
        print(f"  {write_page(version())}")
        return 0
    godot = rt.find_godot(args.godot)
    folder, tag = godot_version(godot)
    tdir = templates_dir(godot, folder)
    if args.install_templates or args.templates_file:
        install_templates(godot, args.templates_file)
        print("Templates installed. Build with:  python tools/build.py")
        return 0
    missing = missing_templates(tdir)
    if missing:
        print(f"Godot {tag}'s export templates aren't installed (missing {', '.join(missing)} in {tdir}).")
        print("Install them once with:  python tools/build.py --install-templates")
        print("or in the Godot editor: Editor > Manage Export Templates > Download and Install.")
        return 1
    targets = list(TARGETS) if not args.only else [t.strip() for t in args.only.split(",")]
    for t in targets:
        if t not in TARGETS:
            fail(f"unknown target {t!r} (choose from {', '.join(TARGETS)})")
    ver = version()
    step(f"CyberSweeper {ver} with Godot {tag}: {', '.join(targets)}")
    rt.ensure_import(godot)
    check_pack(pack_listing(godot))
    godot_text = godot_licenses(godot)
    DIST.mkdir(exist_ok=True)
    for t in targets:
        step(f"{t}: exporting and packing")
        exported = export(godot, t)
        dest = DIST / TARGETS[t]["archive"]
        PACK[t](exported, extras(t, ver, godot_text), dest)
        if t == "windows":
            check_windows(dest, ver)
        elif t == "macos":
            check_macos(dest, ver)
        else:
            check_linux(dest)
            if platform.system() == "Linux" and platform.machine() in ("x86_64", "AMD64"):
                test_launch(exported)
    sums = [(sha256_of(DIST / t["archive"]), t["archive"]) for t in TARGETS.values() if (DIST / t["archive"]).exists()]
    (DIST / "SHA256SUMS").write_text("".join(f"{h}  {n}\n" for h, n in sums), encoding="utf-8", newline="\n")
    step("the download page")
    page = None
    if all(archive_version(DIST / TARGETS[t]["archive"]) == ver for t in TARGETS if (DIST / TARGETS[t]["archive"]).exists()) \
            and len(sums) == len(TARGETS):
        page = write_page(ver)
    else:
        print(f"  not written: the page needs all three downloads from {ver} (build the rest, or use --page-only later)")
    step("done")
    for h, n in sums:
        size = (DIST / n).stat().st_size / 1e6
        print(f"  {n:28} {size:6.1f} MB  sha256 {h[:16]}…" + ("" if n in [TARGETS[t]["archive"] for t in targets]
                                                            else "  (from an earlier build)"))
    print(f"  {DIST / 'SHA256SUMS'}")
    if page:
        print(f"  {page}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
