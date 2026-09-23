-- CLOUDS FoodPass FINAL CONSISTENCY FIX
-- Run this ONCE after your existing migrations.
-- It repairs the UUID QR bug, adds food preference, enforces CSE USNs,
-- and recreates the functions used by the current frontend.

create extension if not exists pgcrypto;

alter table public.students alter column usn drop not null;
alter table public.students alter column year drop not null;
alter table public.students add column if not exists section text;
alter table public.students add column if not exists person_type text not null default 'student';
alter table public.students add column if not exists food_preference text;
alter table public.students add column if not exists redeemed_at timestamptz;
alter table public.students add column if not exists foodpass_code text;

update public.students set person_type='student' where person_type is null;

alter table public.students drop constraint if exists students_section_check;
alter table public.students add constraint students_section_check check (section is null or upper(section) in ('A','B','C','D'));
alter table public.students drop constraint if exists students_person_type_check;
alter table public.students add constraint students_person_type_check check (person_type in ('student','teacher'));
alter table public.students drop constraint if exists students_food_preference_check;
alter table public.students add constraint students_food_preference_check check (food_preference is null or food_preference in ('veg','non-veg'));

create unique index if not exists students_foodpass_code_unique on public.students(foodpass_code) where foodpass_code is not null;

-- IMPORTANT: qr_token is intentionally left as UUID. Never assign text/hex to it.
-- The old approval function generated text, which caused the reported error.

-- Replace registration functions so the frontend's 5 parameters are accepted.
drop function if exists public.register_student(text,text,integer,text,text);
drop function if exists public.register_student(text,text,integer,text);
drop function if exists public.register_student(text,text,integer);
create function public.register_student(p_full_name text,p_usn text,p_year integer,p_section text,p_food_preference text)
returns json language plpgsql security definer set search_path=public,extensions as $$
declare clean_usn text:=upper(trim(p_usn)); clean_section text:=upper(trim(p_section)); clean_food text:=lower(trim(p_food_preference)); v_id uuid;
begin
 if trim(coalesce(p_full_name,''))='' then return json_build_object('success',false,'message','Name is required.'); end if;
 if clean_usn !~ '^[0-9]{1,2}SF[0-9]{2}CS[0-9]{3}$' then return json_build_object('success',false,'message','Invalid CSE USN. Example: 4SF24CS181.'); end if;
 if p_year not between 1 and 4 then return json_build_object('success',false,'message','Select a valid year.'); end if;
 if clean_section not in ('A','B','C','D') then return json_build_object('success',false,'message','Select section A, B, C or D.'); end if;
 if clean_food not in ('veg','non-veg') then return json_build_object('success',false,'message','Select Veg or Non-Veg.'); end if;
 if exists(select 1 from public.students where upper(usn)=clean_usn) then return json_build_object('success',false,'message','This USN is already registered.'); end if;
 insert into public.students(full_name,usn,year,section,person_type,food_preference,status,redeemed) values(trim(p_full_name),clean_usn,p_year,clean_section,'student',clean_food,'pending',false) returning id into v_id;
 return json_build_object('success',true,'message','Registration successful.','id',v_id);
exception when unique_violation then return json_build_object('success',false,'message','This USN is already registered.');
end $$;
grant execute on function public.register_student(text,text,integer,text,text) to anon,authenticated;

-- Status lookup includes food preference.
drop function if exists public.get_student_status(text);
create function public.get_student_status(p_usn text)
returns json language plpgsql security definer set search_path=public,extensions as $$
declare v public.students;
begin
 select * into v from public.students where upper(usn)=upper(trim(p_usn)) and person_type='student' limit 1;
 if v.id is null then return json_build_object('success',false,'message','No registration found for this USN.'); end if;
 return json_build_object('success',true,'status',v.status,'name',v.full_name,'usn',v.usn,'year',v.year,'section',v.section,'food_preference',v.food_preference,'qr_token',v.qr_token,'redeemed',v.redeemed,'message',case when v.redeemed then 'This FoodPass has already been used.' when v.status='approved' then 'Your FoodPass has been approved.' when v.status='rejected' then 'Your registration was not approved.' else 'Your registration is waiting for approval.' end);
end $$;
grant execute on function public.get_student_status(text) to anon,authenticated;

