-- LabMates database setup for Supabase (version 5: hardened, Google or email + password, hidden testers)
-- Supabase dashboard → SQL Editor → New query → paste all of this → Run.
-- Safe to run again, and safe to run over earlier versions: it keeps everyone's data and accounts.

-- ─────────────────────────────────────────────
-- 1. Tables
-- ─────────────────────────────────────────────

create table if not exists public.profiles (
  id           uuid primary key references auth.users(id) on delete cascade,
  display_name text not null default '',
  status       text not null default 'pending' check (status in ('pending','approved','rejected')),
  is_admin     boolean not null default false,
  created_at   timestamptz not null default now()
);

create table if not exists public.rosters (
  user_id    uuid primary key references public.profiles(id) on delete cascade,
  data       jsonb not null default '{}'::jsonb,
  updated_at timestamptz not null default now()
);

-- Limits: names up to 40 characters; a roster must be a JSON object under 300 KB
-- (about 2,000 duties), so nobody can fill the database with junk.
do $$
begin
  if not exists (select 1 from pg_constraint where conname = 'profiles_name_len') then
    alter table public.profiles add constraint profiles_name_len check (char_length(display_name) <= 40);
  end if;
  if not exists (select 1 from pg_constraint where conname = 'rosters_data_shape') then
    alter table public.rosters add constraint rosters_data_shape
      check (jsonb_typeof(data) = 'object' and octet_length(data::text) <= 300000);
  end if;
end;
$$;

-- ─────────────────────────────────────────────
-- 2. Helper checks (used by the security rules)
-- ─────────────────────────────────────────────

create or replace function public.is_approved() returns boolean
language sql stable security definer set search_path = '' as $$
  select exists (select 1 from public.profiles where id = auth.uid() and status = 'approved');
$$;

create or replace function public.is_admin() returns boolean
language sql stable security definer set search_path = '' as $$
  select exists (select 1 from public.profiles where id = auth.uid() and status = 'approved' and is_admin);
$$;

-- ─────────────────────────────────────────────
-- 3. New sign-ups: Google or email + password, and everyone starts as "pending".
--    Nobody becomes admin by signing up. You make yourself admin once (step 7).
-- ─────────────────────────────────────────────

create or replace function public.handle_new_user() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  -- Second lock behind the dashboard settings: refuse phone and anonymous sign-ups.
  if coalesce(new.raw_app_meta_data->>'provider', '') in ('phone', 'anonymous') then
    raise exception 'LabMates only allows Google or email sign-in';
  end if;
  insert into public.profiles (id, display_name, status, is_admin)
  values (
    new.id,
    left(trim(coalesce(
      nullif(new.raw_user_meta_data->>'display_name', ''),
      nullif(new.raw_user_meta_data->>'full_name', ''),
      nullif(new.raw_user_meta_data->>'name', ''),
      ''
    )), 40),
    'pending',
    false
  );
  return new;
end;
$$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();

-- What a profile change is allowed to do:
--  • you can change your own name, nothing else about yourself
--  • an admin can approve or remove other people, but not rename them,
--    and not remove another admin
--  • admin rights can't be changed from the app at all (only here, in the SQL Editor)
create or replace function public.guard_profile_update() returns trigger
language plpgsql security invoker set search_path = '' as $$
begin
  if current_user in ('authenticated', 'anon') then
    new.id         := old.id;
    new.is_admin   := old.is_admin;
    new.created_at := old.created_at;
    if old.id = auth.uid() then
      new.status := old.status;
    else
      new.display_name := old.display_name;
      if not public.is_admin() or old.is_admin then
        new.status := old.status;
      end if;
    end if;
  end if;
  new.display_name := left(trim(new.display_name), 40);
  return new;
end;
$$;

drop trigger if exists profiles_guard on public.profiles;
create trigger profiles_guard
  before update on public.profiles
  for each row execute function public.guard_profile_update();

create or replace function public.touch_roster() returns trigger
language plpgsql set search_path = '' as $$
begin
  new.updated_at := now();
  return new;
