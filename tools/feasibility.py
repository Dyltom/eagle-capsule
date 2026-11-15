#!/usr/bin/env python3
"""
Eagle Capsule - paper feasibility model.

Runs the numbers for the build before any money is spent: power budget, battery
life, overnight charge over USB-C, storage, sync time, internal fit and weight. Every input
is listed below with where it came from and how much we trust it, so you can
replace an estimate with a measured value once real hardware is on the bench.

Usage:  python3 tools/feasibility.py            (prints the report)
        python3 tools/feasibility.py --worst    (uses pessimistic values)

Standard library only. MIT licensed - see LICENSE and CREDITS.md.
Hardware references: Seeed Studio XIAO nRF52840 Sense, Nordic nRF52840,
TI BQ25101, Pololu #2597, Infineon IM73D122, Little Bird LB-00237 - credited in CREDITS.md.
"""
import sys

WORST = "--worst" in sys.argv

def pick(typical, worst):
    return worst if WORST else typical

# ---------------------------------------------------------------- power (mA)
# (typical, worst, source / confidence)
LOADS = {
    "nRF52840 CPU (Opus encode ~30% duty @64 MHz, DC/DC)": (1.2, 2.5, "Nordic PS ~3.3 mA active (DC/DC) x duty; Omi DK firmware proves Opus fits - ESTIMATE"),
    "PDM peripheral + HFCLK":                               (0.5, 0.9, "nRF52840 PS: HFXO ~0.25 mA + PDM/EasyDMA - ESTIMATE"),
    # Onboard mic (WMM7035/MSM261, ~64 dBA) held off (P1.10 LOW). Stock-mic fallback was 0.6 / 0.8 mA.
    "PDM mic: Infineon IM73D122 on D4/D6, power D2 (~70 dBA SNR)": (0.8, 1.1, "~690 uA typ at 1.536 MHz/1.8 V (datasheet); 1.28 MHz at ~3.2 V from a GPIO unverified -> net +0.2/+0.3 mA vs stock - MEASURE in T16"),
    "IMU (LSM6DS3TR-C, low-power or gated off)":            (0.1, 1.1, "Seeed forum: ~1.1 mA if the IMU is left powered - VERIFIED risk, gate it"),
    "microSD idle in SPI mode":                             (0.3, 1.0, "datasheets 0.12-0.25 mA, field 0.3-1 mA - MEASURE your card"),
    "microSD write bursts (avg over time)":                 (0.3, 0.8, "~40 mA x ~10 ms per 4 KB block every ~1.4 s at 24 kbps - ESTIMATE"),
    "BLE idle connection/advertising":                      (0.1, 0.3, "Nordic online power profiler, long intervals - ESTIMATE"),
    "Regulator quiescent + VBAT divider + LED off":         (0.05, 0.2, "XIAO schematic; LEDs disabled in firmware - ESTIMATE"),
}

BATTERY_MAH = 600            # Little Bird LB-00237 (listing; options: 400 CE04375, 1100 CE04377)
USABLE_FRACTION = pick(0.85, 0.75)   # cutoff ~3.5 V, ageing, cold
WEAR_HOURS = 16              # unplugged per day
PLUGGED_HOURS = 8            # on USB-C overnight (on the printed stand by the bed)

# ---------------------------------------------------------------- charging
CHARGE_MA = 100              # BQ25101: P0.13 LOW = 100 mA, high-Z = 50 mA (verified)
# Extra battery-node load while syncing. USB CDC: CPU + SD reads at ~30% duty - ESTIMATE.
# BLE fallback: 6.4 mA TX @0 dBm, 16.4 mA @+8 dBm (Nordic PS). The same 7 / 17 mA covers both.
SYNC_EXTRA_MA = pick(7, 17)
SAFETY_TIMER_H = 10          # BQ25101 fixed 10 h fast-charge timer (verified)

