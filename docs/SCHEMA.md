# Data Schema — GK Quiz App

This is the canonical schema. Use it for every question file you ever create.

The content hierarchy is:

```
Domain  ->  Subject  ->  (optional) Sub-level  ->  Questions
 SSC CGL     Ancient History    Mauryan Era          ...
```

The **sub-level** is optional and per-subject. A subject with no sub-levels holds
questions directly (the original, simplest shape). A subject that has sub-levels
holds questions under each sub-level instead. The sub-level's *label* (what it's
called — "Topic", "Month", "Chapter"…) is chosen by the admin **per domain**, so
every subject in the same domain uses consistent wording.

---

## 1. Firestore collections

### `domains/{domainId}`
The catalogue. One document per domain; subjects (and their sub-levels) are
embedded.

| Field | Type | Notes |
|---|---|---|
| `id` | string | slug, e.g. `ssc-cgl` |
| `name` | string | display name, e.g. `SSC CGL` |
| `order` | number | sort order on the home screen |
| `isActive` | boolean | `false` hides it from users (data kept) |
| `version` | number | **content version.** Bumped on every upload |
| `subLevelLabel` | string \| null | admin's name for the 3rd tier (e.g. `Topic`) |
| `subjects` | array | see below |

Each **subject** in `subjects`:

| Field | Type | Notes |
|---|---|---|
| `id` | string | slug |
| `name` | string | display name |
| `order` | number | sort order |
| `isActive` | boolean | `false` hides it (data kept) |
| `subLevels` | array | empty = questions attach directly to the subject |

Each **sub-level** in `subLevels`:

| Field | Type | Notes |
|---|---|---|
| `id` | string | slug |
| `name` | string | display name |
| `order` | number | sort order |
| `isActive` | boolean | `false` hides it (data kept) |

Example:
```json
{
  "id": "ssc-cgl",
  "name": "SSC CGL",
  "order": 0,
  "isActive": true,
  "version": 4,
  "subLevelLabel": "Topic",
  "subjects": [
    {
      "id": "ancient-history", "name": "Ancient History", "order": 0,
      "isActive": true,
      "subLevels": [
        { "id": "mauryan-era", "name": "Mauryan Era", "order": 0, "isActive": true },
        { "id": "gupta-era",   "name": "Gupta Era",   "order": 1, "isActive": true }
      ]
    },
    {
      "id": "indian-polity", "name": "Indian Polity", "order": 1,
      "isActive": true, "subLevels": []
    }
  ]
}
```
Here "Ancient History" is split into Topics; "Indian Polity" holds questions
directly.

### `questions/{questionId}`
One document per question. Flat collection — scales to hundreds of thousands.

| Field | Type | Notes |
|---|---|---|
| `id` | string | same as the document id |
| `domainId` / `domainName` | string | denormalised for offline display |
| `subjectId` / `subjectName` | string | denormalised for offline display |
| `subLevelId` / `subLevelName` | string \| null | **null** = attached directly to the subject |
| `question` | string | the question text |
| `options` | array of string | 2–8 options |
| `correctOptionIndex` | number | **0-based** index into `options` |
| `explanation` | string | short authored explanation (optional) |
| `aiExplanation` | string \| null | Gemini output, filled lazily, shared by all users |
| `difficulty` | number | 1 easy, 2 medium, 3 hard |
| `tags` | array of string | free-form |
| `isActive` | boolean | `false` hides the question |
| `version` | number | the domain version at which it was added/updated |

### `users/{uid}`
| Field | Type | Notes |
|---|---|---|
| `email`, `displayName` | string | from the auth provider |
| `photoUrl` | string \| null | Google account photo, if any |
| `name` | string | **required** |
| `state` | string | **required** |
| `dob` | string \| null | `yyyy-MM-dd` |
| `mobile`, `city`, `pincode` | string \| null | optional |
| `gender` | string \| null | Male / Female / Other |
| `totalScore` | number | 10 points per correct answer |
| `profileComplete` | boolean | true once name + state are filled |

### `reports/{reportId}`
A user-filed "something's wrong with this question" report. Filled in from the
`Report an issue` button on a question; visible to the reporter (their own)
and to admins (all of them).

| Field | Type | Notes |
|---|---|---|
| `questionId`, `questionText` | string | snapshot at report time |
| `domainId`/`Name`, `subjectId`/`Name`, `subLevelId`/`Name` | string | snapshot of the question's path |
| `reportedByUid`, `reporterName`, `reporterEmail` | string | who filed it |
| `reason` | string | one of `ReportModel.reasons` |
| `note` | string | optional free-text detail |
| `status` | string | `open` or `resolved` |
| `createdAt`, `resolvedAt` | timestamp | |
| `resolutionNote` | string \| null | admin's explanation, shown to the reporter |
| `seenByReporter` | boolean | drives the notification badge — reset to `false` whenever a report is resolved, set `true` once the reporter opens *My Reports* |

Notification is in-app only (a badge on the bell icon), not push — this keeps
the app on Firebase's free plan. See README's "Reports & notifications"
section for the reasoning.

---

## 2. The question file you author

Same format as before — you do **not** put `domainId`/`subjectId`/`subLevelId`
in the file. Those are applied at upload time from the domain, subject, and
(if the subject has them) sub-level you pick in the upload screen or pass to the
script.

```json
[
  {
    "question": "Who founded the Maurya Empire?",
    "options": ["Chandragupta Maurya", "Ashoka", "Bindusara", "Bimbisara"],
    "correctOptionIndex": 0,
    "explanation": "Chandragupta Maurya founded the empire in 322 BCE.",
    "difficulty": 1,
    "tags": ["mauryan", "ancient-india"]
  }
]
```

