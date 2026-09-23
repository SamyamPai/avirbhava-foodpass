# CLOUDS FoodPass — Final

Sahyadri College of Engineering & Management · Mangaluru
CLOUDS Association · Branch Entry

## 1. Install

```bash
npm install
```

## 2. Environment

Create `.env` from `.env.example` and add your Supabase project URL and **anon/publishable key**.

Do not put a Supabase service-role key in this Vite frontend.

## 3. Supabase

Your existing tables are retained. Run **only**:

`supabase/MASTER_REPAIR.sql`

Do not run the older migration files after it.

At the end, the SQL editor should show the `register_student` signature:

`public.register_student(text,text,integer,text,text)`

Then reload the PostgREST schema if needed:

```sql
NOTIFY pgrst, 'reload schema';
```

## 4. Staff accounts

Keep your existing `staff_accounts` rows. The final `staff_login` supports existing `crypt()` password hashes and legacy plain event PINs; a legacy plain PIN is upgraded after successful login.

Roles expected by the app:

- `admin`
- `scanner`

## 5. Run

```bash
npm run dev
```

Open the Vite URL shown in the terminal.

Public pages:

- `/` — event landing page
- `/register` — student registration
- `/status` — USN status / QR

Staff pages (not linked from the public home page):

- `/admin` — admin login
- `/admin/dashboard` — admin portal
- `/scanner` — scanner login + live camera

## Scanner

The scanner uses the device camera through `html5-qrcode`. Camera access requires HTTPS in deployed environments; `localhost` is allowed by modern browsers for local testing.

The scanner displays:

- name
- USN / teacher status
- year
- section
- Veg / Non-Veg
- valid / invalid / already-used result

Redemption is atomic in PostgreSQL, so two scanners cannot successfully redeem the same FoodPass at the same time.

## Final flow

Student registers → admin approves → UUID QR is generated → student checks status → scanner scans QR → database atomically redeems → scanner shows food preference → scan is logged.

Footer credit: **made by SAMYAM PAI**
