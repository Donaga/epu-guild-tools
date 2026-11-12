"""Run every test suite, so CI and releases never miss a new one.

    python tests/run_all.py            run everything
    python tests/run_all.py market     only suites whose file name contains "market"

Each tests/test_*.py runs in its own process. The Discord round trip runs a
second time with alternate message timing (EPU_TEST_SEED=1). The exit code is
non-zero if any suite fails, and failing output is printed in full.
"""
import glob
import os
import subprocess
import sys
import time

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
EXTRA_RUNS = {"test_discord.py": [{"EPU_TEST_SEED": "1"}]}


def runs(pattern):
    for path in sorted(glob.glob(os.path.join(HERE, "test_*.py"))):
        name = os.path.basename(path)
        if pattern and pattern not in name:
            continue
        yield name, path, {}
        for env in EXTRA_RUNS.get(name, []):
            yield name, path, env


def main():
    pattern = sys.argv[1] if len(sys.argv) > 1 else ""
    failed, passed, started = [], 0, time.time()
    for name, path, extra in runs(pattern):
        label = name + "".join(f" {k}={v}" for k, v in extra.items())
        t0 = time.time()
        try:
            proc = subprocess.run([sys.executable, path], cwd=ROOT, env={**os.environ, **extra},
                                  capture_output=True, text=True, timeout=900)
            output, code = proc.stdout + proc.stderr, proc.returncode
        except subprocess.TimeoutExpired as e:
            output, code = (e.stdout or "") + "\nTimed out after 900 seconds.", 1
            if isinstance(output, bytes):
                output = output.decode(errors="replace")
        ok = output.count("\nPASS ") + output.startswith("PASS ")
        bad = output.count("\nFAIL ") + output.startswith("FAIL ")
        passed += ok
        status = "ok" if code == 0 and bad == 0 else "FAILED"
        print(f"{status:6} {label:45} {ok:4} checks  {time.time() - t0:5.1f}s", flush=True)
        if status != "ok":
            failed.append(label)
            print(output, flush=True)
    print(f"\n{passed} checks passed in {time.time() - started:.0f}s.", end=" ")
    if failed:
        print("Failed: " + ", ".join(failed))
        sys.exit(1)
    print("All suites passed.")


if __name__ == "__main__":
    main()
