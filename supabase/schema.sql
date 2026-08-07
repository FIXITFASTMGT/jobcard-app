-- ============================================================
-- Shopfloor Job Card System — Supabase (Postgres) schema  [v2 - corrected]
-- Run this once in Supabase SQL Editor (Project -> SQL Editor -> New query)
-- ============================================================

create extension if not exists "pgcrypto"; -- for gen_random_uuid() / gen_random_bytes()

-- ---------- 1. Model Master (ECO-200, ECO-200E, ECO-200U, ECO-200I ...) ----------
create table models (
  id uuid primary key default gen_random_uuid(),
  model_name text not null,        -- e.g. 'ECO-200U'
  base_model text not null,        -- e.g. 'ECO-200'  (groups variants)
  created_at timestamptz default now(),
  unique(model_name)
);

create table model_operations (
  id uuid primary key default gen_random_uuid(),
  model_id uuid references models(id) on delete cascade,
  op_no text,
  group_name text,
  description text not null,
  std_hours numeric,
  std_manpower int default 1,
  execution_mode text not null default 'Series' check (execution_mode in ('Series','Parallel')),
  sequence int not null
);

-- ---------- 2. Jobs (one per QR / one per machine run) ----------
create table jobs (
  id uuid primary key default gen_random_uuid(),
  machine_no text not null,
  customer text,
  model_id uuid references models(id),
  start_date date,
  planned_end_date date,
  delivery_date date,
  qr_token text unique not null default encode(gen_random_bytes(8), 'hex'),
  status text not null default 'Active',   -- 'Active' | 'Completed'
  created_at timestamptz default now(),
  closed_at timestamptz
);

-- job's own editable copy of the operation list (cloned from model_operations at creation,
-- then freely editable per job — reordering, hours, manpower — without touching the master template)
create table job_operations (
  id uuid primary key default gen_random_uuid(),
  job_id uuid references jobs(id) on delete cascade,
  op_no text,
  group_name text,
  description text not null,
  std_hours numeric,
  std_manpower int default 1,
  execution_mode text not null default 'Series' check (execution_mode in ('Series','Parallel')),
  sequence int not null
);

-- ---------- 3. Entries (operator submissions) ----------
create table entries (
  id uuid primary key default gen_random_uuid(),
  job_id uuid references jobs(id) on delete cascade,
  job_operation_id uuid references job_operations(id),
  primary_operator text not null,
  activity_date date not null,
  start_time time not null,
  end_time time not null,
  status text not null,             -- 'Completed' | 'Partial' | 'Hold'
  issue_reason text,                -- required in app logic when Partial/Hold
  submitted_at timestamptz default now()
);

create table entry_operators (
  id uuid primary key default gen_random_uuid(),
  entry_id uuid references entries(id) on delete cascade,
  operator_name text not null,
  hours numeric
);

-- ---------- Indexes ----------
create index idx_entries_job on entries(job_id);
create index idx_entries_date on entries(activity_date);
create index idx_job_operations_job on job_operations(job_id);
create index idx_model_operations_model on model_operations(model_id);
create index idx_jobs_token on jobs(qr_token);
create index idx_jobs_status on jobs(status);

-- ============================================================
-- Row Level Security
--
-- Two access levels only:
--   - anon (operator, no login): can read an active job + its op list (needed to render
--     the scan page), and can INSERT entries/entry_operators. Cannot read entries back,
--     cannot touch jobs/models/operations.
--   - authenticated (supervisor, logged in via Supabase Auth): full read/write on
--     everything — create/edit models & operations, create/close jobs, edit job
--     operations, read & archive entries.
-- ============================================================

alter table jobs enable row level security;
alter table job_operations enable row level security;
alter table entries enable row level security;
alter table entry_operators enable row level security;
alter table models enable row level security;
alter table model_operations enable row level security;

-- ---- jobs ----
create policy "anyone can read jobs" on jobs
  for select using (true);
create policy "supervisor can insert jobs" on jobs
  for insert to authenticated with check (true);
create policy "supervisor can update jobs" on jobs
  for update to authenticated using (true) with check (true);

-- ---- job_operations ----
create policy "anyone can read job_operations" on job_operations
  for select using (true);
create policy "supervisor can insert job_operations" on job_operations
  for insert to authenticated with check (true);
