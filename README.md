# Stray's Call

Stray's Call is a mobile-first Progressive Web App for reporting injured stray
animals and getting them to a veterinary clinic. It is built for Azerbaijan
and available in Azerbaijani, Turkish and English.

How a case moves through the app:

1. Anyone reports an animal with a photo taken in the app's live camera and a
   map pin. Guests can report without an account; they get an anonymous
   session and must confirm they are 18 or older and accept the Terms.
2. A registered user accepts the case as its rescuer.
3. The rescuer picks a verified clinic. The clinic confirms it can take the
   animal, the rescuer marks that they are on the way, and the clinic confirms
   delivery.
4. Open case screens update without a reload when the status changes. The
   app does not receive case rows over Realtime; it listens for changes to
   the small `case_signals` table (a case id and a timestamp, updated by a
   trigger when a public case column changes) and for new `case_events`
   rows, then fetches the case again through the API. People following a
   case also get a notification. Each case has a group chat; the clinic can pin one of its own messages (for example
   bank details for treatment costs). Payments happen outside the app.

The case statuses are `open`, `accepted`, `vet_selected`, `vet_confirmed`,
`en_route`, `resolved` and `closed`. The transitions are enforced in the
database, not in the client.

## Features

These are present in the code (`src/App.tsx` routes, `src/pages/`,
`src/lib/api.ts`, `supabase/migrations/`):

- Home screen with open cases as a list and on a Google Map.
- Report flow (`/report`): live in-app camera only (no file picker), map pin,
  animal type, injury and spot type, urgency (low / medium / high / critical),
  optional landmark, and optional "needs" (water, food, carrier, blanket,
  first aid, transport). A street address is reverse-geocoded from the pin.
- Reports that fail because of bad signal are kept in IndexedDB and sent when
  the device is back online (`src/lib/offlineQueue.ts`).
- Case detail (`/case/:id`) with a status timeline, the rescuer's live
  location visible only to case participants, and a "not here" signal from
  the community.
- Vet picker (`/case/:id/vets`) listing approved clinics: open clinics
  first, then by distance, adjusted by rating. Clinics set their opening
  hours.
- Case chat (`/case/:id/chat`) with read state, one pinned clinic message, and
  a clinic option to close the chat.
- Direct messages (`/messages`): a user can start a conversation with an
  approved clinic; clinics reply but cannot start one; users cannot message
  each other.
- In-app notifications (`/alerts`), optional Web Push, and per-type
  notification switches in Settings.
- Clinic accounts: clinic setup with verification documents (`/vet-setup`),
  a vet dashboard (`/vet-dashboard`), public clinic pages (`/vet/:id`), and
  star ratings from rescuers after a confirmed delivery.
- Profiles with XP and tiers: when a case resolves, the rescuer gets +10 XP
  and the reporter +5 (only if the case is not hidden). Clinics get no XP.
- Advisory duplicate detection: location, time and an on-device perceptual
  photo hash (`src/lib/phash.ts`) produce a "same animal?" flag. It never
  blocks a report.
- Unanswered cases are escalated to more users after 30 minutes, abandoned
  rescues revert to open, and unclaimed cases expire, through a scheduled
  maintenance job.
- Admin screen (`/admin`) with tabs for stats, users, DMs, clinic approvals,
  content reports, accounts with many recent reports against them, and
  sponsors.
- Case photos can start blurred; the viewer chooses which ones in Settings
  (`src/lib/sensitive.ts`).
- Sign-in with email and password or Google, password reset, account
  deletion, and data export.
- Info pages: privacy, terms, safety, community guidelines, about, contact,
  FAQ.

## Stack

