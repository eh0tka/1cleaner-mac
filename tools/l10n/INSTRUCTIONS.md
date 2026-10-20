# Translating 1Cleaner for Mac

1Cleaner is a free macOS disk cleaner for everyone (everyday cleanup: caches, app leftovers, downloads, large
files) with a developer cleaner built in (node_modules, Xcode DerivedData, simulators, Docker, AI agents' data).
Nothing is removed without the person's confirmation; files go to the Trash.

Input: `source.json` — a list of {key, comment, kind}. `key` is the English source text (for `INFOPLIST:*` entries
the English text is in `english`). `comment` explains where it shows and what placeholders mean.

Output: one file per language, `<lang>.json` (lang code exactly: ru, uk, de, nl, es, pt-BR, fr, it, ja, ko,
zh-Hans, zh-Hant, pl, tr, id, vi): a JSON object mapping EVERY key of source.json to its translation:
- kind "plain": a string.
- kind "plural" (one integer `%lld`): an object with the plural categories of the language, each a full string
  with the same placeholders:
  ru, uk, pl: {"one", "few", "many", "other"}; de, nl, es, pt-BR, fr, it, tr: {"one", "other"};
  ja, ko, zh-Hans, zh-Hant, id, vi: a plain string (no plural forms).
- kind "multi" (two or more integers): a plain string. Phrase it so no word must agree with a number
  (e.g. Russian "Очисток: %lld · объектов: %lld · с %@").
Write valid UTF-8 JSON (no comments, no trailing commas). Validate it with `python3 -m json.tool`.

Placeholders (`%@`, `%lld`, `%1$@`, …) must stay exactly as in the key, same count and types. If the word order
of your language needs the placeholders in a different order, switch EVERY placeholder in that string to positional
form (`%1$@`, `%2$lld`, …) numbered by their order in the English key. Keep `…` (one character), `·` separators,
`%lld+`, text in backticks, newlines and trailing punctuation style.

Never translate: 1Cleaner, 1Buck Apps, brand and tool names (Claude, Codex, ChatGPT, Cursor, Docker, Xcode,
Android Studio, Gradle, Homebrew, npm, Ollama, Finder…), file and folder names (node_modules, DerivedData, .build,
~/tmp, /tmp, Library paths), crypto networks and coins.

macOS words must match Apple's own macOS localization in your language exactly: Trash, Empty Trash, Move to Trash,
Put Back, Full Disk Access, Privacy & Security, System Settings, Automation, Finder, Applications, Downloads,
Desktop, Documents, Library, Open Anyway, Apple silicon. Developer terms: use what developers in your language
actually say (often the English word: runtime, build, cache); "simulator", "emulator" as in Xcode/Android docs.

Consistency: translate each recurring UI term once and reuse it everywhere — especially the three safety labels
"Safe" (comes back on its own), "Ask AI" (check with an AI assistant; a short imperative), "Risky" (may lose data
that exists nowhere else), the category names, "Safe List", "Rescan", "Clean…", "Select All".

Style: plain, short, friendly, like Apple's own UI text. Buttons and badges as short as possible. No marketing words.
Texts marked in comments as parts of the AI prompt (the question the user pastes into an AI assistant) are
translated fully; "Answer in English." becomes "Answer in <your language>." written in your language.

Before finishing: run a script that loads source.json and your file and checks (1) every key is present, (2) for
every string/form the multiset of placeholders equals the key's (treat `%1$@` as `%@` etc.), (3) plural objects have
exactly the categories listed above. Fix until clean. Report any key you were unsure about.
