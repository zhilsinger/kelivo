-- =============================================================================
-- Kelivo Supabase Sync — Sync Conflicts Table v1
-- Run this in your Supabase project SQL Editor (https://app.supabase.com)
-- Depends on: pgcrypto extension, public.app_user_id() function (from migration 001)
-- =============================================================================

create table if not exists public.sync_conflicts (
  id              uuid primary key default gen_random_uuid(),
  user_id         text not null,
  thread_id       text not null references public.threads(id) on delete cascade,
  conflict_type   text not null check (conflict_type in (
    'local_deleted_remote_present','remote_deleted_local_present',
    'both_updated','message_divergence','tombstone_mismatch'
  )),
  local_state     jsonb not null default '{}'::jsonb,
  remote_state    jsonb not null default '{}'::jsonb,
  detected_at     timestamptz not null default now(),
  resolved        boolean not null default false,
  resolution      text check (resolution in ('keep_local','take_remote','merge','dismiss')),
  resolved_at     timestamptz,
  notes           text
);

create index if not exists idx_sync_conflicts_user on public.sync_conflicts(user_id);
create index if not exists idx_sync_conflicts_unresolved on public.sync_conflicts(resolved) where resolved = false;

-- RLS: sync_conflicts
alter table public.sync_conflicts enable row level security;

create policy "conflicts_select_own" on public.sync_conflicts
  for select using (user_id = public.app_user_id());

create policy "conflicts_insert_own" on public.sync_conflicts
  for insert with check (user_id = public.app_user_id());

create policy "conflicts_update_own" on public.sync_conflicts
  for update using (user_id = public.app_user_id());

create policy "conflicts_delete_own" on public.sync_conflicts
  for delete using (user_id = public.app_user_id());