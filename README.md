# VN Badminton

Court booking web app for one badminton venue in Vietnam (Rails 8.1, PostgreSQL, Hotwire, Tailwind, Slim), in
Vietnamese and English. The customers' Android app is [vn_badminton_mobile](https://github.com/itssamuelnguyen-vn/vn_badminton_mobile).

- **Set up a new computer** (web, tunnel test site, Android app): [`docs/dev-setup.md`](docs/dev-setup.md)
- Business rules: [`docs/business-rules.md`](docs/business-rules.md) · processes: [`docs/business-processes.md`](docs/business-processes.md) · app API: [`docs/api.md`](docs/api.md)

```bash
bin/setup --skip-server   # gems, databases, sample venue
bin/dev                   # http://localhost:3000
bin/rails test && bin/rubocop && bin/brakeman -q
```