# ---------------------------------------------------------------- data
OPUS_KBPS = pick(24, 32)     # 24 kbps planned (docs/FIRMWARE.md); Omi devkit ships 32 kbps VBR (verified)
CARD_GB = 32
SLOT_BYTES = 256 * 1024     # one chunk per raw-ring slot
CHUNK_S = 60
SPEECH_FRACTION = 0.35       # share of a 24 h day that is not silence (VAD) - ESTIMATE
# BLE bulk sync. Typical 40 KB/s is an ESTIMATE (bleak on Linux ~30-100, Windows ~10-60; chip
# ceiling ~165). Worst 5 KB/s is MEASURED: Boswell (github.com/leakydata/boswell, STANDALONE_CAPTURE.md)
# pulled a file over GATT notifications at 5.07 kB/s on a XIAO nRF52840 Sense while still recording.
BLE_KBYTES_S = pick(40, 5)
# USB CDC-ACM over the capsule's USB-C port, the main sync path. USB full speed is 12 Mbit/s
# (~1.2 MB/s bulk ceiling); the nRF52840 CDC stack, SLIP framing and SD reads over 8 MHz SPI
# while recording continues set the real rate. 300 / 100 KB/s is an ESTIMATE - measure in T11.
USB_KBYTES_S = pick(300, 100)

# ---------------------------------------------------------------- mechanics (mm, g)
PARTS = {
    #  name                      L     W     H    grams
    "XIAO nRF52840 Sense":      (21.0, 17.8, 4.0, 3.0),   # H incl. USB-C receptacle
    "Pololu 2597 microSD + card": (20.3, 17.8, 3.5, 1.6),  # VERIFY card overhang
    "LiPo 600 mAh (LB-00237)":  (36.0, 29.0, 5.5, 10.5),  # listing; VERIFY whether the PCM is inside 5.5 mm
    "IM73D122 mic PCB":         (8.0, 6.0, 2.0, 0.3),     # ~8 x 6 mm, 0.6-0.8 mm PCB + 1.2 mm mic; ESTIMATE
    "ADA805 slide switch":      (8.6, 3.6, 3.5, 0.5),
    "wire, solder, foam, tape": (0, 0, 0, 1.5),
}
WALL = 1.6                   # printed wall thickness
WIRE_GAP = 1.0               # clearance for wires / solder joints per tier
SHELL_DENSITY = 1.27         # PETG g/cm^3 (PLA 1.24)
SHELL_INFILL_FACTOR = 0.9    # thin walls print almost solid

# ============================================================================
def hr(t):
    print("\n" + t + "\n" + "-" * len(t))

def power():
    hr("1. Power budget (%s case)" % ("WORST" if WORST else "typical"))
    total = 0.0
    for k, v in LOADS.items():
        ma = pick(v[0], v[1])
        total += ma
        print(f"  {ma:5.2f} mA  {k}")
    print(f"  {total:5.2f} mA  TOTAL average while recording")
    usable = BATTERY_MAH * USABLE_FRACTION
    life = usable / total
    day_use = total * WEAR_HOURS
    print(f"\n  Battery {BATTERY_MAH} mAh, usable {usable:.0f} mAh -> {life:.0f} h continuous ({life/24:.1f} days)")
    print(f"  Daily draw unplugged ({WEAR_HOURS} h): {day_use:.0f} mAh = {100*day_use/usable:.0f}% of usable capacity")
    verdict = "PASS" if life >= 24 * 1.5 else ("MARGINAL" if life >= 24 else "FAIL")
    print(f"  Target >= 24 h with 50% margin: {verdict}")
    return total, day_use

def charging(rec_ma, day_use):
    hr("2. Overnight charge over USB-C (recording + syncing continues)")
    net = CHARGE_MA - rec_ma - SYNC_EXTRA_MA
    hours = day_use / net * 1.3   # +30% for CV taper
    print(f"  Charger {CHARGE_MA} mA - load {rec_ma:.1f} mA - sync load {SYNC_EXTRA_MA} mA = {net:.0f} mA net into cell")
    print(f"  Refill {day_use:.0f} mAh -> ~{hours:.1f} h (plugged-in window {PLUGGED_HOURS} h, safety timer ~{SAFETY_TIMER_H} h)")
    print("  NOTE: BQ25101 has no power-path. With the system load on the battery node the charger")
    print("  may terminate early or re-cycle; harmless at this tiny daily depth, but log VBAT to confirm.")
    print(f"  Verdict: {'PASS' if hours < PLUGGED_HOURS else 'FAIL'}")

