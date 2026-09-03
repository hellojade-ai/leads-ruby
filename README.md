# hellojade-intake (Ruby)

Ruby client for the **hellojade Partner Intake API** — one `POST` that hands a lead to a
hellojade customer, durably, with idempotency and sane retries built in.

- Ruby ≥ 3.0, `Net::HTTP` only, **no runtime dependencies**
- Typed `Lead`, `Accepted`, `ApiError`, `ValidationError#fields`, `RateLimited#retry_after`
- Retry policy that follows the API's rules: 5xx and timeouts back off, `429` honors
  `Retry-After` without spending a delivery attempt, every other 4xx is final
- The API key never appears in an exception, `inspect` or log line (tested)

| | |
|---|---|
| API reference and live playground | <https://intake.hellojade.ai/api> |
| OpenAPI 3.0 contract | <https://intake.hellojade.ai/api/openapi.json> |
| Integration brief (the eight rules) | <https://intake.hellojade.ai/api/INTEGRATION.md> |
| Becoming a lead provider | <https://hellojade.ai/developers/provide-leads> |
| Other kits | [PHP](https://github.com/hellojade-ai/hellojade-php) · [Java](https://github.com/hellojade-ai/hellojade-java) · [.NET](https://github.com/hellojade-ai/hellojade-dotnet) |

## Install

The gem is distributed from GitHub, not RubyGems. In your `Gemfile`:

```ruby
gem "hellojade-intake", git: "https://github.com/hellojade-ai/hellojade-ruby", tag: "v0.1.0"
```

Or build it locally: `gem build hellojade-intake.gemspec && gem install ./hellojade-intake-0.1.0.gem`.

```ruby
require "hellojade/intake"
```

## Quickstart

### 1. Prove the key first — it stores nothing

The API authenticates *before* it validates, so an empty body sent with a valid key comes
back `422` and nothing is stored, delivered or emailed. Do this before writing any code and
again on launch day.

```ruby
client = Hellojade::Intake::Client.new(api_key: ENV.fetch("HELLOJADE_API_KEY"))

client.check_key   # => true  (422: key valid, nothing stored)
                   # => false (401: missing, mistyped, revoked, or wrong host)
```

### 2. Submit a lead

```ruby
lead = Hellojade::Intake::Lead.new(
  first_name: "Dana",
  last_name: "Whitfield",
  phone: "(630) 555-0142",
  email: "dana.whitfield@example.com",
  street_address: "418 N Maple St",
  city: "Naperville",
  state: "IL",
  zip: "60540",
  country: "US",
  project_area: "roof",                 # live list: client.vocabulary
  project_service: "replacement",       # replacement | repair | remodel | maintain
  project_material: "asphalt shingle",
  project_details: "Hail damage on the south slope, insurance claim already filed.",
  external_id: "A-99812",
  cost: 555.55,                         # omit if there is no charge — never send 0
  extra: { "partner_job_id" => "XZ-1" } # unmodeled fields are preserved, never rejected
)

result = client.submit_lead(lead, idempotency_key: "acme-leads:A-99812", request_id: "acme-leads/A-99812")

result.event_id   # "evt_0198f2c1a4b00000a3d19f4c2b7e" — store this against your lead
result.status     # "accepted" (202) or "duplicate" (200) — both are success
result.source     # your key's registered label
result.flags      # [] — non-fatal observations, never errors
```

Only `first_name`, `last_name` and `phone` are required. Send everything you have and
nothing you do not — a `nil` field is omitted from the JSON, never sent as `null` or a
placeholder. Do **not** send `source`: it comes from your API key and the `Lead` refuses it.

### 3. Handle every outcome

```ruby
begin
  result = client.submit_lead(lead, idempotency_key: "acme-leads:#{lead_id}")
rescue Hellojade::Intake::ValidationError => e   # 422
  e.fields      # {"first_name"=>"required", "phone"=>"required"} — ALL failing fields at once
  e.request_id
rescue Hellojade::Intake::Unauthorized => e      # 401 — configuration problem, not a retry
rescue Hellojade::Intake::RateLimited => e       # 429, after the wait budget is spent
  e.retry_after
rescue Hellojade::Intake::ApiError => e          # 400, 413, or a 5xx after retries
  e.status; e.code; e.request_id
rescue Hellojade::Intake::TransportError => e    # no response after retries
  e.attempts
end
```

Full, runnable versions are in [`examples/`](examples/).

## Client options

```ruby
Hellojade::Intake::Client.new(
  api_key:      ENV.fetch("HELLOJADE_API_KEY"),   # required; from env or a secret store, never source
  base_url:     "https://intake.hellojade.ai",    # HTTPS only — there is no listener on port 80
  timeout:      20,                               # seconds; the API bounds its own handler at 20 s
  user_agent:   "acme-leads-sync/2.3",            # appended to hellojade-intake-ruby/<version>
  retry_policy: Hellojade::Intake::RetryPolicy.new(
    max_attempts: 5,          # delivery attempts (a 429 does not consume one)
    max_rate_limit_waits: 10, # consecutive 429s to wait out before raising RateLimited
    base_delay: 1.0,          # backoff = min(base * 2**(n-1), max) + rand * jitter
    max_delay: 30.0,
    jitter: 0.5
  )
)
```

`RetryPolicy.none` makes exactly one attempt for callers that run their own loop.

## Client surface

| method | HTTP | returns |
|---|---|---|
| `check_key(request_id: nil)` | `POST /v1/intake` with `{}` | `true` on 422, `false` on 401 |
| `submit_lead(lead, idempotency_key:, request_id: nil)` | `POST /v1/intake` | `Accepted` on 202 or 200 |
| `vocabulary` | `GET /v1/vocabulary` (unauthenticated) | `Vocabulary` — `project_area` terms with status, `project_service` enum, `required` |
| `health` | `GET /healthz` (unauthenticated) | `Health` for both 200 and 503 |

`lead` may be a `Lead` or a plain `Hash`. `Lead.from_h(hash)` routes unmodeled keys into
`extra` for you.

## Errors

| HTTP | API `error` | raised | retried? | what to do |
|---|---|---|---|---|
| 202 | — | *(returns `Accepted`, status `accepted`)* | — | store `event_id`; done |
| 200 | — | *(returns `Accepted`, status `duplicate`)* | — | same `event_id` as before; done |
| 400 | `invalid_json` | `ApiError` | no | log, alert |
| 401 | `unauthorized` | `Unauthorized` | no | fix the key / host; see the key check |
| 413 | `body_too_large` | `ApiError` | no | body over 64 KiB — trim `project_details` |
| 422 | `validation_failed` | `ValidationError` (`#fields`) | no | fix every listed field |
| 429 | `rate_limited` | `RateLimited` (`#retry_after`) only after the wait budget | yes — waits `max(Retry-After, backoff)` | usually nothing; back off further if sustained |
| 503 | `not_accepting` | `ApiError` after `max_attempts` | yes — exponential backoff | this is hellojade's side |
| other 5xx | — | `ApiError` after `max_attempts` | yes | |
| no response | — | `TransportError` after `max_attempts` | yes | check `https://`, egress, DNS |

Every error carries `request_id` (from the body, or the `X-Request-Id` header when the
body has none). Quote it — or the `event_id` — in any support conversation. Never the key.

## Retry and idempotency semantics

1. **Always send `idempotency_key`, and make it your own stable id for the lead**, namespaced
   to you: `acme-leads:1234`, not `1234`, not a timestamp, not a fresh UUID per attempt.
   Dedupe is scoped to the *tenant*, so a bare `1234` can collide with another source's lead
   and yours is silently never stored. The client refuses an empty key.
2. A repeat of an accepted key returns `200` with the **original** `event_id` and status
   `duplicate`. That is success — it is what a retry is supposed to produce.
3. **Retries are automatic** for transport errors (DNS, connect, TLS, timeout) and 5xx, with
   exponential backoff plus jitter, up to `max_attempts`. The same `Idempotency-Key` goes out
   on every attempt, so a request that actually arrived cannot create a duplicate.
4. **`429` waits `max(Retry-After, backoff(n))`** and does not consume a delivery attempt.
   `Retry-After` is a floor, not a strategy, so the wait grows with consecutive 429s.
5. **Any other 4xx is never retried.** A `422` means the body needs fixing; a `401` means the
   configuration does.
6. **Flags are not errors.** `phone_unnormalized`, `project_area_unknown`,
   `project_service_unknown`, `email_shape_suspect`, `extra_fields_preserved` and
   `country_unrecognized` arrive on a *successful* response. Read them, do not retry on them.
7. A `422` does not consume the `Idempotency-Key`; send the same key again with a fixed body.
8. `X-Request-Id`: pass your own correlation id (≤ 64 chars) or let the client generate one.
   It is echoed in the response header and in any error body.

## Development

```sh
bundle install
bundle exec rake test     # minitest against a local WEBrick stub — nothing touches the real API
bundle exec rubocop
```

The suite scripts every documented status code (200, 202, 400, 401, 413, 422, 429, 503,
plus timeouts and connection refusals) and asserts the exact backoff sequence, the
`Retry-After` handling, that a 429 does not consume an attempt, and that the API key never
appears in an exception.

## Releasing

Tags on GitHub only — this gem is **not** published to RubyGems. See
[CONTRIBUTING.md](CONTRIBUTING.md#releasing).

## License

[MIT](LICENSE) © hellojade
