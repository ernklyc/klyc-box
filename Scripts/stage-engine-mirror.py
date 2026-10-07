#!/usr/bin/env python3
"""Stages a copy of the default engine's downloads, ready to be published as a GitHub release of our
own, so the app no longer depends on someone else's servers. Local only: it uploads nothing.

For every component of spike/engine-manifest.json it finds the file in the local backups, checks
its sha256 against the manifest, copies it, and writes next to the files:
  - SOURCES.md   where each file came from and under which license
  - mirror-manifest.json   the manifest with the URLs pointed at the mirror (sha256 unchanged)
D3DMetal itself (Apple's) is never staged: the script stops if a component looks like it.

Usage: Scripts/stage-engine-mirror.py [--repo ernklyc/klyc-engine] [--tag components-20261006]
"""
import argparse, glob, hashlib, json, os, re, shutil, subprocess, sys

_PARENT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
ROOTS = [os.environ.get("ENGINE_BACKUP", os.path.join(_PARENT, "engine-backup")), os.environ.get("KLYC_DOWNLOADS", os.path.join(_PARENT, "KLYC-Data", "downloads"))]
OUT = os.environ.get("ENGINE_MIRROR", os.path.join(_PARENT, "engine-mirror"))

def sha256(path):
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()

# Anything under these paths is Apple's Game Porting Toolkit / D3DMetal, which may not be redistributed.
APPLE_PATTERN = re.compile(r"renderer/d3dmetal/|libd3dshared|apple_gptk|D3DMetal\.framework", re.I)