| Layer | What is used |
| --- | --- |
| Frontend | React `^18.3.1`, React Router `^6.28.0`, TypeScript `^5.6.3`, Vite `^5.4.11` |
| PWA | `vite-plugin-pwa` `^0.21.1` in `injectManifest` mode with a custom service worker (`src/sw.ts`) built on Workbox 7 |
| Backend | Supabase: Postgres, Auth, Realtime, Storage, Edge Functions (`@supabase/supabase-js` `^2.47.0`) |
| Scheduled jobs | `pg_cron` in the Supabase database |
| Maps and place search | Google Maps JavaScript API and Places API (`@types/google.maps` for types) |
| Bot protection (optional) | Cloudflare Turnstile on guest reports |
| Error monitoring (optional) | Sentry (`@sentry/react` `^8.42.0`), errors only |
| Fonts | Geologica and Onest, self-hosted through Fontsource |
| Hosting | Any static host; `vercel.json` is included for Vercel |

## Languages

Translations live in `src/i18n/`: Azerbaijani (`az.ts`, default), Turkish
(`tr.ts`), English (`en.ts`) and Russian (`ru.ts`). Only the locales in
`ENABLED_LOCALES` in `src/i18n/index.ts` can be picked; it is currently
`['az', 'tr', 'en']`, so Russian is translated but hidden. A saved `ru`
setting falls back to English. To enable Russian, add `'ru'` to
`ENABLED_LOCALES`.

## Security and abuse controls

Each item below links to where it is implemented.

- **Row-level security.** RLS is enabled on the app's tables and access goes
  through policies (`001_init.sql`, then `003`, `007`, `014`, `036`).
  The anon key in the frontend is public; the policies decide what it can
  read and write.
- **State changes through database functions.** Case transitions (accept,
  select vet, confirm, deliver, drop) are `SECURITY DEFINER` functions, so a
  client cannot set a case status directly (`001_init.sql`).
- **Explicit table grants.** `004_grants.sql` sets table privileges in SQL,
  so the app does not depend on the Supabase "Automatically expose new
  tables" setting. Some profile columns are hidden by column grants
  (`005_security.sql`).
- **Security audit fixes.** `005_security.sql` and `011_security.sql`. For
  example, the server sets `creator_uid` from the session instead of trusting
  the client, and photos of hidden cases are not readable.
- **Report limits.** The `enforce_case_limits()` trigger (latest version in
  `035_guest_report_consent.sql`) refuses a new report when the reporter's
  session has 4 reports in the last hour, 3 open reports, or 7 reports in the
  last 24 hours. Guest reports as a whole are paused after 40 in one hour.
  Banned accounts cannot report.
- **Reporter abuse review.** Admins can see open content reports grouped by
  account and hide all of an account's cases and ban it in one action
  (`015_reporter_abuse.sql`).
- **Moderation.** Users can report cases, messages and profiles; admins can
  hide content and ban accounts (`003_production.sql`).
- **Ban checks.** Banned accounts cannot upload case photos
  (`031_photo_uploads_ban_check.sql`) or move cases, post in chats, pin
  messages or rate clinics (`033_ban_case_actions.sql`).
- **Clinic verification.** Clinics stay `pending` until an admin approves
  them; unapproved clinics are not shown to rescuers (`003_production.sql`).
  Changing a clinic's identity fields sends it back for review
  (`007_prelaunch.sql`). Verification documents are in a private bucket
  (`014_vet_profiles.sql`) that accepts only JPEG, PNG, WebP, HEIC and PDF
  (`039_vet_documents_mime.sql`).
- **Private case photos.** The `case-photos` bucket is private and the app
  uses signed URLs that expire after one hour (`018_private_case_photos.sql`).
  Photos are re-encoded on the device before upload, which removes EXIF data
  such as GPS position; a photo that cannot be cleaned is refused
  (`src/lib/photos.ts`).
- **Case privacy.** The rescuer's live location is in a separate table that
  only case participants and admins can read, and is deleted on delivery,
  drop or revert. `creator_uid` and the consent fields are no longer readable
  by clients, and the `cases` table is no longer broadcast over Realtime
  (`036_case_privacy.sql`).
- **Direct message rules.** Users can only start a conversation with an
  approved clinic (`032_vet_only_dms_and_closable_case_chat.sql`, which
  replaces the rule from `012_dm_restriction.sql`). Users can also block
  other users (`007_prelaunch.sql`).
