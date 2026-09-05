# GK Quiz App

Offline-first quiz app: Flutter + Firebase Auth + Firestore + Isar cache + Gemini AI explanations.

```
Domain (SSC CGL) -> Subject (Ancient History) -> Questions
```

---

## What you must do before it runs

Work through these in order. Steps 1–5 are required; 6 is optional (AI feature).

### 1. Put your Firebase config back

`google-services.json` is gitignored, so it is **not** in this zip. Copy your
existing file to:

```
android/app/google-services.json
```

(If you lost it: Firebase Console → Project Settings → Your apps → Android → download.)

### 2. Enable sign-in methods

Firebase Console → **Authentication** → Sign-in method → enable:
- **Google**
- **Email/Password**

### 3. Add your SHA-1 fingerprint (required for Google Sign-In on Android)

Google Sign-In silently fails without this. Get your debug fingerprint:

```bash
# macOS / Linux
keytool -list -v -keystore ~/.android/debug.keystore -alias androiddebugkey -storepass android -keypass android

# Windows (PowerShell)
keytool -list -v -keystore $env:USERPROFILE\.android\debug.keystore -alias androiddebugkey -storepass android -keypass android
```

Copy the **SHA1** and **SHA256** values → Firebase Console → Project Settings →
your Android app → *Add fingerprint*. Then **re-download google-services.json**
and replace the one in `android/app/`.

> When you later publish to Play Store you must also add the **release** and
> **Play App Signing** SHA-1 fingerprints, or Google Sign-In breaks in production.

### 4. Publish security rules

Firebase Console → Firestore Database → **Rules** → paste the contents of
`firestore.rules` → Publish.

Your email is already whitelisted as admin in that file. If you add more admins,
update **both** `firestore.rules` and `lib/core/constants/app_constants.dart`.

### 5. Create the Firestore index

The delta-sync query needs one composite index. Easiest path: run the app once,
open a domain, and Firestore will print an error containing a **direct link** —
click it and press Create.

Or deploy it: `firebase deploy --only firestore:indexes` (uses `firestore.indexes.json`).

### 6. (Optional) Gemini API key

Without a key the app runs fine — the AI button just shows "AI not configured".

Get a key at https://aistudio.google.com/apikey, then either:

**Option A — pass at run time (key stays out of your source):**
```bash
flutter run --dart-define=GEMINI_API_KEY=your_key_here
```

**Option B — hardcode it:** edit `defaultValue` in `lib/core/config/gemini_config.dart`.

> The key ships inside the app (Firebase's free Spark plan can't run Cloud
> Functions to hide it). Restrict the key in Google Cloud Console to the
> *Generative Language API* + your Android app. Because every explanation is
> cached in Firestore and shared by all users, each unique question calls Gemini
> **at most once, ever**.

---

## Run it

```bash
flutter pub get
flutter pub run build_runner build --delete-conflicting-outputs   # REQUIRED
dart run flutter_launcher_icons                                   # REQUIRED (app icon)
flutter run
```

**Both marked REQUIRED steps matter.** The question model changed, so the
Isar adapter must be regenerated. And the app icon lives as source files in
`assets/icon/` — nothing shows up on your phone's home screen until you run
the generator once. Re-run just the icon command whenever you replace the
files in `assets/icon/`.

## App icon

Your icon (light background) is at `assets/icon/icon_light.png`, with two more
files alongside it that make Android's icon system work properly:

- `icon_light.png` — flattened, opaque, white background. Used for the classic
  launcher icon and iOS.
- `icon_foreground.png` — the graphic only, transparent background, inset to
  Android's "safe zone" so it doesn't get clipped when a launcher masks it into
  a circle, squircle, or rounded square.
- `icon_monochrome.png` — a white silhouette of the same graphic. Powers
  Android 13+'s themed icon, where the system recolors your icon to match the
  phone's wallpaper-based light/dark theme automatically.
- `play_store_icon_512.png` — **not used by the app at all.** This is the
  512×512 image Play Console asks for separately when you fill out your store
  listing (under "Publishing to Play Store" below) — it's never bundled
  into the APK.

If you ever want a different icon, replace `icon_light.png` in that folder with
your new square artwork (1024×1024 recommended) and re-run
`dart run flutter_launcher_icons`. If your new source already has a transparent
background, you can reuse it directly as `icon_foreground.png` too instead of
regenerating one.

---

## First-time content setup