-- Admin list includes food preference.
drop function if exists public.admin_get_students(text);
create function public.admin_get_students(p_token text)
returns json language plpgsql security definer set search_path=public,extensions as $$
declare v_role text; v json;
begin
 select a.role into v_role from public.staff_sessions s join public.staff_accounts a on a.id=s.staff_id where s.token_hash=encode(digest(p_token,'sha256'),'hex') and s.expires_at>now() and a.active=true limit 1;
 if v_role<>'admin' then return '[]'::json; end if;
 select coalesce(json_agg(x order by x.person_type,x.year nulls last,x.section nulls last,x.full_name),'[]'::json) into v from (select id,full_name,usn,year,section,person_type,food_preference,status,redeemed,qr_token,approved_at,created_at from public.students) x;
 return v;
end $$;
grant execute on function public.admin_get_students(text) to anon,authenticated;

-- Admin add person, with student food preference and teacher-safe NULL year/section/USN.
drop function if exists public.admin_add_person(text,text,text,text,integer,text,text);
create function public.admin_add_person(p_token text,p_person_type text,p_full_name text,p_usn text default null,p_year integer default null,p_section text default null,p_food_preference text default null,p_status text default 'pending')
returns json language plpgsql security definer set search_path=public,extensions as $$
declare role_name text; typ text:=lower(trim(p_person_type)); u text:=nullif(upper(trim(coalesce(p_usn,''))), ''); sec text:=nullif(upper(trim(coalesce(p_section,''))), ''); food text:=nullif(lower(trim(coalesce(p_food_preference,''))), ''); idv uuid;
begin
 select a.role into role_name from public.staff_sessions s join public.staff_accounts a on a.id=s.staff_id where s.token_hash=encode(digest(p_token,'sha256'),'hex') and s.expires_at>now() and a.active=true limit 1;
 if role_name<>'admin' then return json_build_object('success',false,'message','Admin authorization required.'); end if;
 if trim(coalesce(p_full_name,''))='' then return json_build_object('success',false,'message','Name is required.'); end if;
 if typ not in ('student','teacher') then return json_build_object('success',false,'message','Invalid user type.'); end if;
 if typ='student' then
   if u is null or u !~ '^[0-9]{1,2}SF[0-9]{2}CS[0-9]{3}$' then return json_build_object('success',false,'message','Invalid CSE USN.'); end if;
   if p_year not between 1 and 4 or sec not in ('A','B','C','D') then return json_build_object('success',false,'message','Student requires year and section A-D.'); end if;
   if food not in ('veg','non-veg') then return json_build_object('success',false,'message','Select Veg or Non-Veg.'); end if;
 else u:=null; p_year:=null; sec:=null; food:=null; end if;
 if u is not null and exists(select 1 from public.students where upper(usn)=u) then return json_build_object('success',false,'message','This USN is already registered.'); end if;
 insert into public.students(full_name,usn,year,section,person_type,food_preference,status,redeemed) values(trim(p_full_name),u,p_year,sec,typ,food,coalesce(p_status,'pending'),false) returning id into idv;
 return json_build_object('success',true,'message',initcap(typ)||' added.','id',idv);
end $$;
grant execute on function public.admin_add_person(text,text,text,text,integer,text,text,text) to anon,authenticated;

-- Approval: UUID-safe. This is the direct fix for "qr_token is uuid but expression is text".
drop function if exists public.admin_approve_student(text,uuid);
create function public.admin_approve_student(p_token text,p_student_id uuid)
returns json language plpgsql security definer set search_path=public,extensions as $$
declare role_name text; nm text; new_qr uuid;
begin
 select a.role into role_name from public.staff_sessions s join public.staff_accounts a on a.id=s.staff_id where s.token_hash=encode(digest(p_token,'sha256'),'hex') and s.expires_at>now() and a.active=true limit 1;
 if role_name<>'admin' then return json_build_object('success',false,'message','Admin authorization required.'); end if;
 select full_name into nm from public.students where id=p_student_id;
 if nm is null then return json_build_object('success',false,'message','Entry not found.'); end if;
 new_qr:=gen_random_uuid();
 update public.students set status='approved',qr_token=new_qr,approved_at=now() where id=p_student_id;
 return json_build_object('success',true,'message','Approved.','qr_token',new_qr::text);
end $$;
grant execute on function public.admin_approve_student(text,uuid) to anon,authenticated;

