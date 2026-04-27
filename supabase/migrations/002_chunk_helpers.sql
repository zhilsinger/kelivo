-- =============================================================================
-- PR4: Chunk Indexing Helpers
-- Run AFTER the message_chunks table additions in 001_base_schema.sql
-- =============================================================================

-- RPC: upsert_message_chunk
-- Used by the SupabaseIndexService to insert/update chunks during indexing.
-- Uses ON CONFLICT (message_id, chunk_index) for idempotent upserts.
create or replace function public.upsert_message_chunk(
  p_user_id                text,
  p_thread_id              text,
  p_message_id             text,
  p_chunk_index            integer,
  p_chunk_text             text,
  p_chunk_hash             text,
  p_token_estimate         integer,
  p_source_thread_title    text,
  p_source_message_role    text,
  p_source_created_at      timestamptz,
  p_source_position        integer,
  p_chunker_version        text
)
returns void
language plpgsql
as $$
begin
  insert into public.message_chunks (
    user_id, thread_id, message_id, chunk_index,
    chunk_text, chunk_hash, token_estimate,
    source_thread_title, source_message_role, source_created_at, source_position,
    chunker_version, indexed_at, needs_reindex
  ) values (
    p_user_id, p_thread_id, p_message_id, p_chunk_index,
    p_chunk_text, p_chunk_hash, p_token_estimate,
    p_source_thread_title, p_source_message_role, p_source_created_at, p_source_position,
    p_chunker_version, now(), false
  )
  on conflict (message_id, chunk_index) do update set
    chunk_text = excluded.chunk_text,
    chunk_hash = excluded.chunk_hash,
    token_estimate = excluded.token_estimate,
    source_thread_title = excluded.source_thread_title,
    source_message_role = excluded.source_message_role,
    source_created_at = excluded.source_created_at,
    source_position = excluded.source_position,
    chunker_version = excluded.chunker_version,
    indexed_at = now(),
    needs_reindex = false;
end;
$$;

-- RPC: check_chunk_hashes
-- Returns the subset of hashes that already exist (for dedup).
create or replace function public.check_chunk_hashes(
  p_hashes   text[],
  p_user_id  text
)
returns setof text
language sql
stable
as $$
  select chunk_hash
  from public.message_chunks
  where user_id = p_user_id
    and chunk_hash = any(p_hashes);
$$;