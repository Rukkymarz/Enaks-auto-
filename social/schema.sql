-- Express Cleaning Consult social media system: storage + publishing-safety logic.
-- All tables live in public with an soc_ prefix; RLS on, no policies: only the service role (n8n) can read/write.

create table if not exists soc_config (
  key   text primary key,
  value jsonb not null,
  note  text
);

create table if not exists soc_content (
  id               bigint generated always as identity primary key,
  created_at       timestamptz not null default now(),
  updated_at       timestamptz not null default now(),
  parent_id        bigint references soc_content(id),
  pillar           text not null,
  format           text not null check (format in ('single','carousel','video','text','poll','thread')),
  platforms        text[] not null default '{}',
  topic            text not null,
  topic_key        text generated always as (md5(regexp_replace(lower(topic), '[^a-z0-9]+', ' ', 'g'))) stored,
  angle            text,
  hook             text,
  purpose          text,
  audience         text,
  is_promotional   boolean not null default false,
  status           text not null default 'idea' check (status in
                   ('idea','generating','needs_media','pending_approval','revision','approved','rejected',
                    'publishing','published','failed')),
  content          jsonb not null default '{}'::jsonb,   -- captions per platform, slides, script, hashtags, cta
  media_urls       text[] not null default '{}',
  scheduled_at     timestamptz,
  approval_note    text,
  revision_count   int not null default 0,
  publish_attempts int not null default 0,
  postiz_posts     jsonb not null default '[]'::jsonb,   -- [{postId, integration}]
  published_at     timestamptz,
  last_error       text
);
create unique index if not exists soc_content_topic_unique on soc_content(topic_key);
create index if not exists soc_content_status_idx on soc_content(status, scheduled_at);

create table if not exists soc_metrics (
  id          bigint generated always as identity primary key,
  captured_at timestamptz not null default now(),
  content_id  bigint references soc_content(id),
  platform    text not null,
  postiz_post_id text,
  metric      text not null,          -- e.g. Likes, Impressions, Comments (as returned; never invented)
  value       numeric,
  raw         jsonb
);
create index if not exists soc_metrics_content_idx on soc_metrics(content_id, captured_at);

create table if not exists soc_interactions (
  id              bigint generated always as identity primary key,
  received_at     timestamptz not null default now(),
  platform        text not null,
  external_id     text unique,
  author          text,
  message         text,
  category        text check (category in ('positive','question','inquiry','complaint','spam','partnership','potential_customer','other')),
  sensitive       boolean not null default false,
  suggested_reply text,
  status          text not null default 'new' check (status in ('new','sent_for_review','replied','ignored'))
);

create table if not exists soc_reports (
  id          bigint generated always as identity primary key,
  created_at  timestamptz not null default now(),
  week_start  date not null unique,
  report_md   text not null,
  next_actions jsonb
);

create table if not exists soc_errors (
  id          bigint generated always as identity primary key,
  at          timestamptz not null default now(),
  workflow    text,
  node        text,
  platform    text,
  content_id  bigint,
  message     text,
  execution_url text
);

alter table soc_config       enable row level security;
alter table soc_content      enable row level security;
alter table soc_metrics      enable row level security;
alter table soc_interactions enable row level security;
alter table soc_reports      enable row level security;
alter table soc_errors       enable row level security;

create or replace function soc_touch() returns trigger language plpgsql as $$
begin new.updated_at := now(); return new; end $$;
drop trigger if exists soc_content_touch on soc_content;
create trigger soc_content_touch before update on soc_content for each row execute function soc_touch();

-- Insert ideas, skipping any topic already used (exact or near-exact wording). Returns rows inserted.
create or replace function soc_insert_ideas(ideas jsonb) returns setof soc_content
language sql security definer set search_path = public as $$
  insert into soc_content (parent_id, pillar, format, platforms, topic, angle, hook, purpose, audience, is_promotional)
  select nullif(i->>'parent_id','')::bigint, i->>'pillar', i->>'format',
         coalesce(array(select jsonb_array_elements_text(i->'platforms')), '{}'),
         i->>'topic', i->>'angle', i->>'hook', i->>'purpose', i->>'audience',
         coalesce((i->>'is_promotional')::boolean, false)
  from jsonb_array_elements(ideas) i
  where coalesce(i->>'topic','') <> ''
  on conflict (topic_key) do nothing
  returning *;
$$;

-- Topics already used, newest first, for the strategist prompt (prevents repeats).
create or replace function soc_recent_topics(n int default 120) returns table(topic text, format text, status text)
language sql stable security definer set search_path = public as $$
  select topic, format, status from soc_content order by created_at desc limit n;
$$;

-- Pick ideas for today, respecting posts_per_day and the 60% non-promotional rule, and mark them generating.
create or replace function soc_pick_daily(max_items int default null) returns setof soc_content
language plpgsql security definer set search_path = public as $$
declare k int := coalesce(max_items, (select (value)::text::int from soc_config where key='posts_per_day'), 1);
begin
  return query
  with picked as (
    select id from soc_content
    where status = 'idea'
    order by is_promotional asc, created_at asc
    limit k
    for update skip locked
  )
  update soc_content c set status = 'generating'
  from picked where c.id = picked.id
  returning c.*;
end $$;

