Other posts in my Compatibility Matrix Series
- [How to Check License Compatibility in GHA][skywalking-eyes-howto] (License Compatibility Matrix with Apache SkyWalking Eyes)
- [ActiveRecord / SQlite3 Compatibility Matrix][ar-sqlite3]

[ar-sqlite3]: https://dev.to/galtzo/activerecord-sqlite3-compatibility-matrix-58id
[skywalking-eyes-howto]: https://dev.to/galtzo/how-to-check-license-compatibility-41h0

The world needs a modern matrix showing the maximum working versions of things in Ruby-land.  So I made this.

| ruby               | MRI   | ARM64&<br/>MacOS 12 | gem    | bundler | rubocop<br/>(install) | rubocop-lts<br/>(eval) | rails    |
|--------------------|-------|---------------------|--------|---------|-----------------------|------------------------------|----------|
| 1.8.7-p374         |       | 🙅                  |        |         | [👋][r18]             | 0.3.0                        | 4.0.x    |
| 1.9.3-p551         |       | 🙅                  | 2.7.11 | 1.17.3  | 0.41.2                | 2.3.0                        | 4.2.11.3 |
| jruby-1.7.27       | 1.9   | 🌱                  | 👆️    | 👆️     | 👆️                   | 👆️                          | 👆️      |
| 2.0.0-p648         |       | 🙅                  | 👆️    | 👆️     | 0.50.0                | 4.2.0                        | 👆️      |
| 2.1.10             |       | 🙅                  | 👆️    | 👆️     | 0.57.2                | 6.3.0                        | 👆️      |
| 2.2.10             |       | 🙅                  | 👆️    | 👆️     | 0.68.1                | 8.3.0                        | 5.2.8.1  |
| 2.3.8              |       | 🙅                  | 3.3.27 | 2.3.27  | 0.81.0                | 10.3.0                       | 👆️      |
| jruby-9.1.17.0     | 2.3   | 🌱                  | 👆️    | 👆️     | 👆️                   | 👆️                          | 👆️      |
| 2.4.10             |       | 🙅                  | 👆️    | 👆️     | 1.12.1                | 12.3.0                       | 👆️      |
| 2.5.9              |       | 🙅                  | 👆     | 👆️     | 1.28.2                | 14.3.0                       | 6.0.6.1  |
| jruby-9.2.21.0     | 2.5   | 🌱                  | 👆️    | 👆️     | 👆️                   | 👆️                          | 👆️      |
| 2.6.10             |       | 🌱                  | 3.4.22 | 2.4.22  | 1.50.2                | 16.3.0                       | 6.1.7.10 |
| jruby-9.3.15.0     | 2.6   | 🌱                  | 👆️    | 👆️     | 👆️                   | 👆️                          | 👆️      |
| 2.7.8              |       | 🌱                  | 👆️    | 👆️     | 1.80.x                | 18.4.0                       | 7.2.2.2  |
| 3.0.7              |       | 🌱                  | 3.5.23 | 2.5.23  | 👆️                   | 20.4.0                       | 👆️      |
| truffleruby-22.3.1 | 3.0   | 🌱                  | 🙅️\*  | 🙅️\*   | 👆️                   | 👆️                          | 👆️      |
| 3.1.7              |       | 🌱                  | 3.6.9  | 2.6.9   | 👆️                   | 22.3.0                       | 👆️      |
| truffleruby-23.0.0 | 3.1   | 🌱                  | 🙅️\*  | 🙅️\*   | 👆️                   | 👆️                          | 👆️      |
| jruby-9.4.12.x     | 3.1   | 🌱                  | 👆️    | 👆️     | 👆️                   | 👆️                          | 👆️      |
| 3.2.9              |       | 🌱                  | 3.7.x    | 2.7.x     | 👆️                   | 24.2.0                       | 8.0.x    |
| truffleruby-23.1.2 | 3.2   | 🌱                  | 🙅\*   | 🙅️\*   | 👆️                   | 👆️                          | 👆️      |
| 3.3.9              |       | 🌱                  | 👆️    | 👆️     | 👆️                   | 👆️                          | 👆️      |
| truffleruby-24.1.x | 3.3.5 | 🌱                  | 🙅️\*  | 🙅️\*   | 👆️                   | 👆️                          | 👆️      |
| 3.4.7              |       | 🌱                  | 👆️    | 👆️     | 👆️                   | 👆️                          | 👆️      |

[r18]:https://github.com/rubocop-lts/rubocop-ruby1_8

\* `truffleruby` intentionally does not support upgrading rubygems / bundler at all.

### Template / CI compatibility learnings

- The matrix records two Ruby compatibility concepts for alternate engines:
  - `MRI` is the language compatibility advertised by that engine release.
  - `workflow_ruby` is the appraised Ruby bucket that should be used in generated CI when the newest matching MRI bucket is not actually viable.
