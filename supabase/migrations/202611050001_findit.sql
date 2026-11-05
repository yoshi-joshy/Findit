create extension if not exists pgcrypto;

create table public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  display_name text not null default 'Community member' check (char_length(display_name) between 1 and 60),
  avatar_url text,
  role text not null default 'user' check (role in ('user','admin')),
  suspended boolean not null default false,
  created_at timestamptz not null default now()
);

create or replace function public.is_admin()
returns boolean language sql stable security definer set search_path = '' as $$
  select exists(select 1 from public.profiles p where p.id = (select auth.uid()) and p.role = 'admin' and not p.suspended);
$$;

create or replace function public.protect_profile_privileges()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  if (new.role is distinct from old.role or new.suspended is distinct from old.suspended) and not public.is_admin() then
    raise exception 'Only an administrator may change account privileges';
  end if;
  return new;
end;
$$;

create or replace function public.can_use_account()
returns boolean language sql stable security definer set search_path = '' as $$
  select exists(select 1 from public.profiles p where p.id = (select auth.uid()) and not p.suspended);
$$;

create or replace function public.handle_new_user()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  insert into public.profiles(id, display_name) values (new.id, coalesce(nullif(trim(new.raw_user_meta_data ->> 'display_name'), ''), 'Community member'));
  return new;
end;
$$;
create trigger on_auth_user_created after insert on auth.users for each row execute procedure public.handle_new_user();
create trigger protect_profile_privileges before update on public.profiles for each row execute procedure public.protect_profile_privileges();

