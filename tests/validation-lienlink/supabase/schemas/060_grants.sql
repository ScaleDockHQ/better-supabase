-- The end state of the Data API privileges. This image's default privileges
-- grant every table to anon and authenticated, so the app states what stays.
revoke all on table public.jobs, public.job_audit, public.user_signups from anon;
revoke all on table public.jobs, public.job_audit, public.user_signups from authenticated;
grant select, insert, update on table public.jobs to authenticated;
grant select on table public.job_audit, public.user_signups to authenticated;

revoke all on table public.organizations, public.memberships, public.teams, public.team_members, public.profiles, public.job_attachments from anon;
revoke all on table public.organizations, public.memberships, public.teams, public.team_members, public.profiles, public.job_attachments from authenticated;
grant select on table public.organizations, public.memberships, public.teams, public.team_members, public.profiles to authenticated;
grant select, insert on table public.job_attachments to authenticated;