You start with an empty database, so the home screen will say "No quiz domains yet."

1. Sign in with your admin Gmail (`khurramrashid0786@gmail.com`).
2. Tap the **shield icon** in the app bar → *Domains & Subjects* → **New domain**
   → e.g. `SSC CGL`.
3. Expand it → **Add subject** → e.g. `Ancient History`.
4. → *Upload Questions* → pick domain + subject → **Insert sample** → Upload.
5. Go back home and take the quiz.

### Managing content (every item has a ⋮ menu)

On the *Domains & Subjects* screen, each domain, subject, and sub-level has a
three-dot menu with **Rename**, **Hide/Show**, and **Delete**. Everything
lists alphabetically by name — there's no manual reordering; rename something
if you want it to sort differently.

- **Hide** is the safe, reversible option — the item vanishes from users
  instantly but all its data stays. Unhide it any time. Hidden items show a grey
  `HIDDEN` chip in the admin list.
- **Delete** is permanent and only allowed when the item has **zero** questions
  under it. If it still has questions, the app tells you to hide it instead. This
  protects you from wiping content by accident.

### A third level (optional): Topics / Months / Chapters

A subject can optionally be split into a third tier. You name that tier yourself,
per domain — call it "Topic", "Month", "Chapter", whatever fits.

- On a subject's ⋮ menu → **Add [level]**. The first time, it asks you to name
  the tier for this whole domain, then to name the first entry.
- Subjects with sub-levels show them as a nested, expandable list; each
  sub-level has its own rename/hide/delete menu, and lists alphabetically.
- When uploading, the upload screen shows a third dropdown once you pick a
  subject that has sub-levels — choose which one the batch belongs to.

**One rule:** a subject shows *either* direct questions *or* sub-levels, never
both at once in the app. If a subject already has questions attached directly and
you add a sub-level, those direct questions stop appearing (they stay in the
database). The admin panel warns you before this. See `docs/SCHEMA.md` §3.

### Uploading questions in bulk

Two ways now, both create the domain/subject and bump the version automatically:

**In-app (Admin → Upload Questions):** tap **Choose JSON file** and pick a `.json`
file straight from your phone's storage — no pasting needed, works for
thousands of questions at once. Pasting is still there below it for quick
tests. The file is parsed and validated on-device before anything uploads, and
you'll see a live progress count (`Uploading... 4,200 / 10,000`) during the
write itself.

**From your PC** (`tools/bulk_upload`) — better for truly huge batches or when
your source data is Excel, not JSON:

```bash
cd tools/bulk_upload
npm install
# Firebase Console -> Project Settings -> Service accounts
#   -> Generate new private key -> save here as serviceAccountKey.json

node upload.js --file ../../samples/sample_questions.csv \
               --domain "SSC CGL" --subject "Ancient History" --dry-run

# happy with the preview? drop --dry-run
node upload.js --file yourfile.xlsx --domain "SSC CGL" --subject "Ancient History"

# to load into an optional sub-level (Topic/Month/Chapter), add --sublevel:
node upload.js --file yourfile.json --domain "SSC CGL" \
               --subject "Ancient History" --sublevel "Mauryan Era"
```

It accepts `.xlsx`, `.csv`, and `.json`, validates every row, creates the
domain/subject if missing, writes in batches of 450, and bumps the domain
version so existing installs pull only the new questions.

**Never commit `serviceAccountKey.json`** — it is full admin access to your
project. It is already gitignored.

**Firestore free-tier heads-up:** the Spark plan allows 20,000 document writes
per day, project-wide. One question = one write. A 10,000-question upload uses
half that day's quota by itself — fine for a one-off batch, but if you're
uploading multiple large domains, spread them across different days or expect
a "quota exceeded" error until it resets at midnight Pacific time.

---

## How the offline caching works

- Versioning is **per domain** (not global), so a user who only opens SSC CGL
  never downloads UPSC content.
- First time a domain is opened → downloads all its questions into Isar.
- Later opens → downloads only questions with `version > ` the device's stored
  version. Usually that's zero documents and costs one tiny read.
- No network → the app silently uses the cache. It only errors if nothing is
  cached for that domain yet.
- Questions are upserted by their stable `id`, so re-syncing never duplicates.

## How AI caching works

Local Isar → Firestore → Gemini, in that order, stopping at the first hit. The
generated text is written back to `questions/{id}.aiExplanation`, so the *next*
user anywhere in the world gets it for free.

