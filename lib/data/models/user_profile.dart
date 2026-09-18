import 'package:cloud_firestore/cloud_firestore.dart';
/// The user profile stored at users/{uid}.
///
/// Required fields (enforced in the UI): name, state.
/// Optional: dob, mobile, city, pincode, gender.
class UserProfile {
  final String uid;
  final String email;
  final String displayName;
  final String? photoUrl; // from Google Sign-In, if the account has one

  final String name;   // required
  final String state;  // required
  final String? dob;   // ISO yyyy-MM-dd
  final String? mobile;
  final String? city;
  final String? pincode;
  final String? gender; // 'Male' | 'Female' | 'Other' | null

  final int totalScore;
  final bool profileComplete;

  /// Daily-practice streak. lastActiveDate is an ISO yyyy-MM-dd string.
  /// Latest Terms & Conditions version this user accepted (0 = never).
  final int acceptedTermsVersion;

  /// When this user last opened the "what's new" feed. Anything newer counts
  /// as unseen and drives the badge.
  final DateTime? lastSeenUpdatesAt;

  /// Domain ids this user follows. Followed domains are surfaced first on
  /// the home screen and weighted in the Reels feed.
  final List<String> followedDomains;

  /// Unique public handle other players can search for. Null until the user
  /// picks one. Stored as typed; uniqueness is enforced on the lowercase
  /// form via the `usernames` collection.
  final String? username;

  /// When the handle was last changed — changes are limited to once per 30
  /// days so handles stay stable enough for people to find each other.
  final DateTime? usernameChangedAt;

  /// Optional, only stored if the user granted location permission. Cleared
  /// if they later decline — we never keep a stale location.
  final double? latitude;
  final double? longitude;
  final String? locationName; // e.g. "Mumbai, Maharashtra"
  final String? timeZoneName; // e.g. "IST"

  /// Ordinary admin rights granted from inside the app by another admin.
  /// Super admins (AppConstants.superAdminEmails) are admins regardless.
  final bool isAdminUser;

  /// Paid/ad-free user. Not wired to any billing yet — the field exists so
  /// premium can be switched on later without a data migration, and so an
  /// admin can grant it manually (e.g. testers, early supporters).
  final bool isPremium;

  final int currentStreak;

  /// Lifetime count of questions answered. Shown on the friends list so
  /// people can see what friends are actually doing.
  final int questionsAnswered;

  /// Lifetime correct answers. Paired with questionsAnswered to give
  /// accuracy. Starts at 0 for everyone — there is no historical record to
  /// reconstruct it from, so the accuracy board begins fresh.
  final int correctAnswers;
  final int longestStreak;
  final String? lastActiveDate;

  UserProfile({
    required this.uid,
    required this.email,
    required this.displayName,
    this.photoUrl,
    this.name = '',
    this.state = '',
    this.dob,
    this.mobile,
    this.city,
    this.pincode,
    this.gender,
    this.totalScore = 0,
    this.profileComplete = false,
    this.acceptedTermsVersion = 0,
    this.lastSeenUpdatesAt,
    this.followedDomains = const [],
    this.username,
    this.usernameChangedAt,
    this.latitude,
    this.longitude,
    this.locationName,
    this.timeZoneName,
    this.isAdminUser = false,
    this.isPremium = false,
    this.currentStreak = 0,
    this.questionsAnswered = 0,
    this.correctAnswers = 0,
    this.longestStreak = 0,
    this.lastActiveDate,
  });

  factory UserProfile.fromMap(String uid, Map<String, dynamic> m) => UserProfile(
        uid: uid,
        email: (m['email'] ?? '') as String,
        displayName: (m['displayName'] ?? '') as String,
        photoUrl: m['photoUrl'] as String?,
        name: (m['name'] ?? '') as String,
        state: (m['state'] ?? '') as String,
        dob: m['dob'] as String?,
        mobile: m['mobile'] as String?,
        city: m['city'] as String?,
        pincode: m['pincode'] as String?,
        gender: m['gender'] as String?,
        totalScore: (m['totalScore'] ?? 0) as int,
        questionsAnswered: (m['questionsAnswered'] as num?)?.toInt() ?? 0,
        correctAnswers: (m['correctAnswers'] as num?)?.toInt() ?? 0,
        profileComplete: (m['profileComplete'] ?? false) as bool,
        acceptedTermsVersion: (m['acceptedTermsVersion'] ?? 0) as int,
        lastSeenUpdatesAt: m['lastSeenUpdatesAt'] is Timestamp
            ? (m['lastSeenUpdatesAt'] as Timestamp).toDate()
            : null,
        followedDomains:
            List<String>.from(m['followedDomains'] ?? const <String>[]),
        username: m['username'] as String?,
        usernameChangedAt: m['usernameChangedAt'] is Timestamp
            ? (m['usernameChangedAt'] as Timestamp).toDate()
            : null,
        latitude: (m['latitude'] as num?)?.toDouble(),
        longitude: (m['longitude'] as num?)?.toDouble(),
        locationName: m['locationName'] as String?,
        timeZoneName: m['timeZoneName'] as String?,
        isAdminUser: (m['isAdminUser'] ?? false) as bool,
        isPremium: (m['isPremium'] ?? false) as bool,
        currentStreak: (m['currentStreak'] ?? 0) as int,
        longestStreak: (m['longestStreak'] ?? 0) as int,
        lastActiveDate: m['lastActiveDate'] as String?,
      );