Required: `question`, `options` (>= 2), `correctOptionIndex` (0-based).
Optional: `explanation`, `difficulty` (default 1), `tags`, `isActive`, `id`.

**On `id`:** leave it out and one is generated. Supply your own stable id if you
want to *re-upload and update* a question later instead of creating a duplicate.

### Excel/CSV format
Header row required, one question per row:

| question | optionA | optionB | optionC | optionD | correct | explanation | difficulty | tags |
|---|---|---|---|---|---|---|---|---|
| Who founded the Maurya Empire? | Chandragupta Maurya | Ashoka | Bindusara | Bimbisara | A | ...in 322 BCE. | 1 | mauryan, ancient-india |

`correct` accepts `A/B/C/D`, `1/2/3/4`, or a 0-based index. `tags` is comma-separated.

See `samples/sample_questions.json` and `samples/sample_questions.csv`.

---

## 3. Important rule about mixing direct + sub-level questions

The app shows **one path at a time** for a subject:

- Subject with **no** sub-levels → tapping it starts a quiz from its direct
  questions.
- Subject **with** sub-levels → tapping it shows the sub-level list first;
  questions are read from the chosen sub-level.

So if a subject already has questions attached directly and you then add a
sub-level to it, those direct questions stop appearing in the app (they're still
in the database — just unreachable through browsing). The admin panel warns you
before this happens. To fix it, re-upload those questions under a sub-level. Pick
one shape per subject and stick with it.

---

## 4. How the offline sync works

Per-domain versioning (so a user who only cares about SSC CGL never downloads
UPSC content):

1. Device stores `domain_version_<domainId>` in SharedPreferences.
2. When a domain is opened, the app reads `domains/{id}.version` from Firestore.
3. If server version > local version (or nothing is cached yet), it fetches
   `questions where domainId == X and version > localVersion`.
4. Results are **upserted** into Isar by their string `id`, then the local
   version is advanced.
5. Offline with a populated cache → the app just uses the cache silently.

Uploading always bumps the domain version, so every existing install picks up
exactly the new questions on its next open — nothing else. Hiding/renaming/
reordering a domain, subject, or sub-level is a change to the `domains`
document, which the app re-reads on next launch (or pull-to-refresh on Home).

---

## 5. AI explanation caching

When a user taps "Explain with AI" on a question:

1. Already on the local Isar row? → show it. **No network.**
2. Else read `questions/{id}.aiExplanation` from Firestore — another user may
   have generated it already → cache locally, show it. **No Gemini call.**
3. Else call Gemini, write the result back to `questions/{id}.aiExplanation`,
   cache locally, show it.

So each unique question costs **at most one Gemini call, ever, across all users**.

---

# Versioning

Three numbers, and they move independently. Getting them confused is the
easiest way to ship a release nobody receives.

## 1. `pubspec.yaml` → `version: 1.3.0+4`

`versionName+versionCode`. This is what ends up in the Android manifest.

**Play Store rejects any upload whose versionCode is not higher than the
last one.** It reads that number from here — NOT from app_constants.dart.
Forgetting this is the classic "why won't Play accept my AAB" mistake.

## 2. `AppConstants.appBuildNumber` → `4`

What the in-app update check compares. A user sees the update banner only
when the build you publish in Admin > Publish app update is HIGHER than the
`appBuildNumber` compiled into the APK they are running.

Keep it equal to the versionCode in pubspec. They serve different systems
(Play vs your own updater) but there is no reason for them to disagree.

## 3. `AppConstants.termsVersion` → `3`

Completely separate. Raise it ONLY when the Terms text changes; raising it
re-prompts every existing user to accept. Never bump it just because the app
version changed — that would nag users for no reason.

## The convention in use on THIS project

The version NAME stays where it is — currently `1.3.0`. Only the build number moves, +1 per
release. That is valid: Play Store requires the versionCode to increase but
places no such requirement on the versionName, and two releases may share a
name.

**Never move the version name backwards.** Users and Play both read it as
progress; going 1.3.0 -> 1.0.0 looks like a downgrade even when the build
number rose. If it is not being bumped, leave it exactly as it is.

Worth knowing what you give up: the version name is the only part a user
ever sees (in About, and on a Play listing). Held constant, it tells them
nothing about which release they are on — the build number becomes the only
way to identify a version, and that lives in `pubspec.yaml`, not on screen.
If that ever becomes awkward, switching to `1.3.<build>` is a one-line
change and costs nothing.

The update banner is unaffected either way: it shows whatever version name
you type into Admin > Publish app update, not this constant.

## What to bump, and when

On this project: leave the version name alone, add 1 to the build number.

If you later decide to version names properly, the usual scheme is:

| Change | versionName | build / versionCode |
|---|---|---|
| Bug fixes only | 1.3.0 → 1.3.1 | +1 |
| New features | 1.3.0 → 1.4.0 | +1 |
| Major rework | 1.3.0 → 2.0.0 | +1 |

**The build number ALWAYS increases by one, every single release, no
exceptions** — including a rebuild of the same features. It is the only
number both Play Store and your own updater use to decide "is this newer".

## Release checklist

1. Bump `version:` in `pubspec.yaml` (both parts)
2. Bump `appBuildNumber` and `appVersion` in `app_constants.dart` to match
3. Bump `termsVersion` ONLY if the Terms text changed, and archive the old
   text in `docs/terms/` (see the README there)
4. `flutter analyze` — fix any errors
5. `flutter build apk --release`
6. Upload to a GitHub release tagged with the version name
7. Admin → Publish app update → enter the same build number and version