---

## Project layout

```
lib/
  core/config/gemini_config.dart      Gemini key, model, endpoint
  core/constants/app_constants.dart   admin emails, quiz length, prefs keys
  data/models/                        QuestionModel (Isar), DomainModel, UserProfile
  data/local/isar_service.dart        offline cache + upserts
  data/remote/firestore_service.dart  all Firestore reads/writes
  repositories/                       sync orchestration + AI cache logic
  services/                           auth (Google + email), Gemini REST
  presentation/providers/             Riverpod: profile, domains, quiz
  presentation/screens/               splash, login, home, subject, quiz,
                                      result, review (AI), profile
  presentation/screens/admin/         domains manager, JSON upload
docs/SCHEMA.md                        canonical data schema — read this
samples/                              sample question files (JSON + CSV)
tools/bulk_upload/                    Node script for mass uploads
firestore.rules                       security rules (deploy these!)
firestore.indexes.json                required composite index
```

## Publishing to Play Store

### 1. Generate your upload keystore (once, ever)

Run this on your own machine — never share the output file or password with anyone, including me:

```bash
keytool -genkey -v -keystore ~/upload-keystore.jks -keyalg RSA -keysize 2048 -validity 10000 -alias upload
```

It will ask for a store password, your name, org, city, country — answer honestly, these become
part of your certificate. **Back up `upload-keystore.jks` somewhere safe** (a password manager's
file storage, or an encrypted USB — not GitHub, not Google Drive unencrypted). If you lose it, you
can never publish an update to this app listing again — Play Store would treat your next upload as
a completely different app.

Copy it into the project:
```bash
cp ~/upload-keystore.jks android/upload-keystore.jks
```

Then:
```bash
cp android/key.properties.example android/key.properties
```
and fill in the real password, alias (`upload`), and path in `android/key.properties`.

### 2. Deploy your privacy policy

```bash
npm install -g firebase-tools   # if you haven't already
firebase login
firebase deploy --only hosting
```

Your policy will be live at `https://khurram-quiz-app.web.app/privacy-policy.html` — copy that
URL, you'll paste it into Play Console's store listing form.

### 3. Build the release bundle

```bash
flutter build appbundle --release
```

Output: `build/app/outputs/bundle/release/app-release.aab` — this `.aab` file (not an APK) is what
you upload to Play Console.

**About app size:** the ~80 MB you saw during `flutter run` is the *debug*
build — it bundles the full Dart VM and skips all shrinking. It is not what
users download. Two things keep the real size small:

- **Code + resource shrinking** is enabled for release builds
  (`isMinifyEnabled` / `isShrinkResources` in `android/app/build.gradle.kts`),
  which strips unused code and resources.
- **The App Bundle** you upload lets Google Play generate a per-device APK that
  contains only that phone's screen density and CPU architecture — you don't
  need to configure ABI splits yourself; the bundle does it. A typical user
  downloads roughly **15-25 MB**, not 80.

To see a realistic size locally, build a universal APK and check it:
`flutter build apk --release` (still larger than what Play serves, because it
contains every architecture in one file).

### 4. Upload to Play Console

Console → your app → **Testing → Closed testing** → create a track → upload the `.aab` → add your
12 testers' email addresses → publish to that track. This satisfies Google's mandatory closed-test
requirement for new personal accounts (12 testers, 14 consecutive days) before production access
unlocks.

### Every future update

1. Bump the number after `+` in `pubspec.yaml` (e.g. `1.0.0+1` → `1.0.0+2`)
2. `flutter build appbundle --release`
3. Upload the new `.aab` to Play Console → rolls out to everyone automatically over the next
   day or so via auto-update. No testing wait required for updates once you're in production.

## Troubleshooting

### "Dependency ':x' requires ... compile against version 36 or later"

A Flutter plugin is pinning an old `compileSdk` while one of its own
dependencies now needs a newer one. `file_picker` did exactly this for a long
time. Two protections are already in place:

- `pubspec.yaml` uses a `file_picker` version where this is fixed.
- `android/build.gradle.kts` has a safety-net block that forces **every** plugin
  subproject up to `compileSdk 36`, so one stale plugin can't break your build.

If it ever reappears with a different plugin, run `flutter clean`, then
`flutter pub get`, then build again. The Gradle block prints
`Raised compileSdk to 36 for :<plugin>` when it kicks in.

