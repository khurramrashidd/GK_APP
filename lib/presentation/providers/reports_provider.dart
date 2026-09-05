import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../data/models/report_model.dart';
import 'auth_provider.dart';
import 'database_provider.dart';

/// All reports, for the admin screen. Live — updates the instant a new
/// report comes in or an admin (on another device) resolves one.
final adminReportsProvider = StreamProvider<List<ReportModel>>((ref) {
  return ref.watch(firestoreServiceProvider).streamAllReports();
});

/// The signed-in user's own reports. Empty when signed out. Live — a
/// resolution appears the moment an admin saves it, no refresh needed.
final myReportsProvider = StreamProvider<List<ReportModel>>((ref) {
  final profile = ref.watch(profileProvider);
  if (profile == null) return Stream<List<ReportModel>>.value(const []);
  return ref.watch(firestoreServiceProvider).streamMyReports(profile.uid);
});
