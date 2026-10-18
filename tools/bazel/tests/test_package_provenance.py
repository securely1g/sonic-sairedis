"""Regressions for the effective CI registry and exact Git source overrides."""

import importlib.util
import json
from pathlib import Path
from types import SimpleNamespace
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[3]
SPEC = importlib.util.spec_from_file_location("verify_packages", ROOT / "bazel/ci/verify_packages.py")
VERIFIER = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(VERIFIER)

MAIN = "https://raw.githubusercontent.com/securely1g/sonic-bazel-registry/main"
REVIEWED = MAIN.removesuffix("main") + "codex/source-debian-runtime-dependencies"
COMMIT = "2ef9d75f145bb25a6c614460624fc62360e89ed5"
OVERRIDE = ('git_override(module_name="sonic-swss-common", '
            'remote="https://github.com/securely1g/sonic-swss-common.git", '
            f'commit="{COMMIT}")\n')


class PackageProvenanceTest(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.repo = Path(self.temporary.name)
        self.execution = self.repo / "execroot"
        self.validation = self.repo / "validation"
        self.validation.mkdir()
        (self.repo / ".bazelrc").write_text("common --registry=" + MAIN + "\n")
        self.rc = self.validation / "effective.bazelrc"
        self.rc.write_text("common --registry=" + REVIEWED + "\n")
        (self.repo / "MODULE.bazel").write_text(OVERRIDE)
        self.versions = {"sai": "1.18.0-sonic.1", "sonic-swss-common": "old-registered-version",
                         "sonic-build-infra": "0.0.16-reviewed"}
        self.lock = {}
        for name, version in self.versions.items():
            root = self.execution / "external" / (name + "+")
            root.mkdir(parents=True)
            fetched = "0.0.4" if name == "sonic-swss-common" else version
            (root / "MODULE.bazel").write_text(f'module(name="{name}", version="{fetched}")\n')
            if name != "sonic-swss-common":
                self.lock[REVIEWED + f"/modules/{name}/{version}/source.json"] = "a" * 64
            if name == "sai":
                (root / "SOURCE_PROVENANCE.json").write_text(json.dumps({"source_commit": "b" * 40}))
        self.write_lock()
        self.args = SimpleNamespace(bazel="bazel", bazel_config="", effective_bazelrc=self.rc)

    def write_lock(self):
        (self.repo / "MODULE.bazel.lock").write_text(json.dumps({"registryFileHashes": self.lock}))

    @staticmethod
    def query(command, *_args):
        target = command[2]
        canonical = ("sai+" if "@sai_source" in target else
                     "sonic-swss-common+" if "@sonic_swss_common" in target else "sonic-build-infra+")
        return (canonical + "\n").encode()

    def resolve(self):
        with patch.object(VERIFIER, "run_command", side_effect=self.query):
            return VERIFIER.resolved_dependency_provenance(
                self.args, self.repo, self.validation, self.execution,
                {"bazel_dependency_versions": self.versions})

    def test_effective_registry_and_git_commit_are_retained(self):
        result = self.resolve()
        self.assertEqual(result["sonic-swss-common"]["version"], "0.0.4")
        self.assertEqual(result["sonic-swss-common"]["git_source"]["commit"], COMMIT)
        self.assertNotIn("registry_source", result["sonic-swss-common"])
        self.assertEqual(result["sai"]["registry_source"], {
            REVIEWED + "/modules/sai/1.18.0-sonic.1/source.json": "a" * 64})
        self.assertEqual(result["sai"]["source_provenance"]["source_commit"], "b" * 40)

    def test_tracked_main_cannot_substitute_for_effective_registry(self):
        self.args.effective_bazelrc = None
        with self.assertRaisesRegex(ValueError, "one selected registry source: sai"):
            self.resolve()

    def test_unconfigured_registry_is_rejected(self):
        self.rc.write_text("common --registry=https://example.invalid/registry\n")
        with self.assertRaisesRegex(ValueError, "one selected registry source: sai"):
            self.resolve()

    def test_multiple_source_records_are_still_rejected(self):
        self.rc.write_text(self.rc.read_text() + "common --registry=" + MAIN + "\n")
        self.lock[MAIN + "/modules/sai/1.18.0-sonic.1/source.json"] = "a" * 64
        self.write_lock()
        with self.assertRaisesRegex(ValueError, "one selected registry source: sai"):
            self.resolve()

    def test_registry_version_mismatch_is_rejected(self):
        module = self.execution / "external/sai+/MODULE.bazel"
        module.write_text('module(name="sai", version="another-version")')
        with self.assertRaisesRegex(ValueError, "resolved module differs"):
            self.resolve()

    def test_git_module_identity_is_still_checked(self):
        module = self.execution / "external/sonic-swss-common+/MODULE.bazel"
        module.write_text('module(name="unrelated", version="0.0.4")')
        with self.assertRaisesRegex(ValueError, "resolved module differs"):
            self.resolve()

    def test_moving_git_refs_and_additional_source_changes_are_rejected(self):
        for declaration in (OVERRIDE.replace(COMMIT, "master"),
                            OVERRIDE.replace('commit=', 'branch='),
                            OVERRIDE.replace(')', ', patches=["extra.patch"])')):
            with self.subTest(declaration=declaration), self.assertRaises(ValueError):
                VERIFIER.declared_git_sources(declaration)


if __name__ == "__main__":
    unittest.main()
