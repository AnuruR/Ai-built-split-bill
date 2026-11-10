# Testing the schema locally (optional)

These scripts test `schema.sql` (tables, RLS, `save_receipt`) on a local
PostgreSQL, using `auth_stub.sql` to fake Supabase's `auth.uid()`.
**Never run `auth_stub.sql` on your real Supabase project.**

```bash
createdb snapsplit_test
psql -d snapsplit_test -f supabase/test/auth_stub.sql
psql -d snapsplit_test -f supabase/schema.sql
psql -d snapsplit_test -f supabase/test/rls_test.sql
dropdb snapsplit_test
```

Each `[n ...]` line in the output says what should happen; compare.
