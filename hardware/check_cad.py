#!/usr/bin/env python3
"""Render every CAD variant and fail on any assert, error or interference.

For each line of hardware/variants.txt (OpenSCAD -D settings, e.g.
`battery="400" storage="pololu_sd"`), this renders the capsule's `interference`
part (must be empty), the printable capsule parts and the stand (dock.scad), and
prints the outer size the capsule echoes, the eagle plate or crest size and the stand footprint.

Usage:  python3 hardware/check_cad.py [--openscad PATH] [--keep DIR] [--jobs N]
"""
import argparse
import os
import re
import shlex
import shutil
import subprocess
import sys
import tempfile
from concurrent.futures import ThreadPoolExecutor

HERE = os.path.dirname(os.path.abspath(__file__))
CAPSULE_PARTS = ["body", "lid", "bezel", "pegs", "usb_plug", "gasket"]
STAND_PARTS = ["stand"]
FAIL_PATTERNS = ("ERROR:", "Assertion", "WARNING: Ignoring unknown", "undefined")


def find_openscad(explicit):
    for c in (explicit, os.environ.get("OPENSCAD"), shutil.which("openscad"),
              os.path.expanduser("~/opt/openscad/AppRun")):
        if c and (os.path.exists(c) or shutil.which(c)):
            return c
    sys.exit("openscad not found: install it, set OPENSCAD, or pass --openscad")


def variants():
    path = os.path.join(HERE, "variants.txt")
    if not os.path.exists(path):
        return [[]]
    out = []
    for line in open(path):
        line = line.split("#", 1)[0].strip()
        if line:
            out.append(shlex.split(line, posix=False))
    return out or [[]]


def render(openscad, scad, part, defs, outdir):
    out = os.path.join(outdir, f"{os.path.basename(scad)[:-5]}_{part}.stl")
    cmd = [openscad, "-o", out, "-D", f'part="{part}"']
    for d in defs:
        cmd += ["-D", d]
    cmd.append(scad)
    p = subprocess.run(cmd, capture_output=True, text=True)
    log = p.stdout + p.stderr
    bad = [l for l in log.splitlines() if any(k in l for k in FAIL_PATTERNS)]
    empty = "top level object is empty" in log
    return p.returncode, log, bad, empty


def check_variant(openscad, defs, outdir):
    """Render one variant line; return the lines to print and whether it failed."""
    os.makedirs(outdir, exist_ok=True)
    capsule = os.path.join(HERE, "capsule.scad")
    stand = os.path.join(HERE, "dock.scad")
    label = " ".join(defs) or "(defaults)"
    rc, log, bad, empty = render(openscad, capsule, "interference", defs, outdir)
    size = re.search(r"outer W x H x T = ([^\"]+)", log)
    problems = list(bad)
    if rc != 0 and not empty:   # openscad exits 1 when the result is empty, which is the goal here
        problems.append(f"interference: openscad exit {rc}")
    if not empty:
        problems.append("interference is NOT empty: electronics overlap the shell")
    extra = []
    for scad, parts in ((capsule, CAPSULE_PARTS), (stand, STAND_PARTS)):
        for part in parts:
            rc, log, bad, empty = render(openscad, scad, part, defs, outdir)
            if rc != 0 or bad or empty:
                problems.append(f"{os.path.basename(scad)}:{part}: exit {rc}, "
                                f"{'empty, ' if empty else ''}{'; '.join(bad[:3])}")
            for pat, name in ((r"EAGLE plate W x H x T = ([\d.]+ x [\d.]+ x [\d.]+)", "plate"),
                              (r"CREST relief .*?\(([\d.]+ x [\d.]+) mm\)", "crest"),
                              (r"STAND footprint = ([\d.]+ x [\d.]+)", "stand")):
                m = re.search(pat, log)
                if m and part in ("bezel", "stand"):
                    extra.append(f"{name} {m.group(1)}")
    status = "ok  " if not problems else "FAIL"
    lines = [f"{status} {label}  ->  {size.group(1) if size else 'size not echoed'}"
             + (f"  [{', '.join(extra)}]" if extra else "")]
    lines += [f"       {pr}" for pr in problems]
    return lines, bool(problems)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--openscad")
    ap.add_argument("--keep", help="directory to keep the STLs in (one subdirectory per variant)")
    ap.add_argument("--jobs", type=int, default=min(8, os.cpu_count() or 1),
                    help="variants rendered in parallel (default: up to 8)")
    args = ap.parse_args()
    openscad = find_openscad(args.openscad)
    outdir = args.keep or tempfile.mkdtemp(prefix="eagle-cad-")
    todo = variants()
    failures = 0
    with ThreadPoolExecutor(max_workers=max(1, args.jobs)) as pool:
        jobs = [pool.submit(check_variant, openscad, defs, os.path.join(outdir, f"v{i:02d}"))
                for i, defs in enumerate(todo)]
        for job in jobs:   # results print in variants.txt order
            lines, failed = job.result()
            print("\n".join(lines), flush=True)
            failures += failed
    print(f"\n{failures} failing variant(s) of {len(todo)}")
    sys.exit(1 if failures else 0)


if __name__ == "__main__":
    main()