-- Scanner redemption: safely validate UUID before comparing with uuid column.
drop function if exists public.redeem_qr(text,text);
create function public.redeem_qr(p_token text,p_qr_token text)
returns json language plpgsql security definer set search_path=public,extensions as $$
declare role_name text; v public.students; q uuid;
begin
 select a.role into role_name from public.staff_sessions s join public.staff_accounts a on a.id=s.staff_id where s.token_hash=encode(digest(p_token,'sha256'),'hex') and s.expires_at>now() and a.active=true limit 1;
 if role_name not in ('scanner','admin') then return json_build_object('result','UNAUTHORIZED','message','Scanner authorization required.'); end if;
 if trim(coalesce(p_qr_token,'')) !~* '^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$' then return json_build_object('result','INVALID','message','This QR code is not a valid FoodPass.'); end if;
 q:=trim(p_qr_token)::uuid;
 select * into v from public.students where qr_token=q limit 1;
 if v.id is null then return json_build_object('result','INVALID','message','This QR code is not a valid FoodPass.'); end if;
 if v.status<>'approved' then return json_build_object('result','NOT_APPROVED','message','This FoodPass has not been approved.','name',v.full_name,'usn',coalesce(v.usn,'—'),'year',v.year,'section',v.section,'person_type',v.person_type,'food_preference',v.food_preference); end if;
 if v.redeemed then return json_build_object('result','ALREADY_USED','message','This FoodPass has already been redeemed.','name',v.full_name,'usn',coalesce(v.usn,'—'),'year',v.year,'section',v.section,'person_type',v.person_type,'food_preference',v.food_preference); end if;
 update public.students set redeemed=true,redeemed_at=now() where id=v.id and redeemed=false;
 if not found then return json_build_object('result','ALREADY_USED','message','This FoodPass has already been redeemed.','name',v.full_name,'usn',coalesce(v.usn,'—'),'year',v.year,'section',v.section,'person_type',v.person_type,'food_preference',v.food_preference); end if;
 return json_build_object('result','VALID','message','Food may be served.','name',v.full_name,'usn',coalesce(v.usn,'—'),'year',v.year,'section',v.section,'person_type',v.person_type,'food_preference',v.food_preference);
end $$;
grant execute on function public.redeem_qr(text,text) to anon,authenticated;

-- Fix scanner log lookup against UUID qr_token.
drop function if exists public.scanner_log_scan(text,text,text);
create function public.scanner_log_scan(p_token text,p_qr_token text,p_result text)
returns json language plpgsql security definer set search_path=public,extensions as $$
declare username text; v public.students; q uuid;
begin
 select a.username into username from public.staff_sessions s join public.staff_accounts a on a.id=s.staff_id where s.token_hash=encode(digest(p_token,'sha256'),'hex') and s.expires_at>now() and a.active=true and a.role in ('scanner','admin') limit 1;
 if username is null then return json_build_object('success',false,'message','Scanner authorization required.'); end if;
 if trim(coalesce(p_qr_token,'')) ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$' then q:=trim(p_qr_token)::uuid; select * into v from public.students where qr_token=q limit 1; end if;
 insert into public.scanner_logs(scanner_username,student_id,usn,full_name,year,result,qr_token) values(username,v.id,v.usn,v.full_name,v.year,upper(coalesce(p_result,'INVALID')),case when v.id is null then null else p_qr_token end);
 return json_build_object('success',true);
end $$;
grant execute on function public.scanner_log_scan(text,text,text) to anon,authenticated;

-- Ensure scanner logs can display food/section by joining students in the existing function if desired; no schema change required.

-- Staff sessions/auth (included here so this migration is self-contained).
create table if not exists public.staff_sessions(
 id uuid primary key default gen_random_uuid(),
 staff_id uuid not null references public.staff_accounts(id) on delete cascade,
 token_hash text not null unique,
 expires_at timestamptz not null,
 created_at timestamptz not null default now()
);

create or replace function public.staff_login(p_username text,p_password text)
returns json language plpgsql security definer set search_path=public,extensions as $$
declare a public.staff_accounts; raw text; h text;
begin
 select * into a from public.staff_accounts where lower(username)=lower(trim(p_username)) and active=true limit 1;
 if a.id is null or a.password_hash <> crypt(p_password,a.password_hash) then return json_build_object('success',false,'message','Invalid username or password.'); end if;
 raw:=encode(gen_random_bytes(32),'hex'); h:=encode(digest(raw,'sha256'),'hex');
 insert into public.staff_sessions(staff_id,token_hash,expires_at) values(a.id,h,now()+interval '12 hours');
 return json_build_object('success',true,'token',raw,'username',a.username,'role',a.role);
