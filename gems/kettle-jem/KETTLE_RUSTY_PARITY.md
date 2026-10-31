# kettle-jem / kettle-rusty parity inventory

Status: active inventory for phased work in structuredmerge-ruby issues #92 and
#96. This is not a parity claim. Each surface below has an explicit disposition;
the remaining audit is to map every behavior test and unsupported path.

## Scope distinction

- kettle-jem scaffolds and maintains Ruby gems and monorepos.
- kettle-rusty discovers Cargo projects and applies Rust project, packaged
  template, and README style recipes.
- Only equivalent planning, ownership, rendering, reporting, and convergence
  semantics are candidates for shared fixtures. Ruby gem metadata and Cargo
  package metadata are ecosystem-specific.

## Behavior map

| Surface | Ruby behavior and evidence | Rust behavior and evidence | Disposition |
| --- | --- | --- | --- |
| Project discovery | GemSpecReader, Gemfile/repository/monorepo facts; kettle/jem_spec_spec.rb and e2e/rubygems_thin_vertical_slice_spec.rb | Cargo package/dependency facts and workflows; rust/crates/kettle-rusty/src/lib.rs and tests/thin_slice.rs | Similar purpose, ecosystem-specific schemas. Cargo workspace selection is Rust-specific and covered by #97. |
| Configuration | Current and legacy kettle-jem config, metadata, platform and workflow controls; integration/config_metadata_template_spec.rb and kettle/jem_platforms_config_spec.rb | kettle.yml template and README settings; kettle-rusty parser/planner tests | Separate schemas. Shared unknown-key/default/precedence semantics remain a comparison candidate; no equivalence claim yet. |
| Decisions and ownership | DecisionPolicy, file work units, lock/checksum skips, conflicts and per-run decisions; integration/recipe_planning_spec.rb, byte_offset_edit_spec.rb, and integration/structural_merge_template_spec.rb | Existing destination preservation and README managed-block conflict diagnostics; tests/thin_slice.rs | Shared ownership/convergence fixture for README user-section preservation exists. Broader lock/checksum and conflict semantics remain unpaired. |
| Template selection and bootstrap | Packaged/local roots, profile filters, include/only patterns, bootstrap; integration/template_bootstrap_spec.rb and integration/recipe_planning_spec.rb | Packaged inventory and configured local entries/profile; tests/thin_slice.rs | Shared local-template output/path/idempotence fixture exists. Profile/filter parity is unproven; Ruby bootstrap has Ruby-only gem conventions. |
| Dependency generation | gemspec, Gemfile, Appraisal, dependency floors; integration/gemspec_template_spec.rb, integration/appraisals_and_gemfile_template_spec.rb, integration/appraisal_helper_and_token_spec.rb, bin/kettle_jem_deps_floor_spec.rb | Cargo dependency facts and Rust packaging; tests/thin_slice.rs | Ecosystem-specific output. Ruby dependency generation is Ruby-only. |
| Workflow generation | Ruby/platform matrices and workflow pins; integration/github_workflow_template_spec.rb, kettle/jem_style_workflow_template_spec.rb, bin/kettle_jem_workflow_pins_spec.rb | Workflow path/fact discovery and Rust CI templates; tests/thin_slice.rs | Path/fact reporting is comparable; Ruby runtime matrix and pin policy are Ruby-only unless a Rust counterpart is added. |
| README and changelog | README generation, badge normalization, package-section sync, changelog transfer; integration/readme_changelog_template_spec.rb and kettle/jem_readme_star_history_template_spec.rb | README profile/style renderer, badges, license, managed blocks; tests/thin_slice.rs | Shared user-section preservation fixture exists. Ruby changelog and Ruby-runtime badge policy are Ruby-only. |
| Apply and convergence | Recipe planning/application, bootstrap and selected post-apply tasks; integration/recipe_planning_spec.rb, integration/template_bootstrap_spec.rb, system/install_orchestration_spec.rb | Project/template/README plan and apply, second-run no-op; tests/thin_slice.rs | Shared local-template convergence fixture exists. Remaining exact report/change-set semantics require paired cases. |
| CLI and reporting | Commands, options, policy, text/debug/report outputs and statuses; cli_spec.rb and e2e/rubygems_thin_vertical_slice_spec.rb | plan/apply/template/README commands and JSON reports; rust/crates/kettle-rusty/tests/cli.rs | Contracts differ. Shared process-level failure/status conventions are candidates; no full CLI parity claim. |
| Tasks and integrations | Rake tasks for install, prepare, template and self-test; rake_tasks_spec.rb, system/install_orchestration_spec.rb, self_test_task_spec.rb | No equivalent Rake/task integration | Ruby-only orchestration. |
| Plugins and hooks | Plugin registry/loader/context and pre/post phase hooks; public implementation in lib/kettle/jem.rb | No plugin lifecycle equivalent | Ruby-only until a Rust extension contract is requested. |
| Release and packaging | Gem release packaging, require boundaries, docs and scaffold contracts; release_packaging_spec.rb, require_boundary_spec.rb, docs_rake_spec.rb, docs_no_task_control_rake_spec.rb, system/bundle_gem_scaffold_spec.rb | Cargo package metadata and CLI packaging | Ruby gem packaging rules are Ruby-only; compare only portable file ownership where an existing shared fixture applies. |