  Map<String, dynamic> toMap() => {
        'email': email,
        'displayName': displayName,
        'photoUrl': photoUrl,
        'name': name,
        'state': state,
        'dob': dob,
        'mobile': mobile,
        'city': city,
        'pincode': pincode,
        'gender': gender,
        'totalScore': totalScore,
        'profileComplete': profileComplete,
        'acceptedTermsVersion': acceptedTermsVersion,
        'followedDomains': followedDomains,
        'username': username,
        'usernameLower': username?.toLowerCase(),
        'latitude': latitude,
        'longitude': longitude,
        'locationName': locationName,
        'timeZoneName': timeZoneName,
        'isAdminUser': isAdminUser,
        'isPremium': isPremium,
        'currentStreak': currentStreak,
        'longestStreak': longestStreak,
        'lastActiveDate': lastActiveDate,
      };

  UserProfile copyWith({
    String? displayName,
    String? photoUrl,
    String? name,
    String? state,
    String? dob,
    String? mobile,
    String? city,
    String? pincode,
    String? gender,
    int? totalScore,
    bool? profileComplete,
    int? acceptedTermsVersion,
    DateTime? lastSeenUpdatesAt,
    List<String>? followedDomains,
    String? username,
    DateTime? usernameChangedAt,
    double? latitude,
    double? longitude,
    String? locationName,
    String? timeZoneName,
    bool? isAdminUser,
    bool? isPremium,
    bool clearLocation = false,
    int? currentStreak,
    int? questionsAnswered,
    int? correctAnswers,
    int? longestStreak,
    String? lastActiveDate,
  }) {
    return UserProfile(
      uid: uid,
      email: email,
      displayName: displayName ?? this.displayName,
      photoUrl: photoUrl ?? this.photoUrl,
      name: name ?? this.name,
      state: state ?? this.state,
      dob: dob ?? this.dob,
      mobile: mobile ?? this.mobile,
      city: city ?? this.city,
      pincode: pincode ?? this.pincode,
      gender: gender ?? this.gender,
      totalScore: totalScore ?? this.totalScore,
      profileComplete: profileComplete ?? this.profileComplete,
      acceptedTermsVersion: acceptedTermsVersion ?? this.acceptedTermsVersion,
      lastSeenUpdatesAt: lastSeenUpdatesAt ?? this.lastSeenUpdatesAt,
      followedDomains: followedDomains ?? this.followedDomains,
      username: username ?? this.username,
      usernameChangedAt: usernameChangedAt ?? this.usernameChangedAt,
      latitude: clearLocation ? null : (latitude ?? this.latitude),
      longitude: clearLocation ? null : (longitude ?? this.longitude),
      locationName: clearLocation ? null : (locationName ?? this.locationName),
      timeZoneName: clearLocation ? null : (timeZoneName ?? this.timeZoneName),
      isAdminUser: isAdminUser ?? this.isAdminUser,
      isPremium: isPremium ?? this.isPremium,
      currentStreak: currentStreak ?? this.currentStreak,
      questionsAnswered: questionsAnswered ?? this.questionsAnswered,
      correctAnswers: correctAnswers ?? this.correctAnswers,
      longestStreak: longestStreak ?? this.longestStreak,
      lastActiveDate: lastActiveDate ?? this.lastActiveDate,
    );
  }

  /// Days remaining before the public handle can be changed again.
  /// 0 means a change is allowed right now.
  ///
  /// Handles are rate-limited to one change per 30 days so that a username
  /// someone shared stays valid long enough to be useful for finding them.
  int get daysUntilUsernameChangeAllowed {
    if (usernameChangedAt == null) return 0;
    final elapsed = DateTime.now().difference(usernameChangedAt!).inDays;
    return elapsed >= 30 ? 0 : 30 - elapsed;
  }
}
