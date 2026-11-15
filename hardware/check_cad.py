#!/usr/bin/env python3
"""Render every CAD variant and fail on any assert, error or interference.

For each line of hardware/variants.txt (OpenSCAD -D settings, e.g.
`battery="400" storage="pololu_sd"`), this renders the capsule's `interference`
part (must be empty), the printable capsule parts and the dock, and prints the
outer size the capsule echoes.

Usage:  python3 hardware/check_cad.py [--openscad PATH] [--parts body,lid,...]
"""
import argparse
import os
import re
import shlex
import shutil
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
CAPSULE_PARTS = ["body", "lid", "bezel", "pegs", "usb_plug", "gasket"]
DOCK_PARTS = ["dock", "bottom_plate"]
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


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--openscad")
    ap.add_argument("--keep", help="directory to keep the STLs in")
    args = ap.parse_args()
    openscad = find_openscad(args.openscad)
    outdir = args.keep or tempfile.mkdtemp(prefix="eagle-cad-")
    os.makedirs(outdir, exist_ok=True)
    capsule = os.path.join(HERE, "capsule.scad")
    dock = os.path.join(HERE, "dock.scad")
    failures = 0
    for defs in variants():
        label = " ".join(defs) or "(defaults)"
        rc, log, bad, empty = render(openscad, capsule, "interference", defs, outdir)
        size = re.search(r"outer W x H x T = ([^\"]+)", log)
        problems = list(bad)
        if rc != 0 and not empty:   # openscad exits 1 when the result is empty, which is the goal here
            problems.append(f"interference: openscad exit {rc}")
        if not empty:
            problems.append("interference is NOT empty: electronics overlap the shell")
        for scad, parts in ((capsule, CAPSULE_PARTS), (dock, DOCK_PARTS)):
            for part in parts:
                rc, log, bad, empty = render(openscad, scad, part, defs, outdir)
                if rc != 0 or bad or empty:
                    problems.append(f"{os.path.basename(scad)}:{part}: exit {rc}, "
                                    f"{'empty, ' if empty else ''}{'; '.join(bad[:3])}")
        status = "ok  " if not problems else "FAIL"
        print(f"{status} {label}  ->  {size.group(1) if size else 'size not echoed'}")
        for pr in problems:
            print(f"       {pr}")
        failures += bool(problems)
    print(f"\n{failures} failing variant(s)")
    sys.exit(1 if failures else 0)


if __name__ == "__main__":
    main()
