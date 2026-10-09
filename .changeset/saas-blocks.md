---
"better-supabase": minor
---

New SaaS blocks, each an SQL module with a subpath: `better-supabase/blocks/api-keys`, `/audit`, `/settings`, `/usage`, `/billing`, `/flags`, `/comments`, `/attachments`, `/data-lifecycle`, `/sso`, `/onboarding`, `/waitlist`, `/announcements` and `/push`. Add one with `better-supabase sql add <name>`; `stripe` is an optional peer that only billing and usage load.

- SSO serves SCIM 2.0, flags evaluate rollouts in SQL and through an OpenFeature-shaped provider, and `SPEC_PINS` gains `ocsf`, `openfeature` and `scim`. Under the `provider` model, SSO and waitlist roles go through `roleThrough` and need `can_assign` (`SSO_ROLE_FORBIDDEN`, `WAITLIST_ROLE_FORBIDDEN`), and `join_waitlist` always answers `status: "waiting"` to clients.
- Blocks take `ctx.postgres` from `@supabase/server`, `withBlock(key, create)` puts a block on the context, and every block takes `temporal` and a `problem` option (`ProblemFormat`) for error bodies.
- New event types cover organization domains and deletion, `billing.*`, comments, attachments, data exports and `waitlist.approved`.
- **Breaking:** the server's `auth.kind` gains `"apiKey"`, so an exhaustive `switch` over it needs the new case.
