"""merge.py <repo app dir> <tr dir> <langs…>: writes translations into Localizable.xcstrings and InfoPlist.xcstrings."""
import json, re, sys, os
app, tr, langs = sys.argv[1], sys.argv[2], sys.argv[3:]
cat_path = os.path.join(app, "OneCleanerMac/Localizable.xcstrings")
info_path = os.path.join(app, "OneCleanerMac/InfoPlist.xcstrings")
src = json.load(open(os.path.join(tr, "source.json")))
cat = json.load(open(cat_path))
CATS = {"ru": ["one", "few", "many", "other"], "uk": ["one", "few", "many", "other"], "pl": ["one", "few", "many", "other"]}
for l in ["de", "nl", "es", "pt-BR", "fr", "it", "tr", "en"]: CATS[l] = ["one", "other"]
def ph(s): return sorted(re.sub(r"%\d+\$", "%", m) for m in re.findall(r"%(?:\d+\$)?(?:@|lld|ld|d)", s))
def unit(v): return {"stringUnit": {"state": "translated", "value": v}}
errors = []
# Existing InfoPlist translations stay; only the keys in source.json change.
info = json.load(open(info_path)) if os.path.exists(info_path) else {"sourceLanguage": "en", "strings": {}, "version": "1.0"}
en_pl = json.load(open(os.path.join(os.path.dirname(os.path.abspath(__file__)), "en_plurals.json")))
for x in src:
    if x["key"].startswith("INFOPLIST:"):
        entry = info["strings"].setdefault(x["key"][10:], {})
        entry.update({"comment": x["comment"], "extractionState": "manual"})
        entry.setdefault("localizations", {})["en"] = unit(x["english"])
# English plural forms
for k, one in en_pl.items():
    e = cat["strings"].setdefault(k, {})
    e.setdefault("localizations", {})["en"] = {"variations": {"plural": {"one": unit(one), "other": unit(k)}}}
# English for two-count dashboard strings
def sub(name, arg, one, other):
    return {"argNum": arg, "formatSpecifier": "lld",
            "variations": {"plural": {"one": unit(one), "other": unit(other)}}}
specials = {
    "%lld cleanups · %lld items since %@": {"stringUnit": {"state": "translated", "value": "%#@cleanups@ · %#@items@ since %3$@"},
        "substitutions": {"cleanups": sub("cleanups", 1, "%arg cleanup", "%arg cleanups"), "items": sub("items", 2, "%arg item", "%arg items")}},
    "%lld items · %lld folders": {"stringUnit": {"state": "translated", "value": "%#@items@ · %#@folders@"},
        "substitutions": {"items": sub("items", 1, "%arg item", "%arg items"), "folders": sub("folders", 2, "%arg folder", "%arg folders")}},
}
for k, v in specials.items():
    cat["strings"].setdefault(k, {}).setdefault("localizations", {})["en"] = v
for lang in langs:
    t = json.load(open(os.path.join(tr, lang + ".json")))
    for x in src:
        k = x["key"]
        if k not in t: errors.append((lang, "missing", k[:60])); continue
        v = t[k]
        forms = v if isinstance(v, dict) else {"_": v}
        for f in forms.values():
            want = ph(x.get("english", k))
            if ph(f) != want: errors.append((lang, "placeholders", k[:60], f[:60]))
        if k.startswith("INFOPLIST:"):
            info["strings"][k[10:]].setdefault("localizations", {})[lang] = unit(v)
            continue
        entry = cat["strings"].setdefault(k, {}).setdefault("localizations", {})
        if isinstance(v, dict):
            want = CATS.get(lang)
            if want and sorted(v) != sorted(want): errors.append((lang, "plural categories", k[:50], sorted(v)))
            entry[lang] = {"variations": {"plural": {c: unit(s) for c, s in v.items()}}}
        else:
            entry[lang] = unit(v)
if errors:
    # Nothing is written while anything is wrong.
    print("not merged,", len(errors), "errors:")
    for e in errors[:40]: print(" ", e)
    sys.exit(1)
json.dump(cat, open(cat_path, "w"), ensure_ascii=False, indent=2, sort_keys=True)
json.dump(info, open(info_path, "w"), ensure_ascii=False, indent=2, sort_keys=True)
print("merged", langs)
