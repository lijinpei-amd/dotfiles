from pathlib import Path
import shlex
import subprocess
import tempfile
import unittest


REPO_ROOT = Path(__file__).resolve().parents[1]
BASE_PATH = "/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"


class ShellStartupTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(prefix="shell-startup-test-")
        self.addCleanup(self.tmp.cleanup)
        self.home = Path(self.tmp.name)
        (self.home / ".sudo_as_admin_successful").touch()
        for name in (
            ".bashrc",
            ".bash_profile",
            ".zprofile",
            ".zshrc",
            ".env_stow.sh",
            ".env_login_stow.sh",
        ):
            source = REPO_ROOT / ("dot_" + name[1:])
            if source.exists():
                (self.home / name).write_bytes(source.read_bytes())
        (self.home / ".env.sh").write_text(
            'path_prepend "$HOME/interactive-shell-bin"\n'
            'printf "interactive\\n" >> "$SHELL_TEST_TRACE"\n'
        )
        (self.home / ".env_login.sh").write_text(
            'case ":$PATH:" in\n'
            '    *":$HOME/.local/bin:"*) ;;\n'
            '    *) return 1 ;;\n'
            'esac\n'
            'path_prepend "$HOME/login-shell-bin"\n'
            'printf "login\\n" >> "$SHELL_TEST_TRACE"\n'
        )
        self.trace = self.home / "trace"
        self.env = {
            "HOME": str(self.home),
            "PATH": BASE_PATH,
            "TERM": "dumb",
            "LANG": "C.UTF-8",
            "SHELL_TEST_TRACE": str(self.trace),
        }

    def run_shell(self, shell, flags, command='printf "%s\\n" "$PATH"'):
        self.trace.write_text("")
        env = dict(self.env)
        result = subprocess.run(
            ["/bin/" + shell, flags, command],
            env=env,
            capture_output=True,
            text=True,
            timeout=20,
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        return result.stdout.splitlines(), self.trace.read_text().splitlines()

    def test_managed_scripts_load_private_overrides_when_sourced(self):
        for shell in ("bash", "zsh"):
            for script, expected, directory in (
                (".env_stow.sh", "interactive", "interactive-shell-bin"),
                (".env_login_stow.sh", "login", "login-shell-bin"),
            ):
                with self.subTest(shell=shell, script=script):
                    command = (
                        'source "$HOME/' + script + '"; printf "%s\\n" "$PATH"'
                    )
                    output, trace = self.run_shell(shell, "-c", command)
                    self.assertEqual(trace, [expected])
                    self.assertIn(str(self.home / directory), output[0].split(":"))

    def test_layers_load_once_in_all_shell_modes(self):
        for shell in ("bash", "zsh"):
            for flags in ("-c", "-ic", "-lc", "-lic"):
                with self.subTest(shell=shell, flags=flags):
                    output, trace = self.run_shell(shell, flags)
                    expected = {
                        "-c": [],
                        "-ic": ["interactive"],
                        "-lc": ["login"],
                        "-lic": ["login", "interactive"],
                    }[flags]
                    self.assertEqual(trace, expected)
                    self.assertEqual(len(output), 1)
                    parts = output[0].split(":")
                    self.assertEqual(len(parts), len(set(parts)))
                    self.assertEqual(
                        str(self.home / "interactive-shell-bin") in parts,
                        "i" in flags,
                    )
                    self.assertEqual(
                        str(self.home / "login-shell-bin") in parts,
                        "l" in flags,
                    )

    def test_nested_shells_reload_layers_without_growing_path(self):
        child = 'printf "%s\\n" "$PATH"'
        for parent_shell in ("bash", "zsh"):
            for child_shell in ("bash", "zsh"):
                for child_flags in ("-c", "-lc"):
                    with self.subTest(
                        parent=parent_shell, child=child_shell, flags=child_flags
                    ):
                        command = (
                            'printf "%s\\n" "$PATH"; /bin/'
                            + child_shell
                            + " "
                            + child_flags
                            + " "
                            + shlex.quote(child)
                        )
                        output, trace = self.run_shell(parent_shell, "-lc", command)
                        expected = ["login"]
                        if "l" in child_flags:
                            expected.append("login")
                        self.assertEqual(trace, expected)
                        self.assertEqual(len(output), 2)
                        self.assertEqual(output[0], output[1])

    def test_noninteractive_children_inherit_without_sourcing(self):
        child = 'printf "%s\\n" "$PATH" "${BASH_ENV-}"'
        for parent_shell in ("bash", "zsh"):
            for child_shell in ("bash", "zsh"):
                with self.subTest(parent=parent_shell, child=child_shell):
                    command = (
                        'printf "%s\\n" "$PATH"; /bin/'
                        + child_shell
                        + " -c "
                        + shlex.quote(child)
                    )
                    output, trace = self.run_shell(parent_shell, "-lic", command)
                    expected = ["login", "interactive"]
                    self.assertEqual(trace, expected)
                    self.assertEqual(output[0], output[1])
                    self.assertEqual(output[2], "")

    def test_private_scripts_are_optional(self):
        (self.home / ".env.sh").unlink()
        (self.home / ".env_login.sh").unlink()
        for shell in ("bash", "zsh"):
            for flags in ("-c", "-ic", "-lc", "-lic"):
                with self.subTest(shell=shell, flags=flags):
                    output, trace = self.run_shell(shell, flags)
                    self.assertEqual(trace, [])
                    self.assertEqual(len(output), 1)

if __name__ == "__main__":
    unittest.main()
