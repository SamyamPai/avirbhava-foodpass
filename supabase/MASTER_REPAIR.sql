-- ============================================================
-- CLOUDS FOODPASS - MASTER REPAIR / FINAL DATABASE MIGRATION
-- Run this ONCE in the Supabase SQL Editor.
-- It is based on the actual schema:
-- students.qr_token = uuid
-- students.food_preference = text
-- students.person_type = text
-- ============================================================

create extension if not exists pgcrypto;

-- Required columns (safe if already present)
alter table public.students
  add column if not exists section text,
  add column if not exists person_type text not null default 'student',
  add column if not exists foodpass_code text,
  add column if not exists food_preference text,
  add column if not exists redeemed_at timestamptz;

alter table public.students alter column usn drop not null;
alter table public.students alter column year drop not null;

-- Constraints
alter table public.students drop constraint if exists students_section_check;
alter table public.students add constraint students_section_check
  check (section is null or upper(section) in ('A','B','C','D'));

alter table public.students drop constraint if exists students_person_type_check;
alter table public.students add constraint students_person_type_check
  check (person_type in ('student','teacher'));

alter table public.students drop constraint if exists students_food_preference_check;
alter table public.students add constraint students_food_preference_check
  check (food_preference is null or food_preference in ('veg','non-veg'));

create unique index if not exists students_foodpass_code_unique
  on public.students(foodpass_code)
  where foodpass_code is not null;

create index if not exists students_year_section_idx
  on public.students(year, section, person_type);

create index if not exists students_usn_idx on public.students(usn);
create index if not exists students_qr_token_idx on public.students(qr_token);

-- Helper: remove every overloaded version of a function by name.
do $$
declare r record;
begin
  for r in
    select p.oid::regprocedure as sig
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public'
      and p.proname in (
        'register_student',
        'admin_get_students',
        'admin_add_person',
        'admin_approve_student',
        'admin_reject_student',
        'admin_delete_student',
        'get_student_status',
        'get_teacher_status',
        'redeem_qr',
        'scanner_get_logs',
        'scanner_log_scan',
        'staff_login',
        'staff_logout',
        'check_staff_session',
        '_clouds_staff_role'
      )
  loop
    execute 'drop function if exists ' || r.sig || ' cascade';
  end loop;
end $$;

-- Staff sessions must exist before staff functions.
create table if not exists public.staff_sessions(
  id uuid primary key default gen_random_uuid(),
  staff_id uuid not null references public.staff_accounts(id) on delete cascade,
  token_hash text not null unique,
  expires_at timestamptz not null,
  created_at timestamptz not null default now()
);

create index if not exists staff_sessions_token_idx
  on public.staff_sessions(token_hash);
create index if not exists staff_sessions_expiry_idx
  on public.staff_sessions(expires_at);

-- ============================================================
-- STAFF AUTH
-- ============================================================
create function public.staff_login(p_username text, p_password text)
returns json
language plpgsql security definer
set search_path = public, extensions
as $$
declare
  a public.staff_accounts;
  raw text;
  h text;
begin
  select * into a
  from public.staff_accounts
  where lower(username) = lower(trim(p_username))
    and active = true
  limit 1;

  if a.id is null then
    return json_build_object('success',false,'message','Invalid username or password.');
  end if;

  -- Supports both existing bcrypt/crypt hashes and any legacy plain-text
  -- event PINs. A successful legacy login is immediately upgraded to crypt().
  if a.password_hash <> crypt(p_password, a.password_hash)
     and a.password_hash <> p_password then
    return json_build_object('success',false,'message','Invalid username or password.');
  end if;

  if a.password_hash = p_password then
    update public.staff_accounts
      set password_hash = crypt(p_password, gen_salt('bf'))
      where id = a.id;
  end if;

  raw := encode(gen_random_bytes(32),'hex');
  h := encode(digest(raw,'sha256'),'hex');

  insert into public.staff_sessions(staff_id,token_hash,expires_at)
  values(a.id,h,now() + interval '12 hours');

  return json_build_object(
    'success',true,
    'token',raw,
    'username',a.username,
    'role',a.role
  );
end;
$$;

grant execute on function public.staff_login(text,text) to anon, authenticated;

create function public.staff_logout(p_token text)
returns json language plpgsql security definer
set search_path = public, extensions
as $$
begin
  delete from public.staff_sessions
  where token_hash = encode(digest(p_token,'sha256'),'hex');
  return json_build_object('success',true);
