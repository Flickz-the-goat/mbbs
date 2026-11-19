begin;

create table if not exists public.hollow_profiles (
    id uuid primary key references auth.users(id) on delete cascade,
    username text not null unique check (username ~ '^[a-z0-9_]{3,24}$'),
    name text not null check (char_length(btrim(name)) between 1 and 80),
    level integer not null check (level between 2 and 4),
    device_id uuid not null unique
);

create table if not exists public.hollow_saved_contacts (
    owner_id uuid not null references public.hollow_profiles(id) on delete cascade,
    contact_id uuid not null references public.hollow_profiles(id) on delete cascade,
    primary key (owner_id, contact_id),
    check (owner_id <> contact_id)
);

create index if not exists hollow_saved_contacts_contact_id_idx
    on public.hollow_saved_contacts(contact_id);

alter table public.hollow_profiles enable row level security;
alter table public.hollow_saved_contacts enable row level security;

revoke all on public.hollow_profiles, public.hollow_saved_contacts from public, anon, authenticated;
grant select, insert on public.hollow_profiles to authenticated;
grant select on public.hollow_saved_contacts to authenticated;

drop policy if exists hollow_read_own_profile on public.hollow_profiles;
create policy hollow_read_own_profile on public.hollow_profiles
    for select to authenticated using (id = (select auth.uid()));

drop policy if exists hollow_create_own_profile on public.hollow_profiles;
create policy hollow_create_own_profile on public.hollow_profiles
    for insert to authenticated with check (id = (select auth.uid()));

drop policy if exists hollow_read_own_contacts on public.hollow_saved_contacts;
create policy hollow_read_own_contacts on public.hollow_saved_contacts
    for select to authenticated using (owner_id = (select auth.uid()));

-- The exact-name lookup exposes only the fields needed to address a BLE message.
create or replace function public.hollow_add_contact(contact_username text)
returns table (username text, name text, device_id uuid)
language plpgsql
security definer
set search_path = ''
as $$
declare
    caller uuid := auth.uid();
    target public.hollow_profiles%rowtype;
begin
    if caller is null or not exists (select 1 from public.hollow_profiles where id = caller) then
        raise exception 'Complete your Hollow profile before adding contacts.' using errcode = '42501';
    end if;

    select p.* into target from public.hollow_profiles as p
        where p.username = lower(btrim(contact_username)) and p.id <> caller;

    if not found then
        raise exception 'No other resident has that username.' using errcode = 'P0002';
    end if;

    insert into public.hollow_saved_contacts (owner_id, contact_id)
        values (caller, target.id) on conflict do nothing;

    return query select target.username, target.name, target.device_id;
end;
$$;

create or replace function public.hollow_list_contacts()
returns table (username text, name text, device_id uuid)
language sql
stable
security definer
set search_path = ''
as $$
    select p.username, p.name, p.device_id
    from public.hollow_saved_contacts as c
    join public.hollow_profiles as p on p.id = c.contact_id
    where c.owner_id = (select auth.uid())
    order by p.username;
$$;

revoke all on function public.hollow_add_contact(text), public.hollow_list_contacts()
    from public, anon, authenticated;
grant execute on function public.hollow_add_contact(text), public.hollow_list_contacts()
    to authenticated;

commit;