create policy "supervisor can update job_operations" on job_operations
  for update to authenticated using (true) with check (true);
create policy "supervisor can delete job_operations" on job_operations
  for delete to authenticated using (true);

-- ---- models ----
create policy "anyone can read models" on models
  for select using (true);
create policy "supervisor can insert models" on models
  for insert to authenticated with check (true);
create policy "supervisor can update models" on models
  for update to authenticated using (true) with check (true);

-- ---- model_operations ----
create policy "anyone can read model_operations" on model_operations
  for select using (true);
create policy "supervisor can insert model_operations" on model_operations
  for insert to authenticated with check (true);
create policy "supervisor can update model_operations" on model_operations
  for update to authenticated using (true) with check (true);
create policy "supervisor can delete model_operations" on model_operations
  for delete to authenticated using (true);

-- ---- entries ----  (operator can submit but NOT read back; only supervisor reads/archives)
create policy "operator can insert entries" on entries
  for insert with check (true);
create policy "supervisor can read entries" on entries
  for select to authenticated using (true);
create policy "supervisor can delete entries" on entries
  for delete to authenticated using (true);

-- ---- entry_operators ----
create policy "operator can insert entry_operators" on entry_operators
  for insert with check (true);
create policy "supervisor can read entry_operators" on entry_operators
  for select to authenticated using (true);
create policy "supervisor can delete entry_operators" on entry_operators
  for delete to authenticated using (true);

-- ============================================================
-- Seed: ECO-200 base model + variants, and ECO-200's operation list
-- (pulled from your uploaded Gantt chart)
-- ============================================================

insert into models (model_name, base_model) values
  ('ECO-200', 'ECO-200'),
  ('ECO-200E', 'ECO-200'),
  ('ECO-200U', 'ECO-200'),
  ('ECO-200I', 'ECO-200');

insert into model_operations (model_id, op_no, group_name, description, std_hours, std_manpower, sequence)
select id, op_no, group_name, description, std_hours, 1, sequence
from models, (values
  ('10','Caracas','Bed Resting On Pad And Leveling',2,1),
  ('20','Caracas','Bed Rough Scraping',15,2),
  ('30','Caracas','Lifting Pin Fitting (If required)',5.5,3),
  ('40','Caracas','Carriage Housing Fitting',7.5,4),
  ('50','Caracas','Bed Tray and Carriage Tray Fitting',7.5,5),
  ('60','Caracas','Front Plate Fitting',6,6),
  ('70','Caracas','L.T. Rough Scraping',7.5,7),
  ('80','Block Assy','Drum & Worm Box Fitting',7.5,8),
  ('90','Block Assy','Cylinder & Hyd. Block Fitting',7.5,9),
  ('100','Caracas','Bed Final Scraping',15,10),
  ('110','Caracas','Oil Pockets By Moon Scraping Method',2,11),
  ('120','Caracas','Carriage Assy And Fitting',10.5,12),
  ('130','Caracas','Rack Fitting & Cyl. Bkt Fitting',7.5,13),
  ('140','Caracas','L.T. V/F Final & Side Cover Fitting',15,14),
  ('150','Block Assy','Gear Box & Spool Housing Fitting',7.5,15),
  ('160','Piping','Power Pack Fitting',7.5,16),
  ('170','Caracas','Lower Table Top Final Scraping',11.5,17),
  ('180','Caracas','Top Table Matching',15,18),
  ('190','Caracas','Top Table Side Scraping',4,19),
  ('200','Block Assy','Cross Feed Hand Wheel Fitting',7.5,20),
  ('210','Alignment','Work & Tail Stock Alignment',11,21),
  ('220','Alignment','Wheel Head Alignment',7.5,22),
  ('240','QA Check','Quality Check',4.5,23)
) as ops(op_no, group_name, description, std_hours, sequence)
where models.model_name = 'ECO-200';

-- NOTE: ECO-200E / ECO-200U / ECO-200I variants are created with EMPTY operation lists.
-- Use Model Master -> open ECO-200 -> Export to Excel -> edit the copy for each variant's
-- extra/removed operations (e.g. add Internal Head Alignment, Front Door Fitting for U/I) ->
-- Import into that variant. Or build each variant's list directly in the app.