end;
$$;

drop trigger if exists rosters_touch on public.rosters;
create trigger rosters_touch
  before insert or update on public.rosters
  for each row execute function public.touch_roster();

-- Admins see each member's email and sign-in method in Members, so they can tell
-- who they're approving. Only admins get anything back from this.
drop function if exists public.admin_members();
create function public.admin_members()
returns table (id uuid, display_name text, email text, sign_in text, status text, is_admin boolean, created_at timestamptz)
language sql stable security definer set search_path = '' as $$
  select p.id, p.display_name, u.email::text,
         (select string_agg(distinct i.provider, ', ') from auth.identities i where i.user_id = p.id),
         p.status, p.is_admin, p.created_at
  from public.profiles p
  join auth.users u on u.id = p.id
  where public.is_admin()
  order by p.created_at;
$$;

-- ─────────────────────────────────────────────
-- 4. Who may call what
--    Signed-out visitors get nothing. Signed-in people get only the columns the app needs.
-- ─────────────────────────────────────────────

revoke all on public.profiles from anon, authenticated;
revoke all on public.rosters  from anon, authenticated;
grant select on public.profiles to authenticated;
grant update (display_name, status) on public.profiles to authenticated;
grant select, insert, update, delete on public.rosters to authenticated;

revoke all on function public.is_approved()           from public, anon;
revoke all on function public.is_admin()              from public, anon;
revoke all on function public.admin_members()         from public, anon;
revoke all on function public.handle_new_user()       from public, anon, authenticated;
revoke all on function public.guard_profile_update()  from public, anon, authenticated;
revoke all on function public.touch_roster()          from public, anon, authenticated;
grant execute on function public.is_approved()   to authenticated;
grant execute on function public.is_admin()      to authenticated;
grant execute on function public.admin_members() to authenticated;

-- ─────────────────────────────────────────────
-- 5. Security rules (row level security)
-- ─────────────────────────────────────────────

alter table public.profiles enable row level security;
alter table public.rosters  enable row level security;

drop policy if exists "profiles: read" on public.profiles;
create policy "profiles: read" on public.profiles
  for select to authenticated
  using (id = (select auth.uid()) or (select public.is_approved()));

drop policy if exists "profiles: update" on public.profiles;
create policy "profiles: update" on public.profiles
  for update to authenticated
  using (id = (select auth.uid()) or (select public.is_admin()))
  with check (id = (select auth.uid()) or (select public.is_admin()));

drop policy if exists "rosters: read" on public.rosters;
create policy "rosters: read" on public.rosters
  for select to authenticated
  using ((select public.is_approved()));

drop policy if exists "rosters: insert own" on public.rosters;
create policy "rosters: insert own" on public.rosters
  for insert to authenticated
  with check (user_id = (select auth.uid()) and (select public.is_approved()));

drop policy if exists "rosters: update own" on public.rosters;
create policy "rosters: update own" on public.rosters
  for update to authenticated
  using (user_id = (select auth.uid()) and (select public.is_approved()))
  with check (user_id = (select auth.uid()) and (select public.is_approved()));

drop policy if exists "rosters: delete own" on public.rosters;
create policy "rosters: delete own" on public.rosters
  for delete to authenticated
  using (user_id = (select auth.uid()));

-- ─────────────────────────────────────────────
-- 6. Live updates, so the Team tab refreshes when someone saves
-- ─────────────────────────────────────────────

do $$
begin
  begin
    alter publication supabase_realtime add table public.rosters;
  exception when duplicate_object then null;
  end;
  begin
    alter publication supabase_realtime add table public.profiles;
  exception when duplicate_object then null;
  end;
end;
$$;

-- ─────────────────────────────────────────────
-- 6b. Hidden testers: an admin can hide someone from the team.
--     They still see everyone; nobody but the admin sees them.
--     (This replaces the read rules, profile guard and members list above.)
-- ─────────────────────────────────────────────

