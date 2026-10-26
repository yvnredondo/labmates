-- LabMates database setup for Supabase
-- Run this once: Supabase dashboard → SQL Editor → New query → paste all of this → Run.
-- It is safe to run again; it won't delete anyone's data.

-- ─────────────────────────────────────────────
-- 1. Tables
-- ─────────────────────────────────────────────

-- One row per person. Created automatically when someone signs up.
create table if not exists public.profiles (
  id           uuid primary key references auth.users(id) on delete cascade,
  display_name text not null default '',
  status       text not null default 'pending' check (status in ('pending','approved','rejected')),
  is_admin     boolean not null default false,
  created_at   timestamptz not null default now()
);

-- One row per person: their duties, leaves and settings, stored as JSON.
create table if not exists public.rosters (
  user_id    uuid primary key references public.profiles(id) on delete cascade,
  data       jsonb not null default '{}'::jsonb,
  updated_at timestamptz not null default now()
);

-- ─────────────────────────────────────────────
-- 2. Helper checks (used by the security rules)
-- ─────────────────────────────────────────────

create or replace function public.is_approved() returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.profiles where id = auth.uid() and status = 'approved');
$$;

create or replace function public.is_admin() returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.profiles where id = auth.uid() and status = 'approved' and is_admin);
$$;

-- ─────────────────────────────────────────────
-- 3. New sign-ups
--    The very first person to sign up becomes the approved admin.
--    Everyone after that starts as "pending" until an admin approves them.
-- ─────────────────────────────────────────────

create or replace function public.handle_new_user() returns trigger
language plpgsql security definer set search_path = public as $$
declare
  first_user boolean;
begin
  select not exists (select 1 from public.profiles) into first_user;
  insert into public.profiles (id, display_name, status, is_admin)
  values (
    new.id,
    left(trim(coalesce(new.raw_user_meta_data->>'display_name', '')), 40),
    case when first_user then 'approved' else 'pending' end,
    first_user
  );
  return new;
end;
$$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();

-- People can change their own name, but not their own status or admin flag.
create or replace function public.guard_profile_update() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if not public.is_admin() then
    new.status   := old.status;
    new.is_admin := old.is_admin;
  end if;
  -- An admin can't remove their own admin access by accident.
  if old.id = auth.uid() then
    new.is_admin := old.is_admin;
    new.status   := old.status;
  end if;
  new.display_name := left(trim(new.display_name), 40);
  return new;
end;
$$;

drop trigger if exists profiles_guard on public.profiles;
create trigger profiles_guard
  before update on public.profiles
  for each row execute function public.guard_profile_update();

-- Keep updated_at current on roster saves.
create or replace function public.touch_roster() returns trigger
language plpgsql as $$
begin
  new.updated_at := now();
  return new;
end;
$$;

drop trigger if exists rosters_touch on public.rosters;
create trigger rosters_touch
  before insert or update on public.rosters
  for each row execute function public.touch_roster();

-- ─────────────────────────────────────────────
-- 4. Security rules (row level security)
-- ─────────────────────────────────────────────

alter table public.profiles enable row level security;
alter table public.rosters  enable row level security;

-- Profiles: you can always see your own; approved members see everyone.
drop policy if exists "profiles: read" on public.profiles;
create policy "profiles: read" on public.profiles
  for select to authenticated
  using (id = auth.uid() or public.is_approved());

-- Profiles: you can edit your own name; admins can edit anyone (to approve or remove).
drop policy if exists "profiles: update" on public.profiles;
create policy "profiles: update" on public.profiles
  for update to authenticated
  using (id = auth.uid() or public.is_admin())
  with check (id = auth.uid() or public.is_admin());

-- Rosters: approved members can read everyone's roster.
drop policy if exists "rosters: read" on public.rosters;
create policy "rosters: read" on public.rosters
  for select to authenticated
  using (public.is_approved());

-- Rosters: approved members can create and change only their own.
drop policy if exists "rosters: insert own" on public.rosters;
create policy "rosters: insert own" on public.rosters
  for insert to authenticated
  with check (user_id = auth.uid() and public.is_approved());

drop policy if exists "rosters: update own" on public.rosters;
create policy "rosters: update own" on public.rosters
  for update to authenticated
  using (user_id = auth.uid() and public.is_approved())
  with check (user_id = auth.uid() and public.is_approved());

drop policy if exists "rosters: delete own" on public.rosters;
create policy "rosters: delete own" on public.rosters
  for delete to authenticated
  using (user_id = auth.uid());

-- ─────────────────────────────────────────────
-- 5. Live updates, so the Team tab refreshes when someone saves
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
