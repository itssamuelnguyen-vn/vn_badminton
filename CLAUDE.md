# VN Badminton

Court booking web app for one badminton venue in Vietnam (Rails 8.1, PostgreSQL, Hotwire, Tailwind, Slim).
The UI is in Vietnamese (default) and English.

## Business rules

`docs/business-rules.md` lists every business rule with an ID, the code that enforces it and its tests.
When a change adds, removes or changes a rule, update that file in the same PR (and its "Cập nhật" line).
If the document and the tests disagree, the tests are right: fix the document.

## Conventions

- Views are Slim (`.html.slim`), not ERB.
- Datetime columns use `precision: 0` (enforced by `test/models/schema_conventions_test.rb`).
- Every user-facing text is in `config/locales/vi.yml` and `en.yml` with the same keys (`test/i18n`).
- The repository is public: secrets never go in it; `.kamal/secrets` only references files or variables.
- Before committing: `bin/rails test && bin/rubocop && bin/brakeman -q`; after pushing, wait for CI.
