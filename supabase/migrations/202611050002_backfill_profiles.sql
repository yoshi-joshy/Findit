-- Accounts that existed before the profile trigger was added need a profile row
-- for account status checks and poster display names. Keep the user role default.
insert into public.profiles (id, display_name)
select
  u.id,
  coalesce(nullif(trim(u.raw_user_meta_data ->> 'display_name'), ''), 'Community member')
from auth.users as u
on conflict (id) do nothing;