### Google Sign-In does nothing / spins forever

Your SHA-1 fingerprint isn't registered. See step 3 above. This is by far the
most common cause.

### "The query requires an index"

Firestore needs a composite index for the delta-sync query. The error message
contains a direct link — open it and click Create, then wait for the status to
turn **Enabled** (not "Building") and restart the app. Field names are
case-sensitive: it must be `domainId`, not `domainID`.

## Player features

Beyond taking quizzes, signed-in users get:

- **Answer reveal during a quiz.** Pick an option, then tap **Show answer** to
  see correct/wrong + explanation for that question. Revealing locks that
  answer (matches real-test feel). Optional and per-question — skip it and the
  quiz behaves normally.
- **Negative marking toggle** on the pre-quiz start screen. On → UPSC Prelims
  scheme (+2 correct, −0.66 wrong). Off → 0 for wrong. Score never goes below 0.
- **Full answer review** at the end — every question with your answer vs the
  correct one and the explanation, plus optional AI deep-dive.
- **Dark mode** — toggle in Profile, remembers your choice.
- **Bookmarks** — save any question (bookmark icon in the quiz), then
  **revise all saved questions** as their own quiz.
- **History & stats** — every finished quiz with per-quiz accuracy and an
  overall accuracy summary.
- **Daily streak** — practice on consecutive days to build a streak (shown in
  the navigation drawer).
- **Leaderboard** — top scorers by total points. Privacy-safe: a separate
  `leaderboard` collection stores **only** display name + score, never any
  personal data.
- **Share** — share your rank/score to any app via the native share sheet.
- **Search** — find any domain, subject, or topic fast (search icon in the
  app bar).
- **Navigation drawer** — swipe from the left or tap the menu icon for quick
  access to all of the above.

## Global error handling

Any error anywhere in the app is caught by three layers (main.dart) and
logged to Firestore's `error_logs` collection — instead of a crash or a red
error screen, users see a plain "Something went wrong, this has already been
reported" message. Admin > Error logs lists every one, with the full stack
trace, which user hit it, platform, and app version.

**Known gap:** logging requires the user to be signed in (the write rule is
`isSignedIn()`, to stop it being an open spam target). An error on the
login/sign-in screen itself, before authentication completes, won't reach
Firestore — it still prints to a dev console via `debugPrint`, just not to
the dashboard. This is a deliberate scope boundary, not a bug: enabling
unauthenticated writes would need Firebase Anonymous Auth or an open rule,
both bigger changes than this warranted.

## Bulk show/hide for domains and subjects

Admin > Domains & Subjects now has an app-bar menu (the eye icon) for
whole-app bulk visibility: show/hide every domain at once, or every subject
across every domain at once. Each domain's own three-dot menu also gets
"Show/hide all subjects here", scoped to just that domain. Individual
per-item hide/show (the original feature) still works exactly as before —
these are additions, not replacements.

## Building an APK to share before Play Store

