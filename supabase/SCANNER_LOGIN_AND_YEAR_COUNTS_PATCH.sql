-- CLOUDS FoodPass patch: scanner login + normalized staff roles
-- Run this ONCE in Supabase SQL Editor AFTER MASTER_REPAIR.sql.

create extension if not exists pgcrypto;

-- Normalize existing staff roles so Scanner/scanner/ scanner all behave identically.
update public.staff_accounts
set role = lower(trim(role))
where role is not null;

-- Make staff login return a normalized role and create a fresh session.
drop function if exists public.staff_login(text,text);
create function public.staff_login(p_username text, p_password text)
returns json
language plpgsql security definer
set search_path = public, extensions
as $$
declare
  a public.staff_accounts;
  raw text;
  h text;
  normalized_role text;
begin
  select * into a
  from public.staff_accounts
  where lower(trim(username)) = lower(trim(coalesce(p_username,'')))
    and active = true
  limit 1;

  if a.id is null then
    return json_build_object('success',false,'message','Invalid username or password.');
  end if;

  if a.password_hash <> crypt(coalesce(p_password,''), a.password_hash)
     and a.password_hash <> coalesce(p_password,'') then
    return json_build_object('success',false,'message','Invalid username or password.');
  end if;

  -- Upgrade legacy plain-text event PINs after a successful login.
  if a.password_hash = coalesce(p_password,'') then
    update public.staff_accounts
    set password_hash = crypt(p_password, gen_salt('bf'))
    where id = a.id;
  end if;

  normalized_role := lower(trim(a.role));

  if normalized_role not in ('admin','scanner') then
    return json_build_object(
      'success',false,
      'message','This staff account has an invalid role. Set its role to admin or scanner.'
    );
  end if;

  raw := encode(gen_random_bytes(32),'hex');
  h := encode(digest(raw,'sha256'),'hex');

  insert into public.staff_sessions(staff_id,token_hash,expires_at)
  values(a.id,h,now() + interval '12 hours');

  return json_build_object(
    'success',true,
    'token',raw,
    'username',a.username,
    'role',normalized_role
  );
end;
$$;

grant execute on function public.staff_login(text,text) to anon, authenticated;

-- Normalize the role used by all staff authorization checks.
drop function if exists public._clouds_staff_role(text);
create function public._clouds_staff_role(p_token text)
returns text
language sql
security definer
set search_path = public, extensions
as $$
  select lower(trim(a.role))
  from public.staff_sessions s
  join public.staff_accounts a on a.id=s.staff_id
  where s.token_hash=encode(digest(p_token,'sha256'),'hex')
    and s.expires_at>now()
    and a.active=true
  limit 1;
$$;

grant execute on function public._clouds_staff_role(text) to anon, authenticated;

-- Make scanner redemption accept normalized scanner/admin roles.
drop function if exists public.redeem_qr(text,text);
create function public.redeem_qr(p_token text, p_qr_token text)
returns json language plpgsql security definer
set search_path = public, extensions
as $$
declare
  role_name text;
  scanner_username text;
  v public.students;
  q uuid;
begin
  select lower(trim(a.role)), a.username
  into role_name, scanner_username
  from public.staff_sessions s
  join public.staff_accounts a on a.id=s.staff_id
  where s.token_hash=encode(digest(p_token,'sha256'),'hex')
    and s.expires_at>now()
    and a.active=true
  limit 1;

  if role_name not in ('scanner','admin') then
    return json_build_object('result','UNAUTHORIZED','message','Scanner session expired or unauthorized.');
  end if;

  if trim(coalesce(p_qr_token,'')) !~* '^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$' then
    insert into public.scanner_logs(scanner_username,result,qr_token)
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
    return json_build_object('result','NOT_APPROVED','message','This FoodPass has not been approved.','name',v.full_name,'usn',coalesce(v.usn,'—'),'year',v.year,'section',v.section,'person_type',v.person_type,'food_preference',v.food_preference);
  end if;

  if v.redeemed then
    insert into public.scanner_logs(scanner_username,student_id,usn,full_name,year,result,qr_token)
    values(scanner_username,v.id,v.usn,v.full_name,v.year,'ALREADY_USED',p_qr_token);
    return json_build_object('result','ALREADY_USED','message','This FoodPass has already been redeemed. Do not serve again.','name',v.full_name,'usn',coalesce(v.usn,'—'),'year',v.year,'section',v.section,'person_type',v.person_type,'food_preference',v.food_preference);
  end if;

  update public.students
  set redeemed=true, redeemed_at=now(), updated_at=now()
  where id=v.id and redeemed=false;

  if not found then
    insert into public.scanner_logs(scanner_username,student_id,usn,full_name,year,result,qr_token)
    values(scanner_username,v.id,v.usn,v.full_name,v.year,'ALREADY_USED',p_qr_token);
    return json_build_object('result','ALREADY_USED','message','This FoodPass has already been redeemed. Do not serve again.','name',v.full_name,'usn',coalesce(v.usn,'—'),'year',v.year,'section',v.section,'person_type',v.person_type,'food_preference',v.food_preference);
  end if;

  insert into public.scanner_logs(scanner_username,student_id,usn,full_name,year,result,qr_token)
  values(scanner_username,v.id,v.usn,v.full_name,v.year,'VALID',p_qr_token);

  return json_build_object('result','VALID','message','FoodPass verified successfully. Food may be served.','name',v.full_name,'usn',coalesce(v.usn,'—'),'year',v.year,'section',v.section,'person_type',v.person_type,'food_preference',v.food_preference);
end;
$$;

grant execute on function public.redeem_qr(text,text) to anon, authenticated;

-- Scanner logs authorization also uses normalized roles.
drop function if exists public.scanner_get_logs(text,integer);
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
    and lower(trim(a.role)) in ('scanner','admin')
  limit 1;

  if v_username is null then return '[]'::json; end if;

  select coalesce(json_agg(x order by x.scanned_at desc),'[]'::json)
  into result
  from (
    select l.scanned_at,l.scanner_username,l.usn,l.full_name,l.year,l.result,
           s.section,s.food_preference,s.person_type
    from public.scanner_logs l
    left join public.students s on s.id=l.student_id
    order by l.scanned_at desc
    limit greatest(1,least(coalesce(p_limit,40),100))
  ) x;

  return result;
end;
$$;

grant execute on function public.scanner_get_logs(text,integer) to anon, authenticated;

notify pgrst, 'reload schema';

-- Optional diagnostic: run separately if scanner still cannot log in.
-- SELECT id, username, role, active FROM public.staff_accounts ORDER BY username;
