-- UbuntuCircle profile fields required by the connected front end.
-- Run this once in Supabase SQL Editor after checking the existing profiles table.

alter table public.profiles
  add column if not exists role text not null default 'student'
    check (role in ('student', 'mentor')),
  add column if not exists course text not null default '',
  add column if not exists interests text[] not null default '{}';

-- Keep the existing automatic profile trigger, but make it store signup metadata.
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  insert into public.profiles (id, full_name, role, course, interests)
  values (
    new.id,
    coalesce(new.raw_user_meta_data->>'full_name', ''),
    case when new.raw_user_meta_data->>'role' = 'mentor' then 'mentor' else 'student' end,
    coalesce(new.raw_user_meta_data->>'course', ''),
    coalesce(
      array(select jsonb_array_elements_text(coalesce(new.raw_user_meta_data->'interests', '[]'::jsonb))),
      '{}'::text[]
    )
  )
  on conflict (id) do update set
    full_name = excluded.full_name,
    role = excluded.role,
    course = excluded.course,
    interests = excluded.interests;
  return new;
end;
$$;

-- Ensure authenticated users can read public student/mentor profiles
-- and update only their own profile, as controlled by existing RLS policies.
grant select, update on public.profiles to authenticated;


-- Ensure the auth trigger exists and points to the updated function.
drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
after insert on auth.users
for each row execute function public.handle_new_user();
