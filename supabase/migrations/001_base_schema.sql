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

-- =============================================================================
-- MESSAGE CHUNKS (PR4 — Full-text keyword search, no embeddings yet)
-- =============================================================================
create table if not exists public.message_chunks (
  id              uuid primary key default gen_random_uuid(),
  user_id         text not null,
  thread_id       text not null references public.threads(id) on delete cascade,
  message_id      text references public.messages(id) on delete cascade,
  chunk_index     integer not null,
  chunk_text      text not null,
  chunk_hash      text not null,
  token_estimate  integer,
  -- Source metadata for AI context references (not in chunk_text)
  source_thread_title   text,
  source_message_role   text,
  source_created_at     timestamptz,
  source_position       integer,
  -- Full-text search vector
  search_vector   tsvector,
  -- Versioning (PREPARED for PR5 — no embeddings yet)
  embedding_model      text,
  embedding_dimensions integer,
  chunker_version      text default 'kelivo_chunker_v1',
  indexed_at           timestamptz,
  needs_reindex        boolean default false,
  -- Metadata
  created_at      timestamptz default now(),
  -- Memory scoring (PREPARED for PR7 — defaults for now)
  memory_score    integer default 1,
  memory_type     text,
  pinned          boolean default false,
  reviewed        boolean default false,
  -- Access tracking (PREPARED for PR7)
  last_accessed_at  timestamptz,
  access_count      integer default 0,
  decay_after_days  integer,
  stale             boolean default false,
  -- Unique constraint
  unique(message_id, chunk_index)
);

-- Indexes
create index if not exists idx_message_chunks_thread_id on public.message_chunks(thread_id);
create index if not exists idx_message_chunks_user_id   on public.message_chunks(user_id);
create index if not exists idx_message_chunks_hash      on public.message_chunks(chunk_hash);

-- Full-text search index (GIN for tsvector)
create index if not exists idx_message_chunks_search
  on public.message_chunks
  using gin(search_vector);

-- Trigger: auto-populate search_vector from chunk_text on INSERT or UPDATE
create or replace function public.message_chunks_search_update()
returns trigger
language plpgsql
as $$
begin
  new.search_vector := to_tsvector('english', coalesce(new.chunk_text, ''));
  return new;
end;
$$;

drop trigger if exists trg_message_chunks_search on public.message_chunks;
create trigger trg_message_chunks_search
  before insert or update of chunk_text
  on public.message_chunks
  for each row
  execute function public.message_chunks_search_update();

-- =============================================================================
-- RPC: search_message_chunks_fts(query, target_user_id, match_limit)
-- Exact keyword / full-text search. No embeddings. No vector math.
-- Returns chunks ranked by ts_rank, with source metadata.
-- =============================================================================
create or replace function public.search_message_chunks_fts(
  search_query   text,
  target_user_id text,
  match_limit    integer default 20
)
returns table (
  chunk_id              uuid,
  thread_id             text,
  message_id            text,
  chunk_index           integer,
  chunk_text            text,
  source_thread_title   text,
  source_message_role   text,
  source_created_at     timestamptz,
  rank                  real
)
language sql
stable
as $$
  select
    mc.id,
    mc.thread_id,
    mc.message_id,
    mc.chunk_index,
    mc.chunk_text,
    mc.source_thread_title,
    mc.source_message_role,
    mc.source_created_at,
    ts_rank(mc.search_vector, plainto_tsquery('english', search_query)) as rank
  from public.message_chunks mc
  where mc.user_id = target_user_id
    and mc.search_vector @@ plainto_tsquery('english', search_query)
  order by rank desc
  limit match_limit;
$$;

-- RLS: message_chunks
alter table public.message_chunks enable row level security;

create policy "message_chunks_select_own" on public.message_chunks
  for select using (user_id = public.app_user_id());

create policy "message_chunks_insert_own" on public.message_chunks
  for insert with check (user_id = public.app_user_id());

create policy "message_chunks_update_own" on public.message_chunks
  for update using (user_id = public.app_user_id());

create policy "message_chunks_delete_own" on public.message_chunks
  for delete using (user_id = public.app_user_id());