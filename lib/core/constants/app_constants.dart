class AppConstants {
  // App General Strings
  static const String appName = 'GK Quiz Hero';

  // ---------------------------------------------------------------------------
  // ADMIN ACCESS
  // Any signed-in account whose email is in this list unlocks the Admin panel.
  // IMPORTANT: keep this list identical to the `admins` list in firestore.rules,
  // otherwise the UI will show the panel but writes will be rejected by the DB.
  // ---------------------------------------------------------------------------
  /// SUPER ADMINS — hardcoded, and deliberately not editable from inside the
  /// app. These accounts can grant/revoke ordinary admin rights to anyone,
  /// and can never themselves be removed by another admin. This is the
  /// lockout guard: ordinary admins added at runtime (stored in Firestore)
  /// can manage content and other ordinary admins, but can never remove a
  /// super admin or create a new one.
  static const List<String> superAdminEmails = [
    'khurramrashid0786@gmail.com',
  ];

  /// Kept for backwards compatibility with older code paths; super admins are
  /// always admins.
  static const List<String> adminEmails = superAdminEmails;

  // ------------------------------ App info -----------------------------------
  static const String appVersion = '1.0.0';
  static const String companyName = 'Ibtidaa Tech';
  static const String companyEmail = 'ibtidaatech@gmail.com';

  /// Bump this whenever the Terms & Conditions text materially changes.
  /// Every user is re-prompted to accept when their stored accepted version
  /// is lower than this.
  static const int termsVersion = 1;

  // Game/Quiz Configurations
  static const int questionsPerQuiz = 10;

  // ⚠️ PLACEHOLDER — the app isn't published yet. Once your Play Store
  // listing is live, replace this with the real URL (Play Console → your
  // app → the listing's public link, or
  // https://play.google.com/store/apps/details?id=com.khurramrashid.gk_quiz_app
  // once it's live). The web landing page's download button uses this.
  static const String playStoreUrl =
      'https://play.google.com/store/apps/details?id=com.khurramrashid.gk_quiz_app';

  // SharedPreferences key prefix used to store the last-synced version PER DOMAIN.
  // Final key looks like: domain_version_<domainId>
  static const String keyDomainVersionPrefix = 'domain_version_';

  // Cache of the domain catalogue (list of domains + subjects) as JSON.
  static const String keyDomainsCache = 'domains_catalogue_cache';

  static String domainVersionKey(String domainId) =>
      '$keyDomainVersionPrefix$domainId';
}
