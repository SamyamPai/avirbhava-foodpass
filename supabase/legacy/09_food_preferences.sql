-- 09 food preference + strict CSE USN + admin statistics
-- Run after the previous foolproof SQL. This migration is designed to preserve existing data.

alter table public.students
  add column if not exists food_preference text;

alter table public.students
  add column if not exists section text;

-- Existing teachers may have null food preference/section.
-- Existing students can be updated by admin if needed.

do $$
begin
  if not exists (
    select 1 from pg_constraint
    where conname='students_food_preference_check'
  ) then
    alter table public.students add constraint students_food_preference_check
      check (food_preference is null or food_preference in ('veg','non-veg'));
  end if;
end $$;

do $$
begin
  if not exists (
    select 1 from pg_constraint
    where conname='students_section_check'
  ) then
    alter table public.students add constraint students_section_check
      check (section is null or section in ('A','B','C','D'));
  end if;
end $$;

-- Strict CSE USN: one/two digits + SF + two digits + CS + three digits.
-- Example: 4SF24CS181.
-- Case-insensitive because the application normalizes to uppercase.
create or replace function public.register_student(
  p_full_name text,
  p_usn text,
  p_year integer,
  p_section text,
  p_food_preference text
)
returns json
language plpgsql
security definer
set search_path=public,extensions
as $$
declare new_student public.students;
declare clean_usn text := upper(trim(p_usn));
declare clean_section text := upper(trim(p_section));
declare clean_food text := lower(trim(p_food_preference));
begin
  if clean_usn !~ '^[0-9]{1,2}SF[0-9]{2}CS[0-9]{3}$' then
    return json_build_object('success',false,'message','Invalid CSE USN. Example: 4SF24CS181.');
  end if;
  if p_year not between 1 and 4 then
    return json_build_object('success',false,'message','Invalid year.');
  end if;
  if clean_section not in ('A','B','C','D') then
    return json_build_object('success',false,'message','Invalid section.');
  end if;
  if clean_food not in ('veg','non-veg') then
    return json_build_object('success',false,'message','Invalid food preference.');
  end if;
  if exists(select 1 from public.students where upper(usn)=clean_usn) then
    return json_build_object('success',false,'message','This USN is already registered.');
  end if;

  insert into public.students(full_name,usn,year,section,food_preference,status,redeemed)
  values(trim(p_full_name),clean_usn,p_year,clean_section,clean_food,'pending',false)
  returning * into new_student;

  return json_build_object('success',true,'message','Registration successful.');
exception when unique_violation then
  return json_build_object('success',false,'message','This USN is already registered.');
end;
$$;

grant execute on function public.register_student(text,text,integer,text,text) to anon,authenticated;

-- Return the new fields to the existing status page.
create or replace function public.get_student_status(p_usn text)
returns json
language plpgsql security definer
set search_path=public,extensions
as $$
declare student public.students;
begin
 select * into student from public.students where upper(usn)=upper(trim(p_usn)) limit 1;
 if student.id is null then
   return json_build_object('success',false,'message','No registration found for this USN.');
 end if;
 return json_build_object(
   'success',true,'status',student.status,'name',student.full_name,'usn',student.usn,
   'year',student.year,'section',student.section,'food_preference',student.food_preference,
   'qr_token',student.qr_token,'redeemed',student.redeemed,
   'message',case when student.redeemed then 'This FoodPass has already been used.'
     when student.status='approved' then 'Your FoodPass has been approved.'
     when student.status='rejected' then 'Your registration was not approved.'
     else 'Your registration is waiting for approval.' end
 );
end;
$$;
grant execute on function public.get_student_status(text) to anon,authenticated;

-- Recreate admin list with the new fields. Drop first because return type/columns may differ.
drop function if exists public.admin_get_students(text);
create function public.admin_get_students(p_token text)
returns json
language plpgsql security definer
set search_path=public,extensions
as $$
declare result json;
begin
 if not exists(select 1 from public.staff_sessions ss join public.staff_accounts sa on sa.id=ss.staff_id
               where ss.token_hash=encode(digest(p_token,'sha256'),'hex')
               and ss.expires_at>now()) then
   return '[]'::json;
 end if;

 select coalesce(json_agg(row_to_json(x) order by
   case when x.person_type='teacher' then 0 else 1 end,
   coalesce(x.year,99),coalesce(x.section,'Z'),x.full_name), '[]'::json)
 into result
 from (
   select id,full_name,usn,year,section,food_preference,status,redeemed,qr_token,
          coalesce(person_type,'student') as person_type
   from public.students
 ) x;
 return result;
end;
$$;
grant execute on function public.admin_get_students(text) to anon,authenticated;