end;
$$;
grant execute on function public.staff_logout(text) to anon, authenticated;

create function public.check_staff_session(p_token text)
returns json language plpgsql security definer
set search_path = public, extensions
as $$
declare a public.staff_accounts;
begin
  select sa.* into a
  from public.staff_sessions ss
  join public.staff_accounts sa on sa.id = ss.staff_id
  where ss.token_hash = encode(digest(p_token,'sha256'),'hex')
    and ss.expires_at > now()
    and sa.active = true
  limit 1;

  if a.id is null then
    return json_build_object('success',false,'message','Session expired or invalid.');
  end if;

  return json_build_object('success',true,'username',a.username,'role',a.role);
end;
$$;
grant execute on function public.check_staff_session(text) to anon, authenticated;

create function public._clouds_staff_role(p_token text)
returns text language sql security definer
set search_path = public, extensions
as $$
  select a.role
  from public.staff_sessions s
  join public.staff_accounts a on a.id = s.staff_id
  where s.token_hash = encode(digest(p_token,'sha256'),'hex')
    and s.expires_at > now()
    and a.active = true
  limit 1;
$$;

-- ============================================================
-- STUDENT REGISTRATION - EXACT SIGNATURE USED BY THE FRONTEND
-- (text, text, integer, text, text)
-- ============================================================
create function public.register_student(
  p_full_name text,
  p_section text,
  p_year integer,
  p_usn text,
  p_food_preference text
)
returns json language plpgsql security definer
set search_path = public, extensions
as $$
declare
  clean_name text := trim(coalesce(p_full_name,''));
  clean_section text := upper(trim(coalesce(p_section,'')));
  clean_usn text := upper(trim(coalesce(p_usn,'')));
  clean_food text := lower(trim(coalesce(p_food_preference,'')));
  new_id uuid;
begin
  if clean_name = '' then
    return json_build_object('success',false,'message','Please enter your full name.');
  end if;

  -- 4SF24CS181-style CSE USN. Case is normalized to uppercase.
  if clean_usn !~ '^[0-9]{1,2}SF[0-9]{2}CS[0-9]{3}$' then
    return json_build_object('success',false,'message','Invalid CSE USN. Example: 4SF24CS181.');
  end if;

  if p_year not between 1 and 4 then
    return json_build_object('success',false,'message','Select a valid year.');
  end if;

  if clean_section not in ('A','B','C','D') then
    return json_build_object('success',false,'message','Select section A, B, C or D.');
  end if;

  if clean_food not in ('veg','non-veg') then
    return json_build_object('success',false,'message','Select Veg or Non-Veg.');
  end if;

  if exists(select 1 from public.students where upper(usn)=clean_usn) then
    return json_build_object('success',false,'message','This USN is already registered.');
  end if;

  insert into public.students(
    full_name, usn, year, section, person_type,
    food_preference, status, redeemed
  ) values (
    clean_name, clean_usn, p_year, clean_section, 'student',
    clean_food, 'pending', false
  ) returning id into new_id;

  return json_build_object(
    'success',true,
    'message','Registration successful. Check your status later using your USN.',
    'id',new_id
  );
exception
  when unique_violation then
    return json_build_object('success',false,'message','This USN is already registered.');
  when others then
    return json_build_object('success',false,'message',sqlerrm);
end;
$$;

grant execute on function public.register_student(text,text,integer,text,text) to anon, authenticated;

-- ============================================================
-- STUDENT STATUS
-- ============================================================
create function public.get_student_status(p_usn text)
returns json language plpgsql security definer
set search_path = public, extensions
as $$
declare v public.students;
begin
  select * into v
  from public.students
  where upper(usn)=upper(trim(p_usn))
    and person_type='student'
  limit 1;

  if v.id is null then
    return json_build_object('success',false,'message','No registration found for this USN.');
  end if;

  return json_build_object(
    'success',true,
    'status',v.status,
    'name',v.full_name,
    'usn',v.usn,
    'year',v.year,
    'section',v.section,
    'food_preference',v.food_preference,
    'qr_token',v.qr_token,
    'redeemed',v.redeemed,
    'message',case
      when v.redeemed then 'This FoodPass has already been used.'
      when v.status='approved' then 'Your FoodPass has been approved.'
      when v.status='rejected' then 'Your registration was not approved.'
      else 'Your registration is waiting for approval.'
    end
  );