- **Pinned messages.** Only the case's clinic can pin, and only its own
  message (`027_case_pinned_message.sql`, `028_pin_own_message_only.sql`).
- **Consent.** 18+ and Terms acceptance is stored on the profile through an
  RPC (`034_terms_consent.sql`, `src/lib/consent.ts`); guest reports carry it
  on the case row (`035_guest_report_consent.sql`).
- **Data retention.** A daily `pg_cron` job deletes case chat 90 days after a
  case is resolved or closed, notifications after 90 days, and guest sessions
  older than 30 days with no open report (`038_retention.sql`). Photo files
  are only counted, not deleted; see `docs/OPERATOR_GUIDE.md` (B12).
- **Account deletion.** `delete_my_account()` (`009_prelaunch2.sql`, fixed in
  `037_delete_account_fix.sql`) plus the `delete-account` Edge Function,
  which also removes the caller's clinic documents from Storage.
- **Turnstile (optional).** When `VITE_TURNSTILE_SITE_KEY` is set, a guest
  passes a Cloudflare Turnstile check before the anonymous sign-in
  (`src/lib/turnstile.ts`). Captcha protection must also be turned on in
  Supabase Auth.
- **HTTP headers.** `vercel.json` sets a Content-Security-Policy,
  `X-Content-Type-Options`, `Referrer-Policy`, `Permissions-Policy` and
  `X-Frame-Options: DENY`.
- **Secrets.** The Supabase service role key and the VAPID private key are
  used only inside Edge Functions and are never in `VITE_` variables.

## Running it

### 1. Supabase project

