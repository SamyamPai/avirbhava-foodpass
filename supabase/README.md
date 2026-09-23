Run the database SQL from the chat instructions first. Then put your Supabase project URL and publishable key in .env.

## Scanner login patch
If scanner login previously appeared to do nothing, run `SCANNER_LOGIN_AND_YEAR_COUNTS_PATCH.sql` once after `MASTER_REPAIR.sql`. It normalizes staff roles (`scanner`/`Scanner`/spaces), refreshes the RPCs, and reloads PostgREST. The scanner username must belong to an active `scanner` (or `admin`) staff account.
