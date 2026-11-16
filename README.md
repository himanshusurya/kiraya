# Kiraya — PG / tenant management

Two Android apps on one free backend, for a single PG building:

| App | Who | What |
|---|---|---|
| **Kiraya Owner** (`apps/owner`) | Owner (2 logins, same data) | Rooms, tenants, meter readings, bills, payments, move-out, reports |
| **Kiraya** (`apps/tenant`) | Every occupant | See bills & hisaab, pay by UPI and tap "I paid", notices, complaints |

Design: [`docs/HLD.md`](docs/HLD.md) (also `docs/HLD.docx`). English by default, simple Hindi via the हिं button.

```
apps/owner      Flutter owner app
apps/tenant     Flutter tenant app
packages/core   shared code: Supabase API, i18n (en/hi), widgets, updater
supabase/       Postgres schema, billing logic (RPCs), security (RLS), edge function, tests
scripts/        create-owner, CSV history import, build-box setup
.github/        daily cron, nightly backup, APK release on tag
```

## Cost: ₹0 / month

Supabase Free (DB + auth + storage + edge function), GitHub Actions + Releases (APK hosting and updates),
WhatsApp via `wa.me` links (no API). No Play Store fee: the APK is shared directly and the apps
update themselves from GitHub Releases.

## One-time setup

1. **Supabase**: create a [personal access token](https://supabase.com/dashboard/account/tokens), then run
   `scripts\setup-supabase.ps1` (token in `SUPABASE_ACCESS_TOKEN` or a DPAPI file, see the script header). It creates
   the free Mumbai project, turns off email confirmation and public sign-up, pushes migrations + seed, deploys
   `manage-login`, and stores the `SUPABASE_*` GitHub secrets. Manual equivalent with the
   [Supabase CLI](https://supabase.com/docs/guides/cli) (v3):
   ```sh
   supabase link --project-ref <ref>
   supabase db push --remote --include-seed   # runs supabase/migrations + seed.sql (building, 16 rooms, default settings)
   supabase functions deploy manage-login --use-api
   ```
   In *Authentication → Providers → Email*, turn **off** "Confirm email" (logins are phone + PIN) and disable sign-ups.
   After deploy, set the building name/address in the `property` table and the UPI ID/name in the owner app's Settings.
2. **Owner logins** (once per person):
   ```powershell
   .\scripts\create-owner.ps1 -Url https://<ref>.supabase.co -ServiceKey <service_role key> -Name "Papa" -Phone 98xxxxxxxx
   ```
3. **Signing key** (once — keep a backup; every update must use the same key or phones will reject it):
   ```sh
   keytool -genkey -v -keystore kiraya.jks -keyalg RSA -keysize 2048 -validity 10000 -alias kiraya
   ```
   Local builds: create `apps/<app>/android/key.properties` (git-ignored):
   ```
   storeFile=C:/path/kiraya.jks
   storePassword=...
   keyAlias=kiraya
   keyPassword=...
   ```
4. **GitHub secrets** (repo → Settings → Secrets → Actions):
   `SUPABASE_URL`, `SUPABASE_ANON_KEY`, `SUPABASE_SERVICE_ROLE_KEY`, `SUPABASE_DB_URL` (session pooler URI),
   `BACKUP_PASSPHRASE`, `KEYSTORE_B64` (`base64 -w0 kiraya.jks`), `KEYSTORE_PASSWORD`, `KEY_ALIAS`.
   The in-app update check reads `releases/latest` without a token, so the releases must be public
   (public repo, or a separate public repo used only for releases).

## Build & release

```sh
flutter pub get                         # at repo root (pub workspace)
cd apps/owner
flutter build apk --release --dart-define=SUPABASE_URL=https://<ref>.supabase.co \
  --dart-define=SUPABASE_ANON_KEY=<anon key> --dart-define=GITHUB_REPO=<owner>/<repo>
```

Release: bump `version:` in both `apps/*/pubspec.yaml`, then `git tag v0.2.0 && git push --tags`.
The `release` workflow tests, builds both APKs with the same key (versionCode derived from the tag),
and publishes them. **Every shipped change gets a new version.**

## Import the 6-month paper ledger

1. Add each current tenant in the Owner app (room, move-in date, rent, advance).
2. Fill a CSV like [`scripts/import/history.template.csv`](scripts/import/history.template.csv).
3. `node scripts/import/import-history.mjs history.csv --dry-run` — check each room's balance against the register.
4. Set `SUPABASE_URL`, `SUPABASE_ANON_KEY`, `OWNER_PHONE`, `OWNER_PIN` and run without `--dry-run`.

## Tests

```sh
cd supabase/tests && npm ci && node --test     # billing, move-out, shift, security (PGlite, no server)
cd packages/core && flutter test
cd apps/owner && flutter test
cd apps/tenant && flutter test
```

## Notes

- **Money rules live in the database** (`supabase/migrations/*_logic.sql`): bills are drafts until sent,
  the ledger is append-only (fix mistakes with a correction entry), payments can be cancelled, every change is audited.
- **Translations** are Dart maps (`packages/core/lib/src/i18n.dart` + each app's `strings*.dart`); use everyday
  spoken Hindi, not formal words.
- Electricity rate, cleaning charge, notice period, bill due days and reminder text are editable in Owner → Settings.