create table public.items (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id) on delete cascade,
  title text not null check (char_length(title) between 2 and 100),
  description text not null check (char_length(description) between 5 and 1500),
  category text not null check (category in ('Electronics','Bags and backpacks','Clothing','Jewellery','Keys','Wallets','Books and stationery','Sports equipment','Other')),
  item_type text not null check (item_type in ('lost','found')),
  location text not null check (char_length(location) between 2 and 120),
  item_date date not null check (item_date <= current_date),
  image_url text,
  colour text check (colour is null or char_length(colour) <= 50),
  brand text check (brand is null or char_length(brand) <= 80),
  additional_details text check (additional_details is null or char_length(additional_details) <= 1000),
  public_contact boolean not null default false,
  status text not null default 'active' check (status in ('active','resolved','suspended')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index items_feed_idx on public.items(item_type, status, created_at desc);
create index items_category_idx on public.items(category, status);
create index items_location_idx on public.items using gin (to_tsvector('simple', location));
create index items_user_idx on public.items(user_id, created_at desc);
create or replace function public.touch_updated_at() returns trigger language plpgsql as $$ begin new.updated_at = now(); return new; end; $$;
create trigger items_updated_at before update on public.items for each row execute procedure public.touch_updated_at();

create table public.conversations (
  id uuid primary key default gen_random_uuid(),
  item_id uuid not null references public.items(id) on delete cascade,
  sender_id uuid not null references public.profiles(id) on delete cascade,
  receiver_id uuid not null references public.profiles(id) on delete cascade,
  created_at timestamptz not null default now(),
  check(sender_id <> receiver_id),
  unique(item_id, sender_id, receiver_id)
);
create index conversations_sender_idx on public.conversations(sender_id, created_at desc);
create index conversations_receiver_idx on public.conversations(receiver_id, created_at desc);

create table public.messages (
  id uuid primary key default gen_random_uuid(),
  conversation_id uuid not null references public.conversations(id) on delete cascade,
  sender_id uuid not null references public.profiles(id) on delete cascade,
  content text not null check (char_length(content) between 1 and 2000),
  is_read boolean not null default false,
  created_at timestamptz not null default now()
);
create index messages_conversation_idx on public.messages(conversation_id, created_at);

create table public.content_reports (
  id uuid primary key default gen_random_uuid(),
  item_id uuid not null references public.items(id) on delete cascade,
  reporter_id uuid not null references public.profiles(id) on delete cascade,
  reason text not null check (char_length(reason) between 5 and 500),
  status text not null default 'open' check (status in ('open','reviewed','actioned')),
  created_at timestamptz not null default now(),
  unique(item_id, reporter_id)
);

alter table public.profiles enable row level security;
alter table public.items enable row level security;
alter table public.conversations enable row level security;
alter table public.messages enable row level security;
alter table public.content_reports enable row level security;

-- Names shown on listings are public; privilege and suspension fields never are.
revoke select on public.profiles from anon, authenticated;
grant select (id, display_name, avatar_url) on public.profiles to anon, authenticated;
revoke update on public.messages from anon, authenticated;
grant update (is_read) on public.messages to authenticated;

create policy "public listing poster names" on public.profiles for select to anon using (not suspended);
create policy "profiles are visible to signed-in users" on public.profiles for select to authenticated using (not suspended or id = (select auth.uid()) or (select public.is_admin()));
create policy "users create their profile" on public.profiles for insert to authenticated with check (id = (select auth.uid()) and role = 'user' and suspended = false);
create policy "users edit their own non-privileged profile" on public.profiles for update to authenticated using (id = (select auth.uid())) with check (id = (select auth.uid()));
create policy "admins manage profiles" on public.profiles for all to authenticated using ((select public.is_admin())) with check ((select public.is_admin()));

create policy "active items are public; owners and admins can view all" on public.items for select using (status = 'active' or user_id = (select auth.uid()) or (select public.is_admin()));
create policy "signed-in users can create their own items" on public.items for insert to authenticated with check (user_id = (select auth.uid()) and (select public.can_use_account()));
create policy "owners update own items; admins moderate" on public.items for update to authenticated using (user_id = (select auth.uid()) or (select public.is_admin())) with check ((user_id = (select auth.uid()) and status <> 'suspended') or (select public.is_admin()));
create policy "owners or admins delete items" on public.items for delete to authenticated using (user_id = (select auth.uid()) or (select public.is_admin()));

create policy "conversation participants or admins can read" on public.conversations for select to authenticated using (sender_id = (select auth.uid()) or receiver_id = (select auth.uid()) or (select public.is_admin()));
create policy "contact item owner" on public.conversations for insert to authenticated with check (sender_id = (select auth.uid()) and exists(select 1 from public.items i where i.id=item_id and i.user_id=receiver_id and i.status='active') and (select public.can_use_account()));
create policy "participants or admins can delete conversations" on public.conversations for delete to authenticated using (sender_id = (select auth.uid()) or receiver_id = (select auth.uid()) or (select public.is_admin()));

create policy "participants or admins can read messages" on public.messages for select to authenticated using (exists(select 1 from public.conversations c where c.id=conversation_id and ((select auth.uid()) in (c.sender_id,c.receiver_id))) or (select public.is_admin()));
create policy "participants can send as themselves" on public.messages for insert to authenticated with check (sender_id = (select auth.uid()) and exists(select 1 from public.conversations c where c.id=conversation_id and (select auth.uid()) in (c.sender_id,c.receiver_id)) and (select public.can_use_account()));
create policy "recipient marks messages read" on public.messages for update to authenticated using (exists(select 1 from public.conversations c where c.id=conversation_id and c.receiver_id=(select auth.uid()))) with check (exists(select 1 from public.conversations c where c.id=conversation_id and c.receiver_id=(select auth.uid())));

create policy "reporters submit content reports" on public.content_reports for insert to authenticated with check (reporter_id = (select auth.uid()));
create policy "reporters and admins view reports" on public.content_reports for select to authenticated using (reporter_id=(select auth.uid()) or (select public.is_admin()));
create policy "admins review reports" on public.content_reports for update to authenticated using ((select public.is_admin())) with check ((select public.is_admin()));

insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types)
values ('item-images','item-images',true,8388608,array['image/jpeg','image/png','image/webp'])
on conflict(id) do update set public=true,file_size_limit=8388608,allowed_mime_types=array['image/jpeg','image/png','image/webp'];
create policy "public read item photos" on storage.objects for select using (bucket_id='item-images');
create policy "users upload photos to own folder" on storage.objects for insert to authenticated with check (bucket_id='item-images' and (storage.foldername(name))[1]=(select auth.uid())::text);
create policy "users update own photos" on storage.objects for update to authenticated using (bucket_id='item-images' and (storage.foldername(name))[1]=(select auth.uid())::text) with check (bucket_id='item-images' and (storage.foldername(name))[1]=(select auth.uid())::text);
create policy "users delete own photos" on storage.objects for delete to authenticated using (bucket_id='item-images' and (storage.foldername(name))[1]=(select auth.uid())::text);

-- To grant the first administrator, use the Supabase SQL editor as project owner:
-- update public.profiles set role='admin' where id='<trusted-user-uuid>';