end $$;
grant execute on function public.staff_login(text,text) to anon,authenticated;

create or replace function public.staff_logout(p_token text)
returns json language plpgsql security definer set search_path=public,extensions as $$
begin delete from public.staff_sessions where token_hash=encode(digest(p_token,'sha256'),'hex'); return json_build_object('success',true); end $$;
grant execute on function public.staff_logout(text) to anon,authenticated;

create or replace function public.check_staff_session(p_token text)
returns json language plpgsql security definer set search_path=public,extensions as $$
declare a public.staff_accounts;
begin
 select sa.* into a from public.staff_sessions ss join public.staff_accounts sa on sa.id=ss.staff_id where ss.token_hash=encode(digest(p_token,'sha256'),'hex') and ss.expires_at>now() and sa.active=true limit 1;
 if a.id is null then return json_build_object('success',false,'message','Session expired or invalid.'); end if;
 return json_build_object('success',true,'username',a.username,'role',a.role);
end $$;
grant execute on function public.check_staff_session(text) to anon,authenticated;

-- Teacher FoodPass code + direct teacher status lookup.
create or replace function public.admin_add_person(p_token text,p_person_type text,p_full_name text,p_usn text default null,p_year integer default null,p_section text default null,p_food_preference text default null,p_status text default 'pending')
returns json language plpgsql security definer set search_path=public,extensions as $$
declare role_name text; typ text:=lower(trim(p_person_type)); u text:=nullif(upper(trim(coalesce(p_usn,''))), ''); sec text:=nullif(upper(trim(coalesce(p_section,''))), ''); food text:=nullif(lower(trim(coalesce(p_food_preference,''))), ''); idv uuid; code text;
begin
 select a.role into role_name from public.staff_sessions s join public.staff_accounts a on a.id=s.staff_id where s.token_hash=encode(digest(p_token,'sha256'),'hex') and s.expires_at>now() and a.active=true limit 1;
 if role_name<>'admin' then return json_build_object('success',false,'message','Admin authorization required.'); end if;
 if trim(coalesce(p_full_name,''))='' then return json_build_object('success',false,'message','Name is required.'); end if;
 if typ not in ('student','teacher') then return json_build_object('success',false,'message','Invalid user type.'); end if;
 if typ='student' then
   if u is null or u !~ '^[0-9]{1,2}SF[0-9]{2}CS[0-9]{3}$' then return json_build_object('success',false,'message','Invalid CSE USN.'); end if;
   if p_year not between 1 and 4 or sec not in ('A','B','C','D') then return json_build_object('success',false,'message','Student requires year and section A-D.'); end if;
   if food not in ('veg','non-veg') then return json_build_object('success',false,'message','Select Veg or Non-Veg.'); end if;
 else u:=null; p_year:=null; sec:=null; food:=null; code:='TCH-'||upper(substr(encode(gen_random_bytes(5),'hex'),1,8)); end if;
 if u is not null and exists(select 1 from public.students where upper(usn)=u) then return json_build_object('success',false,'message','This USN is already registered.'); end if;
 insert into public.students(full_name,usn,year,section,person_type,food_preference,foodpass_code,status,redeemed) values(trim(p_full_name),u,p_year,sec,typ,food,code,coalesce(p_status,'pending'),false) returning id into idv;
 return json_build_object('success',true,'message',initcap(typ)||' added.','id',idv,'foodpass_code',code);
end $$;
grant execute on function public.admin_add_person(text,text,text,text,integer,text,text,text) to anon,authenticated;

create or replace function public.get_teacher_status(p_code text)
returns json language plpgsql security definer set search_path=public,extensions as $$
declare v public.students;
begin
 select * into v from public.students where upper(foodpass_code)=upper(trim(p_code)) and person_type='teacher' limit 1;
 if v.id is null then return json_build_object('success',false,'message','Teacher FoodPass code not found.'); end if;
 return json_build_object('success',true,'name',v.full_name,'foodpass_code',v.foodpass_code,'status',v.status,'qr_token',v.qr_token,'redeemed',v.redeemed);
end $$;
grant execute on function public.get_teacher_status(text) to anon,authenticated;
