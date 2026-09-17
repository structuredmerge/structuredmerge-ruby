# Typed-core development CI

`current.yml` builds the committed generated Ruby binding from
`structuredmerge/structuredmerge` main. It does not install a fork of Alef or
regenerate bindings. The kernel revision is recorded with the exported artifact.
The kernel's export and verifier scripts must be available on that branch before
this workflow can run hosted; local commits alone do not prove that integration.

Gem-suite, coverage and dependency-HEAD jobs consume the same pre-publication
platform gem. Producer and consumers use Ruby 4.0 on Ubuntu; this is not the full
supported-platform or Ruby-version matrix. The composite installer verifies the
archive and report before a local gem install. Bundler resolves its dependencies,
then an unconditional check compares installed payload bytes and loads the core.
No filename search of a consumer Gemfile can skip that check.

The shared bundle template is copied into the selected gem as `ci_core.gemfile`.
Its location matters: kettle-test discovers the project from the bundle path.
`KETTLE_FAMILY_BUNDLE_GEMFILE` propagates that same bundle to Git subprocess tests.
Dependency-HEAD mode replaces runtime dependency declarations as before, but the
core itself remains the exact verified artifact. The bundle rejects any prototype
dependency rather than resolving it as an alternative product.

These are installed-artifact development gates, **not registry-install gates**.
They do not establish publication readiness, upstream-only generation, a default
provider change or full language parity. Clean registry installation remains a
separate post-publication gate under the active plan. Do not publish the abandoned
prototype or reintroduce its publication switches to make these jobs pass.

Local workflow checks:

```sh
actionlint .github/workflows/current.yml
python3 -m unittest discover -s .github/tests -v
```

The structural tests complement, not replace, actual artifact installation,
consumer tests and hosted workflow validation. Generated CI bundle lockfiles and
development workspace locks are not release evidence and must not be committed
with local path dependencies.
