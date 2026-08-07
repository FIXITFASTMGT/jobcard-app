// Supabase Edge Function: weekly-export
// Pulls all entries, builds a CSV (Excel-openable), emails it to one address via Resend (free tier).
// Deploy: supabase functions deploy weekly-export
// Schedule weekly via Supabase Dashboard -> Database -> Cron Jobs (pg_cron), or
// Project Settings -> Edge Functions -> Schedule, calling this function every Monday 06:00.

import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

const SUPABASE_URL = Deno.env.get('SUPABASE_URL')!;
const SERVICE_ROLE_KEY = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!; // set as a secret, never expose client-side
const RESEND_API_KEY = Deno.env.get('RESEND_API_KEY')!;              // free tier at resend.com
const SEND_TO = Deno.env.get('WEEKLY_REPORT_EMAIL')!;                // your one supervisor email address

Deno.serve(async () => {
  const sb = createClient(SUPABASE_URL, SERVICE_ROLE_KEY);

  const { data: entries, error } = await sb
    .from('entries')
    .select('*, jobs(machine_no, customer), job_operations(op_no, description)')
    .order('submitted_at', { ascending: false });

  if (error) {
    return new Response(JSON.stringify({ error: error.message }), { status: 500 });
  }

  const header = ['Machine', 'Customer', 'Op No', 'Description', 'Operator', 'Date', 'Start', 'End', 'Status', 'Issue', 'Logged At'];
  const rows = (entries || []).map(e => [
    e.jobs?.machine_no, e.jobs?.customer, e.job_operations?.op_no, e.job_operations?.description,
    e.primary_operator, e.activity_date, e.start_time, e.end_time, e.status, e.issue_reason || '', e.submitted_at
  ]);
  const csv = [header, ...rows].map(r => r.map(v => `"${(v ?? '').toString().replace(/"/g, '""')}"`).join(',')).join('\n');
  const base64Csv = btoa(unescape(encodeURIComponent(csv)));

  const emailRes = await fetch('https://api.resend.com/emails', {
    method: 'POST',
    headers: {
      Authorization: `Bearer ${RESEND_API_KEY}`,
      'Content-Type': 'application/json'
    },
    body: JSON.stringify({
      from: 'Shopfloor Job Cards <reports@yourdomain.com>',
      to: [SEND_TO],
      subject: `Weekly Production Log — ${new Date().toLocaleDateString()}`,
      text: `Attached: full production log export, ${rows.length} entries as of today.`,
      attachments: [{ filename: 'weekly_production_log.csv', content: base64Csv }]
    })
  });

  if (!emailRes.ok) {
    const t = await emailRes.text();
    return new Response(JSON.stringify({ error: 'email failed', detail: t }), { status: 500 });
  }

  return new Response(JSON.stringify({ ok: true, count: rows.length }), { status: 200 });
});
