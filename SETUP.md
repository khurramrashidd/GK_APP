# Setting up this project after extracting the zip

Two files are NOT in the zip and must come from elsewhere. Both are
deliberately excluded — see `.gitignore` — but the build fails without the
first one.

## 1. google-services.json  (REQUIRED — build fails without it)

Put it at: `android/app/google-services.json`

Either copy it from your previous project folder, or download a fresh one:

  console.firebase.google.com
    -> khurram-quiz-app
    -> Settings (gear icon) -> Project settings
    -> Your apps -> the Android app
    -> download google-services.json

It must contain `"package_name": "com.khurramrashid.gk_quiz_app"`. If it
names a different package, the build fails with:

    No matching client found for package name 'com.khurramrashid.gk_quiz_app'

## 2. Generated code (*.g.dart)

Not shipped, because it is rebuilt from source. Run:

    flutter pub run build_runner build --delete-conflicting-outputs

Needed whenever the Isar models change, and always on a fresh checkout.

## Full first-build sequence

    flutter pub get
    flutter pub run build_runner build --delete-conflicting-outputs
    flutter analyze
    flutter build apk --release

## Already included (do not go looking for them)

- `lib/firebase_options.dart` — present
- `android/key.properties` — present, holds the release signing password

## Security note about this zip

Because the two files above are inside it, this archive contains your
release signing password and Firebase configuration. Keep it private:
do not attach it to a public issue, upload it anywhere public, or pass it
on. Your Git repository is clean — `.gitignore` excludes both — so this
applies to the zip only.
