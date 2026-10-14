---
"better-supabase": minor
---

Add the `service-principals` block (`better-supabase/blocks/service-principals` and the `service-principals` SQL module): organization members that are not people, each an `auth.users` row that cannot sign in and holds its role through a membership. `create`, `setRole`, `disable`, `defaultFor` and `list` manage them; a member who asks for the change needs `service_principals.manage` and may only assign a role they could assign. A workflow-builder version the organization owns runs as its default principal, capped to the permissions the version stored, and a service webhook endpoint gets an event only when the default principal may read it.
