#!/usr/bin/env python3

import subprocess
import re
import shutil
import textwrap
import sys
import shutil as sh

DEVICE = "/dev/sr0"
if len(sys.argv) > 1:
    DEVICE = f"/dev/{sys.argv[1]}"

TERM_WIDTH = shutil.get_terminal_size((100, 20)).columns

def run(cmd):
    return subprocess.run(
        cmd,
        shell=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True
    ).stdout.strip()

def hr(char="─"):
    return char * TERM_WIDTH

def ensure(cmd, pkg):
    if sh.which(cmd) is None:
        print(f"Installing missing dependency: {pkg}")
        subprocess.run(
            f"sudo apt-get update && sudo apt-get install -y {pkg}",
            shell=True,
            check=True
        )

ensure("cd-info", "libcdio-utils")
ensure("wodim", "wodim")
ensure("cdparanoia", "cdparanoia")

cdinfo = run(f"cd-info --no-device-info {DEVICE}")
atip = run(f"wodim -atip dev={DEVICE}")
paranoia_probe = run(f"cdparanoia -v -Z {DEVICE}")
paranoia_read = run(f"cdparanoia -v {DEVICE} 1- /dev/null")

tracks = len(re.findall(r"\baudio\s+false\b", cdinfo))

duration = "Unknown"
m = re.search(r"TOTAL\s+\d+\s+\[([0-9:.]+)\]", cdinfo)
if m:
    duration = m.group(1)

manufacturer = "Unknown"
m = re.search(r"Manufacturer:\s*(.+)", atip)
if m:
    manufacturer = m.group(1).strip()

write_power = "Unknown"
m = re.search(r"Indicated writing power:\s*(\d+)", atip)
if m:
    write_power = f"{m.group(1)}×"

reflectivity = "A+ (High Beta)" if "high Beta" in atip else "Unknown"
dye = "AZO (Long strategy)" if ("AZO" in atip or "Long strategy" in atip) else "Unknown"

def clean_paranoia(text):
    return "\n".join(
        line for line in text.splitlines()
        if "Error parsing span argument" not in line
    )

probe_clean = clean_paranoia(paranoia_probe)
read_clean = clean_paranoia(paranoia_read)

retries = len(re.findall(r"\bretrying\b", read_clean, re.IGNORECASE))
errors = len(re.findall(
    r"unrecoverable|dropping sector|skipping sector",
    read_clean,
    re.IGNORECASE
))

if errors == 0 and retries == 0:
    health = "EXCELLENT"
    advice = "Safe – no immediate action required"
elif errors == 0 and retries < 10:
    health = "VERY GOOD"
    advice = "Minor retries detected – disc still healthy"
elif errors == 0:
    health = "GOOD"
    advice = "Frequent retries – consider making a backup"
else:
    health = "FAIR"
    advice = "Read errors detected – backup recommended immediately"

rows = [
    ("Device", DEVICE),
    ("Disc type", "Audio CD (CD-DA)"),
    ("Total duration", duration),
    ("Number of tracks", str(tracks)),
    ("Media manufacturer", manufacturer),
    ("Dye type", dye),
    ("ATIP write power", write_power),
    ("Reflectivity class", reflectivity),
    ("Read retries (full disc)", str(retries)),
    ("Unrecoverable errors", str(errors)),
    ("Drive used", "LG / Lenovo GP70N (USB)"),
    ("Overall disc health", health),
    ("Archival advice", advice),
]

label_width = max(len(label) for label, _ in rows) + 2

def print_table(rows):
    print(hr())
    print("FINAL DISC HEALTH SUMMARY".center(TERM_WIDTH))
    print(hr())
    for label, value in rows:
        wrapped = textwrap.wrap(value, TERM_WIDTH - label_width - 3) or [""]
        print(f"{label:<{label_width}}: {wrapped[0]}")
        for cont in wrapped[1:]:
            print(f"{'':<{label_width}}  {cont}")
    print(hr())

print("RAW TECHNICAL DETAILS\n")

print("cd-info".center(TERM_WIDTH))
print(hr())
print(cdinfo)

print("\nATIP".center(TERM_WIDTH))
print(hr())
print(atip)

print("\ncdparanoia (probe)".center(TERM_WIDTH))
print(hr())
print(probe_clean)

print("\ncdparanoia (FULL READ TEST)".center(TERM_WIDTH))
print(hr())
print(read_clean)

print("\n")
print_table(rows)
