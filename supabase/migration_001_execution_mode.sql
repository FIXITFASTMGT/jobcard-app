-- ============================================================
-- Migration: add Series/Parallel execution mode to operations
-- Run this ONLY IF you already ran the original schema.sql before.
-- (If you're setting up fresh, ignore this — the updated schema.sql
-- already includes this column.)
-- Supabase → SQL Editor → New query → paste this → Run.
-- ============================================================

alter table model_operations
  add column if not exists execution_mode text not null default 'Series'
  check (execution_mode in ('Series','Parallel'));

alter table job_operations
  add column if not exists execution_mode text not null default 'Series'
  check (execution_mode in ('Series','Parallel'));