-- 1. A "hidden" flag on each member
alter table public.profiles add column if not exists hidden boolean not null default false;

-- 2. Who can be seen: yourself, everyone if you're the admin,
--    otherwise only approved members who aren't hidden.
create or replace function public.is_visible(target uuid) returns boolean
language sql stable security definer set search_path = '' as $$
  select target = auth.uid()
      or exists (select 1 from public.profiles me where me.id = auth.uid() and me.status = 'approved' and me.is_admin)
      or (
        exists (select 1 from public.profiles me where me.id = auth.uid() and me.status = 'approved')
        and exists (select 1 from public.profiles t where t.id = target and t.status = 'approved' and not t.hidden)
      );
$$;
revoke all on function public.is_visible(uuid) from public, anon;
grant execute on function public.is_visible(uuid) to authenticated;

drop policy if exists "profiles: read" on public.profiles;
create policy "profiles: read" on public.profiles
  for select to authenticated
  using (id = (select auth.uid()) or (select public.is_admin()) or ((select public.is_approved()) and status = 'approved' and not hidden));

drop policy if exists "rosters: read" on public.rosters;
create policy "rosters: read" on public.rosters
  for select to authenticated
  using ((select public.is_approved()) and public.is_visible(user_id));

-- 3. Only an admin can hide or unhide someone (not themselves, not another admin)
create or replace function public.guard_profile_update() returns trigger
language plpgsql security invoker set search_path = '' as $$
begin
  if current_user in ('authenticated', 'anon') then
    new.id         := old.id;
    new.is_admin   := old.is_admin;
    new.created_at := old.created_at;
    if old.id = auth.uid() then
      new.status := old.status;
      new.hidden := old.hidden;
    else
      new.display_name := old.display_name;
      if not public.is_admin() or old.is_admin then
        new.status := old.status;
        new.hidden := old.hidden;
      end if;
    end if;
  end if;
  new.display_name := left(trim(new.display_name), 40);
  return new;
end;
$$;
revoke all on function public.guard_profile_update() from public, anon, authenticated;

revoke update on public.profiles from authenticated;
grant update (display_name, status, hidden) on public.profiles to authenticated;

-- 4. Members list for the admin, now with the hidden flag
drop function if exists public.admin_members();
create function public.admin_members()
returns table (id uuid, display_name text, email text, sign_in text, status text, is_admin boolean, hidden boolean, created_at timestamptz)
language sql stable security definer set search_path = '' as $$
  select p.id, p.display_name, u.email::text,
         (select string_agg(distinct i.provider, ', ') from auth.identities i where i.user_id = p.id),
         p.status, p.is_admin, p.hidden, p.created_at
  from public.profiles p
  join auth.users u on u.id = p.id
  where public.is_admin()
  order by p.created_at;
$$;
revoke all on function public.admin_members() from public, anon;
grant execute on function public.admin_members() to authenticated;

-- ─────────────────────────────────────────────
-- 7. Make yourself the admin (one time)
--    Sign in to the app first, then put your email below,
--    remove the two dashes at the start of the line, and run just that line.
-- ─────────────────────────────────────────────

-- update public.profiles set status = 'approved', is_admin = true where id = (select id from auth.users where email = 'YOUR-EMAIL@example.com');

-- Check who has access. Only you should have is_admin = true.
select p.display_name, u.email, p.status, p.is_admin,
       (select string_agg(i.provider, ', ') from auth.identities i where i.user_id = u.id) as sign_in_methods,
       p.created_at
from public.profiles p join auth.users u on u.id = p.id
order by p.created_at;

-- ─────────────────────────────────────────────
-- 8. Resetting someone's password (when they forget it)
--    Put their email and a new temporary password, remove the dashes, run that line,
--    and tell them to change it in More → Set or change password.
-- ─────────────────────────────────────────────

-- update auth.users set encrypted_password = extensions.crypt('NEW-PASSWORD', extensions.gen_salt('bf')) where email = 'THEIR-EMAIL@example.com';