def data():
    hr("3. Storage and sync")
    mb_per_h = OPUS_KBPS * 1000 / 8 * 3600 / 1e6
    full_day = mb_per_h * 24
    vad_day = full_day * SPEECH_FRACTION
    # The raw ring stores one 60 s chunk per fixed 256 KiB slot (docs/FIRMWARE.md section 8),
    # so capacity counts slots, not bytes, and doesn't change with bitrate.
    slots = CARD_GB * 1e9 * 0.95 / SLOT_BYTES
    days = slots * CHUNK_S / 86400
    print(f"  Opus {OPUS_KBPS} kbps -> {mb_per_h:.1f} MB/h, {full_day:.0f} MB per 24 h ungated, {vad_day:.0f} MB with VAD")
    print(f"  {CARD_GB} GB card holds ~{days:.0f} days ({slots:,.0f} slots of 256 KiB, one per {CHUNK_S} s chunk; a ring buffer, not an archive)")
    for label, mb in (("ungated", full_day), ("VAD-gated", vad_day)):
        ble = mb * 1000 / BLE_KBYTES_S / 3600
        usb = mb * 1000 / USB_KBYTES_S / 60
        print(f"  Sync {label:9s}: USB CDC @{USB_KBYTES_S} KB/s = {usb:3.0f} min | BLE @{BLE_KBYTES_S} KB/s = {ble:4.1f} h  (window {PLUGGED_HOURS} h)")
    usb_ok = full_day * 1000 / USB_KBYTES_S / 3600 < 1.0
    ok = full_day * 1000 / BLE_KBYTES_S / 3600 < PLUGGED_HOURS
    ok_vad = vad_day * 1000 / BLE_KBYTES_S / 3600 < PLUGGED_HOURS
    print(f"  Verdict: USB CDC moves a full day in under 1 h: {'PASS' if usb_ok else 'FAIL'}"
          f"; ungated BLE fits the night: {'PASS' if ok else 'FAIL'}; VAD-gated BLE: {'PASS' if ok_vad else 'FAIL'}")
    if not ok:
        print("  -> USB CDC is the sync path; BLE is the fallback (plain charger, no PC) and for on-demand pulls.")

def fit():
    hr("4. Internal fit and weight")
    xiao, sd, bat, mic = (PARTS[k] for k in list(PARTS)[:4])
    top_l = xiao[0] + sd[0] + 1.0           # side by side, 1 mm gap
    top_w = max(xiao[1], sd[1])
    top_h = max(xiao[2], sd[2] + mic[2])    # mic PCB on the lid's inner face, over the SD board (box model)
    cav_l = max(top_l, bat[0]) + 1.0
    cav_w = max(top_w, bat[1]) + 1.0
    cav_h = bat[2] + top_h + 2 * WIRE_GAP
    # no external connector: the XIAO's own USB-C faces a slot in the wall; switch on a side wall
    out_l = cav_l + 2 * WALL
    out_w = cav_w + 2 * WALL
    out_h = cav_h + 2 * WALL
    print(f"  Top tier (XIAO beside SD, mic PCB over the SD): {top_l:.1f} x {top_w:.1f} x {top_h:.1f}")
    print(f"  Cavity: {cav_l:.1f} x {cav_w:.1f} x {cav_h:.1f}")
    print(f"  Outer shell (USB-C through a side slot, no dock connector): {out_l:.1f} x {out_w:.1f} x {out_h:.1f} mm")
    overhang = top_l - bat[0]
    print(f"  Top tier overhangs the battery by {overhang:.1f} mm - the XIAO antenna end must sit in that")
    print("  overhang, clear of the cell, or BLE range suffers (the original plan put the cell under it).")
    shell_cm3 = (out_l * out_w * out_h - cav_l * cav_w * cav_h) / 1000
    shell_g = shell_cm3 * SHELL_DENSITY * SHELL_INFILL_FACTOR
    parts_g = sum(p[3] for p in PARTS.values())
    print(f"  Weight: parts {parts_g:.1f} g + shell {shell_g:.1f} g = {parts_g + shell_g:.1f} g (before the eagle plate and cord)")
    print("  Box model only. The CAD (hardware/capsule.scad) lays the parts out for the antenna,")
    print("  switch, mic-port and USB-C rules; its size and weight per variant are in hardware/README.md.")

def main():
    print("EAGLE CAPSULE - feasibility model" + ("  [--worst]" if WORST else ""))
    rec_ma, day_use = power()
    charging(rec_ma, day_use)
    data()
    fit()
    print("\nAll inputs marked ESTIMATE/VERIFY are replaced with bench measurements in build stage 2.")

if __name__ == "__main__":
    main()
