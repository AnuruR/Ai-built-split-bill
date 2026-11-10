-- =====================================================================
-- SnapSplit database schema (Supabase / PostgreSQL)
-- Run once in Supabase Dashboard -> SQL Editor -> New query -> Run.
-- Safe to re-run: it only creates what is missing / replaces functions.
--
-- Users: Supabase already manages them in auth.users, so there is no
-- separate users table; every table has user_id -> auth.users.
-- Money: bigint cents. Never floats.
-- =====================================================================

-- ---------- categories: shared, read-only list -----------------------
create table if not exists public.categories (
  id   text primary key,
  name text not null
);

insert into public.categories (id, name) values
  ('groceries', 'Groceries'), ('produce', 'Fruit & Veg'),
  ('meat_fish', 'Meat & Fish'), ('dairy', 'Dairy & Eggs'),
  ('bakery', 'Bakery'), ('beverages', 'Beverages'), ('snacks', 'Snacks'),
  ('dining', 'Food & Dining'), ('household', 'Household'),
  ('personal_care', 'Personal Care'), ('other', 'Other')
on conflict (id) do update set name = excluded.name;

-- ---------- people: each user's own list -----------------------------
create table if not exists public.people (
  id         uuid primary key default gen_random_uuid(),
  user_id    uuid not null default auth.uid() references auth.users (id) on delete cascade,
  name       text not null check (char_length(trim(name)) between 1 and 40),
  created_at timestamptz not null default now()
);
-- No two people with the same name (case-insensitive) for one user.
create unique index if not exists people_user_name_uq on public.people (user_id, lower(name));

-- ---------- receipts -------------------------------------------------
create table if not exists public.receipts (
  id           uuid primary key default gen_random_uuid(),
  user_id      uuid not null default auth.uid() references auth.users (id) on delete cascade,
  store_name   text not null,
  receipt_date date not null,
  total_cents  bigint not null,
  -- Local file path for now; can later hold a Supabase Storage key.
  image_path   text,
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now()
);
create index if not exists receipts_user_date_idx on public.receipts (user_id, receipt_date desc);

-- ---------- items ----------------------------------------------------
create table if not exists public.items (
  id           uuid primary key default gen_random_uuid(),
  receipt_id   uuid not null references public.receipts (id) on delete cascade,
  user_id      uuid not null default auth.uid() references auth.users (id) on delete cascade,
  position     int  not null default 0,          -- keeps the receipt's order
  name         text not null check (char_length(trim(name)) > 0),
  amount_cents bigint not null,
  category_id  text not null default 'other' references public.categories (id),
  split_method text not null default 'equal' check (split_method in ('equal', 'exact', 'percentage'))
);
create index if not exists items_receipt_idx on public.items (receipt_id);

-- ---------- assignments: item + person + allocated amount ------------
create table if not exists public.assignments (
  item_id         uuid not null references public.items (id) on delete cascade,
  -- RESTRICT: a person used on a saved receipt can't be deleted, so old
  -- receipts never lose who paid what.
  person_id       uuid not null references public.people (id) on delete restrict,
  user_id         uuid not null default auth.uid() references auth.users (id) on delete cascade,
  position        int  not null default 0,  -- order matters: remainder cents go to the first person
  share           bigint,                   -- raw input: cents (exact) or basis points (percentage)
  allocated_cents bigint not null,
  primary key (item_id, person_id)
);
create index if not exists assignments_person_idx on public.assignments (person_id);

-- =====================================================================
-- Row Level Security: every query is filtered to the signed-in user.
-- Without a matching policy, a row is invisible and cannot be written.
-- (select auth.uid()) is evaluated once per query, which is faster than
-- calling auth.uid() for every row.
-- =====================================================================
alter table public.categories  enable row level security;
alter table public.people      enable row level security;
alter table public.receipts    enable row level security;
alter table public.items       enable row level security;
alter table public.assignments enable row level security;

drop policy if exists "categories readable" on public.categories;
create policy "categories readable" on public.categories
  for select to authenticated using (true);

