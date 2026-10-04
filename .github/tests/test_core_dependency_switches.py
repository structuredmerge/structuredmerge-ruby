"""Evaluate real Bundler DSLs without installing packages or fetching repositories."""
import json
import pathlib
import subprocess
import unittest


class CoreDependencySwitchTest(unittest.TestCase):
    root = pathlib.Path(__file__).resolve().parents[2]
    consumers = ["ast-crispr", "ast-template", "ast-merge-git", "bash-merge",
                 "go-merge", "json-merge", "rust-merge", "typescript-merge", "tree_haver"]
    native_only = ["yaml-merge", "markdown-merge", "kettle-jem"]

    def evaluate(self, names, switches):
        script = r'''
require "bundler"
require "json"
# Evaluate configuration, never regex-match Ruby source or resolve/install gems.
%w[STRUCTUREDMERGE_CORE_DEV STRUCTUREDMERGE_CORE_PUBLISHED STRUCTUREDMERGE_RUST_DEV
   STRUCTUREDMERGE_RUST_HOST_PUBLISHED STRUCTUREDMERGE_DEV K_JEM_TEMPLATING
   KETTLE_DEV_DEV GALTZO_FLOSS_DEV UR_BRAIN_DEV].each { |key| ENV[key] = "false" }
JSON.parse(ARGV.shift).each { |key, value| ENV[key] = value }
result = ARGV.to_h do |name|
  dsl = Bundler::Dsl.new
  dsl.eval_gemfile(File.join("gems", name, "Gemfile"))
  selected = dsl.dependencies.select { |dep| ["structuredmerge-core", "structuredmerge_host_prototype"].include?(dep.name) }
  [name, selected.map { |dep| {name: dep.name, requirement: dep.requirement.to_s,
    path: dep.source.is_a?(Bundler::Source::Path) ? dep.source.path.to_s : nil} }]
end
puts JSON.generate(result: result, home: Dir.home)
'''
        completed = subprocess.run(["ruby", "-e", script, json.dumps(switches), *names],
                                   cwd=self.root, text=True, capture_output=True, check=True)
        return json.loads(completed.stdout)

    def test_default_and_false_values_do_not_add_core(self):
        for value in [None, "", "false", "0", "no", "off"]:
            with self.subTest(value=value):
                result = self.evaluate(self.consumers, {"STRUCTUREDMERGE_CORE_DEV": value})
                self.assertTrue(all(not deps for deps in result["result"].values()))

    def test_explicit_paths_and_true_workspace_default(self):
        for value in ["/workspace/kernel", "src/custom-kernel", "true", "1", "yes", "on"]:
            with self.subTest(value=value):
                result = self.evaluate(self.consumers, {"STRUCTUREDMERGE_CORE_DEV": value,
                                                        "STRUCTUREDMERGE_CORE_PUBLISHED": "true"})
                home = pathlib.Path(result["home"])
                expected = (home / "src/my/structuredmerge/structuredmerge" if value in ["true", "1", "yes", "on"]
                            else home / value) / "packages/ruby"
                for name, deps in result["result"].items():
                    self.assertEqual(deps, [{"name": "structuredmerge-core", "requirement": ">= 0",
                                             "path": str(expected)}], name)

    def test_registry_switch_selects_only_intended_package(self):
        result = self.evaluate(self.consumers, {"STRUCTUREDMERGE_CORE_PUBLISHED": "true"})
        for name, deps in result["result"].items():
            self.assertEqual(deps, [{"name": "structuredmerge-core", "requirement": "~> 0.2", "path": None}], name)

    def test_old_switches_cannot_select_prototype_or_kernel(self):
        result = self.evaluate(self.consumers + self.native_only,
                               {"STRUCTUREDMERGE_RUST_DEV": "/workspace/old-rust",
                                "STRUCTUREDMERGE_RUST_HOST_PUBLISHED": "true"})
        self.assertTrue(all(not deps for deps in result["result"].values()))

    def test_native_only_gems_do_not_gain_unneeded_core_dependency(self):
        result = self.evaluate(self.native_only, {"STRUCTUREDMERGE_CORE_DEV": "/workspace/kernel",
                                                  "STRUCTUREDMERGE_CORE_PUBLISHED": "true"})
        self.assertTrue(all(not deps for deps in result["result"].values()))


if __name__ == "__main__":
    unittest.main()
