"""Structural regressions for the pre-publication typed-core CI contract."""
import json
import pathlib
import subprocess
import unittest


class TypedCoreWorkflowTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.root = pathlib.Path(__file__).resolve().parents[2]
        result = subprocess.run(
            ["ruby", "-ryaml", "-rjson", "-e",
             'puts JSON.generate(YAML.load_file(".github/workflows/current.yml"))'],
            cwd=cls.root, check=True, text=True, capture_output=True)
        cls.workflow = json.loads(result.stdout)

    def test_producer_builds_kernel_without_alef_fork(self):
        producer = self.workflow["jobs"]["typed-core"]
        checkout = next(step for step in producer["steps"] if step["name"] == "Checkout kernel HEAD")
        self.assertEqual(checkout["with"]["repository"], "structuredmerge/structuredmerge")
        commands = "\n".join(step.get("run", "") for step in producer["steps"])
        self.assertIn("bundle exec rake compile", commands)
        self.assertIn("--package-only", commands)
        self.assertNotIn("cargo install", commands)
        self.assertNotIn("alef publish", commands)

    def test_all_three_consumers_require_artifact_and_load_check(self):
        for name in ["gem-suite", "coverage", "dep-heads"]:
            with self.subTest(job=name):
                job = self.workflow["jobs"][name]
                self.assertIn("typed-core", job["needs"])
                steps = job["steps"]
                setup = next(step for step in steps if step["name"] == "Setup Ruby")
                self.assertEqual(setup["with"]["ruby-version"], "4.0")
                install = next(i for i, step in enumerate(steps) if step.get("uses") == "./.github/actions/typed-core")
                bundle = next(i for i, step in enumerate(steps) if step["name"] == "Install dependencies")
                verify = next(i for i, step in enumerate(steps) if step["name"] == "Verify installed typed core loads")
                checks = next(i for i, step in enumerate(steps) if step["name"].startswith("Run checks"))
                self.assertLess(install, bundle)
                self.assertLess(bundle, verify)
                self.assertLess(verify, checks)
                self.assertNotIn("if", steps[verify])
                self.assertEqual(job["env"]["BUNDLE_GEMFILE"], job["env"]["KETTLE_FAMILY_BUNDLE_GEMFILE"])
                self.assertIn("${{ matrix.gem }}/ci_core.gemfile", job["env"]["BUNDLE_GEMFILE"])
                self.assertEqual(job["env"]["STRUCTUREDMERGE_CI_DEP_HEADS"], str(name == "dep-heads").lower())

    def test_native_provider_is_packaged_from_candidate_and_required_before_export(self):
        job = self.workflow["jobs"]["typed-core"]
        steps = job["steps"]
        candidate = next(i for i, step in enumerate(steps) if step["name"] == "Checkout Ruby provider candidate")
        self.assertEqual(steps[candidate]["with"]["path"], "native-ruby")
        self.assertNotIn("ref", steps[candidate]["with"])
        build = next(i for i, step in enumerate(steps) if "rake compile" in step.get("run", ""))
        package = next(i for i, step in enumerate(steps) if "Gem::Package.build" in step.get("run", ""))
        verify = next(i for i, step in enumerate(steps) if "--provider-gem" in step.get("run", ""))
        export = next(i for i, step in enumerate(steps) if step["name"] == "Upload typed core export")
        self.assertLess(candidate, package)
        self.assertLess(build, verify)
        self.assertLess(package, verify)
        self.assertLess(verify, export)
        self.assertEqual(steps[package]["working-directory"], "native-ruby/gems/psych-merge")
        self.assertIn("core_parser_host.rb", steps[package]["run"])
        self.assertEqual(steps[verify]["working-directory"], "kernel")
        self.assertNotIn("if", steps[verify])
        self.assertNotIn("continue-on-error", steps[verify])
        self.assertIn("set -euo pipefail", steps[verify]["run"])
        self.assertIn("ulimit -c 0", steps[verify]["run"])
        self.assertNotIn("gem push", json.dumps(job))

    def test_native_job_preserves_evidence_and_cleans_only_its_compiler_target(self):
        job = self.workflow["jobs"]["typed-core"]
        self.assertEqual(job["env"]["CARGO_BUILD_JOBS"], "1")
        self.assertEqual(job["env"]["CARGO_INCREMENTAL"], "0")
        self.assertEqual(job["env"]["CARGO_PROFILE_DEV_DEBUG"], "0")
        self.assertTrue(job["env"]["CARGO_TARGET_DIR"].endswith("/kernel/tmp/typed-core-target"))
        evidence = next(step for step in job["steps"] if step["name"] == "Upload native-provider evidence")
        self.assertEqual(evidence["if"], "always()")
        self.assertIn("failure.json", evidence["with"]["path"])
        cleanup = job["steps"][-1]
        self.assertEqual(cleanup["if"], "always()")
        self.assertEqual(cleanup["run"].count("rm -r --"), 1)
        self.assertIn("rm -r -- kernel/tmp/typed-core-target", cleanup["run"])

    def test_obsolete_producer_and_publication_switch_are_absent(self):
        text = json.dumps(self.workflow)
        for obsolete in ["rust-host", "structuredmerge-rust", "structuredmerge_host_prototype",
                         "STRUCTUREDMERGE_RUST_HOST_PUBLISHED"]:
            self.assertNotIn(obsolete, text)
        self.assertIn("typed-core", self.workflow["jobs"]["check"]["needs"])

    def test_installer_verifies_before_install_and_keeps_bundle_gem_scoped(self):
        result = subprocess.run(
            ["ruby", "-ryaml", "-rjson", "-e",
             'puts JSON.generate(YAML.load_file(".github/actions/typed-core/action.yml"))'],
            cwd=self.root, check=True, text=True, capture_output=True)
        steps = json.loads(result.stdout)["runs"]["steps"]
        self.assertEqual(steps[0]["with"]["name"], "structuredmerge-core-head")
        commands = steps[1]["run"]
        self.assertLess(commands.index("verify_core_ruby_export.rb"), commands.index("gem install"))
        self.assertIn("--local", commands)
        self.assertIn('${STRUCTUREDMERGE_CI_GEM_DIR}/ci_core.gemfile', commands)


if __name__ == "__main__":
    unittest.main()
