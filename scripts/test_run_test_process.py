import os
from pathlib import Path
import signal
import subprocess
import sys
import tempfile
import time
import unittest
from unittest import mock

import run_test_process


class TestProcessTests(unittest.TestCase):
    def assert_stopped(self, pid):
        # A zombie may await system reaping, so check that it cannot execute.
        try:
            state = subprocess.check_output(['ps', '-o', 'stat=', '-p', str(pid)], text=True).strip()
        except subprocess.CalledProcessError:
            state = ''
        self.assertTrue(not state or state.startswith('Z'), state)

    def test_exit_status_and_both_output_streams_are_preserved(self):
        with tempfile.TemporaryDirectory() as folder:
            log = Path(folder) / 'result.log'
            result = run_test_process.run([sys.executable, '-c', 'import sys; print("out"); print("err",file=sys.stderr); sys.exit(7)'], log, 5)
            self.assertEqual(result, 7)
            self.assertEqual(set(log.read_text().splitlines()), {'out', 'err'})

    def test_timeout_stops_parent_and_inherited_child_group(self):
        with tempfile.TemporaryDirectory() as folder:
            pidfile = Path(folder) / 'child.pid'
            command = [sys.executable, '-c',
                'import subprocess,sys,time,pathlib; '
                'p=subprocess.Popen([sys.executable,"-c","import time; time.sleep(60)"]); '
                'pathlib.Path(sys.argv[1]).write_text(str(p.pid)); time.sleep(60)', str(pidfile)]
            start = time.monotonic()
            result = run_test_process.run(command, Path(folder) / 'timeout.log', 0.5, grace=0.2)
            self.assertEqual(result, 124)
            self.assertLess(time.monotonic() - start, 3)
            self.assert_stopped(int(pidfile.read_text()))

    def test_darwin_dead_group_permission_error_is_distinct_from_live_group(self):
        process = mock.Mock(pid=12345)
        denied = PermissionError(1, 'Operation not permitted')
        with mock.patch.object(run_test_process.os, 'killpg', side_effect=denied):
            with mock.patch.object(run_test_process.subprocess, 'check_output', return_value='12345 Z+\n77 S\n'):
                run_test_process.stop_group(process, 0.1)
                process.wait.assert_called_once()
            with mock.patch.object(run_test_process.subprocess, 'check_output', return_value='12345 S\n'):
                with self.assertRaises(PermissionError):
                    run_test_process.stop_group(process, 0.1)
            with mock.patch.object(run_test_process.subprocess, 'check_output', side_effect=OSError('ps failed')):
                with self.assertRaises(OSError):
                    run_test_process.stop_group(process, 0.1)

    def test_cancellation_signal_is_forwarded_to_the_test_group(self):
        with tempfile.TemporaryDirectory() as folder:
            started = Path(folder) / 'started'
            command = [sys.executable, str(Path(run_test_process.__file__)), '--timeout', '30', '--log', str(Path(folder) / 'log'), '--',
                sys.executable, '-c', 'import os,pathlib,sys,time; pathlib.Path(sys.argv[1]).write_text(str(os.getpid())); time.sleep(60)', str(started)]
            wrapper = subprocess.Popen(command, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
            try:
                deadline = time.monotonic() + 5
                while not started.exists() and time.monotonic() < deadline:
                    time.sleep(0.01)
                self.assertTrue(started.exists())
                os.kill(wrapper.pid, signal.SIGTERM)
                self.assertEqual(wrapper.wait(timeout=5), 143)
                self.assert_stopped(int(started.read_text()))
            finally:
                if wrapper.poll() is None:
                    wrapper.kill(); wrapper.wait()
