# SPDX-License-Identifier: Apache-2.0
"""Credential environment controls do not start networking or the UI."""
import os
import subprocess
import sys


for values in ({"BIRC_SASL_USER": "env-user", "BIRC_SASL_PASS": "env-pass"},
               {"BIRC_SASL_USER": "", "BIRC_SASL_PASS": ""}, {}):
    env = os.environ.copy()
    env.pop("BIRC_SASL_USER", None)
    env.pop("BIRC_SASL_PASS", None)
    env.update(values)
    env["BIRC_M21_EXPECT_USER"] = values.get("BIRC_SASL_USER", "")
    env["BIRC_M21_EXPECT_PASS"] = values.get("BIRC_SASL_PASS", "")
    result = subprocess.run([sys.argv[1]], env=env, capture_output=True,
                            text=True, timeout=15, check=False)
    assert result.returncode == 0, (result.returncode, result.stdout, result.stderr)
    assert result.stdout.splitlines() == ["m21_sasl_env=ok"], result.stdout
    assert not result.stderr, result.stderr
print("sasl_env=ok")