```bash
flutter build apk --release
```
Output: `build/app/outputs/flutter-apk/app-release.apk` — send that file to
anyone; they install it directly (they may need to allow "install from
unknown sources" once). This is separate from the `.aab` you upload to Play.

For smaller per-device files, `flutter build apk --split-per-abi` produces
one APK per CPU architecture; `app-arm64-v8a-release.apk` covers almost all
modern phones.

## Admin rights, users and export

- **Super admins** are hardcoded in `AppConstants.superAdminEmails` AND in
  `firestore.rules` (keep both in sync). They can never be demoted from
  inside the app — this is the guard against an admin lockout.
- **Ordinary admins** are granted at runtime: Admin > *Users & admin rights*
  > toggle. Only a super admin sees that toggle. Rights are stored as
  `isAdminUser` on the user's own profile, and the security rules explicitly
  forbid a user from setting that field on themselves.
- **Export**: Admin > *Export questions as JSON*, per domain or per subject.
  The output matches the bulk-upload format, so exports round-trip.

## Bulk upload across many subjects

Admin > *Bulk upload (multi-subject)* takes ONE JSON file whose questions
each carry `domain` and `subject`, and files every question automatically:

```json
[
  { "domain": "UPSC", "subject": "History", "question": "...", "options": ["..."],
    "correctOptionIndex": 0, "explanation": "...", "difficulty": 1, "classLevel": 8 }
]
```

Matching is case-insensitive (slugified), so `History` / `HISTORY` /
`hISTory` all land in the same subject. Duplicate question text within a
subject is skipped automatically, so re-running a file is safe. Unknown
domain/subject pairs are **reported, not silently created** — turn on
"create missing" if you do want them created (hidden).

## Terms & Conditions

Full text lives in `lib/core/legal/terms_and_conditions.dart`. Acceptance is
stored per user as a **version number**, not a boolean:

- new users accept during first run;
- existing users who never accepted get the gate on next launch;
- **bump `AppConstants.termsVersion` whenever you change the text** and every
  user is re-prompted automatically.

Declining signs the user out — there's no path into the app without
accepting. Two separate checkboxes are required: the Terms themselves, and a
specific acknowledgement that questions are AI-generated and may contain
errors.

> This is a thorough good-faith draft, not legal advice. Have a lawyer review
> it before public launch, particularly regarding India's DPDP Act since the
> app collects personal data and optional location.

## Optional location

Used only to show local date/time and place in the drawer. Entirely optional:
declining leaves an "Enable location" button the user can tap later, and
nothing is stored. Permissions are declared as coarse + fine in the Android
manifest; coarse is all the app actually needs.

## Monetisation readiness

No ads are integrated, but the structure supports adding them without
rework: quiz flow, result screens and the home grid are all separate widgets
with their own build methods, so banner/interstitial slots can be inserted at
those seams. A premium "remove ads" flag would sit naturally as another
boolean on `UserProfile` alongside `isAdminUser`, gated the same way.

## Shared subjects across domains

A subject can draw from ONE question pool shared by every domain that uses
it. Turn it on per subject: Admin > Domains & Subjects > (subject menu) >
**Share across domains**.

- **Matching is by slug id**, which is the lowercased name — so `History`,
  `HISTORY`, and `hISTory` all resolve to `history` and match each other.
  Case is handled for you; no need to keep names typed identically.
- **Sharing is mutual.** Marking `History` shared under UPSC merges it only
  with domains that have ALSO marked their `History` shared. One domain can
  never pull in another's questions unilaterally.
- **Sub-levels merge.** If UPSC > History has Ancient/Medieval and Academics
  > History has Class 6/Class 7, a shared subject shows all four in one
  combined list, deduplicated by id and sorted alphabetically.
- Shared subjects show a **SHARED** badge in the admin panel and a small hub
  icon to users.

**Trade-off — shared subjects are online-only.** Normal subjects cache to
Isar per-domain (keyed on domainId plus a version counter on the domain
document). A shared question belongs to several domains at once, which that
cache can't represent, so shared subjects read straight from Firestore. Only
subjects you explicitly share give this up; everything else keeps working
offline exactly as before.

## Question counts in the admin panel

The **Domains & Subjects** screen now shows how many questions exist at every
level:

- A banner at the top shows the **total across the whole app**.
- Each domain's row shows its own total (e.g. "142 questions") next to its
  subject count — always loaded, since there are only ~30 domains.
- Each subject's row shows its own total too — but only once you **expand**
  that domain. Loading all ~540 subjects' counts at once (across every
  domain) isn't worth firing that many queries before you've even looked at
  them, so they load lazily as you open each domain.

All of this uses Firestore's `count()` aggregation queries, which count
matching documents server-side without downloading them — cheap and fast
even as your question bank grows into the thousands.

## Web admin console

The web build is admin-only. Anyone who signs in but isn't in
`AppConstants.adminEmails` sees a plain "download the app" page instead —
there's no quiz-playing on web at all, by design (see below for why).

### One-time setup (you need to do this before it'll run)

**1. Register a Web app in Firebase.** Firebase Console → your project →
Project Settings (gear icon) → General tab → scroll to "Your apps" → click
**Add app** → choose **Web** (`</>`) → give it a nickname like "GK Quiz Web
Admin" → **Register app**. It'll show you a config object — copy it, you need
two values from it in the next step.

**2. Fill in `lib/firebase_options.dart`.** Find the `static const
FirebaseOptions web = FirebaseOptions(...)` block near the bottom — it has
two placeholders, `REPLACE_WITH_WEB_API_KEY` and `REPLACE_WITH_WEB_APP_ID`.
Paste in the real `apiKey` and `appId` from the config Firebase just showed
you. Everything else in that block (project id, storage bucket, auth domain)
is already correct — Firebase project-level values are the same across all
your apps.

