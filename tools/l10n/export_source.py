"""export_source.py <app dir> <out dir>: writes source.json (every catalog key with its comment and kind) for translators.

Run `xcodebuild -exportLocalizations -project OneCleanerMac.xcodeproj -localizationPath /tmp/l10n -exportLanguage en`
first: it refreshes OneCleanerMac/Localizable.xcstrings from the code. Info.plist permission texts are added as
`INFOPLIST:<key>` entries from OneCleanerMac/InfoPlist.xcstrings.
"""
import json, os, re, sys

app, out = sys.argv[1], sys.argv[2]
catalog = json.load(open(os.path.join(app, "OneCleanerMac/Localizable.xcstrings")))
info = json.load(open(os.path.join(app, "OneCleanerMac/InfoPlist.xcstrings")))
only_new = "--untranslated" in sys.argv
source = []
for key, value in sorted(catalog["strings"].items()):
    if not key.strip() or value.get("shouldTranslate") is False:
        continue
    if only_new and len(value.get("localizations", {})) > 1:
        continue
    counts = len(re.findall(r"%(?:\d+\$)?lld", key))
    source.append({"key": key, "comment": value.get("comment", ""),
                   "kind": "plain" if counts == 0 else ("plural" if counts == 1 else "multi")})
for key, value in sorted(info["strings"].items()):
    source.append({"key": "INFOPLIST:" + key, "english": value["localizations"]["en"]["stringUnit"]["value"],
                   "comment": value.get("comment", ""), "kind": "plain"})
os.makedirs(out, exist_ok=True)
json.dump(source, open(os.path.join(out, "source.json"), "w"), ensure_ascii=False, indent=1)
print(len(source), "strings →", os.path.join(out, "source.json"))
