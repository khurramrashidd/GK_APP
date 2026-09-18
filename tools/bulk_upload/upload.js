#!/usr/bin/env node
/**
 * Bulk-upload questions to Firestore from a JSON or Excel file.
 *
 * SETUP (once):
 *   1. Firebase Console -> Project Settings -> Service accounts
 *      -> "Generate new private key" -> save as serviceAccountKey.json in THIS folder.
 *   2. cd tools/bulk_upload && npm install
 *
 * USAGE:
 *   node upload.js --file questions.xlsx --domain "SSC CGL" --subject "Ancient History"
 *   node upload.js --file questions.json --domain "SSC CGL" --subject "Ancient History"
 *
 * The script will:
 *   - create the domain/subject if they don't exist,
 *   - stamp every question with the domain's NEXT version,
 *   - write in batches of 450,
 *   - bump the domain version so existing installs pull only these as a delta.
 *
 * EXCEL COLUMNS (header row required):
 *   question | optionA | optionB | optionC | optionD | correct | explanation | difficulty | tags
 *   - "correct" may be A/B/C/D or 1/2/3/4 or 0-based index.
 *   - tags is comma-separated, optional.
 *   - difficulty is 1/2/3, optional (defaults 1).
 */

const fs = require('fs');
const path = require('path');
const admin = require('firebase-admin');

// ----------------------------- arg parsing ---------------------------------
function arg(name, fallback = null) {
  const i = process.argv.indexOf(`--${name}`);
  return i !== -1 && process.argv[i + 1] ? process.argv[i + 1] : fallback;
}

const filePath = arg('file');
const domainName = arg('domain');
const subjectName = arg('subject');
const subLevelName = arg('sublevel'); // optional 3rd tier
const subLevelLabelArg = arg('sublevel-label'); // optional, names the tier (e.g. Topic)
const dryRun = process.argv.includes('--dry-run');

if (!filePath || !domainName || !subjectName) {
  console.error('Usage: node upload.js --file <questions.xlsx|json> --domain "SSC CGL" --subject "Ancient History" [--sublevel "Mauryan Era"] [--sublevel-label Topic] [--dry-run]');
  process.exit(1);
}

const slug = (s) =>
  s.toLowerCase().trim().replace(/[^a-z0-9\s-]/g, '').replace(/\s+/g, '-') || 'item';

const domainId = slug(domainName);
const subjectId = slug(subjectName);
const subLevelId = subLevelName ? slug(subLevelName) : null;

// ----------------------------- firebase init -------------------------------
const keyPath = path.join(__dirname, 'serviceAccountKey.json');
if (!fs.existsSync(keyPath)) {
  console.error('Missing serviceAccountKey.json in tools/bulk_upload/.');
  console.error('Firebase Console -> Project Settings -> Service accounts -> Generate new private key.');
  process.exit(1);
}
admin.initializeApp({ credential: admin.cert(require(keyPath)) });
const db = admin.firestore();

// ------------------------------ file loading -------------------------------
function loadJson(p) {
  const raw = JSON.parse(fs.readFileSync(p, 'utf8'));
  if (!Array.isArray(raw)) throw new Error('JSON must be an array of question objects.');
  return raw;
}

function normalizeCorrect(value, optionCount) {
  if (value === undefined || value === null || value === '') return null;
  const s = String(value).trim().toUpperCase();
  const letter = 'ABCDEFGH'.indexOf(s);
  if (s.length === 1 && letter !== -1) return letter;
  const n = Number(s);
  if (!Number.isNaN(n)) {
    // Accept 0-based or 1-based.
    if (n >= 0 && n < optionCount) return n;
    if (n >= 1 && n <= optionCount) return n - 1;
  }
  return null;
}

function loadExcel(p) {
  const XLSX = require('xlsx');
  const wb = XLSX.readFile(p);
  const sheet = wb.Sheets[wb.SheetNames[0]];
  const rows = XLSX.utils.sheet_to_json(sheet, { defval: '' });

  return rows.map((r) => {
    const options = [r.optionA, r.optionB, r.optionC, r.optionD]
      .map((o) => String(o ?? '').trim())
      .filter((o) => o.length > 0);
    return {
      question: String(r.question ?? '').trim(),
      options,
      correctOptionIndex: normalizeCorrect(r.correct, options.length),
      explanation: String(r.explanation ?? '').trim(),
      difficulty: Number(r.difficulty) || 1,
      tags: String(r.tags ?? '')
        .split(',')
        .map((t) => t.trim())
        .filter(Boolean),
    };
  });
}

