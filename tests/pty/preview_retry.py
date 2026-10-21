#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
"""Delay a known missing-file result; retry must wait for its completion."""
import os
from pathlib import Path
import subprocess
import sys
import tempfile

from media_envelope import envelope


with tempfile.TemporaryDirectory(prefix='birc-preview-retry-') as directory:
    encoded, _ = envelope(1, 1, (0, 0, 0, 255))
    delayed = Path(directory) / 'helper'
    payload = Path(directory) / 'still.b64'
    payload.write_text(encoded + '\n')
    delayed.write_text('#!' + sys.executable + '\n' + r'''
import os
from pathlib import Path
import sys
import time
root = Path(__file__).parent
if sys.argv[1:2] == ['--local'] and not Path(sys.argv[2]).exists():
    time.sleep(1.5)
    raise SystemExit(1)
print(root.joinpath('still.b64').read_text().strip(), flush=True)
''')
    delayed.chmod(0o755)
    environment = dict(os.environ, BIRC_MEDIA_HELPER=str(delayed),
                       BIRC_HISTORY='none', BIRC_IMAGES='off')
    subprocess.run([sys.executable, str(Path(__file__).with_name('preview_kitty.py')), sys.argv[1]],
                   env=environment, check=True, timeout=30)
print('preview_retry=ok')
