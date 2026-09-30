# Terms & Conditions archive

One file per published version of the Terms. The live text lives in
`lib/core/legal/terms_and_conditions.dart`; these are frozen copies of what
users actually agreed to at each version.

## Why keep them

`AppConstants.termsVersion` is the number users' acceptances are recorded
against. If someone accepted version 2, the only way to know what they
agreed to is to have kept version 2. Without an archive that record is gone
the moment the live file is edited — which matters if a term is ever
disputed.

## Versions

| File | termsVersion | What changed |
|------|--------------|--------------|
| `terms_v1.txt` | 1 | Original terms shipped with the app. |
| `terms_v2.txt` | 2 | Added **2.6 Ongoing review after public release** — content is reviewed continuously and may be corrected or withdrawn; users encouraged to report errors. |
| `terms_v3.txt` | 3 | Added **2.7 No exam guarantee** — competitive-exam content is preparation material only; no affiliation with any board or commission. |

## Procedure when changing the Terms

1. Edit `lib/core/legal/terms_and_conditions.dart`.
2. Increment `AppConstants.termsVersion` — existing users are re-prompted to
   accept only when this number rises.
3. Copy the new text to `docs/terms/terms_v<N>.txt`.
4. Add a row to the table above saying what changed and why.

**Never edit an archived file.** They are the record of what was agreed. A
correction to old wording is a new version, not an edit to an old one.

## Honest note on v1 and v2

Archiving began at version 3. `terms_v1.txt` and `terms_v2.txt` were
reconstructed by removing the clauses known to have been added in v2 and v3
respectively. They are accurate as to those clauses, but were not captured
at the time they were live — treat v3 onward as the authoritative record.
