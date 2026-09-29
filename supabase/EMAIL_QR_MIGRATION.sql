-- CLOUDS FoodPass - college email + QR email support
-- Run ONCE in Supabase SQL Editor after your current database repair scripts.
-- Existing registrations are NOT deleted. Existing rows simply get NULL email.

alter table public.students
  add column if not exists email text,
  add column if not exists qr_email_sent_at timestamptz;

create index if not exists students_email_idx
  on public.students(lower(email));

-- Exact college-domain check. Example:
-- samyam.p.cs24@sahyadri.edu.in
alter table public.students drop constraint if exists students_college_email_check;
alter table public.students add constraint students_college_email_check
  check (
    email is null
    or email ~* '^[a-z0-9._%+-]+@sahyadri\\.edu\\.in$'
  );

-- ============================================================
-- STUDENT REGISTRATION WITH COLLEGE EMAIL
-- ============================================================
drop function if exists public.register_student(text,text,integer,text,text);
drop function if exists public.register_student(text,text,text,integer,text,text);

create function public.register_student(
  p_full_name text,
  p_email text,
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
  clean_email text := lower(trim(coalesce(p_email,'')));
  clean_section text := upper(trim(coalesce(p_section,'')));
  clean_usn text := upper(trim(coalesce(p_usn,'')));
  clean_food text := lower(trim(coalesce(p_food_preference,'')));
  new_id uuid;
begin
  if clean_name = '' then
    return json_build_object('success',false,'message','Please enter your full name.');
  end if;

  if clean_email !~ '^[a-z0-9._%+-]+@sahyadri\\.edu\\.in$' then
    return json_build_object('success',false,'message','Please use your Sahyadri college email ending with @sahyadri.edu.in.');
  end if;

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
    full_name, email, usn, year, section, person_type,
    food_preference, status, redeemed, qr_email_sent_at
  ) values (
    clean_name, clean_email, clean_usn, p_year, clean_section, 'student',
    clean_food, 'pending', false, null
  ) returning id into new_id;

  return json_build_object(
    'success',true,
    'message','Registration successful. After approval, your QR will be sent to your college email.',
    'id',new_id
  );
exception
  when unique_violation then
    return json_build_object('success',false,'message','This USN is already registered.');
  when others then
    return json_build_object('success',false,'message',sqlerrm);
end;
$$;

grant execute on function public.register_student(text,text,text,integer,text,text) to anon, authenticated;

-- ============================================================
-- ADMIN LIST: include email + email sent timestamp
-- ============================================================
drop function if exists public.admin_get_students(text);
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
    select id, full_name, email, usn, year, section, person_type,
           food_preference, status, redeemed, qr_token,
           approved_at, created_at, qr_email_sent_at
    from public.students
  ) x;

  return result;
end;
$$;
grant execute on function public.admin_get_students(text) to anon, authenticated;

-- ============================================================
-- ADMIN ADD PERSON: optional email for student/teacher
-- ============================================================
drop function if exists public.admin_add_person(text,text,text,text,integer,text,text,text);

create function public.admin_add_person(
  p_token text,
  p_person_type text,
  p_full_name text,
  p_email text default null,
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
  clean_email text := nullif(lower(trim(coalesce(p_email,''))), '');
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

  if clean_email is not null and clean_email !~ '^[a-z0-9._%+-]+@sahyadri\\.edu\\.in$' then
    return json_build_object('success',false,'message','Use a valid @sahyadri.edu.in email address.');
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
    full_name, email, usn, year, section, person_type,
    food_preference, foodpass_code, status, redeemed
  ) values (
    clean_name, clean_email, u, p_year, sec, typ,
    food, code, p_status, false
  ) returning id into new_id;

  return json_build_object('success',true,'id',new_id,'message','User added.');
exception
  when unique_violation then
    return json_build_object('success',false,'message','This user already exists.');
  when others then
    return json_build_object('success',false,'message',sqlerrm);
end;
$$;
grant execute on function public.admin_add_person(text,text,text,text,text,integer,text,text,text) to anon, authenticated;

-- ============================================================
-- ADMIN SET / UPDATE EMAIL FOR EXISTING REGISTRATIONS
-- This lets you add emails to already-approved rows without
-- deleting/re-registering them.
-- ============================================================
drop function if exists public.admin_update_student_email(text,uuid,text);
create function public.admin_update_student_email(
  p_token text,
  p_student_id uuid,
  p_email text
)
returns json language plpgsql security definer
set search_path = public, extensions
as $$
declare role_name text; clean_email text; v public.students;
begin
  role_name := public._clouds_staff_role(p_token);
  if role_name <> 'admin' then
    return json_build_object('success',false,'message','Admin authorization required.');
  end if;

  clean_email := lower(trim(coalesce(p_email,'')));
  if clean_email !~ '^[a-z0-9._%+-]+@sahyadri\\.edu\\.in$' then
    return json_build_object('success',false,'message','Use a valid @sahyadri.edu.in email address.');
  end if;

  update public.students
  set email=clean_email,
      qr_email_sent_at=null,
      updated_at=now()
  where id=p_student_id
  returning * into v;

  if v.id is null then
    return json_build_object('success',false,'message','Entry not found.');
  end if;

  return json_build_object('success',true,'message','College email saved.','email',v.email);
end;
$$;
grant execute on function public.admin_update_student_email(text,uuid,text) to anon, authenticated;

-- Existing approved rows keep working exactly as before.
-- The email function will send only when an email is present.

select id, full_name, email, status, qr_email_sent_at
from public.students
order by created_at desc
limit 5;
