-- Deploy the collection-free proxy and web app before applying this migration.
-- Export the legacy tables immediately before applying it if a short-lived
-- rollback backup is required.

do $$
declare
  scheduled_job record;
begin
  if to_regclass('cron.job') is null then
    return;
  end if;

  for scheduled_job in
    select jobid
    from cron.job
    where command ilike any (
      array[
        '%rollup_traffic_hourly%',
        '%rollup_traffic_daily%',
        '%cleanup_old_traffic%',
        '%recompute_all_rollups%'
      ]
    )
  loop
    perform cron.unschedule(scheduled_job.jobid);
  end loop;

  if exists (
    select 1
    from cron.job
    where command ilike any (
      array[
        '%rollup_traffic_hourly%',
        '%rollup_traffic_daily%',
        '%cleanup_old_traffic%',
        '%recompute_all_rollups%'
      ]
    )
  ) then
    raise exception 'legacy traffic analytics cron jobs are still scheduled';
  end if;
end;
$$;

do $$
declare
  legacy_routine record;
begin
  for legacy_routine in
    select p.oid::regprocedure as signature
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public'
      and p.proname = any (
        array[
          'rollup_traffic_hourly',
          'rollup_traffic_daily',
          'cleanup_old_traffic',
          'recompute_all_rollups',
          'execute_sql'
        ]
      )
  loop
    execute format('drop routine if exists %s cascade', legacy_routine.signature);
  end loop;
end;
$$;

drop table if exists public.llm_insights cascade;
drop table if exists public.traffic_summaries cascade;
drop table if exists public.traffic_events cascade;
drop table if exists public.cron_runs cascade;
drop table if exists public.vpn_clients cascade;

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
