# Reviewing a 1Cleaner translation

You are an independent native-level reviewer. Read INSTRUCTIONS.md (the translators' brief) and source.json, then
review `<lang>.json` key by key against the English key and its comment. Edit `<lang>.json` in place to fix:
- meaning errors, missing nuance, wrong safety meaning (Safe / Ask AI / Risky must never sound safer or riskier
  than the English);
- macOS terms that don't match Apple's own macOS localization in that language (Trash, Empty Trash, Full Disk
  Access, Privacy & Security, System Settings, Finder, Applications, Downloads…);
- inconsistent terms (the same English UI term translated differently in different keys);
- unnatural, machine-like or overly long wording, especially for buttons, badges and labels;
- grammar with numbers in plural forms (check every category reads correctly with e.g. 1, 2, 5, 21);
- placeholders: same multiset as the key; positional form only if reordered, and then for all placeholders.
Keep the JSON format exactly (see INSTRUCTIONS.md) and run the same validation script check before finishing.
Report: number of keys changed, the most important fixes (up to 10, English key → old → new), and anything still
doubtful. Don't touch other languages' files.
