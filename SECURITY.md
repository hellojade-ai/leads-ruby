# Security

## Reporting a vulnerability

Email **security@hellojade.ai**. Please include the gem version, a description, and
reproduction steps. Do not open a public issue for a security report. You will get an
acknowledgement within two business days.

## Your API key

- The key is a bearer credential. Keep it in an environment variable or a secret store —
  never in source, a URL, a log line, or a support ticket.
- This gem never writes the key to any error message, exception, `inspect` output or log.
  The test suite asserts this.
- If a key is exposed, contact the person at hellojade who issued it and ask for a
  rotation. Keys are stored hashed on the server; a lost key is rotated, never recovered.

## Transport

- The API is HTTPS only (TLS 1.2+, HTTP/2). There is no listener on port 80.
- The gem uses Ruby's `Net::HTTP` with certificate verification on. Do not disable it.

## Supported versions

Security fixes land on the latest minor release. Ruby 3.0 and newer are supported.
