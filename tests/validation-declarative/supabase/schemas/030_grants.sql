-- The final Data API privileges of the app's tables. This image's default
-- privileges grant every table to anon and authenticated, so the app takes
-- back what no policy uses. The modules' own grants (select for authenticated)
-- stay where the modules declare them.
revoke all on table public.organizations from anon;
revoke all on table public.memberships from anon;
revoke all on table public.profiles from anon;
revoke all on table public.projects from anon;
revoke truncate, references, trigger on table public.organizations from authenticated;
revoke truncate, references, trigger on table public.memberships from authenticated;
revoke truncate, references, trigger on table public.profiles from authenticated;
revoke truncate, references, trigger on table public.projects from authenticated;
revoke all on table public.my_organizations from anon;
revoke truncate, references, trigger on table public.my_organizations from authenticated;
