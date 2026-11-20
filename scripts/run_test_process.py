#!/usr/bin/env python3
"""Bound a test process group so a timed-out suite cannot overlap its successor."""
import argparse
import os
from pathlib import Path
import signal
import subprocess
import sys


def group_has_live_members(pgid):
    # Darwin may report EPERM for a group containing only zombies after the
    # leader exits. Do not confuse that with permission to ignore a live group.
    output = subprocess.check_output(['ps', '-A', '-o', 'pgid=,stat='], text=True)
    return any(int(parts[0]) == pgid and not parts[1].startswith('Z')
               for line in output.splitlines() if len(parts := line.split()) == 2)


def stop_group(process, grace):
    for sig in (signal.SIGINT, signal.SIGTERM, signal.SIGKILL):
        try:
            os.killpg(process.pid, sig)
        except ProcessLookupError:
            break
        except PermissionError:
            # Fail closed if ps fails or a live member remains. A dead child
            # awaiting reaping cannot overlap the next test suite.
            if group_has_live_members(process.pid):
                raise
            break
        try:
            process.wait(timeout=grace)
        except subprocess.TimeoutExpired:
            continue
        # Even when the parent has exited, remaining group members must stop.
    process.wait()


def run(command, log, timeout, grace=5):
    Path(log).parent.mkdir(parents=True, exist_ok=True)
    with open(log, 'wb') as output:
        process = subprocess.Popen(command, stdout=output, stderr=subprocess.STDOUT, start_new_session=True)
        previous = {}

        def interrupted(signum, _frame):
            raise SystemExit(128 + signum)

        try:
            for sig in (signal.SIGINT, signal.SIGTERM):
                previous[sig] = signal.signal(sig, interrupted)
            try:
                return process.wait(timeout=timeout)
            except subprocess.TimeoutExpired:
                print(f'Test process exceeded {timeout}s; stopping its process group.', file=sys.stderr)
                return 124
        finally:
            try:
                stop_group(process, grace)
            finally:
                for sig, handler in previous.items():
                    signal.signal(sig, handler)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--timeout', type=float, required=True)
    parser.add_argument('--log', required=True)
    parser.add_argument('command', nargs=argparse.REMAINDER)
    args = parser.parse_args()
    command = args.command[1:] if args.command[:1] == ['--'] else args.command
    if not command or not 0 < args.timeout <= 3600:
        parser.error('Specify a command and timeout in (0, 3600].')
    result = run(command, args.log, args.timeout)
    # The artifact is written continuously; also retain ordinary Actions output.
    with open(args.log, 'rb') as source:
        for chunk in iter(lambda: source.read(65536), b''):
            sys.stdout.buffer.write(chunk)
    return result if result >= 0 else 128 - result


if __name__ == '__main__':
    sys.exit(main())
