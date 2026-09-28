"""Flag our own class names that collide with names exported by packages we
import unprefixed.

This is the gap that broke the build with `Refreshable`: the symbol resolved
fine, our import was correct, and nothing was missing — but Riverpod exports
a class of the same name, so Dart couldn't tell which one was meant.

Not exhaustive; it encodes the public names of the packages this project
actually imports widely. Add to RESERVED when a new package is adopted.
"""
import os, re

# Names exported by packages imported unprefixed across this project.
RESERVED = {
    # flutter_riverpod / riverpod
    'Refreshable', 'Consumer', 'ConsumerWidget', 'ProviderScope', 'Family',
    'Override', 'ProviderContainer', 'AsyncValue', 'AsyncData', 'AsyncError',
    'AsyncLoading', 'StateNotifier', 'Provider', 'Ref', 'WidgetRef',
    # cloud_firestore
    'Query', 'Transaction', 'Settings', 'Source', 'Timestamp', 'GeoPoint',
    'FieldValue', 'FieldPath', 'Filter', 'SetOptions',
    # firebase_auth
    'UserInfo', 'UserMetadata', 'ActionCodeInfo', 'AuthCredential',
    # flutter
    'Badge', 'Card', 'Page', 'Router', 'Table', 'Action', 'Notification',
    'Image', 'State', 'Element', 'Theme', 'Icon', 'Colors', 'Scrollable',
    'Feedback', 'Banner', 'Hero', 'Flow', 'Shortcuts', 'Title', 'Tooltip',
}

problems = []
for root, _, files in os.walk('lib'):
    for f in sorted(files):
        if not f.endswith('.dart'):
            continue
        p = os.path.join(root, f)
        src = open(p).read()
        for m in re.finditer(r'^\s*(?:abstract\s+)?(?:class|enum|mixin|typedef)\s+(\w+)',
                             src, re.M):
            name = m.group(1)
            # Private names (_Foo) can't collide across libraries.
            if name.startswith('_'):
                continue
            if name in RESERVED:
                line = src[:m.start()].count('\n') + 1
                problems.append(
                    f"{p}:{line}  '{name}' collides with a package export — rename it")

print("\n".join(sorted(set(problems))) if problems else "COLLISION CHECK: CLEAN")
