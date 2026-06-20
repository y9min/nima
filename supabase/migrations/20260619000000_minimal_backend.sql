create extension if not exists pgcrypto;

create table if not exists public.android_waitlist (
  email text primary key,
  created_at timestamptz not null default now(),
  constraint android_waitlist_email_format check (
    email = lower(btrim(email))
    and email ~ '^[a-z0-9.!#$%&''*+/=?^_`{|}~-]+@[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?(?:\.[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?)+$'
  )
);

create or replace function public.normalize_android_waitlist_email()
returns trigger
language plpgsql
as $$
begin
  new.email = lower(btrim(new.email));
  return new;
end;
$$;

drop trigger if exists normalize_android_waitlist_email_before_insert on public.android_waitlist;
create trigger normalize_android_waitlist_email_before_insert
before insert on public.android_waitlist
for each row
execute function public.normalize_android_waitlist_email();

alter table public.android_waitlist enable row level security;

revoke all on table public.android_waitlist from anon, authenticated;
grant insert on table public.android_waitlist to anon, authenticated;

drop policy if exists "public can join android waitlist" on public.android_waitlist;
create policy "public can join android waitlist"
on public.android_waitlist
for insert
to anon, authenticated
with check (true);

create table if not exists public.subscription_cancellation_feedback (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  reason text not null,
  details text,
  created_at timestamptz not null default now(),
  constraint subscription_cancellation_feedback_reason check (
    reason in (
      'too_expensive',
      'not_using',
      'did_not_help',
      'technical_issue',
      'missing_feature',
      'privacy_concern',
      'temporary_pause',
      'other'
    )
  ),
  constraint subscription_cancellation_feedback_details_length check (
    details is null or char_length(details) <= 500
  )
);

alter table public.subscription_cancellation_feedback enable row level security;

revoke all on table public.subscription_cancellation_feedback from anon, authenticated;
grant insert on table public.subscription_cancellation_feedback to authenticated;

drop policy if exists "users can insert own cancellation feedback" on public.subscription_cancellation_feedback;
create policy "users can insert own cancellation feedback"
on public.subscription_cancellation_feedback
for insert
to authenticated
with check (user_id = auth.uid());