drop policy if exists "own people" on public.people;
create policy "own people" on public.people
  for all to authenticated
  using (user_id = (select auth.uid()))
  with check (user_id = (select auth.uid()));

drop policy if exists "own receipts" on public.receipts;
create policy "own receipts" on public.receipts
  for all to authenticated
  using (user_id = (select auth.uid()))
  with check (user_id = (select auth.uid()));

-- Items: own rows, AND the parent receipt must be yours too
-- (stops attaching items to someone else's receipt id).
drop policy if exists "own items" on public.items;
create policy "own items" on public.items
  for all to authenticated
  using (user_id = (select auth.uid()))
  with check (
    user_id = (select auth.uid())
    and exists (select 1 from public.receipts r
                where r.id = receipt_id and r.user_id = (select auth.uid()))
  );

-- Assignments: own rows, and both the item and the person must be yours.
drop policy if exists "own assignments" on public.assignments;
create policy "own assignments" on public.assignments
  for all to authenticated
  using (user_id = (select auth.uid()))
  with check (
    user_id = (select auth.uid())
    and exists (select 1 from public.items i
                where i.id = item_id and i.user_id = (select auth.uid()))
    and exists (select 1 from public.people p
                where p.id = person_id and p.user_id = (select auth.uid()))
  );

-- =====================================================================
-- save_receipt: saves a receipt with all items and assignments in ONE
-- transaction. If anything fails (network, validation) nothing is saved,
-- so there are never half-saved receipts. Re-saving the same id replaces
-- its items (used by "edit and recalculate", FR-13).
--
-- SECURITY INVOKER = runs as the calling user, so all RLS policies above
-- still apply inside the function.
-- =====================================================================
create or replace function public.save_receipt(p jsonb)
returns uuid
language plpgsql
security invoker
set search_path = public
as $$
declare
  r_id uuid := (p->>'id')::uuid;
  it   jsonb;
  a    jsonb;
  bad  record;
begin
  if auth.uid() is null then
    raise exception 'Not signed in';
  end if;

  insert into receipts (id, user_id, store_name, receipt_date, total_cents, image_path)
  values (r_id, auth.uid(), p->>'store_name', (p->>'receipt_date')::date,
          (p->>'total_cents')::bigint, p->>'image_path')
  on conflict (id) do update
    set store_name   = excluded.store_name,
        receipt_date = excluded.receipt_date,
        total_cents  = excluded.total_cents,
        image_path   = excluded.image_path,
        updated_at   = now();

  -- Replace all items (assignments are removed by ON DELETE CASCADE).
  delete from items where receipt_id = r_id;

  for it in select * from jsonb_array_elements(coalesce(p->'items', '[]'::jsonb)) loop
    insert into items (id, receipt_id, user_id, position, name, amount_cents, category_id, split_method)
    values ((it->>'id')::uuid, r_id, auth.uid(), (it->>'position')::int, it->>'name',
            (it->>'amount_cents')::bigint, it->>'category_id', it->>'split_method');

    for a in select * from jsonb_array_elements(coalesce(it->'assignments', '[]'::jsonb)) loop
      insert into assignments (item_id, person_id, user_id, position, share, allocated_cents)
      values ((it->>'id')::uuid, (a->>'person_id')::uuid, auth.uid(), (a->>'position')::int,
              (a->>'share')::bigint, (a->>'allocated_cents')::bigint);
    end loop;
  end loop;

  -- Enforce the core rule in the database too: every item's assignments
  -- must add up exactly to the item amount.
  select i.name into bad
  from items i
  left join assignments s on s.item_id = i.id
  where i.receipt_id = r_id
  group by i.id, i.name, i.amount_cents
  having coalesce(sum(s.allocated_cents), 0) <> i.amount_cents
  limit 1;

  if found then
    raise exception 'Assignments for "%" do not add up to the item amount', bad.name;
  end if;

  return r_id;
end;
$$;

grant execute on function public.save_receipt(jsonb) to authenticated;

-- Tell the Supabase API (PostgREST) to reload its table list right away.
notify pgrst, 'reload schema';
