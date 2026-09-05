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

  /// Optional, only stored if the user granted location permission. Cleared
  /// if they later decline — we never keep a stale location.
  final double? latitude;
  final double? longitude;
  final String? locationName; // e.g. "Mumbai, Maharashtra"
  final String? timeZoneName; // e.g. "IST"

  /// Ordinary admin rights granted from inside the app by another admin.
  /// Super admins (AppConstants.superAdminEmails) are admins regardless.
  final bool isAdminUser;

  final int currentStreak;
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
    this.latitude,
    this.longitude,
    this.locationName,
    this.timeZoneName,
    this.isAdminUser = false,
    this.currentStreak = 0,
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
        profileComplete: (m['profileComplete'] ?? false) as bool,
        acceptedTermsVersion: (m['acceptedTermsVersion'] ?? 0) as int,
        latitude: (m['latitude'] as num?)?.toDouble(),
        longitude: (m['longitude'] as num?)?.toDouble(),
        locationName: m['locationName'] as String?,
        timeZoneName: m['timeZoneName'] as String?,
        isAdminUser: (m['isAdminUser'] ?? false) as bool,
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
        'latitude': latitude,
        'longitude': longitude,
        'locationName': locationName,
        'timeZoneName': timeZoneName,
        'isAdminUser': isAdminUser,
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
    double? latitude,
    double? longitude,
    String? locationName,
    String? timeZoneName,
    bool? isAdminUser,
    bool clearLocation = false,
    int? currentStreak,
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
      latitude: clearLocation ? null : (latitude ?? this.latitude),
      longitude: clearLocation ? null : (longitude ?? this.longitude),
      locationName: clearLocation ? null : (locationName ?? this.locationName),
      timeZoneName: clearLocation ? null : (timeZoneName ?? this.timeZoneName),
      isAdminUser: isAdminUser ?? this.isAdminUser,
      currentStreak: currentStreak ?? this.currentStreak,
      longestStreak: longestStreak ?? this.longestStreak,
      lastActiveDate: lastActiveDate ?? this.lastActiveDate,
    );
  }
}
