# VN Badminton

Court booking web app for one badminton venue in Vietnam (Rails 8.1, PostgreSQL, Hotwire, Tailwind, Slim).
The UI is in Vietnamese (default) and English.

## Business rules

`docs/business-rules.md` lists every business rule with an ID, the code that enforces it and its tests.
When a change adds, removes or changes a rule, update that file in the same PR (and its "Cập nhật" line).
If the document and the tests disagree, the tests are right: fix the document.
`docs/business-processes.md` describes the step-by-step processes per role, citing those rule IDs: update it in the same PR
when a change alters a process (a new step, screen or role).

## Conventions

- Views are Slim (`.html.slim`), not ERB.
- Datetime columns use `precision: 0` (enforced by `test/models/schema_conventions_test.rb`).
- Every user-facing text is in `config/locales/vi.yml` and `en.yml` with the same keys (`test/i18n`).
- The repository is public: secrets never go in it; `.kamal/secrets` only references files or variables.
- Before committing: `bin/rails test && bin/rubocop && bin/brakeman -q`; after pushing, do not wait for CI (see below).

## GitHub usage rules (IMPORTANT – my account was once suspended for bot-like activity)

Every git/gh action you run counts as activity from my personal account.
Behave like a careful human developer, not an automation script.

### 1. No polling or watching
- NEVER run `gh pr checks --watch`, `gh run watch`, or any loop that repeatedly
  checks status (no while/sleep loops, no `watch` command).
- After pushing, do NOT wait for CI. Tell me the PR is pushed and stop.
  I will check CI myself, or ask you to check once.
- If I ask you to check CI: run ONE check command. If it is still running,
  report that and stop. Do not re-check unless I ask again.

### 2. Fewer, larger pull requests
- Group related changes into one PR per feature or fix. Do not open a PR
  for every small change.
- Aim for at most 3–5 PRs per day. If we are about to exceed that, tell me
  and suggest combining the work.
- Do NOT merge PRs automatically. Ask me before every merge.

### 3. Ask before any account-level or bulk action
Ask for my confirmation before:
- `git push --force`, deleting branches, or rewriting history
- creating/deleting repositories, changing repo settings, secrets, or webhooks
- creating multiple issues, labels, comments, or releases in a row
- any `gh api` call inside a loop or script

### 4. GitHub Actions
- Do not add scheduled (cron) workflows without asking me.
- Workflows must use `concurrency` with `cancel-in-progress` so repeated pushes
  to a PR do not stack up runs (cancel only PR runs, not runs on `main`).
- Do not re-run failed jobs repeatedly. If CI fails, read the logs once,
  fix the code locally, then push.

### 5. Errors and rate limits
- If any GitHub command returns a rate-limit error, HTTP 403/429, or an
  "abuse detection" / "secondary rate limit" message: STOP all GitHub
  activity immediately and tell me. Do not retry.

### 6. Security
- Never commit secrets, `.env` files, credentials, or `config/master.key`.
- Run `bin/rails test && bin/rubocop && bin/brakeman -q` locally before pushing,
  so CI is not used as a trial-and-error loop.

### 7. GitHub activity summary
At the end of every reply in which you ran GitHub commands, list each GitHub action
you performed (pushes, PRs opened/merged, API calls) so I can review my account activity.
