#!/usr/bin/env python3
"""Offline, deterministic Unicode 17 / CLDR 48 canonical catalog compiler."""
import hashlib
import json
import re
import unicodedata
import xml.etree.ElementTree as ET
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "Vendor/Unicode/emoji-test-17.0.txt"
CLDR = ROOT / "Vendor/Unicode/cldr-48-en.xml"
VERSION = "unicode17-cldr48-canonical1-features1"

def normalized(glyph):
    return glyph.replace("\ufe0f", "")

def main():
    annotations = {}
    for item in ET.parse(CLDR).iter("annotation"):
        if item.get("type") != "tts":
            annotations[normalized(item.get("cp", ""))] = (item.text or "").split(" | ")
    raw, buckets = [], {}
    group = subgroup = ""
    for line in SOURCE.read_text().splitlines():
        if line.startswith("# group: "):
            group = line[9:]
        elif line.startswith("# subgroup: "):
            subgroup = line[12:]
        match = re.match(r"^([0-9A-F ]+)\s*; fully-qualified\s*# (\S+) E[\d.]+ (.+)$", line)
        if not match:
            continue
        _, glyph, name = match.groups()
        skin = any(0x1F3FB <= ord(c) <= 0x1F3FF for c in glyph)
        gender = bool(re.search(r"\b(man|woman|men|women)\b", name))
        entry = dict(id=len(raw), glyph=glyph, shortName=name,
                     keywords=annotations.get(normalized(glyph), []), group=group, subgroup=subgroup,
                     isFlag=subgroup in ("country-flag", "subdivision-flag"), isKeycap=subgroup=="keycap",
                     isSkinToneVariant=skin, isGenderVariant=gender, isZWJSequence="\u200d" in glyph)
        raw.append(entry)
        # Collapse modifiers only through a matching canonical sequence/name, keeping complete RGI representatives.
        base = re.sub(r"(?:light|medium-light|medium|medium-dark|dark) skin tone(?:, )?", "", name)
        base = re.sub(r"\b(man|woman)\b", "person", base)
        base = re.sub(r"\b(men|women)\b", "people", base)
        base = base.replace(" facing right", "").strip(" :, ")
        if subgroup == "family":
            base = "family" if name.startswith("family") else base
        buckets.setdefault(base, []).append(entry)
    # Occupational neutral names often omit "person" (scientist, teacher, etc.).
    # Merge only when that exact neutral concept exists in the official source.
    for name in list(buckets):
        if name.startswith("person ") and name[7:] in buckets:
            buckets[name[7:]].extend(buckets.pop(name))
    concepts = []
    for name, members in sorted(buckets.items()):
        representative = min(members, key=lambda e: (e["isSkinToneVariant"], e["isGenderVariant"], len(e["glyph"]), e["id"]))
        g, s = representative["group"], representative["subgroup"]
        is_face = s.startswith("face") or s=="cat-face"
        human = g=="People & Body" and s not in ("body-parts", "hand-fingers-open", "hand-fingers-partial", "hand-single-finger", "hand-fingers-closed", "hands", "hand-prop")
        structural = (representative["isFlag"] or representative["isKeycap"] or s in
            ("arrow", "av-symbol", "alphanum", "geometric", "time", "math", "punctuation", "currency", "other-symbol"))
        animal = s.startswith("animal")
        scene = s.startswith("place") or s in ("sky & weather", "transport-water")
        atmosphere = s=="sky & weather" or name in ("sparkles", "fire", "milky way", "rainbow")
        material = any(w in name.split() for w in ("ice", "snow", "water", "gem", "thread", "yarn", "feather", "wood", "rock", "droplet"))
        feature = s=="body-parts" or s.startswith("plant") or atmosphere or material
        roles = dict(subject=.95 if animal or human else .78, feature=.9 if feature else .6,
                     material=.95 if material else .18, accessory=.8 if g in ("Objects", "Activities") else .4,
                     setting=.95 if scene else .15, atmosphere=.95 if atmosphere else .15,
                     emotionSymbol=.9 if is_face or g=="Smileys & Emotion" else .1)
        if atmosphere:
            roles["subject"] = .35
        visual = dict(concreteness=.25 if structural else .9, visualSalience=.9, objectness=.25 if scene or structural else .9,
                      characterLikeness=.95 if animal or human or is_face else .05, sceneLikeness=.8 if scene else .05,
                      symbolicness=.95 if structural else (.55 if is_face else .1),
                      intrinsicComplexity=.8 if human and representative["isZWJSequence"] else (.55 if scene else .25),
                      transformability=.9 if feature else (.3 if human else .6))
        tags = []
        text = name + " " + s
        rules = {"waste": r"poo|drool|sweat droplets", "illness": r"vomit|nauseat|sneez|thermometer",
                 "injury": r"blood|bandage", "weapons": r"pistol|knife|dagger|sword|bomb|axe|bow and arrow",
                 "medical": r"syringe|pill|stethoscope|medical|hospital", "insects": r"animal-bug",
                 "religion": r"religion|mosque|church|synagogue|temple|kaaba", "death": r"skull|coffin|headstone|funeral"}
        tags += [tag for tag, pattern in rules.items() if re.search(pattern, text)]
        if g=="Food & Drink": tags.append("food")
        if is_face: tags.append("faces")
        if human: tags.append("humans")
        concepts.append(dict(id=len(concepts), canonicalGlyph=representative["glyph"], canonicalName=name,
            rawEmojiIDs=[e["id"] for e in members], keywords=sorted(set(representative["keywords"])),
            group=g, subgroup=s, roles=roles, visualFeatures=visual,
            defaultEligibility="exploratoryOnly" if structural else "strict", exclusions=tags,
            isFace=is_face, isHuman=human, isZWJSequence=representative["isZWJSequence"]))
    out = dict(version=VERSION, raw=raw, concepts=concepts)
    target = ROOT / "Sources/GlyphCore/Resources/emoji_catalog.json"
    target.write_text(json.dumps(out, ensure_ascii=False, sort_keys=True, separators=(",", ":")) + "\n")
    report = dict(catalogVersion=VERSION, unicodeVersion="17.0", cldrVersion="48", rawRGICount=len(raw),
        canonicalizedEntries=len(raw)-len(concepts), canonicalConceptCount=len(concepts),
        excludedStructuralConcepts=sum(c["defaultEligibility"] != "strict" for c in concepts),
        strictConceptCount=sum(c["defaultEligibility"] == "strict" for c in concepts),
        sourceSHA256={p.name:hashlib.sha256(p.read_bytes()).hexdigest() for p in (SOURCE,CLDR)},
        catalogSHA256=hashlib.sha256(target.read_bytes()).hexdigest())
    (ROOT / "Resources/emoji_catalog_report.json").write_text(json.dumps(report, indent=2, sort_keys=True)+"\n")
    print(json.dumps(report, indent=2))

if __name__ == "__main__":
    main()
