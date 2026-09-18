"""Verify every method called on FirestoreService actually exists on it.

This is the check that would have caught a whole block of methods being
deleted: the code still parsed, imports still resolved, and only a full
type-check revealed that eight methods had vanished.
"""
import os, re

svc = open('lib/data/remote/firestore_service.dart').read()

# Methods and getters declared on the service.
declared = set()
declared |= set(re.findall(r'^\s{2}(?:Future|Stream)<[^>]*>+\s+(\w+)\s*\(', svc, re.M))
declared |= set(re.findall(r'^\s{2}(?:Future|Stream)<\([^)]*\)>\s+(\w+)\s*\(', svc, re.M))
declared |= set(re.findall(r'^\s{2}[\w<>?, ]+\s+(\w+)\s*\(', svc, re.M))
declared |= set(re.findall(r'^\s{2}\w+\s+get\s+(\w+)', svc, re.M))

called = {}
pat = re.compile(r'(?:firestoreServiceProvider\)|\bfs)\s*\.\s*(\w+)\s*\(')
for root, _, files in os.walk('lib'):
    for f in sorted(files):
        if not f.endswith('.dart'):
            continue
        p = os.path.join(root, f)
        if p.endswith('firestore_service.dart'):
            continue
        src = re.sub(r'//[^\n]*', '', open(p).read())
        for m in pat.finditer(src):
            called.setdefault(m.group(1), set()).add(p)

missing = []
for name, where in sorted(called.items()):
    if name not in declared:
        for w in sorted(where):
            missing.append(f"{w}: FirestoreService has no '{name}'")

print("\n".join(missing) if missing else "SERVICE CHECK: CLEAN")
