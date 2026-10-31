#!/usr/bin/env python3
"""Builds PromoStudio/Resources/Localizable.xcstrings from the strings the
compiler extracted (SWIFT_EMIT_LOC_STRINGS → *.stringsdata) and the
translations in l10n/<language>*.json.

Translation files map the English source as written in Swift, with
`\\(...)` interpolations verbatim, to the translation with the same
interpolations in the same order:

    {"Rendering \\(name)…": "\\(name) render ediliyor…"}

The script finds the catalog key the compiler generated for each entry
(`Rendering %@…`) and copies its format specifiers into the translation.

Usage (after a Debug build into ./build):
    python3 scripts/l10n.py            # write the catalog
    python3 scripts/l10n.py --check    # fail if a key has no translation
"""
import glob
import json
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
CATALOG = os.path.join(ROOT, "PromoStudio/Resources/Localizable.xcstrings")
# Same languages as Remote Code
LANGUAGES = ["tr", "de", "es", "fr", "it", "pt-BR", "ja", "ko", "zh-Hans"]
SPECIFIER = r"%(?:\d+\$)?(?:lld|llu|ld|lu|d|u|@|lf|f)"
INTERPOLATION = re.compile(r"\\\((?:[^()]|\((?:[^()]|\([^()]*\))*\))*\)")


def extracted_keys():
    keys = set()
    for path in glob.glob(os.path.join(ROOT, "build/Build/Intermediates.noindex/**/*.stringsdata"), recursive=True):
        with open(path) as handle:
            data = json.load(handle)
        for entry in data.get("tables", {}).get("Localizable", []):
            keys.add(entry["key"])
    return keys


def load_translations(language):
    merged = {}
    for path in sorted(glob.glob(os.path.join(ROOT, f"l10n/{language}-*.json"))):
        with open(path) as handle:
            merged.update(json.load(handle))
    return merged


def pattern_for(source):
    parts = INTERPOLATION.split(source)
    return re.compile("^" + SPECIFIER.join(re.escape(p) for p in parts) + "$")


def translate(key, source, target):
    """Copies the specifiers of `key` into `target` in order."""
    specifiers = re.findall(SPECIFIER, key)
    pieces = INTERPOLATION.split(target)
    if len(pieces) - 1 != len(specifiers):
        return None
    out = pieces[0]
    for specifier, piece in zip(specifiers, pieces[1:]):
        out += specifier + piece
    return out


def main():
    check = "--check" in sys.argv
    keys = extracted_keys()
    if not keys:
        sys.exit("No extracted strings found. Build first: xcodebuild -scheme PromoStudio -derivedDataPath build build")
    strings = {}
    missing = []
    for language in LANGUAGES:
        table = load_translations(language)
        # l10n/catalog.<language>.json: catalog keys verbatim (specifiers, proper nouns)
        exact_path = os.path.join(ROOT, f"l10n/catalog.{language}.json")
        exact = json.load(open(exact_path)) if os.path.exists(exact_path) else {}
        patterns = [(pattern_for(source), source, target) for source, target in table.items()]
        for key in sorted(keys):
            entry = strings.setdefault(key, {})
            value = None
            if key in exact:
                value = exact[key]
            elif key in table and not re.search(SPECIFIER, key):
                value = table[key]
            else:
                for pattern, source, target in patterns:
                    if pattern.match(key):
                        value = translate(key, source, target)
                        break
            if value is None:
                missing.append((language, key))
                continue
            entry.setdefault("localizations", {})[language] = {"stringUnit": {"state": "translated", "value": value}}
    catalog = {"sourceLanguage": "en", "strings": strings, "version": "1.0"}
    with open(CATALOG, "w") as handle:
        json.dump(catalog, handle, ensure_ascii=False, indent=2, sort_keys=True)
        handle.write("\n")
    print(f"{len(keys)} keys, {len(missing)} without translation")
    for language, key in missing:
        print(f"  MISSING [{language}] {json.dumps(key, ensure_ascii=False)}")
    if check and missing:
        sys.exit(1)


if __name__ == "__main__":
    main()