-- Next free publishing slot in the audience timezone: slots come from config (set by the owner, tuned by data),
-- at most one post per slot, never in the past, minimum gap between posts.
create or replace function soc_next_slot() returns timestamptz
language plpgsql stable security definer set search_path = public as $$
declare
  tz    text := coalesce((select value #>> '{}' from soc_config where key='timezone'), 'America/New_York');
  slots jsonb := coalesce((select value from soc_config where key='post_slots'), '["12:00"]'::jsonb);
  gap   interval := make_interval(hours => coalesce((select (value)::text::int from soc_config where key='min_gap_hours'), 4));
  d     date := (now() at time zone tz)::date;
  s     text;
  cand  timestamptz;
begin
  for day_offset in 0..30 loop
    for s in select jsonb_array_elements_text(slots) order by 1 loop
      cand := ((d + day_offset)::text || ' ' || s)::timestamp at time zone tz;
      if cand > now() + interval '30 minutes'
         and not exists (select 1 from soc_content
                         where scheduled_at is not null
                           and status in ('needs_media','pending_approval','revision','approved','publishing','published')
                           and abs(extract(epoch from (scheduled_at - cand))) < extract(epoch from gap)) then
        return cand;
      end if;
    end loop;
  end loop;
  return null;
end $$;

-- Atomically claim ONE approved post that is due, so two runs can never publish it twice.
create or replace function soc_claim_due() returns setof soc_content
language plpgsql security definer set search_path = public as $$
begin
  return query
  with due as (
    select id from soc_content
    where status = 'approved' and scheduled_at <= now() and postiz_posts = '[]'::jsonb
    order by scheduled_at asc
    limit 1
    for update skip locked
  )
  update soc_content c set status = 'publishing', publish_attempts = c.publish_attempts + 1
  from due where c.id = due.id
  returning c.*;
end $$;

-- Record a publish result. Success stores Postiz ids; failure retries up to 3 attempts, then marks failed.
create or replace function soc_publish_result(p_id bigint, p_ok boolean, p_posts jsonb, p_error text)
returns soc_content language plpgsql security definer set search_path = public as $$
declare r soc_content;
begin
  if p_ok then
    update soc_content set status='published', postiz_posts=coalesce(p_posts,'[]'::jsonb),
           published_at=now(), last_error=null where id=p_id returning * into r;
  else
    update soc_content set
      status = case when publish_attempts >= 3 then 'failed' else 'approved' end,
      scheduled_at = case when publish_attempts >= 3 then scheduled_at else now() + interval '15 minutes' end,
      last_error = p_error
    where id=p_id returning * into r;
    insert into soc_errors(workflow, node, platform, content_id, message)
    values ('SOC-07 Publishing', 'Postiz create post', array_to_string(r.platforms, ','), p_id, p_error);
  end if;
  return r;
end $$;

-- Weekly digest input: last 7 days of published posts with their latest metric values.
create or replace function soc_week_performance(days int default 7) returns jsonb
language sql stable security definer set search_path = public as $$
  select coalesce(jsonb_agg(row_to_json(t)), '[]'::jsonb) from (
    select c.id, c.pillar, c.format, c.platforms, c.topic, c.hook, c.is_promotional, c.published_at,
           (select jsonb_object_agg(m.metric, m.value) from (
              select distinct on (metric) metric, value from soc_metrics
              where content_id = c.id order by metric, captured_at desc) m) as metrics
    from soc_content c
    where c.status = 'published' and c.published_at >= now() - make_interval(days => days)
    order by c.published_at
  ) t;
$$;

revoke all on function soc_insert_ideas(jsonb), soc_recent_topics(int), soc_pick_daily(int), soc_next_slot(),
  soc_claim_due(), soc_publish_result(bigint, boolean, jsonb, text), soc_week_performance(int) from public, anon, authenticated;

insert into soc_config(key, value, note) values
  ('timezone',      '"America/New_York"', 'Audience timezone for scheduling'),
  ('posts_per_day', '1',                  'Start low; raise once approvals keep up'),
  ('post_slots',    '["12:00"]',          'STARTING slot only, not a claimed best time. Owner sets; weekly report suggests changes from real data'),
  ('min_gap_hours', '4',                  'Minimum hours between any two posts'),
  ('auto_publish',  'false',              'true skips email approval. Leave false until tested and trusted'),
  ('approval_email','"expressconsulting92@gmail.com"', 'Where approval requests go'),
  ('postiz_base_url','""',                'e.g. https://social.<host>/api/public/v1 once Postiz is hosted'),
  ('from_email',    '"Express Cleaning Consult <expressconsulting92@gmail.com>"', 'Sender for approval and report emails; must match the SMTP login'),
  ('services_confirmed', '["House and residential cleaning","Deep cleaning","Office and janitorial","Move-in and move-out cleaning","Airbnb and short-term rental turnovers","Post-construction cleaning","Pressure washing","Junk removal","Floor care"]', 'Listed on expresscleaningconsult.com as of 2026-11-27. Only these are promoted'),
  ('services_pending', '["Medical and professional office cleaning","Apartment turnovers","Retail and storefront cleaning","Common area cleaning","Interior window and glass cleaning","Event cleaning","Vehicle cleaning"]', 'In the brief but not seen on the site: educational content only, no promotion until the owner confirms and moves them to services_confirmed'),
  ('facebook_page_id','""', 'Facebook Page id for the comment monitor'),
  ('postiz_integrations','{}',            'Map platform -> Postiz integration id, filled after channels are connected in Postiz')
on conflict (key) do nothing;
