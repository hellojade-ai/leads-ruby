# Contributing

Thanks for helping partners send leads correctly.

## Ground rules

- **The API contract is the source of truth**, not this gem. If the gem and
  <https://intake.hellojade.ai/api/openapi.json> disagree, the gem is wrong — open an
  issue with the request, the response, and the `request_id`.
- **Never post real-looking leads to production while developing.** The test suite runs
  against a local stub. To exercise the live endpoint, use the key check
  (`Client#check_key`, which stores nothing) or ask hellojade for a sandbox key.
- **Never commit an API key.** `grep -r "hj_" .` before you push; CI does not know your
  key and cannot catch it for you.
- **No runtime dependencies.** The client is `Net::HTTP` only, on purpose. Development
  dependencies (minitest, rake, rubocop, webrick) are fine.
- American English in code, comments and docs.

## Setup

```sh
git clone https://github.com/hellojade-ai/hellojade-ruby
cd hellojade-ruby
bundle install
bundle exec rake test
bundle exec rubocop
```

## Making a change

1. Branch from `main`.
2. Add or update a test in `test/` first. Every documented status code has a test; a
   behavior change without one will not be merged.
3. Keep `README.md` and `CHANGELOG.md` current in the same pull request.
4. Open a pull request. CI runs the suite on every supported Ruby.

## Releasing

Releases are GitHub tags, not RubyGems (see the README). Bump
`lib/hellojade/intake/version.rb`, add a CHANGELOG entry, commit, then:

```sh
git tag -a vX.Y.Z -m "hellojade-intake vX.Y.Z"
git push origin main --tags
```
