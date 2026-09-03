# Changelog

All notable changes to this gem are recorded here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and the gem follows
[Semantic Versioning](https://semver.org/).

## [0.1.0] — 2026-09-03

### Added

- `Hellojade::Intake::Client` with `check_key`, `submit_lead`, `vocabulary` and `health`.
- `Lead` value object with every modeled field, top-level `extra` passthrough, and
  guards against the reserved `source` / `extra` keys.
- `Accepted`, `Vocabulary`, `Health` response structs.
- `ApiError`, `Unauthorized`, `ValidationError` (with `fields`), `RateLimited`
  (with `retry_after`) and `TransportError`.
- `RetryPolicy`: exponential backoff with jitter on 5xx and transport errors,
  `Retry-After`-aware waits on 429 that do not consume a delivery attempt, no
  retry on any other 4xx.
- Minitest suite against a local WEBrick stub covering every documented status.
- CI on Ruby 3.1, 3.2, 3.3 and 3.4.

[0.1.0]: https://github.com/hellojade-ai/leads-ruby/releases/tag/v0.1.0