## Ruby spec-file disposition index

Every first-party spec file is listed below. Ruby-only means kettle-rusty has no
equivalent contract; candidate means comparable semantics still need paired
cases; shared refers only to the fixture IDs listed above.

| Spec paths | Disposition |
| --- | --- |
| e2e/rubygems_thin_vertical_slice_spec.rb | Mixed integration: Ruby gem discovery, recipe application, and CLI; only template convergence overlaps a shared fixture. |
| integration/recipe_planning_spec.rb; integration/template_bootstrap_spec.rb | Candidate/shared local template convergence; remaining selection and bootstrap behavior is Ruby-only or unpaired. |
| integration/structural_merge_template_spec.rb; kettle/jem_template_markdown_merge_spec.rb; byte_offset_edit_spec.rb | Shared README preservation fixture for the narrow user-owned-section case; Markdown/byte-offset algorithms are Ruby-only or unpaired. |
| integration/config_metadata_template_spec.rb; kettle/jem_platforms_config_spec.rb | Ruby config and platform policy; separate schema, semantic comparison deferred. |
| integration/gemspec_template_spec.rb; integration/appraisals_and_gemfile_template_spec.rb; integration/appraisal_helper_and_token_spec.rb; bin/kettle_jem_deps_floor_spec.rb | Ruby-only gem/dependency generation. |
| integration/github_workflow_template_spec.rb; kettle/jem_style_workflow_template_spec.rb; bin/kettle_jem_workflow_pins_spec.rb | Ruby runtime matrix and pin policy are Ruby-only; path reporting is a comparison candidate. |
| integration/readme_changelog_template_spec.rb; kettle/jem_readme_star_history_template_spec.rb; kettle/jem/maintenance_changelog_spec.rb | Shared README preservation only; changelog transfer and Ruby badge policy are Ruby-only. |
| integration/coverage_template_spec.rb; integration/duel_template_spec.rb; integration/shim_profile_spec.rb; integration/x_std_libs_sweep_reference_guard_spec.rb; template_version_gem_bootstrap_spec.rb; version_gem_pattern_spec.rb | Ruby ecosystem-specific generated artifacts and profile policy. |
| kettle/jem_style_template_spec.rb | Ruby style-template rendering and defaults; no paired Rust style-template contract is claimed. |
| cli_spec.rb | Ruby CLI options, policy, stdout/stderr and report behavior; contract differs from Rust CLI; common process failure cases remain candidates. |
| kettle/jem_spec.rb; kettle/jem/version_spec.rb; old_public_spec_audit_spec.rb; require_boundary_spec.rb | Ruby public API, versioning, compatibility and load-boundary contracts; no equivalent Rust API. |
| rake_tasks_spec.rb; kettle/jem_rake_docs_task_spec.rb; docs_rake_spec.rb; docs_no_task_control_rake_spec.rb; self_test_task_spec.rb | Ruby Rake and documentation task orchestration; Ruby-only. |
| kettle/jem/tasks/install_task_normal_lockfile_env_spec.rb; kettle/jem/tasks/prepare_task_spec.rb; system/install_orchestration_spec.rb | Ruby install/prepare orchestration, lockfile environment and side effects; Ruby-only. |
| system/bundle_gem_scaffold_spec.rb; release_packaging_spec.rb | Ruby bundle/gem scaffold and release archive contracts; Ruby-only. |

This file-level index is not an example-level audit. Mixed files need example
group dispositions before #96 can close. Passing a suite does not establish
parity. An unsupported Rust operation requires an explicit diagnostic and
regression test; it cannot be inferred from a missing crate.

## Shared fixture records

| Fixture | Consumers | Contract |
| --- | --- | --- |
| fixtures/packaging/kettle-portable-template-convergence.json | Ruby kettle-jem recipe planning; Rust kettle-rusty thin-slice | Same source/target, expected bytes, changed path, and second-run no-op. |
| fixtures/packaging/kettle-readme-preservation.json | Ruby kettle-jem structural merge; Rust kettle-rusty thin-slice | User-owned README section body survives managed section rendering; heading format is ecosystem-specific. |

Separate language-specific fixtures are test inputs, not parity evidence. No
other cross-language fixture pair is currently claimed.

## Rust workspace selection

kettle-rusty accepts a root Cargo package, one literal workspace member, or one
literal default-members entry that is also explicitly present in members.
Missing/empty workspace package selection, multiple default entries, globs, and
traversal fail closed with diagnostics. Ruby has no equivalent Cargo workspace
selection surface. Implementation and tests are recorded in #97.

## Evidence and remaining work

- Ruby focused suites recorded on #96 pass 173 examples across the e2e thin
  slice, recipe planning, template bootstrap, README/changelog, workflow, and CLI
  groups. This is Ruby implementation evidence, not cross-language parity.
- Rust cargo test -p kettle-rusty --locked passes 4 unit, 3 CLI, and 20
  thin-slice tests after the #97 workspace selection change.
- Shared fixture contracts are recorded in #98 and in the fixtures repository.
- Remaining audit: inspect every public kettle-jem behavior spec and assign each
  example group to shared semantics, Ruby-only, unsupported, or deferred.
  Expand paired fixtures only when Rust and Ruby implement the same contract.
