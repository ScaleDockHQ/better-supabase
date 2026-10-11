---
"better-supabase": minor
---

`createServer` takes an `authorizer`: a runtime decision point (`apiVersion: 1`) that receives each request in the AuthZEN information model (subject, action, resource and context) and returns `granted`, `denied` or `approval-required`. better-supabase builds the subject from the verified request only and refuses anything but `granted`. `defineAuthorizer` and its types (`Authorizer`, `AnyAuthorizer`, `AuthorizationRequest`, `AuthorizationOutcome`, `AuthorizationSubject`, `AuthorizationResource`, `PermissionRef`) are exported from `better-supabase/server`, and `better-supabase/testing` adds `testAuthorizer`, `staticAuthorizer` and the `testDocumentFormat` conformance kit.

Routes, actions, `bs.require` and the guards in every adapter take a `permission` option that the authorizer checks. `defineResource` adds `hooks` that run around the repository call and `actions` (`defineAction`) on an item or a collection, served next to the collection and item routes by Hono `resource()`, edge `resources()` and the new Next.js `bs.resources()`, which returns the handlers for a catch-all route. MCP tools take a `permission` too, and `tools/list` hides the tools the authorizer denies.
