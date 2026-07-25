create table if not exists public.runtime_feature_flags (
  key text primary key,
  enabled boolean not null default false,
  rollout_percentage smallint not null default 0,
  minimum_build integer not null default 0,
  updated_at timestamptz not null default now(),
  constraint runtime_feature_flags_rollout_percentage_range
    check (rollout_percentage between 0 and 100),
  constraint runtime_feature_flags_minimum_build_nonnegative
    check (minimum_build >= 0)
);

alter table public.runtime_feature_flags enable row level security;

revoke all on table public.runtime_feature_flags from anon, authenticated;
grant select on table public.runtime_feature_flags to anon, authenticated;

drop policy if exists "clients can read runtime feature flags" on public.runtime_feature_flags;
create policy "clients can read runtime feature flags"
on public.runtime_feature_flags
for select
to anon, authenticated
using (true);

insert into public.runtime_feature_flags (
  key,
  enabled,
  rollout_percentage,
  minimum_build
)
values (
  'ios_vpn_on_demand_recovery',
  false,
  0,
  10
)
on conflict (key) do nothing;