end;
$$;
grant execute on function public.get_student_status(text) to anon, authenticated;

-- ============================================================
-- ADMIN LIST
-- ============================================================
create function public.admin_get_students(p_token text)
returns json language plpgsql security definer
set search_path = public, extensions
as $$
declare v_role text; result json;
begin
  v_role := public._clouds_staff_role(p_token);
  if v_role <> 'admin' then return '[]'::json; end if;

  select coalesce(json_agg(row_to_json(x) order by
      case when x.person_type='student' then 0 else 1 end,
      x.year nulls last,
      x.section nulls last,
      x.full_name), '[]'::json)
  into result
  from (
    select id, full_name, usn, year, section, person_type,
           food_preference, status, redeemed, qr_token,
           approved_at, created_at
    from public.students
  ) x;

  return result;
end;
$$;
grant execute on function public.admin_get_students(text) to anon, authenticated;

-- ============================================================
-- ADMIN ADD STUDENT / TEACHER
-- ============================================================
create function public.admin_add_person(
  p_token text,
  p_person_type text,
  p_full_name text,
  p_usn text default null,
  p_year integer default null,
  p_section text default null,
  p_food_preference text default null,
  p_status text default 'pending'
)
returns json language plpgsql security definer
set search_path = public, extensions
as $$
declare
  role_name text;
  typ text := lower(trim(p_person_type));
  clean_name text := trim(coalesce(p_full_name,''));
  u text := nullif(upper(trim(coalesce(p_usn,''))), '');
  sec text := nullif(upper(trim(coalesce(p_section,''))), '');
  food text := nullif(lower(trim(coalesce(p_food_preference,''))), '');
  code text := null;
  new_id uuid;
begin
  role_name := public._clouds_staff_role(p_token);
  if role_name <> 'admin' then
    return json_build_object('success',false,'message','Admin authorization required.');
  end if;

  if clean_name='' then
    return json_build_object('success',false,'message','Name is required.');
  end if;

  if typ not in ('student','teacher') then
    return json_build_object('success',false,'message','Invalid user type.');
  end if;

  if typ='student' then
    if u is null or u !~ '^[0-9]{1,2}SF[0-9]{2}CS[0-9]{3}$' then
      return json_build_object('success',false,'message','Invalid CSE USN. Example: 4SF24CS181.');
    end if;
    if p_year not between 1 and 4 or sec not in ('A','B','C','D') then
      return json_build_object('success',false,'message','Student requires year and section A-D.');
    end if;
    if food not in ('veg','non-veg') then
      return json_build_object('success',false,'message','Select Veg or Non-Veg.');
    end if;
  else
    u := null;
    p_year := null;
    sec := null;
    food := null;
    loop
      code := 'TCH-' || upper(substr(encode(gen_random_bytes(6),'hex'),1,8));
      exit when not exists(select 1 from public.students where foodpass_code=code);
    end loop;
  end if;

  if u is not null and exists(select 1 from public.students where upper(usn)=u) then
    return json_build_object('success',false,'message','This USN is already registered.');
  end if;

  insert into public.students(
    full_name, usn, year, section, person_type,
    food_preference, foodpass_code, status, redeemed
  ) values (
    clean_name, u, p_year, sec, typ,
    food, code, coalesce(p_status,'pending'), false
  ) returning id into new_id;

  return json_build_object(
    'success',true,
    'message',initcap(typ)||' added.',
    'id',new_id,
    'foodpass_code',code
  );
exception
  when unique_violation then
    return json_build_object('success',false,'message','That user already exists.');
  when others then
    return json_build_object('success',false,'message',sqlerrm);
end;
$$;
grant execute on function public.admin_add_person(text,text,text,text,integer,text,text,text) to anon, authenticated;

-- ============================================================
-- ADMIN APPROVAL: QR TOKEN IS UUID, NOT TEXT
-- ============================================================
create function public.admin_approve_student(p_token text, p_student_id uuid)
returns json language plpgsql security definer
set search_path = public, extensions
as $$
declare
  role_name text;
  v public.students;
  new_qr uuid;
