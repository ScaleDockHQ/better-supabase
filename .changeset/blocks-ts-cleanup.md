---
"better-supabase": minor
---

`createBlocks` in the new `better-supabase/blocks` subpath builds several blocks from one set of options, and the blocks share their helpers, option names and page shape.

- `createBlocks({ transport, service, schema, credentials, events, audit }, factories)` builds the blocks you pass and wires their siblings: the AI files block into knowledge, `credentials` into connectors, ai-providers and the workflow builder, notifications into ai-tasks (with `aiTaskNotification`), and block events into an audit sink. The subpath also exports `rpcTransport`, `sqlTransport` and the `BlockOptions` and `CursorPageOptions` types.
- `audit.sink()` returns an `EventSink` that records each CloudEvent in the audit log, with its type, subject, tenant and data. `createServer({ audit })` sends `account.suspended`, `account.unsuspended`, `account.deleted` and `account.sessions_ended` from `suspendAccount`, `deleteAccount` and `endSessions`, and forwards `support.denied`; a failing sink never changes a result.
- Block lists page with `{ limit, cursor }`, which replace `size`, `before` and `after`.
- Notifications, organizations, profiles and outgoing webhooks take `mappers` instead of `errorMappers`.
- `CredentialProvider` gains an optional `set(ref, value, { subject, description })`, which Vault implements and the workflow builder uses. `credentialRouter(providers)` serves several providers as one, and `revokeIfConfigured(provider, ref, { subject, tenant })` revokes only when a provider is configured, can revoke the ref and the ref is in the tenant.
- `Embedder`, `EveDocumentBackend`, `AiTaskRunner`, `GraphCompiler` and `BuilderStarter` take an optional `apiVersion: 1`; a block refuses another version. `better-supabase/testing` adds `testEmbedder`, `testEveDocumentBackend`, `testAiTaskRunner`, `testGraphCompiler` and `testBuilderStarter`.
- The block row decoders moved into the core and every block uses the same ones; `better-supabase/blocks/knowledge` no longer exports `vectorLiteral`.
