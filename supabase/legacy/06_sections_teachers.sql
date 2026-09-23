-- CLOUDS FoodPass: sections + teacher/staff event users
-- Run once in Supabase SQL Editor AFTER the previous FoodPass SQL files.

alter table public.students
  alter column usn drop not null;

alter table public.students
  add column if not exists section text,
  add column if not exists person_type text not null default 'student',
  add column if not exists redeemed_at timestamptz;

update public.students set person_type = 'student' where person_type is null;

-- Keep section controlled to A/B/C/D for students; teachers may leave it null.
alter table public.students drop constraint if exists students_section_check;
alter table public.students add constraint students_section_check
  check (section is null or upper(section) in ('A','B','C','D'));

alter table public.students drop constraint if exists students_person_type_check;
alter table public.students add constraint students_person_type_check
  check (person_type in ('student','teacher'));

create index if not exists students_year_section_idx
  on public.students (year, section, person_type);

-- Shared helper for staff authorization.
create or replace function public._clouds_staff_role(p_token text)
returns text
language sql
security definer
set search_path = public, extensions
as $$
  select a.role
  from public.staff_sessions s
  join public.staff_accounts a on a.id = s.staff_id
  where s.token_hash = encode(digest(p_token, 'sha256'), 'hex')
    and s.expires_at > now()
    and a.active = true
  limit 1;
$$;

-- Student registration now includes section.
create or replace function public.register_student(
  p_full_name text,
  p_usn text,
  p_year integer,
  p_section text
)
returns json
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_usn text := upper(trim(p_usn));
  v_section text := upper(trim(p_section));
  v_id uuid;
begin
  if trim(coalesce(p_full_name,'')) = '' or v_usn = '' then
    return json_build_object('success',false,'message','Name and USN are required.');
  end if;
  if p_year not between 1 and 4 then
    return json_build_object('success',false,'message','Select a valid year.');
  end if;
  if v_section not in ('A','B','C','D') then
    return json_build_object('success',false,'message','Select section A, B, C or D.');
  end if;

  if exists(select 1 from public.students where upper(usn)=v_usn) then
    return json_build_object('success',false,'message','This USN is already registered.');
  end if;

  insert into public.students(full_name,usn,year,section,person_type,status,redeemed)
  values(trim(p_full_name),v_usn,p_year,v_section,'student','pending',false)
  returning id into v_id;

  return json_build_object('success',true,'message','Registration successful.','id',v_id);
exception
  when unique_violation then
    return json_build_object('success',false,'message','This USN is already registered.');
end;
$$;

-- Keep compatibility with the old 3-argument frontend until it is replaced.
create or replace function public.register_student(
  p_full_name text,
  p_usn text,
  p_year integer
)
returns json
language plpgsql
security definer
set search_path = public, extensions
as $$
begin
  return public.register_student(p_full_name,p_usn,p_year,'A');
end;
$$;

grant execute on function public.register_student(text,text,integer,text) to anon, authenticated;
grant execute on function public.register_student(text,text,integer) to anon, authenticated;

-- Status now includes section/person type.
create or replace function public.get_student_status(p_usn text)
returns json
language plpgsql
security definer
set search_path = public, extensions
as $$
declare v_person public.students;
begin
  select * into v_person from public.students
  where upper(usn)=upper(trim(p_usn)) and person_type='student'
  limit 1;
  if v_person.id is null then
    return json_build_object('success',false,'message','No registration found for this USN.');
  end if;
  return json_build_object(
    'success',true,'status',v_person.status,'name',v_person.full_name,'usn',v_person.usn,
    'year',v_person.year,'section',v_person.section,'qr_token',v_person.qr_token,
    'redeemed',v_person.redeemed,
    'message',case when v_person.redeemed then 'This FoodPass has already been used.'
      when v_person.status='approved' then 'Your FoodPass has been approved.'
      when v_person.status='rejected' then 'Your registration was not approved.'
      else 'Your registration is waiting for approval.' end
  );
end;
$$;
grant execute on function public.get_student_status(text) to anon, authenticated;

-- Admin: list students AND teachers.
create or replace function public.admin_get_students(p_token text)
returns json
language plpgsql
security definer
set search_path = public, extensions
as $$
declare v_role text; v_result json;
begin
  v_role := public._clouds_staff_role(p_token);
  if v_role <> 'admin' then return '[]'::json; end if;
  select coalesce(json_agg(x order by x.person_type, x.year nulls last, x.section nulls last, x.full_name), '[]'::json)
  into v_result
  from (
    select id,full_name,usn,year,section,person_type,status,redeemed,qr_token,approved_at,created_at
    from public.students
  ) x;
  return v_result;
end;
$$;
grant execute on function public.admin_get_students(text) to anon, authenticated;

