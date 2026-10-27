#!/usr/bin/env python3
import argparse
import ipaddress
import json
import re
from pathlib import Path

import pytesseract
from PIL import Image, ImageDraw

KEEP_IPS = {"192.168.1.1", "192.168.1.3", "192.168.1.11", "192.168.1.213", "192.168.1.0", "127.0.0.1", "0.0.0.0", "255.255.255.255"}
KEEP_NETS = [ipaddress.ip_network("10.30.0.0/24")]
SAFE_DOMAINS = ("splunk.com", "ubuntu.com", "wazuh.com", "microsoft.com", "github.com", "debian.org", "proxmox.com", "sysinternals.com", "githubusercontent.com", "google.com")
FILL = (110, 110, 110)

IPV4 = re.compile(r"(\d{1,3})[.,](\d{1,3})[.,]([\d@]{1,3})[.,]([\d@]{1,3})")
IPV6 = re.compile(r"^[0-9a-f]{1,4}(:[0-9a-f]{0,4}){3,}$", re.I)
MAC = re.compile(r"([0-9a-z/]{2,3}[:-]){4,}[0-9a-z/]{2}", re.I)
DOMAIN = re.compile(r"[a-z0-9-]+(\.[a-z0-9-]+)*\.(com|net|org|io|tv|gg|co|us|app|xyz|cloud|ai|dev|me|edu|gov|info|live|be|ly)\b", re.I)


def keep_ip(ip):
    if ip in KEEP_IPS:
        return True
    try:
        addr = ipaddress.ip_address(ip)
    except ValueError:
        return False
    return any(addr in net for net in KEEP_NETS)


def sensitive(word, keywords):
    m = IPV4.search(word)
    if m and not keep_ip(".".join(m.groups()).replace("@", "0")):
        return True
    if MAC.search(word):
        return True
    if IPV6.match(word.strip("{},;()[]")):
        return True
    d = DOMAIN.search(word)
    if d and not d.group(0).lower().endswith(SAFE_DOMAINS):
        return True
    return bool(keywords and keywords.search(word))


def redact(src, dst, boxes, keywords):
    im = Image.open(src).convert("RGB")
    scale = 2 if im.width < 2000 else 1
    big = im.resize((im.width * scale, im.height * scale))
    data = pytesseract.image_to_data(big, output_type=pytesseract.Output.DICT)
    draw = ImageDraw.Draw(im)
    hits = []
    for i, word in enumerate(data["text"]):
        if word.strip() and sensitive(word, keywords):
            x, y, w, h = (data[k][i] // scale for k in ("left", "top", "width", "height"))
            draw.rectangle([x - 3, y - 3, x + w + 3, y + h + 3], fill=FILL)
            hits.append(word)
    for box in boxes:
        draw.rectangle(box, fill=FILL)
    dst.parent.mkdir(parents=True, exist_ok=True)
    im.save(dst)
    return hits


def main():
    p = argparse.ArgumentParser(description="Black out public IPs, MACs, IPv6, external domains and keywords in screenshots before publishing.")
    p.add_argument("input", type=Path, help="Image file or folder of images")
    p.add_argument("output", type=Path, help="Output folder")
    p.add_argument("--boxes", type=Path, help='JSON of manual boxes: {"file-stem": [[x1, y1, x2, y2], ...]}')
    p.add_argument("--keyword", action="append", default=[], help="Extra word to redact (repeatable)")
    a = p.parse_args()

    boxes = json.loads(a.boxes.read_text()) if a.boxes else {}
    keywords = re.compile("|".join(map(re.escape, a.keyword)), re.I) if a.keyword else None
    files = [a.input] if a.input.is_file() else sorted(f for f in a.input.iterdir() if f.suffix.lower() in (".png", ".jpg", ".jpeg"))

    for f in files:
        hits = redact(f, a.output / f"{f.stem}.png", boxes.get(f.stem, []), keywords)
        print(f"{f.name}: {len(hits)} redacted {hits}")
    print("\nOCR misses things. Open every output and add manual boxes for anything left.")


if __name__ == "__main__":
    main()