- `truffleruby-23.1.2` advertises MRI Ruby 3.2 compatibility, but the generated template should appraise it as Ruby 3.1 for now. Rails 8.0 failed on this engine, while the Ruby 3.1 / Rails 7.2 appraisal is the newest stable compatibility target from the recent `sanitize_email` CI pass.
- Do not upgrade RubyGems or Bundler on TruffleRuby workflows. Use the engine-provided toolchain.
- For TruffleRuby entries where `Gem.ruby_version < 3.3`, pin `psych < 5.3` if the project needs an explicit Psych dependency. `psych` 5.3.x failed to compile on older TruffleRuby during the `sanitize_email` CI pass.
- Avoid adding a root gemspec development dependency on `json` unless a project truly needs it. Recent patched `json` C-extension releases failed to build on older TruffleRuby engines during the `sanitize_email` CI pass.
- JRuby 9.3 can need `jar-dependencies ~> 0.4.1` when the resolved Psych/default-gem stack activates a newer incompatible `jar-dependencies`.

### Rubocop-LTS [Even](https://github.com/rubocop-lts/rubocop-lts#even-major-release) Versions:

```ruby
"2.0.x"
"2.2.x"
"4.2.x"
"6.2.x"
# ... etc
```

`rubocop-lts` has even versions (odds are deprecated or non-extant).

Latest even releases can be installed on Ruby 2.7+, but are able to evaluate Ruby code down to the minimum they target.
For example, the `rubocop-lts` 2.0.x track targets Ruby 1.8, and will work on libraries that support Ruby 1.8 - 3.x.
This is intended for applications and libraries that lint against a range of Ruby versions,
starting at some minimum version.

### Magic install commands

On old Rubies you can't run `gem update --system`, nor `bundle update --bundler`, because they have fallen out of support. So in order to upgrade to the latest version that will work with an older ruby you can do this instead:

```console
RUBYGEMS_VERSION=3.4.22
# Adds > /dev/null 2>&1 to make it quiet
gem install rubygems-update -v ${RUBYGEMS_VERSION} > /dev/null 2>&1
# Updates both RubyGems and Bundler!
update_rubygems > /dev/null 2>&1
```

## Support & Funding Info

I am a full-time FLOSS maintainer. If you find [my work](github.com/pboling) valuable I ask that you become a sponsor. Every dollar helps!

| 🥰 Support FLOSS work 🥰                                                                                                   | Get access                                                                                    | "Sponsors" channel                            | on Galtzo FLOSS                            | Discord 👇️ [![Live Chat on Discord][✉️discord-invite-img-ftb]][✉️discord-invite]                            |
|----------------------------------------------------------------------------------------------------------------------------|-----------------------------------------------------------------------------------------------|-----------------------------------------------|--------------------------------------------|--------------------------------------------------------------------------------------------------------------|
| [![OpenCollective Backers][🖇osc-backers-i]][🖇osc-backers] [![OpenCollective Sponsors][🖇osc-sponsors-i]][🖇osc-sponsors] | [![Buy me a coffee][🖇buyme-small-img]][🖇buyme] [![Donate at ko-fi.com][🖇kofi-img]][🖇kofi] | [![Donate on PayPal][🖇paypal-img]][🖇paypal] | [![Sponsor Me on Github][🖇sponsor-img]][🖇sponsor] [![Liberapay Goal Progress][⛳liberapay-img]][⛳liberapay] |

[⛳liberapay-img]: https://raster.shields.io/liberapay/goal/pboling.png?logo=liberapay&color=a51611&style=flat
[⛳liberapay]: https://liberapay.com/pboling/donate
[🖇osc-backers]: https://opencollective.com/rubocop-lts#backer
[🖇osc-backers-i]: https://raster.shields.io/opencollective/backers/rubocop-lts.png?style=for-the-badge
[🖇osc-sponsors]: https://opencollective.com/rubocop-lts#sponsor
[🖇osc-sponsors-i]: https://raster.shields.io/opencollective/sponsors/rubocop-lts.png?style=for-the-badge
[🖇sponsor-img]: https://raster.shields.io/badge/Sponsor_Me!-pboling.png?style=social&logo=github
[🖇sponsor]: https://github.com/sponsors/pboling
[🖇kofi-img]: https://raster.shields.io/badge/ko--fi-✓-a51611.png?style=flat
[🖇kofi]: https://ko-fi.com/O5O86SNP4
[🖇buyme-small-img]: https://raster.shields.io/badge/buy_me_a_coffee-✓-a51611.png?style=flat
[🖇buyme]: https://www.buymeacoffee.com/pboling
[🖇paypal-img]: https://raster.shields.io/badge/donate-paypal-a51611.png?style=flat&logo=paypal
[🖇paypal]: https://www.paypal.com/paypalme/peterboling
[✉️discord-invite]: https://discord.gg/3qme4XHNKN
[✉️discord-invite-img-ftb]: https://raster.shields.io/discord/1373797679469170758?style=for-the-badge

> [Cover Photo](https://unsplash.com/photos/A7EhsPtM14A) by [Sufyan](https://unsplash.com/@blenderdesigner_1688)
