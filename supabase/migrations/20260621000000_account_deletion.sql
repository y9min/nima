create or replace function public.delete_account_linked_rows(target_user_id uuid)
returns void
language plpgsql
security definer
set search_path = public, auth
as $$
begin
  if to_regclass('public.blocker_state') is not null then
    delete from public.blocker_state where user_id = target_user_id;
  end if;

  if to_regclass('public.subscription_cancellation_feedback') is not null then
    delete from public.subscription_cancellation_feedback where user_id = target_user_id;
  end if;

  if to_regclass('public.profiles') is not null then
    delete from public.profiles where id = target_user_id;
  end if;
end;
$$;

revoke all on function public.delete_account_linked_rows(uuid) from public, anon, authenticated;
grant execute on function public.delete_account_linked_rows(uuid) to service_role;