// -------------------------------- main -------------------------------------
(async () => {
  const ext = path.extname(filePath).toLowerCase();
  let items;
  try {
    items = ext === '.json' ? loadJson(filePath) : loadExcel(filePath);
  } catch (e) {
    console.error('Could not read file:', e.message);
    process.exit(1);
  }

  // Validate
  const valid = [];
  const problems = [];
  items.forEach((raw, i) => {
    const q = String(raw.question ?? '').trim();
    const options = (raw.options || []).map((o) => String(o).trim()).filter(Boolean);
    const correct = typeof raw.correctOptionIndex === 'number'
      ? raw.correctOptionIndex
      : normalizeCorrect(raw.correctOptionIndex, options.length);

    if (!q) return problems.push(`Row ${i + 1}: empty question`);
    if (options.length < 2) return problems.push(`Row ${i + 1}: needs >= 2 options`);
    if (correct === null || correct < 0 || correct >= options.length) {
      return problems.push(`Row ${i + 1}: bad correct answer`);
    }
    valid.push({ question: q, options, correctOptionIndex: correct, raw });
  });

  console.log(`Parsed ${items.length} rows -> ${valid.length} valid, ${problems.length} problem(s).`);
  problems.slice(0, 20).forEach((p) => console.warn('  ! ' + p));
  if (problems.length > 20) console.warn(`  ... and ${problems.length - 20} more`);
  if (valid.length === 0) process.exit(1);

  // Read / create the domain, compute next version.
  const domainRef = db.collection('domains').doc(domainId);
  const domainSnap = await domainRef.get();
  const existing = domainSnap.exists ? domainSnap.data() : null;
  const currentVersion = existing?.version ?? 0;
  const newVersion = currentVersion + 1;

  const subjects = existing?.subjects ? [...existing.subjects] : [];
  let subject = subjects.find((s) => s.id === subjectId);
  if (!subject) {
    subject = { id: subjectId, name: subjectName, order: subjects.length, isActive: true, subLevels: [] };
    subjects.push(subject);
  }
  if (!subject.subLevels) subject.subLevels = [];
  if (subLevelId && !subject.subLevels.some((sl) => sl.id === subLevelId)) {
    subject.subLevels.push({ id: subLevelId, name: subLevelName, order: subject.subLevels.length, isActive: true });
  }
  // Domain-wide label for the 3rd tier, if provided (or defaults to "Topic"
  // the first time any sub-level is added via this script).
  const subLevelLabel = subLevelLabelArg
    || existing?.subLevelLabel
    || (subLevelId ? 'Topic' : undefined);

  if (dryRun) {
    console.log(`[dry-run] Would write ${valid.length} questions to`);
    console.log(`[dry-run]   domain "${domainName}" (${domainId}) v${currentVersion} -> v${newVersion}`);
    console.log(`[dry-run]   subject "${subjectName}" (${subjectId})`);
    if (subLevelId) console.log(`[dry-run]   sublevel "${subLevelName}" (${subLevelId})`);
    console.log('[dry-run] First item:', JSON.stringify(valid[0], null, 2));
    process.exit(0);
  }

  await domainRef.set(
    {
      id: domainId,
      name: domainName,
      isActive: existing?.isActive ?? true,
      order: existing?.order ?? 0,
      version: currentVersion || 1,
      subjects,
      ...(subLevelLabel ? { subLevelLabel } : {}),
    },
    { merge: true }
  );

  // Write in batches.
  const CHUNK = 450;
  let written = 0;
  for (let i = 0; i < valid.length; i += CHUNK) {
    const batch = db.batch();
    const slice = valid.slice(i, i + CHUNK);
    slice.forEach((v, j) => {
      const id = v.raw.id && String(v.raw.id).trim()
        ? String(v.raw.id).trim()
        : `${domainId}_${subjectId}_${Date.now()}_${i + j}`;
      const ref = db.collection('questions').doc(id);
      batch.set(
        ref,
        {
          id,
          domainId,
          domainName,
          subjectId,
          subjectName,
          subLevelId: subLevelId,
          subLevelName: subLevelName || null,
          question: v.question,
          options: v.options,
          correctOptionIndex: v.correctOptionIndex,
          explanation: String(v.raw.explanation ?? ''),
          difficulty: Number(v.raw.difficulty) || 1,
          tags: Array.isArray(v.raw.tags) ? v.raw.tags : [],
          isActive: v.raw.isActive === false ? false : true,
          version: newVersion,
          updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        },
        { merge: true }
      );
    });
    await batch.commit();
    written += slice.length;
    console.log(`  committed ${written}/${valid.length}`);
  }

  await domainRef.update({ version: newVersion });

  console.log(`\nDone. Uploaded ${written} questions.`);
  console.log(`Domain "${domainName}" is now version ${newVersion}.`);
  console.log('Existing app installs will pull only these on next open.');
  process.exit(0);
})().catch((e) => {
  console.error('Upload failed:', e);
  process.exit(1);
});
