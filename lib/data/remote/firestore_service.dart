import 'dart:math';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/question_model.dart';
import '../models/domain_model.dart';
import '../models/user_profile.dart';
import '../models/report_model.dart';
import '../models/quiz_result.dart';
import '../models/match_model.dart';
import '../models/suggestion_model.dart';
import '../models/error_log_model.dart';

/// All Firestore reads/writes live here.
///
/// Collections:
///   domains/{domainId}      -> DomainModel (name, order, isActive, version, subjects[])
///   questions/{questionId}  -> QuestionModel fields (+ domainId, subjectId, version)
///   users/{uid}             -> UserProfile
class FirestoreService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  // --------------------------- Domains -------------------------------------

  Future<List<DomainModel>> fetchDomains() async {
    final snap = await _db
        .collection('domains')
        .where('isActive', isEqualTo: true)
        .get();
    final list = snap.docs
        .map((d) => DomainModel.fromMap(d.data(), docId: d.id))
        .toList()
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return list;
  }

  /// Same as [fetchDomains] but includes hidden (isActive: false) domains too
  /// — for the admin screen, which needs to manage and unhide them.
  Future<List<DomainModel>> fetchAllDomainsForAdmin() async {
    final snap = await _db.collection('domains').get();
    final list = snap.docs
        .map((d) => DomainModel.fromMap(d.data(), docId: d.id))
        .toList()
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return list;
  }

  Future<int> fetchDomainVersion(String domainId) async {
    final doc = await _db.collection('domains').doc(domainId).get();
    if (doc.exists && doc.data() != null) {
      return (doc.data()!['version'] ?? 1) as int;
    }
    return 0;
  }

  // --------------------------- Questions -----------------------------------

  /// Delta fetch: only questions in a domain whose version is greater than the
  /// device's last-synced version. On first open (localVersion 0) this returns
  /// everything for that domain.
  Future<List<QuestionModel>> fetchDomainQuestionsAfter(
      String domainId, int localVersion) async {
    final snap = await _db
        .collection('questions')
        .where('domainId', isEqualTo: domainId)
        .where('version', isGreaterThan: localVersion)
        .get();
    return snap.docs
        .map((d) => QuestionModel.fromMap(d.data(), docId: d.id))
        .toList();
  }

  /// Read the (possibly newer) AI explanation for a question written by another
  /// user, so we don't regenerate it.
  Future<String?> fetchAiExplanation(String questionId) async {
    final doc = await _db.collection('questions').doc(questionId).get();
    if (doc.exists && doc.data() != null) {
      return doc.data()!['aiExplanation'] as String?;
    }
    return null;
  }

  /// Cache an AI explanation globally on the question document. Security rules
  /// allow any authenticated user to update ONLY the aiExplanation field.
  Future<void> saveAiExplanation(String questionId, String aiText) async {
    await _db
        .collection('questions')
        .doc(questionId)
        .update({'aiExplanation': aiText});
  }

  // ----------------------------- Users -------------------------------------

  Future<UserProfile?> fetchUserProfile(String uid) async {
    final doc = await _db.collection('users').doc(uid).get();
    if (doc.exists && doc.data() != null) {
      return UserProfile.fromMap(uid, doc.data()!);
    }
    return null;
  }

  Future<void> createUserProfileIfMissing(UserProfile profile) async {
    final ref = _db.collection('users').doc(profile.uid);
    final doc = await ref.get();
    if (!doc.exists) {
      await ref.set({
        ...profile.toMap(),
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
    }
  }

  Future<void> saveUserProfile(UserProfile profile) async {
    await _db.collection('users').doc(profile.uid).set({
      ...profile.toMap(),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<void> incrementUserScore(String uid, int points) async {
    await _db
        .collection('users')
        .doc(uid)
        .set({'totalScore': FieldValue.increment(points)}, SetOptions(merge: true));
  }

  // ----------------------------- Admin -------------------------------------

  Future<void> createOrUpdateDomain(DomainModel domain) async {
    await _db.collection('domains').doc(domain.id).set(domain.toMap(), SetOptions(merge: true));
  }

  Future<void> bumpDomainVersion(String domainId, int newVersion) async {
    await _db.collection('domains').doc(domainId).update({'version': newVersion});
  }

  /// Counts questions under a domain, optionally narrowed to a subject and/or
  /// sub-level. Used before a permanent delete to make sure nothing is lost —
  /// deletion of a non-empty domain/subject/sub-level is refused; hide it
  /// instead (see [createOrUpdateDomain] with isActive: false).
  Future<int> countQuestions({
    required String domainId,
    String? subjectId,
    String? subLevelId,
  }) async {
    Query<Map<String, dynamic>> q =
        _db.collection('questions').where('domainId', isEqualTo: domainId);
    if (subjectId != null) q = q.where('subjectId', isEqualTo: subjectId);
    if (subLevelId != null) q = q.where('subLevelId', isEqualTo: subLevelId);
    final agg = await q.count().get();
    return agg.count ?? 0;
  }

  /// Counts questions attached DIRECTLY to a subject (subLevelId is null) —
  /// used to warn an admin before they add the first sub-level to a subject
  /// that already has direct questions, since the app can only show one path
  /// at a time: once any sub-level exists, direct questions become unreachable
  /// through normal browsing (they're still in the database, just orphaned
  /// from the UI) until moved under a sub-level.
  Future<int> countDirectQuestions(
      {required String domainId, required String subjectId}) async {
    final agg = await _db
        .collection('questions')
        .where('domainId', isEqualTo: domainId)
        .where('subjectId', isEqualTo: subjectId)
        .where('subLevelId', isEqualTo: null)
        .count()
        .get();
    return agg.count ?? 0;
  }

  /// Permanently deletes a domain document. Caller must have already verified
  /// (via [countQuestions]) that it has zero questions — this method does not
  /// re-check, since subject/sub-level "deletion" is a filter-and-rewrite of
  /// the same document (composed by the caller), not a separate primitive.
  Future<void> deleteDomainDoc(String domainId) async {
    await _db.collection('domains').doc(domainId).delete();
  }

  /// Bulk upload questions in batches of 450 (Firestore batch limit is 500).
  /// Returns the number written. Each question is stamped with [version] and its
  /// domain/subject names for offline display. [onProgress] fires after every
  /// committed batch — use it to show live progress on large (thousands-strong)
  /// uploads.
  Future<int> bulkUploadQuestions(
    List<Map<String, dynamic>> questions, {
    void Function(int written, int total)? onProgress,
  }) async {
    int written = 0;
    const chunk = 450;
    for (var i = 0; i < questions.length; i += chunk) {
      final batch = _db.batch();
      final slice = questions.sublist(
          i, (i + chunk > questions.length) ? questions.length : i + chunk);
      for (final q in slice) {
        final ref = _db.collection('questions').doc(q['id'] as String);
        batch.set(ref, {...q, 'updatedAt': FieldValue.serverTimestamp()},
            SetOptions(merge: true));
      }
      await batch.commit();
      written += slice.length;
      onProgress?.call(written, questions.length);
    }
    return written;
  }

  /// Lowercased, trimmed question texts already present in a subject — used to
  /// block duplicate uploads. Scoped to domain+subject so it stays cheap even
  /// as the overall bank grows into the tens of thousands.
  Future<Set<String>> fetchQuestionTextsForSubject(
      String domainId, String subjectId) async {
    final snap = await _db
        .collection('questions')
        .where('domainId', isEqualTo: domainId)
        .where('subjectId', isEqualTo: subjectId)
        .get();
    return snap.docs
        .map((d) => ((d.data()['question'] ?? '') as String).trim().toLowerCase())
        .where((t) => t.isNotEmpty)
        .toSet();
  }

  /// Fetch a single question by its document id (for the admin edit flow).
  /// Returns null if it no longer exists.
  Future<QuestionModel?> fetchQuestionById(String questionId) async {
    final doc = await _db.collection('questions').doc(questionId).get();
    if (!doc.exists) return null;
    return QuestionModel.fromMap(doc.data()!, docId: doc.id);
  }

  /// Apply an admin's edits to a question AND bump its domain version, so every
  /// device that already downloaded the old version pulls the fix on next sync.
  /// The question's own `version` is stamped to the new domain version so it
  /// falls inside the delta-sync window (`version > localVersion`).
  Future<int> updateQuestionAndBump({
    required String questionId,
    required String domainId,
    required int currentDomainVersion,
    required Map<String, dynamic> fields,
  }) async {
    final newVersion = currentDomainVersion + 1;
    await _db.collection('questions').doc(questionId).update({
      ...fields,
      'version': newVersion,
      'updatedAt': FieldValue.serverTimestamp(),
    });
    await bumpDomainVersion(domainId, newVersion);
    return newVersion;
  }

  // ---------------------- Bookmarks / History / Streak -----------------------

  /// Bookmarks live at users/{uid}/bookmarks/{questionId}, storing a snapshot
  /// of the question so the "saved questions" list works offline-ish and
  /// survives the original being edited or removed.
  Future<void> addBookmark(String uid, QuestionModel q) async {
    await _db
        .collection('users')
        .doc(uid)
        .collection('bookmarks')
        .doc(q.id)
        .set({
      'id': q.id,
      'questionId': q.id,
      'question': q.question,
      'options': q.options,
      'correctOptionIndex': q.correctOptionIndex,
      'explanation': q.explanation,
      'domainId': q.domainId,
      'domainName': q.domainName,
      'subjectId': q.subjectId,
      'subjectName': q.subjectName,
      'subLevelId': q.subLevelId,
      'subLevelName': q.subLevelName,
      'difficulty': q.difficulty,
      'savedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> removeBookmark(String uid, String questionId) async {
    await _db
        .collection('users')
        .doc(uid)
        .collection('bookmarks')
        .doc(questionId)
        .delete();
  }

  Stream<List<QuestionModel>> streamBookmarks(String uid) {
    return _db
        .collection('users')
        .doc(uid)
        .collection('bookmarks')
        .snapshots()
        .map((snap) {
      final list = snap.docs
          .map((d) => QuestionModel.fromMap(d.data(), docId: d.id))
          .toList();
      return list;
    });
  }

  Future<Set<String>> fetchBookmarkIds(String uid) async {
    final snap = await _db
        .collection('users')
        .doc(uid)
        .collection('bookmarks')
        .get();
    return snap.docs.map((d) => d.id).toSet();
  }

  /// Append a completed quiz to history (users/{uid}/history), and publish
  /// the running total to the public leaderboard slice in the same step.
  Future<void> saveQuizResult(
      String uid, QuizResult result, String displayName, int newTotalScore) async {
    final batch = _db.batch();
    final histRef = _db
        .collection('users')
        .doc(uid)
        .collection('history')
        .doc();
    batch.set(histRef, result.toCreateMap());

    // Public, privacy-safe leaderboard entry: ONLY name + score, nothing else.
    final lbRef = _db.collection('leaderboard').doc(uid);
    batch.set(lbRef, {
      'displayName': displayName,
      'totalScore': newTotalScore,
      'updatedAt': FieldValue.serverTimestamp(),
    });
    await batch.commit();
  }

  Stream<List<QuizResult>> streamHistory(String uid) {
    return _db
        .collection('users')
        .doc(uid)
        .collection('history')
        .snapshots()
        .map((snap) {
      final list =
          snap.docs.map((d) => QuizResult.fromMap(d.id, d.data())).toList();
      list.sort((a, b) =>
          (b.takenAt ?? DateTime(0)).compareTo(a.takenAt ?? DateTime(0)));
      return list;
    });
  }

  /// Top scorers, from the public leaderboard slice. Sorted client-side to
  /// avoid needing an index; capped at [limit].
  Stream<List<Map<String, dynamic>>> streamLeaderboard({int limit = 50}) {
    return _db.collection('leaderboard').snapshots().map((snap) {
      final list = snap.docs
          .map((d) => {
                'uid': d.id,
                'displayName': (d.data()['displayName'] ?? 'Anonymous') as String,
                'totalScore': (d.data()['totalScore'] ?? 0) as int,
              })
          .toList();
      list.sort((a, b) =>
          (b['totalScore'] as int).compareTo(a['totalScore'] as int));
      return list.take(limit).toList();
    });
  }

  // ------------------------------ Multiplayer --------------------------------
  // A "match" is a single Firestore doc both players read/write directly — no
  // Cloud Functions. Random matchmaking and invite-code joining both use the
  // SAME primitive: an open ('waiting') match. Invite flow = share the code so
  // one specific person joins it; random flow = search for ANY open match in
  // that subject and auto-join the first one found, or create one and wait if
  // none exists. A Firestore transaction on join prevents two people claiming
  // the same waiting match in a race.

  String _generateInviteCode() {
    const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789'; // no 0/O/1/I confusion
    final rand = Random();
    return List.generate(6, (_) => chars[rand.nextInt(chars.length)]).join();
  }

  Future<String> createMatch({
    required String uid,
    required String playerName,
    required String domainId,
    required String domainName,
    required String subjectId,
    required String subjectName,
    String? subLevelId,
    String? subLevelName,
    required List<String> questionIds,
  }) async {
    final match = MatchModel(
      id: '',
      status: 'waiting',
      inviteCode: _generateInviteCode(),
      domainId: domainId,
      domainName: domainName,
      subjectId: subjectId,
      subjectName: subjectName,
      subLevelId: subLevelId,
      subLevelName: subLevelName,
      questionIds: questionIds,
      player1Uid: uid,
      player1Name: playerName,
    );
    final ref = await _db.collection('matches').add(match.toCreateMap());
    return ref.id;
  }

  Future<bool> _tryJoinMatch(
      DocumentReference<Map<String, dynamic>> ref, String uid, String name) async {
    try {
      return await _db.runTransaction<bool>((tx) async {
        final snap = await tx.get(ref);
        if (!snap.exists) return false;
        final data = snap.data()!;
        if (data['status'] != 'waiting') return false;
        if (data['player1Uid'] == uid) return false; // can't join your own
        tx.update(ref, {
          'player2Uid': uid,
          'player2Name': name,
          'status': 'active',
        });
        return true;
      });
    } catch (_) {
      return false;
    }
  }

  /// Joins a specific match via its 6-character invite code. Returns the
  /// match id on success, or null if the code is invalid/already taken.
  Future<String?> joinMatchByCode(String code, String uid, String name) async {
    final snap = await _db
        .collection('matches')
        .where('inviteCode', isEqualTo: code.trim().toUpperCase())
        .where('status', isEqualTo: 'waiting')
        .limit(1)
        .get();
    if (snap.docs.isEmpty) return null;
    final doc = snap.docs.first;
    if (doc.data()['player1Uid'] == uid) return null;
    final ok = await _tryJoinMatch(doc.reference, uid, name);
    return ok ? doc.id : null;
  }

  /// Finds an open match for this exact subject/sub-level and joins it; if
  /// none exists (or a join race is lost), creates a new one and returns it
  /// so the caller waits in it instead. Only considers matches created in the
  /// last 10 minutes, so a stale abandoned match can't be joined forever.
  Future<String> findOrCreateRandomMatch({
    required String uid,
    required String playerName,
    required String domainId,
    required String domainName,
    required String subjectId,
    required String subjectName,
    String? subLevelId,
    String? subLevelName,
    required List<String> questionIds,
  }) async {
    final snap = await _db
        .collection('matches')
        .where('status', isEqualTo: 'waiting')
        .where('domainId', isEqualTo: domainId)
        .where('subjectId', isEqualTo: subjectId)
        .limit(20)
        .get();

    final cutoff = DateTime.now().subtract(const Duration(minutes: 10));
    final candidates = snap.docs.where((d) {
      final data = d.data();
      if (data['player1Uid'] == uid) return false;
      if ((data['subLevelId'] as String?) != subLevelId) return false;
      final ts = data['createdAt'];
      if (ts is Timestamp && ts.toDate().isBefore(cutoff)) return false;
      return true;
    }).toList();

    for (final doc in candidates) {
      final ok = await _tryJoinMatch(doc.reference, uid, playerName);
      if (ok) return doc.id;
      // lost the race — try the next candidate before giving up and creating.
    }

    return createMatch(
      uid: uid,
      playerName: playerName,
      domainId: domainId,
      domainName: domainName,
      subjectId: subjectId,
      subjectName: subjectName,
      subLevelId: subLevelId,
      subLevelName: subLevelName,
      questionIds: questionIds,
    );
  }

  /// Cancels a match that's still waiting for an opponent (e.g. creator backs
  /// out). No-ops harmlessly if it's already been joined or finished.
  Future<void> cancelWaitingMatch(String matchId) async {
    final doc = await _db.collection('matches').doc(matchId).get();
    if (doc.exists && doc.data()?['status'] == 'waiting') {
      await doc.reference.delete();
    }
  }

  Stream<MatchModel?> streamMatch(String matchId) {
    return _db.collection('matches').doc(matchId).snapshots().map((snap) {
      if (!snap.exists) return null;
      return MatchModel.fromMap(snap.id, snap.data()!);
    });
  }

  /// Records one answer for one player without touching the other player's
  /// data — a dotted field path updates just that map key, not the whole map.
  Future<void> submitMatchAnswer(
      String matchId, int playerSlot, String questionId, int answerIndex) async {
    final field = playerSlot == 1 ? 'player1Answers' : 'player2Answers';
    await _db.collection('matches').doc(matchId).update({
      '$field.$questionId': answerIndex,
    });
  }

  /// Marks one player finished with their score. When both are finished, also
  /// flips the match status so both screens know to show final results.
  Future<void> finishMatchPlayer(String matchId, int playerSlot, int score) async {
    final ref = _db.collection('matches').doc(matchId);
    final scoreField = playerSlot == 1 ? 'player1Score' : 'player2Score';
    final finishedField = playerSlot == 1 ? 'player1Finished' : 'player2Finished';
    await ref.update({scoreField: score, finishedField: true});

    final snap = await ref.get();
    final data = snap.data();
    if (data != null &&
        data['player1Finished'] == true &&
        data['player2Finished'] == true) {
      await ref.update({'status': 'finished'});
    }
  }

  /// Fetches a fixed set of questions by id in one query (Firestore's
  /// whereIn caps at 10, which matches the fixed match size exactly). Used
  /// during a match so both players see identical, fresh question content
  /// regardless of what's in their local offline cache.
  Future<List<QuestionModel>> fetchQuestionsByIds(List<String> ids) async {
    if (ids.isEmpty) return [];
    final snap = await _db
        .collection('questions')
        .where(FieldPath.documentId, whereIn: ids)
        .get();
    final byId = {for (final d in snap.docs) d.id: QuestionModel.fromMap(d.data(), docId: d.id)};
    // Preserve the original order — whereIn doesn't guarantee it.
    return [for (final id in ids) if (byId.containsKey(id)) byId[id]!];
  }

  // --------------------------- Question counts --------------------------------
  // countQuestions(domainId: ..., subjectId: ..., subLevelId: ...) already
  // exists above (used for the pre-delete safety check) and covers per-domain
  // and per-subject totals. This adds only the one thing it can't do: the
  // grand total across every question with no domain filter at all.
  Future<int> countAllQuestions() async {
    final snap = await _db.collection('questions').count().get();
    return snap.count ?? 0;
  }

  // --------------------------- Shared subjects --------------------------------
  // A subject marked isShared draws from a pool keyed on its id alone (the
  // slugified name, so History/HISTORY/hISTory all resolve to 'history'),
  // ignoring which domain you reached it through.
  //
  // NOTE ON OFFLINE: the normal question path caches to Isar per-domain
  // (ensureDomainSynced + a version counter on each domain document). A
  // shared question belongs to several domains at once, which that model
  // can't express — so shared subjects read straight from Firestore and are
  // ONLINE-ONLY. Non-shared subjects keep working offline exactly as before.
  // This is the honest trade for opt-in sharing without rewriting the whole
  // sync layer; only subjects you explicitly mark shared give up offline.

  /// All questions for a shared subject, from every domain that uses that
  /// subject id. Equality-only filter, so no composite index is needed.
  Future<List<QuestionModel>> fetchSharedSubjectQuestions(
    String subjectId, {
    String? subLevelId,
  }) async {
    Query<Map<String, dynamic>> q =
        _db.collection('questions').where('subjectId', isEqualTo: subjectId);
    if (subLevelId != null) {
      q = q.where('subLevelId', isEqualTo: subLevelId);
    }
    final snap = await q.get();
    return snap.docs
        .map((d) => QuestionModel.fromMap(d.data(), docId: d.id))
        .where((question) => question.isActive)
        .toList();
  }

  /// Counts questions in a shared subject's pool across all domains.
  Future<int> countSharedSubjectQuestions(String subjectId,
      {String? subLevelId}) async {
    Query<Map<String, dynamic>> q =
        _db.collection('questions').where('subjectId', isEqualTo: subjectId);
    if (subLevelId != null) {
      q = q.where('subLevelId', isEqualTo: subLevelId);
    }
    final agg = await q.count().get();
    return agg.count ?? 0;
  }

  /// The merged sub-level list for a shared subject: the union of sub-levels
  /// from every domain that has a subject with this id ALSO marked shared.
  /// Deduplicated by sub-level id, sorted alphabetically. A domain whose
  /// copy of the subject is NOT marked shared is left out entirely — sharing
  /// is mutual by design, so one domain can't pull in another's content
  /// without that domain also opting in.
  Future<List<SubLevelModel>> fetchMergedSubLevels(String subjectId) async {
    final domains = await fetchAllDomainsForAdmin();
    final byId = <String, SubLevelModel>{};
    for (final d in domains) {
      for (final s in d.subjects) {
        if (s.id != subjectId || !s.isShared) continue;
        for (final sl in s.subLevels) {
          byId.putIfAbsent(sl.id, () => sl);
        }
      }
    }
    final merged = byId.values.where((sl) => sl.isActive).toList()
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return merged;
  }

  /// Every domain name that shares this subject id (and has it marked
  /// shared) — used to tell the admin what a toggle will actually affect.
  Future<List<String>> domainsSharingSubject(String subjectId) async {
    final domains = await fetchAllDomainsForAdmin();
    return [
      for (final d in domains)
        if (d.subjects.any((s) => s.id == subjectId && s.isShared)) d.name,
    ]..sort();
  }

  // --------------------------- Admin management -------------------------------
  // Ordinary admin rights live on the user profile (isAdminUser) so they can
  // be granted/revoked at runtime. Super admins are hardcoded in
  // AppConstants.superAdminEmails and can never be removed from inside the
  // app — that's the guard against admins locking each other (or you) out.

  Future<List<UserProfile>> fetchAllUsers({int limit = 500}) async {
    final snap = await _db.collection('users').limit(limit).get();
    final list =
        snap.docs.map((d) => UserProfile.fromMap(d.id, d.data())).toList();
    list.sort((a, b) => a.email.toLowerCase().compareTo(b.email.toLowerCase()));
    return list;
  }

  Future<void> setUserAdmin(String uid, bool isAdmin) async {
    await _db.collection('users').doc(uid).update({'isAdminUser': isAdmin});
  }

  /// Records that a user accepted a given Terms version.
  Future<void> acceptTerms(String uid, int version) async {
    await _db
        .collection('users')
        .doc(uid)
        .update({'acceptedTermsVersion': version});
  }

  /// Saves (or clears) a user's optional location.
  Future<void> saveUserLocation(
    String uid, {
    double? latitude,
    double? longitude,
    String? locationName,
    String? timeZoneName,
  }) async {
    await _db.collection('users').doc(uid).update({
      'latitude': latitude,
      'longitude': longitude,
      'locationName': locationName,
      'timeZoneName': timeZoneName,
    });
  }

  // ------------------------------ Suggestions ---------------------------------

  Future<void> submitSuggestion(SuggestionModel s) async {
    await _db.collection('suggestions').add(s.toCreateMap());
  }

  Stream<List<SuggestionModel>> streamAllSuggestions() {
    return _db.collection('suggestions').snapshots().map((snap) {
      final list = snap.docs
          .map((d) => SuggestionModel.fromMap(d.id, d.data()))
          .toList();
      list.sort((a, b) =>
          (b.createdAt ?? DateTime(0)).compareTo(a.createdAt ?? DateTime(0)));
      return list;
    });
  }

  Stream<List<SuggestionModel>> streamMySuggestions(String uid) {
    return _db
        .collection('suggestions')
        .where('userUid', isEqualTo: uid)
        .snapshots()
        .map((snap) {
      final list = snap.docs
          .map((d) => SuggestionModel.fromMap(d.id, d.data()))
          .toList();
      list.sort((a, b) =>
          (b.createdAt ?? DateTime(0)).compareTo(a.createdAt ?? DateTime(0)));
      return list;
    });
  }

  Future<void> respondToSuggestion(
      String id, String status, String? adminResponse) async {
    await _db.collection('suggestions').doc(id).update({
      'status': status,
      'adminResponse': adminResponse,
      'seenByUser': false,
    });
  }

  Future<void> markSuggestionSeen(String id) async {
    await _db.collection('suggestions').doc(id).update({'seenByUser': true});
  }

  // ------------------------------ JSON export ---------------------------------

  /// Every question for a domain (optionally one subject), as plain maps ready
  /// to be written out as a JSON file from the admin dashboard.
  /// Recursively converts Firestore-specific types (Timestamp, GeoPoint,
  /// DocumentReference) into plain JSON-safe values, so the result can
  /// always be passed to jsonEncode without guessing field names in advance.
  /// Handles nested maps and lists too.
  dynamic _sanitizeForJson(dynamic value) {
    if (value is Timestamp) return value.toDate().toIso8601String();
    if (value is GeoPoint) {
      return {'latitude': value.latitude, 'longitude': value.longitude};
    }
    if (value is DocumentReference) return value.path;
    if (value is Map) {
      return value.map((k, v) => MapEntry(k.toString(), _sanitizeForJson(v)));
    }
    if (value is List) return value.map(_sanitizeForJson).toList();
    return value;
  }

  Future<List<Map<String, dynamic>>> exportQuestions({
    required String domainId,
    String? subjectId,
  }) async {
    Query<Map<String, dynamic>> q =
        _db.collection('questions').where('domainId', isEqualTo: domainId);
    if (subjectId != null) q = q.where('subjectId', isEqualTo: subjectId);
    final snap = await q.get();
    return snap.docs.map((d) {
      final m = Map<String, dynamic>.from(d.data());
      m['id'] = d.id;
      // Sanitize the WHOLE map generically rather than removing specific
      // named fields — any current or future Timestamp/GeoPoint field is
      // handled the same way, so this can't silently break again when a
      // new field is added elsewhere in the app.
      return _sanitizeForJson(m) as Map<String, dynamic>;
    }).toList();
  }

  // ------------------------- Per-subject question sync -------------------------

  /// Questions for ONE subject, fetched directly. Used by the new
  /// download-on-demand path: rather than pulling an entire domain the first
  /// time a user opens it (which for a 50-subject domain means downloading
  /// everything to read one subject), we fetch only what they tapped.
  Future<List<QuestionModel>> fetchSubjectQuestions(
    String domainId,
    String subjectId, {
    String? subLevelId,
  }) async {
    Query<Map<String, dynamic>> q = _db
        .collection('questions')
        .where('domainId', isEqualTo: domainId)
        .where('subjectId', isEqualTo: subjectId);
    if (subLevelId != null) q = q.where('subLevelId', isEqualTo: subLevelId);
    final snap = await q.get();
    return snap.docs
        .map((d) => QuestionModel.fromMap(d.data(), docId: d.id))
        .where((x) => x.isActive)
        .toList();
  }

  // ------------------------------- Error logs ---------------------------------
  // Best-effort by design: a failure to LOG an error must never itself
  // crash the app or surface to the user, so every call site wraps this in
  // its own try/catch (see ErrorReporter). Anyone signed in can write one —
  // that's how a crashed, half-signed-in session still gets logged — but
  // only admins can read the list back.

  Future<void> logError(ErrorLogModel log) async {
    await _db.collection('error_logs').add(log.toCreateMap());
  }

  Stream<List<ErrorLogModel>> streamErrorLogs({int limit = 200}) {
    return _db
        .collection('error_logs')
        .orderBy('createdAt', descending: true)
        .limit(limit)
        .snapshots()
        .map((snap) =>
            snap.docs.map((d) => ErrorLogModel.fromMap(d.id, d.data())).toList());
  }

  Future<void> deleteErrorLog(String id) async {
    await _db.collection('error_logs').doc(id).delete();
  }

  Future<void> clearAllErrorLogs() async {
    final snap = await _db.collection('error_logs').get();
    final batch = _db.batch();
    for (final d in snap.docs) {
      batch.delete(d.reference);
    }
    await batch.commit();
  }

  // ------------------------------- Reports -----------------------------------
  // Deliberately sorted CLIENT-SIDE (no .orderBy() in the query) rather than
  // via Firestore, so these queries never need a composite index — report
  // volume is small enough that this costs nothing in practice.

  Future<void> submitReport(ReportModel report) async {
    await _db.collection('reports').add(report.toCreateMap());
  }

  List<ReportModel> _sorted(List<ReportModel> list) {
    list.sort((a, b) =>
        (b.createdAt ?? DateTime(0)).compareTo(a.createdAt ?? DateTime(0)));
    return list;
  }

  /// All reports, for the admin screen.
  Stream<List<ReportModel>> streamAllReports() {
    return _db.collection('reports').snapshots().map((snap) => _sorted(
        snap.docs.map((d) => ReportModel.fromMap(d.id, d.data())).toList()));
  }

  /// One user's own reports, for their notification/history screen.
  Stream<List<ReportModel>> streamMyReports(String uid) {
    return _db
        .collection('reports')
        .where('reportedByUid', isEqualTo: uid)
        .snapshots()
        .map((snap) => _sorted(
            snap.docs.map((d) => ReportModel.fromMap(d.id, d.data())).toList()));
  }

  /// Marks a report resolved. Resets seenByReporter to false — that's what
  /// makes the reporter's notification badge appear.
  Future<void> resolveReport(String reportId, String resolutionNote) async {
    await _db.collection('reports').doc(reportId).update({
      'status': 'resolved',
      'resolutionNote': resolutionNote,
      'resolvedAt': FieldValue.serverTimestamp(),
      'seenByReporter': false,
    });
  }

  /// Marks reports as seen (clears the badge) — called when the reporter
  /// opens their "My Reports" screen.
  Future<void> markReportsSeen(List<String> reportIds) async {
    if (reportIds.isEmpty) return;
    final batch = _db.batch();
    for (final id in reportIds) {
      batch.update(_db.collection('reports').doc(id), {'seenByReporter': true});
    }
    await batch.commit();
  }
}
