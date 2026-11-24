-- The agent run and approval story of the AI sample: one agent, a failed and a
-- completed run, a tool call waiting for a decision and the guardrail hits.
-- Owner of everything is the Acme owner (a1); all ids are fixed so the seed can
-- run again.
insert into better_supabase.agents (id, tenant_id, owner_id, slug, name, description, instructions, model, tools, visibility, published_at) values
  ('00000000-0000-4000-8000-00000a9e0001', '00000000-0000-4000-8000-000000000001', '00000000-0000-4000-8000-0000000000a1',
   'renewals-desk', 'Renewals desk', 'Prepares renewal quotes and asks before it grants a discount.',
   'Read the account, propose a renewal and request an approval for any discount.', null,
   '["requestDiscountApproval"]'::jsonb, 'organization', now())
on conflict (id) do nothing;

insert into better_supabase.ai_chats (id, tenant_id, owner_id, agent_id, title) values
  ('00000000-0000-4000-8000-00000a9c0001', '00000000-0000-4000-8000-000000000001', '00000000-0000-4000-8000-0000000000a1', 'renewals-desk', 'Globex renewal'),
  ('00000000-0000-4000-8000-00000a9c0002', '00000000-0000-4000-8000-000000000001', '00000000-0000-4000-8000-0000000000a1', 'renewals-desk', 'Initech renewal')
on conflict (id) do nothing;

insert into better_supabase.ai_runs (id, chat_id, owner_id, engine, model, status, usage, cost_micro_usd, error, started_at, ended_at) values
  ('00000000-0000-4000-8000-00000a9a0001', '00000000-0000-4000-8000-00000a9c0001', '00000000-0000-4000-8000-0000000000a1',
   'ai-sdk', 'demo', 'completed', '{"inputTokens": 820, "outputTokens": 190}'::jsonb, 1800, null, now() - interval '2 hours', now() - interval '2 hours' + interval '14 seconds'),
  ('00000000-0000-4000-8000-00000a9a0002', '00000000-0000-4000-8000-00000a9c0002', '00000000-0000-4000-8000-0000000000a1',
   'ai-sdk', 'demo', 'failed', '{"inputTokens": 410}'::jsonb, 600, 'The renewal tool timed out', now() - interval '1 hour', now() - interval '1 hour' + interval '30 seconds')
on conflict (id) do nothing;

insert into better_supabase.ai_run_steps (run_id, chat_id, owner_id, step_key, label, status, detail, started_at, ended_at)
select r.run_id::uuid, r.chat_id::uuid, '00000000-0000-4000-8000-0000000000a1', r.step_key, r.label, r.status, '{}'::jsonb, now() - interval '2 hours', now() - interval '2 hours' + interval '5 seconds'
from (values
  ('00000000-0000-4000-8000-00000a9a0001', '00000000-0000-4000-8000-00000a9c0001', 'read-account', 'Read the account', 'done'),
  ('00000000-0000-4000-8000-00000a9a0001', '00000000-0000-4000-8000-00000a9c0001', 'ask-approval', 'Request the discount approval', 'done'),
  ('00000000-0000-4000-8000-00000a9a0002', '00000000-0000-4000-8000-00000a9c0002', 'read-account', 'Read the account', 'done'),
  ('00000000-0000-4000-8000-00000a9a0002', '00000000-0000-4000-8000-00000a9c0002', 'draft-renewal', 'Draft the renewal', 'error')
) as r(run_id, chat_id, step_key, label, status)
on conflict (run_id, step_key) do nothing;

insert into better_supabase.ai_tool_approvals (approval_id, chat_id, owner_id, run_id, tool, tool_call_id, input) values
  ('areas-12-13-approval-1', '00000000-0000-4000-8000-00000a9c0001', '00000000-0000-4000-8000-0000000000a1',
   '00000000-0000-4000-8000-00000a9a0001', 'requestDiscountApproval', 'call-areas-1',
   '{"reason": "Globex asked for 10 percent on a three year renewal"}'::jsonb)
on conflict (approval_id) do nothing;

insert into better_supabase.guardrail_decisions (id, tenant_id, agent, stage, decision, reasons, chat_id) values
  ('00000000-0000-4000-8000-00000a9d0001', '00000000-0000-4000-8000-000000000001', 'renewals-desk', 'input', 'redact',
   '[{"code": "pii", "detail": "An email address was masked"}]'::jsonb, '00000000-0000-4000-8000-00000a9c0001'),
  ('00000000-0000-4000-8000-00000a9d0002', '00000000-0000-4000-8000-000000000001', 'renewals-desk', 'output', 'block',
   '[{"code": "topic", "detail": "The reply left the renewal topic"}]'::jsonb, '00000000-0000-4000-8000-00000a9c0002')
on conflict (id) do nothing;
