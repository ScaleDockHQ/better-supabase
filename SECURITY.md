# Security policy

## Reporting a vulnerability

Report vulnerabilities privately. Do not open a public GitHub issue, discussion, or pull request.

Use GitHub private vulnerability reporting:

https://github.com/ScaleDockHQ/better-supabase/security/advisories/new

We acknowledge security reports within 48 hours.

## Supported versions

better-supabase is on `0.x`. Patch releases of the current minor are supported. There is no long-term support line until 1.0.

| Version                | Supported |
| ---------------------- | --------- |
| 0.2.x                  | Yes       |
| 0.x (an earlier minor) | No        |

## What to include

- Affected version (or commit) and import path, for example `better-supabase/next`
- Reproduction steps, including the SQL for the tables and policies involved
- Impact: an RLS bypass, a service-role client reachable from a user request, a leaked token or cookie, SQL injection through a filter, and similar
- Whether the issue is already public

## Scope

In scope: everything published in the `better-supabase` and `@better-supabase/cli` npm packages, including the SQL kit modules the CLI writes, the code it generates, and the Agent Skills the library ships. Both packages share a version, so the table covers both. Supabase itself (Auth, PostgREST, Storage, Realtime) is out of scope; report those to [Supabase](https://supabase.com/.well-known/security.txt).
