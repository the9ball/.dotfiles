"""Exercise regular and personal Codex modify templates in isolated chezmoi fixtures.

Run: python3 -B tests/codex-config.py -v
"""

import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import tomllib
import unittest


REPOSITORY = Path(__file__).resolve().parents[1]
PROFILES = {"work": ("dot_codex", "codex-defaults.toml"),
            "personal": ("dot_codex-personal", "codex-personal-defaults.toml")}


class CodexConfigTests(unittest.TestCase):
    """Protect profile separation, runtime state, and host-local override behavior."""

    @classmethod
    def setUpClass(cls):
        """Resolve an installed native chezmoi binary before creating isolated fixtures."""
        cls.chezmoi = os.environ.get("CHEZMOI_TEST_BINARY")
        if not cls.chezmoi:
            aqua = shutil.which("aqua")
            if not aqua:
                raise unittest.SkipTest("aqua or CHEZMOI_TEST_BINARY is required")
            cls.chezmoi = subprocess.check_output(
                [aqua, "which", "chezmoi"], text=True, timeout=30
            ).strip()

    def setUp(self):
        """Copy only tracked template inputs into a temporary source and destination."""
        temporary_directory = tempfile.TemporaryDirectory(prefix="codex-config-test-")
        self.addCleanup(temporary_directory.cleanup)
        self.root = Path(temporary_directory.name)
        self.source = self.root / "source"
        self.home = self.root / "home"
        self.home.mkdir()
        self.templates = self.source / ".chezmoitemplates"
        self.templates.mkdir(parents=True)
        self.configuration = self.root / "chezmoi.toml"
        self.configuration.write_text("", encoding="utf-8")
        for template_name in (
            "codex-common-defaults.toml", "codex-config-modify.tmpl",
            "codex-defaults.toml", "codex-personal-defaults.toml",
        ):
            original = REPOSITORY / "chezmoi" / ".chezmoitemplates" / template_name
            if original.is_file():
                shutil.copyfile(original, self.templates / template_name)
        for directory, _ in PROFILES.values():
            destination = self.source / directory
            destination.mkdir()
            shutil.copyfile(
                REPOSITORY / "chezmoi" / directory / "modify_config.toml",
                destination / "modify_config.toml",
            )

    def render(self, profile, existing="", overrides=None, check=True):
        """Render a real modifier with fixture stdin and optional synthetic local defaults."""
        directory, defaults_name = PROFILES[profile]
        if overrides is not None:
            (self.templates / (defaults_name + ".local")).write_text(
                overrides, encoding="utf-8"
            )
        return subprocess.run(
            [
                self.chezmoi, "--source", str(self.source),
                "--destination", str(self.home),
                "--config", str(self.configuration),
                "--persistent-state", str(self.root / "state.boltdb"),
                "--cache", str(self.root / "cache"),
                "execute-template", "--with-stdin", "--file",
                str(self.source / directory / "modify_config.toml"),
            ],
            input=existing, text=True, capture_output=True, check=check, timeout=30,
        )

    def test_defaults_keep_profiles_separate(self):
        """Supply shared defaults while selecting only each profile's permission family."""
        for profile in PROFILES:
            with self.subTest(profile=profile):
                configuration = tomllib.loads(self.render(profile).stdout)
                self.assertEqual(configuration["windows"]["sandbox"], "mxc")
                self.assertEqual(configuration["model"], "gpt-6.1-sol")
                self.assertTrue(configuration["features"]["network_proxy"])
                expected_profile = "default-permissions" if profile == "work" else "personal-standard"
                self.assertEqual(configuration["default_permissions"], expected_profile)
                expected_permissions = (
                    {"default-permissions"} if profile == "work"
                    else {"personal-standard", "personal-emergency"}
                )
                self.assertEqual(set(configuration["permissions"]), expected_permissions)
                self.assertEqual("desktop" in configuration, profile == "personal")

    def test_existing_selections_and_runtime_state_survive(self):
        """Preserve explicit models, unknown integration keys, and Codex-owned state."""
        existing = (
            'model = "selected-model"\nmodel_reasoning_effort = "low"\n'
            '[agents]\ndefault_subagent_model = "selected-worker"\n'
            'default_subagent_reasoning_effort = "medium"\n'
            '[projects.sample]\ntrust_level = "trusted"\n'
            '[hooks.state]\naccepted = true\n'
            '[mcp_servers.custom]\ncommand = "custom-tool"\n'
            '[windows]\nsandbox = "unelevated"\ncustom_setting = true\n'
        )
        for profile in PROFILES:
            with self.subTest(profile=profile):
                configuration = tomllib.loads(self.render(profile, existing).stdout)
                self.assertEqual(configuration["model"], "selected-model")
                self.assertEqual(configuration["model_reasoning_effort"], "low")
                self.assertEqual(configuration["agents"]["default_subagent_model"], "selected-worker")
                self.assertEqual(configuration["agents"]["default_subagent_reasoning_effort"], "medium")
                self.assertEqual(configuration["projects"]["sample"]["trust_level"], "trusted")
                self.assertTrue(configuration["hooks"]["state"]["accepted"])
                self.assertEqual(configuration["mcp_servers"]["custom"]["command"], "custom-tool")
                self.assertEqual(configuration["windows"], {"sandbox": "mxc", "custom_setting": True})

    def test_local_overrides_take_precedence(self):
        """Apply explicit local selections and nested overrides after portable defaults."""
        existing = 'model = "existing-model"\n[windows]\nsandbox = "unelevated"\n'
        overrides = (
            'model = "local-model"\nmodel_reasoning_effort = "medium"\n'
            '[agents]\ndefault_subagent_model = "local-worker"\n'
            '[windows]\nsandbox = "elevated"\n'
        )
        for profile in PROFILES:
            with self.subTest(profile=profile):
                configuration = tomllib.loads(self.render(profile, existing, overrides).stdout)
                self.assertEqual(configuration["model"], "local-model")
                self.assertEqual(configuration["model_reasoning_effort"], "medium")
                self.assertEqual(configuration["agents"]["default_subagent_model"], "local-worker")
                self.assertEqual(configuration["windows"]["sandbox"], "elevated")

    def test_legacy_cleanup_stays_personal_only(self):
        """Remove incompatible legacy keys and prevent work permissions leaking into Personal."""
        existing = (
            'sandbox_mode = "workspace-write"\n'
            '[sandbox_workspace_write]\nnetwork_access = true\n'
            '[permissions.default-permissions]\nextends = ":workspace"\n'
            '[permissions.custom]\nextends = ":read-only"\n'
        )
        overrides = (
            'sandbox_mode = "read-only"\n'
            '[sandbox_workspace_write]\nnetwork_access = false\n'
            '[permissions.default-permissions.network]\nenabled = true\n'
        )
        for profile in PROFILES:
            with self.subTest(profile=profile):
                configuration = tomllib.loads(self.render(profile, existing, overrides).stdout)
                self.assertNotIn("sandbox_mode", configuration)
                self.assertNotIn("sandbox_workspace_write", configuration)
                self.assertIn("custom", configuration["permissions"])
                self.assertEqual("default-permissions" in configuration["permissions"], profile == "work")

    def test_repeated_render_is_stable(self):
        """Produce identical output when the rendered config becomes the next input."""
        for profile in PROFILES:
            with self.subTest(profile=profile):
                first = self.render(profile).stdout
                self.assertEqual(self.render(profile, first).stdout, first)

    def test_invalid_existing_toml_fails(self):
        """Reject malformed existing configuration instead of silently replacing its contents."""
        for profile in PROFILES:
            with self.subTest(profile=profile):
                result = self.render(profile, 'model = [', check=False)
                self.assertNotEqual(result.returncode, 0)
                self.assertEqual(result.stdout, "")


if __name__ == "__main__":
    result = unittest.main(exit=False).result
    raise SystemExit(not result.wasSuccessful() or bool(result.skipped))