begin
  role_name := public._clouds_staff_role(p_token);
  if role_name <> 'admin' then
    return json_build_object('success',false,'message','Admin authorization required.');
  end if;

  select * into v from public.students where id=p_student_id for update;
  if v.id is null then
    return json_build_object('success',false,'message','Entry not found.');
  end if;

  new_qr := coalesce(v.qr_token, gen_random_uuid());

  update public.students
  set status='approved',
      qr_token=new_qr,
      approved_at=now(),
      updated_at=now()
  where id=p_student_id;

  return json_build_object(
    'success',true,
    'message','Approved.',
    'qr_token',new_qr::text
  );
end;
$$;
grant execute on function public.admin_approve_student(text,uuid) to anon, authenticated;

create function public.admin_reject_student(p_token text, p_student_id uuid)
returns json language plpgsql security definer
set search_path = public, extensions
as $$
declare role_name text;
begin
  role_name := public._clouds_staff_role(p_token);
  if role_name <> 'admin' then
    return json_build_object('success',false,'message','Admin authorization required.');
  end if;

  update public.students
  set status='rejected', updated_at=now()
  where id=p_student_id;

  if not found then
    return json_build_object('success',false,'message','Entry not found.');
  end if;

  return json_build_object('success',true,'message','Registration rejected.');
end;
$$;
grant execute on function public.admin_reject_student(text,uuid) to anon, authenticated;

create function public.admin_delete_student(p_token text, p_student_id uuid)
returns json language plpgsql security definer
set search_path = public, extensions
as $$
declare role_name text;
begin
  role_name := public._clouds_staff_role(p_token);
  if role_name <> 'admin' then
    return json_build_object('success',false,'message','Admin authorization required.');
  end if;

  delete from public.students where id=p_student_id;
  if not found then
    return json_build_object('success',false,'message','Entry not found.');
  end if;

  return json_build_object('success',true,'message','Entry deleted.');
end;
$$;
grant execute on function public.admin_delete_student(text,uuid) to anon, authenticated;

-- ============================================================
-- TEACHER FOODPASS STATUS
-- ============================================================
create function public.get_teacher_status(p_code text)
returns json language plpgsql security definer
set search_path = public, extensions
as $$
declare v public.students;
begin
  select * into v
  from public.students
  where upper(foodpass_code)=upper(trim(p_code))
    and person_type='teacher'
  limit 1;

  if v.id is null then
    return json_build_object('success',false,'message','Teacher FoodPass code not found.');
  end if;

  return json_build_object(
    'success',true,
    'name',v.full_name,
    'foodpass_code',v.foodpass_code,
    'status',v.status,
    'qr_token',v.qr_token,
    'redeemed',v.redeemed
  );
end;
$$;
grant execute on function public.get_teacher_status(text) to anon, authenticated;

-- ============================================================
-- SCANNER: ATOMIC REDEMPTION + LOGGING
-- ============================================================
create function public.redeem_qr(p_token text, p_qr_token text)
returns json language plpgsql security definer
set search_path = public, extensions
as $$
declare
  role_name text;
  scanner_username text;
  v public.students;
  q uuid;
  outcome text;
  msg text;