-- Admin: add either a student or a teacher directly.
create or replace function public.admin_add_person(
  p_token text,
  p_person_type text,
  p_full_name text,
  p_usn text default null,
  p_year integer default null,
  p_section text default null,
  p_status text default 'pending'
)
returns json
language plpgsql
security definer
set search_path = public, extensions
as $$
declare v_role text; v_id uuid; v_type text := lower(trim(p_person_type)); v_usn text := nullif(upper(trim(coalesce(p_usn,''))), ''); v_section text := nullif(upper(trim(coalesce(p_section,''))), '');
begin
  v_role := public._clouds_staff_role(p_token);
  if v_role <> 'admin' then return json_build_object('success',false,'message','Admin authorization required.'); end if;
  if trim(coalesce(p_full_name,''))='' then return json_build_object('success',false,'message','Name is required.'); end if;
  if v_type not in ('student','teacher') then return json_build_object('success',false,'message','Invalid user type.'); end if;
  if v_type='student' and (v_usn is null or p_year not between 1 and 4 or v_section not in ('A','B','C','D')) then
    return json_build_object('success',false,'message','Student requires USN, year and section A-D.');
  end if;
  if v_type='teacher' then
    v_usn := null; p_year := null; v_section := null;
  end if;
  if v_usn is not null and exists(select 1 from public.students where upper(usn)=v_usn) then
    return json_build_object('success',false,'message','This USN is already registered.');
  end if;
  insert into public.students(full_name,usn,year,section,person_type,status,redeemed)
  values(trim(p_full_name),v_usn,p_year,v_section,v_type,coalesce(p_status,'pending'),false)
  returning id into v_id;
  return json_build_object('success',true,'message',initcap(v_type)||' added.','id',v_id);
exception when unique_violation then
  return json_build_object('success',false,'message','That user already exists.');
end;
$$;
grant execute on function public.admin_add_person(text,text,text,text,integer,text,text) to anon, authenticated;

-- Approval works for both students and teachers.
create or replace function public.admin_approve_student(p_token text,p_student_id uuid)
returns json
language plpgsql
security definer
set search_path = public, extensions
as $$
declare v_role text; v_qr text; v_name text;
begin
  v_role := public._clouds_staff_role(p_token);
  if v_role <> 'admin' then return json_build_object('success',false,'message','Admin authorization required.'); end if;
  select full_name into v_name from public.students where id=p_student_id;
  if v_name is null then return json_build_object('success',false,'message','Entry not found.'); end if;
  v_qr := encode(gen_random_bytes(18),'hex');
  update public.students set status='approved',qr_token=v_qr,approved_at=now() where id=p_student_id;
  return json_build_object('success',true,'message','Approved.','qr_token',v_qr);
end;
$$;
grant execute on function public.admin_approve_student(text,uuid) to anon, authenticated;

-- Scanner redemption works for students and teachers.
create or replace function public.redeem_qr(p_token text,p_qr_token text)
returns json
language plpgsql
security definer
set search_path = public, extensions
as $$
declare v_role text; v_person public.students;
begin
  v_role := public._clouds_staff_role(p_token);
  if v_role not in ('scanner','admin') then return json_build_object('result','UNAUTHORIZED','message','Scanner authorization required.'); end if;
  select * into v_person from public.students where qr_token=p_qr_token limit 1;
  if v_person.id is null then return json_build_object('result','INVALID','message','This QR code is not a valid FoodPass.'); end if;
  if v_person.status <> 'approved' then return json_build_object('result','NOT_APPROVED','message','This FoodPass has not been approved.','name',v_person.full_name,'usn',coalesce(v_person.usn,'—'),'year',v_person.year,'section',v_person.section,'person_type',v_person.person_type); end if;
  if v_person.redeemed then return json_build_object('result','ALREADY_USED','message','This FoodPass has already been redeemed.','name',v_person.full_name,'usn',coalesce(v_person.usn,'—'),'year',v_person.year,'section',v_person.section,'person_type',v_person.person_type); end if;
  update public.students set redeemed=true,redeemed_at=now() where id=v_person.id;
  return json_build_object('result','VALID','message','Food may be served.','name',v_person.full_name,'usn',coalesce(v_person.usn,'—'),'year',v_person.year,'section',v_person.section,'person_type',v_person.person_type);
end;
$$;
grant execute on function public.redeem_qr(text,text) to anon, authenticated;

-- Delete must also work for teachers, whose USN is intentionally null.
create or replace function public.admin_delete_student(p_token text,p_student_id uuid)
returns json
language plpgsql
security definer
set search_path = public, extensions
as $$
declare v_role text; v_name text; v_usn text;
begin
  v_role := public._clouds_staff_role(p_token);
  if v_role <> 'admin' then return json_build_object('success',false,'message','Admin authorization required.'); end if;
  select full_name,usn into v_name,v_usn from public.students where id=p_student_id;
  if v_name is null then return json_build_object('success',false,'message','Entry not found.'); end if;
  delete from public.students where id=p_student_id;
  return json_build_object('success',true,'message','Entry deleted.','usn',v_usn,'name',v_name);
end;
$$;
grant execute on function public.admin_delete_student(text,uuid) to anon, authenticated;