**3. Add your Play Store URL** once it's live — `AppConstants.playStoreUrl`
in `lib/core/constants/app_constants.dart` is a working placeholder built
from your `applicationId`, so it'll start working automatically the moment
your listing goes live. No code change needed unless your package name ever
changes.

### Sign-in on web

Uses the same `users/{uid}` accounts as mobile — sign in with the same
Google account or email/password you use as admin there. Google sign-in on
web uses Firebase's own popup flow (`signInWithPopup`), not the
`google_sign_in` plugin's web path — simpler, and needs no extra OAuth
client setup beyond what's already enabled for mobile. It'll only work on a
domain listed under Firebase Console → Authentication → Settings →
Authorized domains — `localhost` and your Firebase Hosting domain
(`<project-id>.web.app` / `.firebaseapp.com`) are there by default, so
deploying to the hosting you already have set up (next section) just works.

### Build & deploy

```bash
flutter build web
firebase deploy --only hosting
```

That's it — same one-command deploy you already use for the privacy policy.
`firebase.json`'s hosting now points at `build/web` (the Flutter web output)
instead of the old `public/` folder, and `web/privacy-policy.html` gets
copied into that output automatically by `flutter build web`, so it's still
reachable at `/privacy-policy.html` on the same site as before — nothing
about the Play Console privacy-policy link needs to change.

### Why quiz-playing isn't on web

Your offline sync uses **Isar** (`isar: ^3.1.0`), which compiles to native
binaries via `dart:ffi` — a mechanism that doesn't exist in a browser at
all, not even as a "works but slower" fallback. Rather than swap out a
database your whole mobile app depends on right before launch, the web
build is scoped to admin tools + a download page, which never touch local
caching in the first place. Two files (`question_model.dart`,
`isar_service.dart`) automatically switch to a plain-Dart, Isar-free version
when compiling for web (Dart's conditional export mechanism) — everything
else in the app imports them exactly as before and doesn't need to know or
care which version got picked.

## 1v1 Quiz Battle (multiplayer)

Reachable from the drawer. Two players answer the same 10 questions; higher
score wins. No negative marking here — kept simple, it's a race, not an exam.

- **Create & invite** — generates a 6-character code to share (native share
  sheet included). The other person enters it under "Have an invite code?".
- **Find a random opponent** — looks for anyone else waiting in the same
  subject and joins instantly; if nobody's waiting, you become the one
  waiting, and the next matching random-searcher joins you.
- Both flows land in the same waiting room, which is really just "is there
  a second player yet?" — the moment there is, both screens move on
  automatically, no polling.
- Once in a match: pick an option, it locks immediately and auto-advances —
  no going back, no answer reveal mid-match. Both players' progress (`3/10`
  etc.) updates live for each other. The result screen appears the instant
  you finish; it just waits quietly if your opponent hasn't caught up yet.

**No Cloud Functions, no new Firestore index.** Matching two random players
is done with a Firestore *transaction* (whoever's write lands first claims
the open match; the loser of that race just creates their own and waits) —
this keeps the free Spark plan working, same as everywhere else in this app.
All match queries are equality-only (no `orderBy` combined with `where`), so
none of them need a manual composite index either.

## Reports & notifications

Any signed-in user can tap **"Report an issue"** on a question (in the quiz
itself, or in AI Review) to flag something wrong — a bad answer key, a typo,
an unclear question. It shows up for admins under **Admin → Reports**, with an
Open/Resolved toggle and a badge showing how many are waiting.

When you resolve one (with a short note on what you did), the reporter sees it
the next time they open the app: a badge appears on the bell icon in the home
app bar, and **My Reports** shows the resolution note.

**This is in-app notification, not push.** True push notifications need
either Cloud Functions (which require the paid Blaze plan) or a fair amount of
native FCM setup. The bell badge is Firestore-only — free, simple, and still
updates live while the app is open, since it's a Firestore stream, not a
one-time fetch. If you outgrow this later (e.g. you want a notification even
when the app is closed), that's a separate, addable feature — ask.

## Known limits / next steps

- Admin check is an email whitelist. Fine for one admin; move to Firebase
  **custom claims** if you ever add staff you don't fully trust.
- Gemini key is client-side. Move to a Cloud Function when you upgrade to Blaze —
  only `GeminiService` changes.
- No per-user quiz history or leaderboard yet, only a cumulative score.
- Web is not configured (`firebase_options.dart` throws for web).
