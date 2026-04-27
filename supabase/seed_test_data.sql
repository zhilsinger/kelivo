-- =============================================================================
-- Kelivo Memory Retrieval Test Fixture
-- 3 conversations, 12 messages across them.
-- Used to validate that keyword search + future vector search works.
--
-- Replace 'test-user-00000000-0000-0000-0000-000000000000' with your
-- actual device_user_id from Kelivo Settings.
-- =============================================================================

-- Helper: replace this with your actual user_id
\set uid 'test-user-00000000-0000-0000-0000-000000000000'

-- Clean test data if re-running
DELETE FROM public.sync_manifest   WHERE user_id = :'uid';
DELETE FROM public.messages        WHERE user_id = :'uid';
DELETE FROM public.threads         WHERE user_id = :'uid';

-- =============================================================================
-- Conversation 1: "Supabase backup setup"
-- =============================================================================
INSERT INTO public.threads (id, user_id, title, source, created_at, updated_at)
VALUES (
  'thread-supabase-001',
  :'uid',
  'Supabase backup setup',
  'kelivo',
  '2026-04-20T10:00:00Z',
  '2026-04-20T11:30:00Z'
);

INSERT INTO public.messages (id, user_id, thread_id, role, content, content_hash, created_at) VALUES
('msg-s001-01', :'uid', 'thread-supabase-001', 'user',
 'How do I add Supabase via this S3?',
 'a1b2c3d4e5',
 '2026-04-20T10:00:00Z'),
('msg-s001-02', :'uid', 'thread-supabase-001', 'assistant',
 'You can use the Supabase Storage S3 endpoint. The S3 config screen expects an endpoint, bucket, region, access key, and secret key. Supabase provides S3-compatible storage at https://<project>.supabase.co/storage/v1/s3.',
 'f6g7h8i9j0',
 '2026-04-20T10:01:00Z'),
('msg-s001-03', :'uid', 'thread-supabase-001', 'user',
 'So I see if I use a bucket it will just go against my 50 mb allowance...',
 'k1l2m3n4o5',
 '2026-04-20T10:05:00Z'),
('msg-s001-04', :'uid', 'thread-supabase-001', 'assistant',
 'Because that 50 MB is the max individual file upload, not total bucket size. The bucket can hold many files. Supabase Storage buckets are designed for organizing files and controlling file access models.',
 'p6q7r8s9t0',
 '2026-04-20T10:06:00Z');

-- =============================================================================
-- Conversation 2: "Flutter APK compile error"
-- =============================================================================
INSERT INTO public.threads (id, user_id, title, source, created_at, updated_at)
VALUES (
  'thread-flutter-002',
  :'uid',
  'Flutter APK compile error',
  'kelivo',
  '2026-04-25T14:00:00Z',
  '2026-04-25T15:45:00Z'
);

INSERT INTO public.messages (id, user_id, thread_id, role, content, content_hash, created_at) VALUES
('msg-f002-01', :'uid', 'thread-flutter-002', 'user',
 'flutter build apk fails with ndkVersion 27.0.12077973 not found',
 'u1v2w3x4y5',
 '2026-04-25T14:00:00Z'),
('msg-f002-02', :'uid', 'thread-flutter-002', 'assistant',
 'This is a known issue. You need to install NDK version 27.0.12077973 via Android Studio SDK Manager. Go to SDK Tools, check "Show Package Details", and select NDK 27.0.12077973.',
 'z6a7b8c9d0',
 '2026-04-25T14:02:00Z'),
('msg-f002-03', :'uid', 'thread-flutter-002', 'user',
 'Fixed it. Also had to set ndkVersion in android/app/build.gradle.kts',
 'e1f2g3h4i5',
 '2026-04-25T15:45:00Z');

-- =============================================================================
-- Conversation 3: "Personal preferences — dark mode"
-- =============================================================================
INSERT INTO public.threads (id, user_id, title, source, created_at, updated_at)
VALUES (
  'thread-preferences-003',
  :'uid',
  'App theme preferences',
  'kelivo',
  '2026-04-18T08:00:00Z',
  '2026-04-18T08:20:00Z'
);

INSERT INTO public.messages (id, user_id, thread_id, role, content, content_hash, created_at) VALUES
('msg-p003-01', :'uid', 'thread-preferences-003', 'user',
 'I prefer dark mode with a pure black background and minimal UI.',
 'j6k7l8m9n0',
 '2026-04-18T08:00:00Z'),
('msg-p003-02', :'uid', 'thread-preferences-003', 'assistant',
 'Got it. You prefer dark mode with pure black OLED background. This saves battery on AMOLED screens and reduces eye strain at night. I''ll remember this preference.',
 'o1p2q3r4s5',
 '2026-04-18T08:01:00Z'),
('msg-p003-03', :'uid', 'thread-preferences-003', 'user',
 'Also I like concise answers, not essays. And use my local timezone for dates.',
 't6u7v8w9x0',
 '2026-04-18T08:05:00Z'),
('msg-p003-04', :'uid', 'thread-preferences-003', 'assistant',
 'Preferences noted: concise answers, local timezone formatting.',
 'y1z2a3b4c5',
 '2026-04-18T08:06:00Z'),
('msg-p003-05', :'uid', 'thread-preferences-003', 'user',
 'Actually can you use Celsius not Fahrenheit for weather?',
 'd6e7f8g9h0',
 '2026-04-18T08:20:00Z');

-- =============================================================================
-- Sync manifest entries (mark test data as synced)
-- =============================================================================
INSERT INTO public.sync_manifest (user_id, entity_type, entity_id, content_hash, sync_status)
VALUES
  (:'uid', 'thread', 'thread-supabase-001',    'hash-thread-001', 'synced'),
  (:'uid', 'thread', 'thread-flutter-002',     'hash-thread-002', 'synced'),
  (:'uid', 'thread', 'thread-preferences-003', 'hash-thread-003', 'synced');

-- =============================================================================
-- Expected retrieval test cases (documented, not executed in SQL):
--
-- Test 1: Keyword search for "ndkVersion 27.0.12077973"
--   Expected: returns msg-f002-01 (Flutter APK thread)
--
-- Test 2: Keyword search for "dark mode pure black"
--   Expected: returns msg-p003-01 (Preferences thread)
--
-- Test 3: Keyword search for "bucket 50 MB"
--   Expected: returns msg-s001-03 (Supabase thread)
--
-- Test 4: Semantic search for "OLED battery saving"
--   Expected: returns msg-p003-02 (Preferences thread mentioning AMOLED)
--
-- Test 5: Semantic search for "where to get NDK for Flutter"
--   Expected: returns msg-f002-02 (SDK Manager instructions)
-- =============================================================================
