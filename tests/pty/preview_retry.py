#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
"""Delay a known missing-file result; retry must wait for its completion."""
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile

helper = os.environ.get('BIRC_MEDIA_HELPER') or shutil.which('birc-image')
assert helper and os.path.isfile(helper), 'the provisioned image helper is required'
with tempfile.TemporaryDirectory(prefix='birc-preview-retry-') as directory:
    delayed = Path(directory) / 'helper'
    delayed.write_text('#!' + sys.executable + '\n' + r'''
import os
from pathlib import Path
import sys
import time
if sys.argv[1:2] == ['--local'] and not Path(sys.argv[2]).exists():
    time.sleep(1.5)
    raise SystemExit(1)
helper = os.environ['BIRC_TEST_REAL_IMAGE_HELPER']
os.execv(helper, [helper, *sys.argv[1:]])
''')
    delayed.chmod(0o755)
    environment = dict(os.environ, BIRC_MEDIA_HELPER=str(delayed),
                       BIRC_TEST_REAL_IMAGE_HELPER=os.path.abspath(helper),
                       BIRC_HISTORY='none', BIRC_IMAGES='off')
    subprocess.run([sys.executable, str(Path(__file__).with_name('preview_kitty.py')), sys.argv[1]],
                   env=environment, check=True, timeout=30)
print('preview_retry=ok')
