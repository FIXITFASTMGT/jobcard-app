# Shopfloor Job Card System — Setup Guide

Stack: **Supabase** (database + login + weekly email) + **Vercel** (hosts the app, free) + **GitHub** (code storage, free).

## 1. Create the Supabase project (free)
1. supabase.com → New Project. Note your **Project URL** and **anon public key** (Project Settings → API).
2. SQL Editor → New query → paste the entire contents of `supabase/schema.sql` → Run.
   This creates all tables, sets up permissions (RLS), and seeds the ECO-200 model + its full operation list from your Gantt chart.
3. Create your supervisor login: Authentication → Users → Add User.
   - Email: e.g. `admin@yourcompany.local`
   - Password: e.g. `ADMIN@1234`
   - **Tick "Auto Confirm User"** — without this, login will fail with an "email not confirmed" error since there's no real inbox to click a confirmation link.

## 1b. Already ran the schema before? Run one more migration
If you'd already set up your database before this version, run `supabase/migration_001_execution_mode.sql` in SQL Editor too — it adds the Series/Parallel field to operations. Skip this if you're setting up fresh (it's already in `schema.sql`).

## 2. Configure the app
Open `public/index.html`, find these two lines near the top of the `<script>` block, and fill in your real values from Supabase (Project Settings → API):
```js
const SUPABASE_URL = 'YOUR_SUPABASE_PROJECT_URL';
const SUPABASE_ANON_KEY = 'YOUR_SUPABASE_ANON_KEY';
```
The anon key is safe to expose in client-side code. Permissions are enforced by the database (Row Level Security), not by hiding the key:
- **Anyone (operator, no login)** can read an active job's info + its operation list, and can submit entries. They **cannot** read other entries back, and cannot touch jobs, models, or operation lists.
- **Only the logged-in supervisor** can create/edit models, create/close jobs, edit a job's operation list, read the dashboard, or archive entries.

## 3. Push to GitHub
```bash
git init
git add .
git commit -m "Shopfloor job card system"
git remote add origin https://github.com/<you>/jobcard-app.git
git push -u origin main
```

## 4. Deploy to Vercel (free)
1. vercel.com → New Project → Import your GitHub repo.
2. Framework preset: **Other** (static site, no build step — `public/index.html` is plain HTML/JS).
3. Set root/output directory to `public`.
4. Deploy. You get a permanent URL like `https://jobcard-app.vercel.app` — this is what your QR codes will point to.

## 5. Weekly auto-email (Excel export)
1. Sign up free at resend.com, get an API key (their test sending domain works to start; verify your own domain for production use).
2. Deploy the email function:
   ```bash
   supabase functions deploy weekly-export
   supabase secrets set RESEND_API_KEY=your_resend_key WEEKLY_REPORT_EMAIL=your@email.com
   ```
3. Schedule it: Supabase Dashboard → Database → Cron Jobs → New Job → call `weekly-export` every Monday (or your preferred day/time).

## Day-to-day usage
- **Model Master**: create/edit ECO-200 variants (base, E, U, I). Each has its own operation list — reorder with ▲▼, edit hours/manpower inline, add/remove rows, or **Import an Excel file** (columns: OpNo, Group, Description, StdHours, StdManpower) / **Export** the current list to Excel.
- **New Job**: pick machine no., customer, model variant, dates. Operations auto-copy from that model's template into the job's own editable list.
- **Jobs / QR Labels**: for any active job, **Edit Ops** opens the same reorder/edit/import/export editor — but scoped to just that job, so you can adjust it (e.g. this ECO-200U build skips one operation) without touching the master template. Tick jobs → Print Selected Labels → generates a sheet laid out for standard 64×34mm, 24-per-sheet A4 label stock. Print, stick onto the paper Gantt chart. **Mark Completed** kills that job's QR immediately.
- **Operator**: scans the QR on the Gantt chart → sees machine/customer/model, no login → fills name, operation (dropdown scoped to that job), date, start/end time, status (Completed / Partial / Hold — issue reason required for the latter two), optional extra operators' hours → Submit.
- **Dashboard**: live entries, filter by machine/status, size shown, one-click Excel export anytime, plus **Archive**: pick a cutoff date, it exports everything before that date to Excel and then deletes it from the live table (irreversible, confirms before running) — this is how you clear weekly/monthly without losing the data.

## Known simplifications (fine for this scale, worth knowing)
- Reordering uses ▲▼ buttons instead of true drag-and-drop — same result, more reliable to build/maintain. Can upgrade later if it matters to you.
- The weekly email uses Resend's free tier; swap the fetch call for any other provider (Postmark, SendGrid) if you prefer.
- Storage size on the dashboard is an estimate from the loaded data's size; Supabase Dashboard → Database → Usage has the exact number anytime.
- New model variants (E/U/I) are seeded empty — only base ECO-200 has its operations pre-filled from your uploaded Gantt chart. Fill in each variant's list once via Model Master (export the base list, edit the copy, re-import).
