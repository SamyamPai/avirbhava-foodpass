-- CLOUDS FoodPass: secure admin delete feature
-- Run this once in Supabase SQL Editor after the existing FoodPass SQL.
--
-- Uses the existing staff_accounts + staff_sessions setup.
-- Only an active ADMIN session can delete a student.

create or replace function public.admin_delete_student(
  p_token text,
  p_student_id uuid
)
returns json
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_staff_id uuid;
  v_role text;
  v_student_usn text;
begin
  if p_token is null or length(trim(p_token)) = 0 then
    return json_build_object('success', false, 'message', 'Unauthorized.');
  end if;

  -- staff_sessions stores the SHA-256 token hash.
  select s.staff_id, a.role
    into v_staff_id, v_role
  from public.staff_sessions s
  join public.staff_accounts a on a.id = s.staff_id
  where s.token_hash = encode(digest(p_token, 'sha256'), 'hex')
    and s.expires_at > now()
    and a.active = true
  limit 1;

  if v_staff_id is null or v_role <> 'admin' then
    return json_build_object('success', false, 'message', 'Admin authorization required.');
  end if;

  select usn into v_student_usn
  from public.students
  where id = p_student_id;

  if v_student_usn is null then
    return json_build_object('success', false, 'message', 'Student entry not found.');
  end if;

  delete from public.students
  where id = p_student_id;

  return json_build_object(
    'success', true,
    'message', 'Student deleted.',
    'usn', v_student_usn
  );
end;
$$;

revoke all on function public.admin_delete_student(text, uuid) from public;
grant execute on function public.admin_delete_student(text, uuid) to anon, authenticated;
