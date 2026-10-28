#!/usr/bin/env python3
"""Generate or verify the public updater's release manifest."""
import hashlib
import json
import re
import sys
from pathlib import Path

root = Path(__file__).resolve().parents[1]
version = re.search(r"^  VERSION = '([0-9.]+)'", (root / 'kero_cabinet/core.rb').read_text(), re.M).group(1)
files = ['kero_cabinet.rb', 'kero_cabinet/core.rb', 'kero_cabinet/updater.rb']
value = {'schema': 1, 'version': version, 'files': {
    path: hashlib.sha256((root / path).read_bytes()).hexdigest() for path in files
}}
path = root / 'update.json'
if '--check' in sys.argv:
    if not path.exists() or json.loads(path.read_text()) != value:
        raise SystemExit('Update manifest is stale. Run python3 scripts/update_manifest.py.')
    print('Update manifest verified.')
else:
    path.write_text(json.dumps(value, indent=2) + '\n')
    print('Update manifest generated.')
