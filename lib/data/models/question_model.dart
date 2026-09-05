/// Picks the right QuestionModel implementation for the compile target.
///
/// Mobile/desktop (dart:io available): question_model_isar.dart — the real,
/// Isar-annotated class used for local offline caching.
///
/// Web (dart:io NOT available): question_model_web.dart — a plain class with
/// the identical public shape but no Isar dependency at all, since Isar's
/// classic package can't even compile for web (it uses dart:ffi, which
/// doesn't exist in a browser).
///
/// Every other file in the app just does `import '.../question_model.dart'`
/// as usual — this file is invisible plumbing, nothing else needs to change.
export 'question_model_isar.dart' if (dart.library.html) 'question_model_web.dart';