1. Create a project at [supabase.com](https://supabase.com). The existing docs
   use the Frankfurt region (`eu-central-1`).
2. In the SQL Editor, run every file in `supabase/migrations/` in numeric
   order, one at a time (full list below). There is no `026`; go from `025`
   to `027`.
3. Authentication: turn on **anonymous sign-ins** (guest reports need them).
   Email sign-in is on by default. To use "Continue with Google", enable the
   Google provider in Supabase Auth.
4. Database extensions: make sure `pg_cron` is enabled. Migrations `011` and
   `038` schedule the case maintenance and retention jobs; if `pg_cron` is not
   available they print a notice and the jobs must be scheduled by hand.
5. Make yourself admin after signing up in the app:
   ```sql
   update public.profiles set is_admin = true where id = 'YOUR-ID';
   ```

`supabase/seed.sql` has notes on seeding demo clinics.

### 2. Environment variables

```bash
cp .env.example .env
```

| Variable | Required | Purpose |
| --- | --- | --- |
| `VITE_SUPABASE_URL` | yes | Supabase project URL |
| `VITE_SUPABASE_ANON_KEY` | yes | Supabase anon (public) key |
| `VITE_GOOGLE_MAPS_API_KEY` | no | Maps and place search; without it map areas show "map unavailable" |
| `VITE_VAPID_PUBLIC_KEY` | no | Public half of the Web Push key pair; needed for push |
| `VITE_TURNSTILE_SITE_KEY` | no | Turnstile on guest reports |
| `VITE_SENTRY_DSN` | no | Sentry error monitoring |
| `VITE_CONTACT_EMAIL` | no | Address on the Contact page |

Everything with a `VITE_` prefix ends up in the public bundle.

### 3. Local development

```bash
npm install
npm run dev        # Vite dev server
npm run typecheck  # tsc -b --noEmit
npm run build      # typecheck and production build into dist/
npm run preview    # serve the production build
```

Geolocation, the camera and PWA install need HTTPS or `localhost`.

### 4. Google Maps key

1. In [console.cloud.google.com](https://console.cloud.google.com), create a
   project and link a billing account. Setting a budget alert is a good idea.
2. Enable **Maps JavaScript API** and **Places API**.
3. Create an API key under APIs & Services, Credentials.
4. Restrict it: application restriction **Websites** with
   `http://localhost:5173/*` and your deployed URLs; API restriction to the
   two APIs above. The key is in the public bundle, so the restrictions are
   what prevent other sites from using it.
5. Set it as `VITE_GOOGLE_MAPS_API_KEY` locally and on the host.

### 5. Edge Functions

Both are in `supabase/functions/` and are deployed with the Supabase CLI
(`supabase login`, `supabase link --project-ref YOUR-PROJECT-REF`).

- `send-push` sends a Web Push message for each new row in
  `public.notifications`.
  ```bash
  npx web-push generate-vapid-keys
  supabase secrets set VAPID_PUBLIC_KEY=... VAPID_PRIVATE_KEY=... \
    VAPID_SUBJECT=mailto:you@example.com PUSH_WEBHOOK_SECRET=...
  supabase functions deploy send-push --no-verify-jwt
  ```
  Then add a database webhook on `public.notifications` (INSERT) that calls
  `send-push` with the header `x-push-secret` set to `PUSH_WEBHOOK_SECRET`.
- `delete-account` handles self-service account deletion:
  ```bash
  supabase functions deploy delete-account
  ```
  JWT verification stays on.

### 6. Deploying to Vercel

Import the repository in Vercel. Build command `npm run build`, output
directory `dist`. Add the environment variables from the table above.
`vercel.json` provides the SPA rewrite and the security headers. On other
static hosts, add a rewrite of all routes to `/index.html`.

More detail: `docs/DEPLOYMENT.md` and `docs/OPERATOR_GUIDE.md`.

## Migrations

Run in this order. Migration `026` does not exist and never did.

| File | What it does |
| --- | --- |
| `001_init.sql` | Initial schema: tables, RLS policies, case state machine functions, notification triggers, XP awards, realtime publication, `case-photos` bucket |
| `002_locale.sql` | `profiles.locale` language preference, carried over from guest browsing at signup |
| `003_production.sql` | Admin role and bans, guest reporting with anonymous auth and rate limits, clinic verification, moderation, push subscriptions, duplicate detection, sponsors, indexes |
| `004_grants.sql` | Explicit table privilege grants |
| `005_security.sql` | Security audit fixes (see `docs/TESTING_REPORT.md`) |
| `006_features.sql` | Time-to-acceptance stats, case escalation, partner organizations, public impact aggregates |
| `007_prelaunch.sql` | Abandoned-rescue timeout, injury and spot type fields, "not here" signal and 24-hour expiry for unclaimed cases, clinic re-verification, user blocking, safety acknowledgment, data export, `closed` status |
| `008_performance.sql` | Indexes and a bounding-box filter for the open-cases map and notification fan-out |
| `009_prelaunch2.sql` | Self-service account deletion and a stored safety acknowledgment |
| `010_vet_hours.sql` | Clinic opening hours |
| `011_security.sql` | Hidden check on case photos, `pg_cron` schedule for case maintenance, other security fixes |
| `012_dm_restriction.sql` | New DMs only between people on the same active case (later replaced by `032`) |
| `013_escalation_timeline.sql` | Escalations are written to the case timeline |
| `014_vet_profiles.sql` | Clinic verification documents (private bucket), clinic ratings, public and private clinic fields, name and phone on profiles |
| `015_reporter_abuse.sql` | Admin functions to group reports by account and hide and ban in one action |
| `016_locale_ru.sql` | Allows `ru` as a locale |
| `017_case_chat_read_state.sql` | Per-user read state for case chats |
| `018_private_case_photos.sql` | Makes `case-photos` private; the app uses signed URLs |
| `019_vets_upsert_grant.sql` | Grant fix for saving a clinic |
| `020_upsert_my_vet_rpc.sql` | `upsert_my_vet()` RPC for saving a clinic |
| `021_case_limits_tightened.sql` | Report limits: 3 open reports, 7 per 24 hours |
| `022_case_urgency.sql` | Urgency field on reports |
| `023_xp_retune_and_review_lists.sql` | XP changes (reporter +5, rescuer +10, no clinic XP) and admin review lists |
| `024_oauth_signup_metadata.sql` | Signup trigger handles Google sign-in metadata |
| `025_become_vet_rpc.sql` | `become_vet()` so an existing account can register a clinic |
| `027_case_pinned_message.sql` | One pinned message per case, pinned by the case's clinic |
| `028_pin_own_message_only.sql` | A clinic can pin only its own message |
| `029_case_street_address.sql` | Reverse-geocoded street address on a case |
| `030_admin_list_users.sql` | `admin_list_users()` for the admin Users tab |
| `031_photo_uploads_ban_check.sql` | Banned accounts cannot add case photos |
| `032_vet_only_dms_and_closable_case_chat.sql` | DMs only from users to clinics, admin access to DMs, clinic can close a case chat |
| `033_ban_case_actions.sql` | Banned accounts cannot move cases or manage chats |
| `034_terms_consent.sql` | 18+ and Terms consent stored on the profile |
| `035_guest_report_consent.sql` | Guest reports carry 18+ and Terms consent |
| `036_case_privacy.sql` | Rescuer live location in a participants-only table, server-only case columns, `cases` removed from Realtime |
| `037_delete_account_fix.sql` | Fixes account deletion for users who posted in case chat |
| `038_retention.sql` | Data retention job |
| `039_vet_documents_mime.sql` | Clinic documents limited to JPEG, PNG, WebP, HEIC and PDF |
| `040_notification_types.sql` | Per-type notification switches, enforced in the database |
| `041_case_needs.sql` | "Needs" list on a case and `set_case_needs()` |
| `042_app_name_in_notifications.sql` | Replaces "PawLine" with "Stray's Call" in two notification texts, including stored ones |

## Project layout

```
supabase/
  migrations/              SQL migrations 001-042 (no 026)
  functions/send-push/     Web Push delivery
  functions/delete-account/ account deletion including Storage files
  seed.sql                 notes for seeding demo clinics
src/
  App.tsx                  routes
  main.tsx                 entry point
  sw.ts                    service worker (precache, runtime cache, push)
  context/AuthContext.tsx  session and profile state
  hooks/useRealtime.ts     realtime subscriptions
  lib/                     API calls (api.ts), Supabase client, maps, photos,
                           perceptual hash, offline queue, push, consent,
                           Turnstile, monitoring, XP tiers, types
  i18n/                    az, tr, en, ru string tables
  components/              UI pieces: maps, live camera, case photo, report
                           form, case needs, onboarding, icons, logo, ink
                           illustrations; legal.tsx (terms, safety, about,
                           contact, FAQ, consent gate) and extras.tsx
                           (privacy page, sponsor strip)
  pages/                   one file per screen; vetAndUserPages.tsx holds the
                           clinic setup, vet dashboard, public clinic and
                           user profile pages
  pages/admin/             admin tabs: users, DMs, growth charts, vet documents
  assets/onboarding/       onboarding images
  styles/                  tokens.css, app.css, index.css
public/                    icons and favicon
docs/                      ARCHITECTURE, DEPLOYMENT, OPERATOR_GUIDE, OPERATIONS,
                           DESIGN_SYSTEM, DESIGN_TOKENS, MONETIZATION,
                           SECURITY_AUDIT_DEPS, TESTING_REPORT,
                           privacy-policy-draft, strays-call-spec, design-v3/
```

## Scope and limitations

- No in-app payments. Clinics can share bank details in the case chat; money
  goes directly to the clinic.
- No native apps; it is a PWA. On iPhone, Web Push works only after the app is
  added to the home screen (iOS 16.4 and later).
- XP and tiers are shown on profiles. There are no cash rewards.
- Photo files are not yet deleted by the retention job; only chat,
  notifications and old guest sessions are.

## Further documentation

- `docs/ARCHITECTURE.md`: state machine and notification design
- `docs/DEPLOYMENT.md`, `docs/OPERATOR_GUIDE.md`: go-live steps and runbook
- `docs/OPERATIONS.md`: day-to-day administration
- `docs/MONETIZATION.md`: funding approach
