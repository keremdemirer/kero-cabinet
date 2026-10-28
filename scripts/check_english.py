#!/usr/bin/env python3
"""Guard reviewed English source against non-ASCII text regressions.

This is a regression guard, not automatic language detection. English review
is still required for new ASCII-only text. Build outputs are checked separately.
"""
from pathlib import Path

root = Path(__file__).resolve().parents[1]
failures = []
for path in sorted(root.rglob('*')):
    relative = path.relative_to(root)
    if any(part in {'.git', 'dist', '__pycache__'} for part in relative.parts):
        continue
    if not str(relative).isascii():
        failures.append(f'Non-ASCII path: {relative}')
    if path.is_file():
        text = path.read_text(encoding='utf-8')
        for number, line in enumerate(text.splitlines(), 1):
            if not line.isascii():
                failures.append(f'{relative}:{number}: non-ASCII text')
if failures:
    raise SystemExit('\n'.join(failures))
print('English source regression guard passed.')
