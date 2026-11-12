#!/usr/bin/env python3
"""Check the deployment fragment through APT's real parser without changing the host."""

import pathlib
import subprocess
import tempfile
import unittest


CONFIG = pathlib.Path(__file__).resolve().parents[1] / "hardening/apt/52unattended-upgrades-local"


class AptPolicyTests(unittest.TestCase):
    def settings(self, later_override=""):
        with tempfile.TemporaryDirectory() as temporary:
            root = pathlib.Path(temporary)
            parts = root / "parts"
            parts.mkdir()
            (parts / "50defaults").write_text(
                'Unattended-Upgrade::Origins-Pattern { "origin=Debian,label=Debian-Security"; };\n'
            )
            (parts / CONFIG.name).write_bytes(CONFIG.read_bytes())
            (parts / "99override").write_text(later_override)
            bootstrap = root / "apt.conf"
            bootstrap.write_text(
                f'Dir::Etc::parts "{parts}";\nDir::Etc::main "/dev/null";\n'
            )
            result = subprocess.run(
                ["apt-config", "dump"], env={"APT_CONFIG": str(bootstrap)},
                check=True, capture_output=True, text=True,
            )
            return result.stdout

    def test_required_reboots_use_the_selected_window(self):
        settings = self.settings()
        self.assertIn('Unattended-Upgrade::Automatic-Reboot "true";', settings)
        self.assertIn('Unattended-Upgrade::Automatic-Reboot-Time "04:00";', settings)
        self.assertIn('Unattended-Upgrade::Automatic-Reboot-WithUsers "true";', settings)

    def test_local_policy_preserves_security_origins(self):
        settings = self.settings()
        self.assertIn('"origin=Debian,label=Debian-Security";', settings)
        self.assertIn('"origin=Debian,codename=${distro_codename}-updates,label=Debian";', settings)

    def test_later_emergency_override_disables_automatic_reboots(self):
        settings = self.settings('Unattended-Upgrade::Automatic-Reboot "false";\n')
        self.assertIn('Unattended-Upgrade::Automatic-Reboot "false";', settings)
        self.assertNotIn('Unattended-Upgrade::Automatic-Reboot "true";', settings)


if __name__ == "__main__":
    unittest.main()
