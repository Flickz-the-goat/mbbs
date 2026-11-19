begin;

insert into auth.users (id, email)
values
    ('a1000000-0000-4000-8000-000000000001', 'hollow-sql-test-a@example.invalid'),
    ('a1000000-0000-4000-8000-000000000002', 'hollow-sql-test-b@example.invalid');

set local role authenticated;
select set_config('request.jwt.claim.sub', 'a1000000-0000-4000-8000-000000000001', true);
insert into public.hollow_profiles (id, username, name, level, device_id)
values ('a1000000-0000-4000-8000-000000000001', 'hollow_sql_test_a', 'Test A', 2,
        'b1000000-0000-4000-8000-000000000001');

do $$
begin
    begin
        insert into public.hollow_profiles (id, username, name, level, device_id)
        values ('a1000000-0000-4000-8000-000000000002', 'hollow_sql_test_b', 'Test B', 3,
                'b1000000-0000-4000-8000-000000000002');
        raise exception 'A user could create another user''s profile';
    exception when insufficient_privilege then
        null;
    end;
end;
$$;

select set_config('request.jwt.claim.sub', 'a1000000-0000-4000-8000-000000000002', true);
insert into public.hollow_profiles (id, username, name, level, device_id)
values ('a1000000-0000-4000-8000-000000000002', 'hollow_sql_test_b', 'Test B', 3,
        'b1000000-0000-4000-8000-000000000002');

select set_config('request.jwt.claim.sub', 'a1000000-0000-4000-8000-000000000001', true);

do $$
begin
    if (select count(*) from public.hollow_profiles) <> 1 then
        raise exception 'A user could read another user''s profile';
    end if;
    if (select device_id from public.hollow_add_contact(' HOLLOW_SQL_TEST_B '))
        is distinct from 'b1000000-0000-4000-8000-000000000002'::uuid then
        raise exception 'Contact lookup returned the wrong device';
    end if;
    perform public.hollow_add_contact('hollow_sql_test_b');
    if (select count(*) from public.hollow_list_contacts()) <> 1 then
        raise exception 'Contact retries should result in one saved contact';
    end if;
    begin
        perform public.hollow_add_contact('hollow_sql_test_a');
        raise exception 'A user could add their own profile';
    exception when no_data_found then
        null;
    end;
end;
$$;

select set_config('request.jwt.claim.sub', 'a1000000-0000-4000-8000-000000000002', true);
do $$
begin
    if exists (select 1 from public.hollow_list_contacts())
        or exists (select 1 from public.hollow_saved_contacts) then
        raise exception 'A user could read another user''s contacts';
    end if;
end;
$$;

set local role anon;
do $$
begin
    if has_table_privilege(current_user, 'public.hollow_profiles', 'SELECT')
        or has_function_privilege(current_user, 'public.hollow_add_contact(text)', 'EXECUTE')
        or has_function_privilege(current_user, 'public.hollow_list_contacts()', 'EXECUTE') then
        raise exception 'Anonymous callers have access to account data';
    end if;
end;
$$;

rollback;
