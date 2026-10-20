# 1Cleaner Mac localization

17 languages: en, ru, uk, de, nl, es, pt-BR, fr, it, pl, tr, ja, ko, zh-Hans, zh-Hant, id, vi.
The app follows macOS's language; About › Language overrides it per app (`Core/AppLanguage.swift`, applies after a
restart). Translations live only in `OneCleanerMac/Localizable.xcstrings` and `InfoPlist.xcstrings`.

Rules for code: every user-facing text is a SwiftUI literal or `String(localized: "…", comment: "…")`, one whole
sentence per key, counts as `Int` interpolations (plural forms in the catalog), no logic on displayed text (badges
are translated). Never localize paths, ids, tool or brand names.

Adding or changing strings:
1. `xcodebuild -exportLocalizations -project OneCleanerMac.xcodeproj -localizationPath /tmp/l10n -exportLanguage en`
   (refreshes the catalog from the code).
2. `python3 tools/l10n/export_source.py . /tmp/tr --untranslated` → `source.json` with the new keys.
3. Translate per language following `INSTRUCTIONS.md` (one translator per language pair), then an independent
   reviewer per language following `REVIEW.md` (every generated text is reviewed by a separate LLM).
   New English plural forms go to `en_plurals.json`.
4. `python3 tools/l10n/merge.py . /tmp/tr ru uk de nl es pt-BR fr it ja ko zh-Hans zh-Hant pl tr id vi` — fails
   loudly on missing keys, placeholder mismatches and wrong plural categories.
5. Check screens with `-AppleLanguages "(de)" -demoData YES -snapshotDir <dir>` (German is the longest, Japanese
   and Chinese the narrowest).