begin
  select a.role, a.username
  into role_name, scanner_username
  from public.staff_sessions s
  join public.staff_accounts a on a.id=s.staff_id
  where s.token_hash=encode(digest(p_token,'sha256'),'hex')
    and s.expires_at>now()
    and a.active=true
  limit 1;

  if role_name not in ('scanner','admin') then
    return json_build_object('result','UNAUTHORIZED','message','Scanner session expired.');
  end if;

  if trim(coalesce(p_qr_token,'')) !~* '^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$' then
    insert into public.scanner_logs(scanner_username, result, qr_token)
    values(scanner_username,'INVALID',null);
    return json_build_object('result','INVALID','message','This is not a valid FoodPass QR code.');
  end if;

  q := trim(p_qr_token)::uuid;

  select * into v
  from public.students
  where qr_token=q
  for update;

  if v.id is null then
    insert into public.scanner_logs(scanner_username,result,qr_token)
    values(scanner_username,'INVALID',p_qr_token);
    return json_build_object('result','INVALID','message','This QR code is not a valid FoodPass.');
  end if;

  if v.status <> 'approved' then
    insert into public.scanner_logs(scanner_username,student_id,usn,full_name,year,result,qr_token)
    values(scanner_username,v.id,v.usn,v.full_name,v.year,'NOT_APPROVED',p_qr_token);
    return json_build_object(
      'result','NOT_APPROVED',
      'message','This FoodPass has not been approved.',
      'name',v.full_name,'usn',coalesce(v.usn,'—'),'year',v.year,
      'section',v.section,'person_type',v.person_type,
      'food_preference',v.food_preference
    );
  end if;

  if v.redeemed then
    insert into public.scanner_logs(scanner_username,student_id,usn,full_name,year,result,qr_token)
    values(scanner_username,v.id,v.usn,v.full_name,v.year,'ALREADY_USED',p_qr_token);
    return json_build_object(
      'result','ALREADY_USED',
      'message','This FoodPass has already been redeemed. Do not serve again.',
      'name',v.full_name,'usn',coalesce(v.usn,'—'),'year',v.year,
      'section',v.section,'person_type',v.person_type,
      'food_preference',v.food_preference
    );
  end if;

  update public.students
  set redeemed=true, redeemed_at=now(), updated_at=now()
  where id=v.id and redeemed=false;

  if not found then
    insert into public.scanner_logs(scanner_username,student_id,usn,full_name,year,result,qr_token)
    values(scanner_username,v.id,v.usn,v.full_name,v.year,'ALREADY_USED',p_qr_token);
    return json_build_object(
      'result','ALREADY_USED',
      'message','This FoodPass has already been redeemed. Do not serve again.',
      'name',v.full_name,'usn',coalesce(v.usn,'—'),'year',v.year,
      'section',v.section,'person_type',v.person_type,
      'food_preference',v.food_preference
    );
  end if;

  insert into public.scanner_logs(scanner_username,student_id,usn,full_name,year,result,qr_token)
  values(scanner_username,v.id,v.usn,v.full_name,v.year,'VALID',p_qr_token);

  return json_build_object(
    'result','VALID',
    'message','FoodPass verified successfully. Food may be served.',
    'name',v.full_name,'usn',coalesce(v.usn,'—'),'year',v.year,
    'section',v.section,'person_type',v.person_type,
    'food_preference',v.food_preference
  );
end;
$$;
grant execute on function public.redeem_qr(text,text) to anon, authenticated;

-- Keep the old logging RPC available for compatibility, but make it safe.
create function public.scanner_log_scan(p_token text,p_qr_token text,p_result text)
returns json language plpgsql security definer
set search_path=public,extensions
as $$
declare username text;
begin
  select a.username into username
  from public.staff_sessions s
  join public.staff_accounts a on a.id=s.staff_id
  where s.token_hash=encode(digest(p_token,'sha256'),'hex')
    and s.expires_at>now()
    and a.active=true
    and a.role in ('scanner','admin')
  limit 1;
  if username is null then
    return json_build_object('success',false,'message','Scanner authorization required.');
  end if;
  return json_build_object('success',true,'message','Logging is handled by redeem_qr.');
end;
$$;
grant execute on function public.scanner_log_scan(text,text,text) to anon, authenticated;

-- ============================================================
-- SCANNER LOGS WITH FOOD PREFERENCE + SECTION
-- ============================================================
create function public.scanner_get_logs(p_token text,p_limit integer default 40)
returns json language plpgsql security definer
set search_path=public,extensions
as $$
declare v_username text; result json;
begin
  select a.username into v_username
  from public.staff_sessions s
  join public.staff_accounts a on a.id=s.staff_id
  where s.token_hash=encode(digest(p_token,'sha256'),'hex')
    and s.expires_at>now()
    and a.active=true
    and a.role in ('scanner','admin')
  limit 1;

  if v_username is null then return '[]'::json; end if;

  select coalesce(json_agg(x order by x.scanned_at desc),'[]'::json)
  into result
  from (
    select
      l.scanned_at,
      l.scanner_username,
      l.usn,
      l.full_name,
      l.year,
      l.result,
      s.section,
      s.food_preference,
      s.person_type
    from public.scanner_logs l
    left join public.students s on s.id=l.student_id
    order by l.scanned_at desc
    limit greatest(1,least(coalesce(p_limit,40),100))
  ) x;

  return result;
end;
$$;
grant execute on function public.scanner_get_logs(text,integer) to anon, authenticated;

-- ============================================================
-- FINAL FUNCTION SIGNATURE CHECK
-- ============================================================
select
  p.oid::regprocedure as function_signature
from pg_proc p
join pg_namespace n on n.oid=p.pronamespace
where n.nspname='public'
  and p.proname='register_student';
