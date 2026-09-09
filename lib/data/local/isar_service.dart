/// Picks the right IsarService implementation for the compile target — same
/// mechanism as question_model.dart, and for the same reason: Isar's classic
/// package can't compile for web at all (dart:ffi doesn't exist there).
///
/// Mobile/desktop: isar_service_mobile.dart (the real local cache).
/// Web: isar_service_web.dart (a no-op stub — never actually called, since
/// nothing reachable from the web build touches local caching; it only
/// exists so provider wiring that constructs an IsarService still compiles).
export 'isar_service_mobile.dart' if (dart.library.html) 'isar_service_web.dart';
