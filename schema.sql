-- Safe to rerun: creates missing objects, adds newer columns, and rebuilds policies.
-- It does not drop tables or delete dictionary data. The first profile is the admin.

create table if not exists public.family_settings (
  id boolean primary key default true check (id),
  member_count integer not null default 0 check (member_count between 0 and 4),
  logo_url text
);
alter table public.family_settings add column if not exists logo_url text;
insert into public.family_settings(id, member_count) values (true, 0) on conflict (id) do nothing;

create table if not exists public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  display_name text not null check (char_length(display_name) between 1 and 32),
  avatar_url text,
  is_admin boolean not null default false,
  created_at timestamptz not null default now()
);
alter table public.profiles add column if not exists avatar_url text;
alter table public.profiles add column if not exists is_admin boolean not null default false;
alter table public.profiles add column if not exists created_at timestamptz not null default now();

create table if not exists public.entries (
  id uuid primary key default gen_random_uuid(),
  word text not null check (char_length(word) between 1 and 80),
  word_type text not null default 'noun' check (word_type in ('noun', 'verb', 'saying')),
  pronunciation text,
  meaning text not null,
  example text,
  topic text,
  created_by uuid not null references public.profiles(id) on delete cascade,
  created_at timestamptz not null default now()
);
alter table public.entries add column if not exists word_type text not null default 'noun';
create index if not exists entries_created_at_idx on public.entries(created_at desc);
create index if not exists entries_word_idx on public.entries using gin(to_tsvector('simple', word || ' ' || meaning || ' ' || coalesce(example,'')));

-- Backfill a partial setup safely. If users already exist but profile creation had not run,
-- create their profiles and make the earliest account the admin.
with missing as (
  select u.id, u.raw_user_meta_data, u.created_at,
         row_number() over (order by u.created_at, u.id) as rn,
         (select count(*) from public.profiles) as profile_count
  from auth.users u
  where not exists (select 1 from public.profiles p where p.id = u.id)
)
insert into public.profiles(id, display_name, is_admin, created_at)
select id,
       coalesce(nullif(trim(raw_user_meta_data->>'display_name'), ''), 'Family member'),
       profile_count = 0 and rn = 1,
       created_at
from missing
on conflict (id) do nothing;
update public.family_settings set member_count = (select count(*) from public.profiles) where id = true;

-- Serialize account creation and reject signups after account four.
create or replace function public.create_family_profile()
returns trigger language plpgsql security definer set search_path = '' as $$
declare current_count integer;
begin
  update public.family_settings
  set member_count = member_count + 1
  where id = true and member_count < 4
  returning member_count into current_count;
  if current_count is null then raise exception 'This family dictionary already has its four accounts.'; end if;
  insert into public.profiles(id, display_name, is_admin)
  values (new.id, coalesce(nullif(trim(new.raw_user_meta_data->>'display_name'), ''), 'Family member'), current_count = 1);
  return new;
end; $$;
create or replace function public.remove_family_profile()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  update public.family_settings set member_count = greatest(member_count - 1, 0) where id = true;
  return old;
end; $$;
drop trigger if exists auth_user_add_profile on auth.users;
drop trigger if exists auth_user_remove_profile on auth.users;
create trigger auth_user_add_profile after insert on auth.users for each row execute function public.create_family_profile();
create trigger auth_user_remove_profile after delete on auth.users for each row execute function public.remove_family_profile();

alter table public.family_settings enable row level security;
alter table public.profiles enable row level security;
alter table public.entries enable row level security;

drop policy if exists "Signed in members can read family settings" on public.family_settings;
drop policy if exists "Only family admin can change app logo" on public.family_settings;
drop policy if exists "Family can see profiles" on public.profiles;
drop policy if exists "Profile names and photos are visible for account selection" on public.profiles;
drop policy if exists "Members can update own profile name" on public.profiles;
drop policy if exists "Family can read dictionary" on public.entries;
drop policy if exists "Guests can read dictionary" on public.entries;
drop policy if exists "Members can add own entries" on public.entries;
drop policy if exists "Authors can edit their own entries" on public.entries;
drop policy if exists "Authors or admin can delete entries" on public.entries;

create policy "Signed in members can read family settings" on public.family_settings for select to authenticated using (true);
create policy "Only family admin can change app logo" on public.family_settings for update to authenticated
  using (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.is_admin))
  with check (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.is_admin));
create policy "Family can see profiles" on public.profiles for select to authenticated using (true);
create policy "Profile names and photos are visible for account selection" on public.profiles for select to anon using (true);
create policy "Members can update own profile name" on public.profiles for update to authenticated
  using (id = (select auth.uid())) with check (id = (select auth.uid()));
create policy "Family can read dictionary" on public.entries for select to authenticated using (true);
create policy "Guests can read dictionary" on public.entries for select to anon using (true);
create policy "Members can add own entries" on public.entries for insert to authenticated with check (created_by = (select auth.uid()));
create policy "Authors can edit their own entries" on public.entries for update to authenticated
  using (created_by = (select auth.uid())) with check (created_by = (select auth.uid()));
create policy "Authors or admin can delete entries" on public.entries for delete to authenticated using (
  created_by = (select auth.uid()) or exists(select 1 from public.profiles p where p.id = (select auth.uid()) and p.is_admin)
);

grant select on public.profiles to authenticated;
grant select(id, display_name, avatar_url, created_at) on public.profiles to anon;
grant update(display_name, avatar_url) on public.profiles to authenticated;
grant select on public.family_settings to authenticated;
grant update(logo_url) on public.family_settings to authenticated;
grant select, insert, update, delete on public.entries to authenticated;
grant select on public.entries to anon;

-- Public photos; each member may write only to their own folder. The app logo is admin-only.
insert into storage.buckets(id, name, public) values ('avatars', 'avatars', true) on conflict (id) do nothing;
insert into storage.buckets(id, name, public) values ('branding', 'branding', true) on conflict (id) do nothing;
drop policy if exists "Anyone can view app logo" on storage.objects;
drop policy if exists "Admin uploads app logo" on storage.objects;
drop policy if exists "Admin replaces app logo" on storage.objects;
drop policy if exists "Anyone can view profile pictures" on storage.objects;
drop policy if exists "Members upload own profile picture" on storage.objects;
drop policy if exists "Members replace own profile picture" on storage.objects;
create policy "Anyone can view app logo" on storage.objects for select using (bucket_id = 'branding');
create policy "Admin uploads app logo" on storage.objects for insert to authenticated with check (
  bucket_id = 'branding' and exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.is_admin)
);
create policy "Admin replaces app logo" on storage.objects for update to authenticated
  using (bucket_id = 'branding' and exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.is_admin))
  with check (bucket_id = 'branding' and exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.is_admin));
create policy "Anyone can view profile pictures" on storage.objects for select using (bucket_id = 'avatars');
create policy "Members upload own profile picture" on storage.objects for insert to authenticated with check (
  bucket_id = 'avatars' and (storage.foldername(name))[1] = (select auth.uid())::text
);
create policy "Members replace own profile picture" on storage.objects for update to authenticated
  using (bucket_id = 'avatars' and (storage.foldername(name))[1] = (select auth.uid())::text)
  with check (bucket_id = 'avatars' and (storage.foldername(name))[1] = (select auth.uid())::text);