def contains_apple_files(path):
    """True when an archive holds Apple's D3DMetal. Plain files (winetricks) are not archives."""
    if not re.search(r"\.tar(\.(gz|xz))?$|\.tgz$", path):
        return False
    flag = "-tJf" if path.endswith(".xz") else "-tzf"
    out = subprocess.run(["tar", flag, path], capture_output=True, text=True).stdout
    return bool(APPLE_PATTERN.search(out))

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--repo", default="ernklyc/klyc-engine")
    ap.add_argument("--tag", default="components-20261006")
    args = ap.parse_args()

    manifest = json.load(open("spike/engine-manifest.json"))
    local = {}
    for root in ROOTS:
        for f in glob.glob(root + "/*"):
            if os.path.isfile(f):
                local.setdefault(os.path.basename(f), f)

    dest = os.path.join(OUT, args.tag)
    os.makedirs(dest, exist_ok=True)
    rows, urls, mirrored, skipped = [], {}, json.loads(json.dumps(manifest)), []
    for name, comp in manifest["components"].items():
        url, want = comp["url"], comp["sha256"]
        base = os.path.basename(url)
        if "d3dmetal" in base.lower() and "tsshim" not in base.lower():
            sys.exit(f"refusing to stage {base}: it looks like Apple's D3DMetal, which must not be redistributed")
        if url in urls:
            mirrored["components"][name]["url"] = urls[url]
            continue
        src = local.get(base)
        if not src:
            sys.exit(f"missing locally: {base} ({name}); download it first")
        if contains_apple_files(src):
            # Not copied: it carries Apple's D3DMetal. The app keeps downloading it from where it is published.
            skipped.append((name, base, url))
            urls[url] = url
            print(f"NOT mirrored: {base} contains Apple's D3DMetal; the manifest keeps its original address")
            continue
        got = sha256(src)
        if got != want:
            sys.exit(f"sha256 mismatch for {base}: manifest {want[:12]}, file {got[:12]}")
        shutil.copy2(src, os.path.join(dest, base))
        new_url = f"https://github.com/{args.repo}/releases/download/{args.tag}/{base}"
        urls[url] = new_url
        mirrored["components"][name]["url"] = new_url
        rows.append((name, base, comp.get("license", ""), url, os.path.getsize(src)))

    with open(os.path.join(dest, "mirror-manifest.json"), "w") as f:
        json.dump(mirrored, f, indent=2)
    with open(os.path.join(dest, "SOURCES.md"), "w") as f:
        f.write(f"# Engine components ({manifest['id']})\n\n")
        f.write("Copies of the files KLYC-Box's engine is assembled from, byte for byte as published upstream "
                "(their sha256 is in the manifest and is checked before the app uses them).\n\n")
        f.write("| Component | File | License | Upstream | Size |\n|---|---|---|---|---|\n")
        for name, base, lic, url, size in rows:
            f.write(f"| {name} | `{base}` | {lic} | {url} | {size // 1048576} MB |\n")
        for name, base, url in skipped:
            f.write(f"\nNot included: `{base}` ({name}). It contains Apple's Game Porting Toolkit / D3DMetal, whose license does not allow us to redistribute it; KLYC-Box downloads it from {url}.\n")
        f.write("\nWine, DXVK, DXMT, MoltenVK and the others are free software; their source code is available from "
                "the projects linked in the README, and the patches and build scripts KLYC-Box's engine carries are in "
                "`source/` of this repository. Apple's D3DMetal is not part of this release.\n")
    # The repository around the release: README, the sources notes, and the patches and build scripts
    # that go with the redistributed binaries (LGPL asks for the source that built them).
    repo = os.path.join(OUT, "repo")
    shutil.rmtree(repo, ignore_errors=True)
    os.makedirs(os.path.join(repo, "source/patches"))
    os.makedirs(os.path.join(repo, "source/build-scripts"))
    for f in glob.glob("spike/patches/*.patch"):
        shutil.copy2(f, os.path.join(repo, "source/patches"))
    for f in glob.glob("Scripts/build-*.sh"):
        shutil.copy2(f, os.path.join(repo, "source/build-scripts"))
    shutil.copy2(os.path.join(dest, "SOURCES.md"), os.path.join(repo, "SOURCES.md"))
    shutil.copy2(os.path.join(dest, "mirror-manifest.json"), os.path.join(repo, "mirror-manifest.json"))
    with open(os.path.join(repo, "README.md"), "w") as f:
        f.write(f"""# KLYC-Box engine components

Copies of the files [KLYC-Box](https://github.com/ernklyc/klyc-box)'s Windows engine is assembled from, so the app does not depend on anyone else's download servers. Each file is exactly what was published upstream: the app checks its SHA-256 (listed in `mirror-manifest.json`) before using it.

**Where the files are:** the [Releases](https://github.com/{args.repo}/releases) of this repository. **What each one is, and under which license:** [SOURCES.md](SOURCES.md).

## Source code

These are free-software binaries (Wine, DXVK, DXMT, MoltenVK and friends). Their sources are at the projects:

- Wine: https://gitlab.winehq.org/wine/wine (Sikarugir's builds: https://github.com/Sikarugir-App/Engines)
- DXMT: https://github.com/3Shain/dxmt, DXVK: https://github.com/doitsujin/dxvk, MoltenVK: https://github.com/KhronosGroup/MoltenVK
- Winetricks: https://github.com/Winetricks/winetricks

The changes KLYC-Box's engine adds to them, and the scripts that build them, are in [`source/`](source): `source/patches` and `source/build-scripts`. Originally written for the [Highball](https://github.com/gauthierpiarrette/highball) project, by Gauthier Piarrette and its contributors, whose work this is built on.

## What is not here

Apple's Game Porting Toolkit / D3DMetal. Its license does not allow redistribution, so it is not in these releases; KLYC-Box asks you to accept Apple's license and downloads it from where it is already published.

## License

Each file keeps the license of its project (see SOURCES.md). This repository is free and non-commercial.
""")
    total = sum(r[4] for r in rows)
    print(f"staged {len(rows)} files, {total // 1048576} MB, in {dest}")
    for r in rows:
        print(f"  {r[1]}  ({r[4] // 1048576} MB)  {r[2][:30]}")

if __name__ == "__main__":
    main()
