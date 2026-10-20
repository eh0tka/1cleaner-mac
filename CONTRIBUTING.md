# Contributing

Thanks for helping make 1Cleaner better.

**Issues are the best way to help:** a bug, a wrong safety label, a cache or tool 1Cleaner misses, or anything it
offers that it shouldn't. For anything that could remove the wrong files, see [SECURITY.md](SECURITY.md).

**Pull requests** are welcome for small, focused changes, such as a new known cache location in
`OneCleanerMac/Scanners/KnownLocations.swift` or a translation fix. Please open an issue first for anything
bigger, so we can agree on the approach.

By submitting a pull request you agree that your contribution is licensed under GPL-3.0, and you grant the
maintainer the right to also distribute it under other terms (for example in an App Store build of 1Cleaner).

Ground rules for code (details in [AGENTS.md](AGENTS.md)):
- Every file-based removal goes to the Trash after the confirmation; never delete scanned files directly.
- Nothing is preselected; safety labels come only from `OneCleanerMac/Core/Safety.swift`.
- No analytics, accounts or third-party dependencies, and no network calls besides Check for Updates and Install and
  Relaunch, which run only when the person asks.
- Every user-facing text is localized (`String(localized:comment:)`); new strings need all 17 languages.
