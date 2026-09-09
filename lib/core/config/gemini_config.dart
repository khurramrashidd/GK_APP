/// Gemini configuration.
///
/// The AI "Deep Review" feature calls Google's Gemini API directly from the app.
/// Because we are on Firebase's free (Spark) plan we cannot use a Cloud Function
/// to hide the key, so the key ships inside the app. To limit exposure:
///   1. Create the key in Google AI Studio: https://aistudio.google.com/apikey
///   2. Restrict it (Android app restriction + the Generative Language API only).
///   3. Every generated explanation is cached in Firestore and reused for ALL
///      users, so each unique question calls Gemini at most once, ever.
///
/// If you leave the key empty, the app still runs — the AI button will simply
/// tell the user the feature is not configured.
class GeminiConfig {
  static const String apiKey = String.fromEnvironment(
    'GEMINI_API_KEY',
    defaultValue: '', // <-- paste your key here, or pass with --dart-define
  );

  // Model + endpoint. Swap the model name here if you want a different one.
  static const String model = 'gemini-3.7-flash';

  static String get endpoint =>
      'https://generativelanguage.googleapis.com/v1beta/models/$model:generateContent';

  static bool get isConfigured => apiKey.trim().isNotEmpty;
}
