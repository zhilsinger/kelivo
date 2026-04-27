-- =============================================================================
-- Kelivo Supabase Memory System — Base Schema v1
-- Run this in your Supabase project SQL Editor (https://app.supabase.com)
-- Requires: pgcrypto extension (for gen_random_uuid())
-- =============================================================================

-- Enable required extensions
create extension if not exists "pgcrypto" with schema extensions;
create extension if not exists "pg_trgm" with schema extensions;
-- pgvector will be added in a later migration when embeddings are introduced

-- =============================================================================
-- Helper: function to extract x-user-id header for RLS policies
-- The app sends this header so RLS can scope rows to the device/user.
-- =============================================================================
create or replace function public.app_user_id()
returns text
language sql
stable
as $$
  select coalesce(
    current_setting('request.headers', true)::json->>'x-user-id',
    ''
  );
$$;

-- =============================================================================
-- THREADS
-- Mirrors local Kelivo conversations.
-- =============================================================================
create table if not exists public.threads (
  id              text primary key,
  user_id         text not null,
  title           text not null default '',
  source          text not null default 'kelivo',
  model_name      text,
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now(),
  synced_at       timestamptz,
  deleted_at      timestamptz,
  allow_ai_memory boolean not null default true,
  privacy_level   text not null default 'normal'
    check (privacy_level in ('normal', 'private', 'excluded', 'encrypted_only')),
  raw_metadata    jsonb not null default '{}'::jsonb
);

-- RLS: threads
ALTER TABLE public.threads ENABLE ROW LEVEL SECURITY;

CREATE POLICY "threads_select_own" ON public.threads
  FOR SELECT USING (user_id = public.app_user_id());

CREATE POLICY "threads_insert_own" ON public.threads
  FOR INSERT WITH CHECK (user_id = public.app_user_id());

CREATE POLICY "threads_update_own" ON public.threads
  FOR UPDATE USING (user_id = public.app_user_id());

CREATE POLICY "threads_delete_own" ON public.threads
  FOR DELETE USING (user_id = public.app_user_id());

-- =============================================================================
-- MESSAGES
-- Individual messages within a thread.  CASCADE delete when thread is removed.
-- =============================================================================
create table if not exists public.messages (
  id              text primary key,
  user_id         text not null,
  thread_id       text not null references public.threads(id) on delete cascade,
  role            text not null check (role in ('user', 'assistant', 'system', 'tool')),
  content         text not null default '',
  content_hash    text,
  model_id        text,
  provider_id     text,
  total_tokens    integer,
  created_at      timestamptz not null default now(),
  raw_metadata    jsonb not null default '{}'::jsonb
);

-- Index for fast per-thread message fetches
create index if not exists idx_messages_thread_id on public.messages(thread_id);
create index if not exists idx_messages_user_id   on public.messages(user_id);

-- RLS: messages
ALTER TABLE public.messages ENABLE ROW LEVEL SECURITY;

CREATE POLICY "messages_select_own" ON public.messages
  FOR SELECT USING (user_id = public.app_user_id());

CREATE POLICY "messages_insert_own" ON public.messages
  FOR INSERT WITH CHECK (user_id = public.app_user_id());

CREATE POLICY "messages_update_own" ON public.messages
  FOR UPDATE USING (user_id = public.app_user_id());

CREATE POLICY "messages_delete_own" ON public.messages
  FOR DELETE USING (user_id = public.app_user_id());

-- =============================================================================
-- SYNC MANIFEST
-- Tracks what has been synced so we avoid full re-sync every time.
-- =============================================================================
create table if not exists public.sync_manifest (
  id              uuid primary key default gen_random_uuid(),
  user_id         text not null,
  entity_type     text not null check (entity_type in ('thread', 'message')),
  entity_id       text not null,
  content_hash    text not null,
  last_synced_at  timestamptz not null default now(),
  sync_status     text not null default 'synced'
    check (sync_status in ('synced', 'failed', 'retrying', 'conflict')),
  error_message   text,
  unique(user_id, entity_type, entity_id)
);

create index if not exists idx_sync_manifest_user on public.sync_manifest(user_id);
create index if not exists idx_sync_manifest_status on public.sync_manifest(sync_status);

-- RLS: sync_manifest
ALTER TABLE public.sync_manifest ENABLE ROW LEVEL SECURITY;

CREATE POLICY "sync_manifest_select_own" ON public.sync_manifest
  FOR SELECT USING (user_id = public.app_user_id());

CREATE POLICY "sync_manifest_insert_own" ON public.sync_manifest
  FOR INSERT WITH CHECK (user_id = public.app_user_id());

CREATE POLICY "sync_manifest_update_own" ON public.sync_manifest
  FOR UPDATE USING (user_id = public.app_user_id());

CREATE POLICY "sync_manifest_delete_own" ON public.sync_manifest
  FOR DELETE USING (user_id = public.app_user_id());

-- =============================================================================
-- BACKUP MANIFESTS
-- Tracks raw backup files uploaded to Supabase Storage.
-- =============================================================================
create table if not exists public.backup_manifests (
  id              uuid primary key default gen_random_uuid(),
  user_id         text not null,
  storage_path    text not null,
  backup_type     text not null default 'full',
  app_version     text,
  schema_version  text,
  size_bytes      bigint,
  sha256_hash     text,
  compressed      boolean not null default true,
  encrypted       boolean not null default false,
  created_at      timestamptz not null default now(),
  completed_at    timestamptz,
  status          text not null default 'pending'
    check (status in ('pending', 'uploading', 'completed', 'failed', 'corrupted')),
  error_message   text
);

create index if not exists idx_backup_manifests_user on public.backup_manifests(user_id);

-- RLS: backup_manifests
ALTER TABLE public.backup_manifests ENABLE ROW LEVEL SECURITY;

CREATE POLICY "backup_manifests_select_own" ON public.backup_manifests
  FOR SELECT USING (user_id = public.app_user_id());

CREATE POLICY "backup_manifests_insert_own" ON public.backup_manifests
  FOR INSERT WITH CHECK (user_id = public.app_user_id());

CREATE POLICY "backup_manifests_update_own" ON public.backup_manifests
  FOR UPDATE USING (user_id = public.app_user_id());

CREATE POLICY "backup_manifests_delete_own" ON public.backup_manifests
  FOR DELETE USING (user_id = public.app_user_id());

-- =============================================================================
-- STORAGE BUCKET (raw backups + attachments)
-- =============================================================================
-- Run this separately via Supabase dashboard or SQL:
-- insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
-- values ('kelivo-backups', 'kelivo-backups', false, 524288000, '{application/zip,application/gzip,application/json}');

-- Storage RLS: only own files
-- CREATE POLICY "storage_select_own" ON storage.objects
--   FOR SELECT USING (owner = public.app_user_id());
-- CREATE POLICY "storage_insert_own" ON storage.objects
--   FOR INSERT WITH CHECK (owner = public.app_user_id());
-- CREATE POLICY "storage_delete_own" ON storage.objects
--   FOR DELETE USING (owner = public.app_user_id());
