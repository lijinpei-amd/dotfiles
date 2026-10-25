import json
import os
from pathlib import Path
import shutil
import stat
import subprocess
import tempfile
import unittest


REPO_ROOT = Path(__file__).resolve().parents[1]


class PiProviderTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(prefix="pi-provider-test-")
        self.addCleanup(self.tmp.cleanup)
        self.home = Path(self.tmp.name) / "home"
        self.home.mkdir()
        self.config = Path(self.tmp.name) / "chezmoi.toml"
        self.config.touch()
        self.source = Path(self.tmp.name) / "source"
        agent = self.source / "private_dot_pi/private_agent"
        agent.mkdir(parents=True)
        for name in ("private_models.json.tmpl", "modify_settings.json"):
            shutil.copyfile(REPO_ROOT / "private_dot_pi/private_agent" / name, agent / name)
        shutil.copyfile(REPO_ROOT / ".chezmoiignore", self.source / ".chezmoiignore")
        self.env = {
            **os.environ,
            "HOME": str(self.home),
            "USERPROFILE": str(self.home),
        }

    def chezmoi(self, *args, data):
        result = subprocess.run(
            [
                os.environ.get("CHEZMOI", "chezmoi"),
                "--config", str(self.config),
                "--source", str(self.source),
                "--destination", str(self.home),
                "--override-data", json.dumps(data),
                *map(str, args),
            ],
            env=self.env,
            capture_output=True,
            text=True,
            timeout=20,
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        return result.stdout

    def render(self, name, data):
        return json.loads(self.chezmoi("cat", self.home / ".pi/agent" / name, data=data))

    def test_missing_or_blank_key_omits_deepseek(self):
        for key in (None, "", " \t "):
            with self.subTest(key=key):
                data = {} if key is None else {"deepseekApiKey": key}
                managed = self.chezmoi("managed", "--include=files", data=data)
                self.assertNotIn(".pi/agent/models.json", managed.splitlines())
                data["llmProxyBaseUrl"] = "http://proxy.test:1/"
                providers = self.render("models.json", data)["providers"]
                self.assertEqual(len(providers), 4)
                self.assertNotIn("deepseek", providers)
                settings = self.render("settings.json", data)
                self.assertNotIn("deepseek/*", settings["enabledModels"])

    def test_key_adds_official_provider_with_or_without_gateway(self):
        key = 'test-"key\\with-backslash'
        for proxy in (None, "http://proxy.test:1/"):
            with self.subTest(proxy=proxy):
                data = {"deepseekApiKey": key}
                if proxy:
                    data["llmProxyBaseUrl"] = proxy
                providers = self.render("models.json", data)["providers"]
                self.assertEqual(providers["deepseek"], {
                    "baseUrl": "https://api.deepseek.com",
                    "api": "openai-completions",
                    "apiKey": key,
                })
                self.assertEqual(len(providers), 5 if proxy else 1)
                settings = self.render("settings.json", data)
                expected_scope = ["deepseek/*"]
                if proxy:
                    expected_scope = [
                        "amd-anthropic/*", "amd-openai/*",
                        "amd-openai-dvue/*", "amd-openai-pdue/*",
                        *expected_scope,
                    ]
                self.assertEqual(settings["enabledModels"], expected_scope)

    @unittest.skipIf(os.name == "nt", "POSIX file permissions")
    def test_rendered_credentials_are_owner_only(self):
        path = self.home / ".pi/agent/models.json"
        path.parent.mkdir(parents=True, mode=0o700)
        self.chezmoi(
            "apply", "--exclude=scripts,externals", path,
            data={"deepseekApiKey": "test-key"},
        )
        self.assertEqual(stat.S_IMODE(path.stat().st_mode), 0o600)


if __name__ == "__main__":
    unittest.main()
