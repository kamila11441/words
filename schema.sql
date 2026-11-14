-- Run this once in Supabase SQL Editor. The first profile created becomes the family admin.
create table public.family_settings (
  id boolean primary key default true check (id),
  member_count integer not null default 0 check (member_count between 0 and 4)
  ,logo_url text
);
insert into public.family_settings(id, member_count) values (true, 0) on conflict (id) do nothing;

create table public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  display_name text not null check (char_length(display_name) between 1 and 32),
  avatar_url text,
  is_admin boolean not null default false,
  created_at timestamptz not null default now()
);

create table public.entries (
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
create index entries_created_at_idx on public.entries(created_at desc);
create index entries_word_idx on public.entries using gin(to_tsvector('simple', word || ' ' || meaning || ' ' || coalesce(example,'')));

-- Serialize account creation and reject signups after the fourth profile.
create or replace function public.create_family_profile()
returns trigger language plpgsql security definer set search_path = '' as $$
declare current_count integer; begin
  update public.family_settings set member_count = member_count + 1 where id = true and member_count < 4 returning member_count into current_count;
  if current_count is null then raise exception 'This family dictionary already has its four accounts.'; end if;
  insert into public.profiles(id, display_name, is_admin)
  values (new.id, coalesce(nullif(trim(new.raw_user_meta_data->>'display_name'), ''), 'Family member'), current_count = 1);
  return new;
end; $$;
create or replace function public.remove_family_profile()
returns trigger language plpgsql security definer set search_path = '' as $$
begin update public.family_settings set member_count = greatest(member_count - 1, 0) where id = true; return old; end; $$;
create trigger auth_user_add_profile after insert on auth.users for each row execute function public.create_family_profile();
create trigger auth_user_remove_profile after delete on auth.users for each row execute function public.remove_family_profile();

alter table public.family_settings enable row level security;
alter table public.profiles enable row level security;
alter table public.entries enable row level security;

create policy "Signed in members can read family settings" on public.family_settings for select to authenticated using (true);
create policy "Only family admin can change app logo" on public.family_settings for update to authenticated using (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.is_admin)) with check (exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.is_admin));
create policy "Family can see profiles" on public.profiles for select to authenticated using (true);
create policy "Profile names and photos are visible for account selection" on public.profiles for select to anon using (true);
create policy "Members can update own profile name" on public.profiles for update to authenticated using (id = (select auth.uid())) with check (id = (select auth.uid()));
create policy "Family can read dictionary" on public.entries for select to authenticated using (true);
create policy "Guests can read dictionary" on public.entries for select to anon using (true);
create policy "Members can add own entries" on public.entries for insert to authenticated with check (created_by = (select auth.uid()));
create policy "Authors can edit their own entries" on public.entries for update to authenticated using (created_by = (select auth.uid())) with check (created_by = (select auth.uid()));
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

-- Public profile photos; each signed-in member may upload only to their own folder.
insert into storage.buckets(id, name, public) values ('avatars', 'avatars', true) on conflict (id) do nothing;
insert into storage.buckets(id, name, public) values ('branding', 'branding', true) on conflict (id) do nothing;
create policy "Anyone can view app logo" on storage.objects for select using (bucket_id = 'branding');
create policy "Admin uploads app logo" on storage.objects for insert to authenticated with check (bucket_id = 'branding' and exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.is_admin));
create policy "Admin replaces app logo" on storage.objects for update to authenticated using (bucket_id = 'branding' and exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.is_admin)) with check (bucket_id = 'branding' and exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.is_admin));
create policy "Anyone can view profile pictures" on storage.objects for select using (bucket_id = 'avatars');
create policy "Members upload own profile picture" on storage.objects for insert to authenticated with check (bucket_id = 'avatars' and (storage.foldername(name))[1] = (select auth.uid())::text);
create policy "Members replace own profile picture" on storage.objects for update to authenticated using (bucket_id = 'avatars' and (storage.foldername(name))[1] = (select auth.uid())::text) with check (bucket_id = 'avatars' and (storage.foldername(name))[1] = (select auth.uid())::text);
