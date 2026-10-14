---
"better-supabase": minor
---

Published workflow-builder versions now run with their publisher's rights. `publish_workflow_version` records `published_by`, `owner_kind` and the `permissions` the version's steps need, and refuses a publisher who lacks one (`WORKFLOW_PUBLISHER_FORBIDDEN`). With `createBuilder({ authorization })`, `automation.mayPublish` also decides each `versions.publish(version, { claims })`.

Breaking: each step must call `builder.versions.runAs(call.version)`, which fails with `WORKFLOW_PUBLISHER_REVOKED` once the publisher loses a permission or their membership, or when `automation.runAs` returns `null`. Versions published before this release have no recorded publisher and fail until they are published again. An organization-owned version, published by the service role, runs only as the service principal `runAs` returns. `GraphStepCall.version` and `GraphRunMeta.versionId` carry the version id to each step.

Workflow nodes, MCP tools and inbox commands read the provider's operations table first: `workflow.node.<step>`, `mcp.tool.<name>` (through the new `createMcp({ operations })`) and `inbox.command.<name>`. Doctor reports `admin()` in a file that runs workflow-builder steps (BS333).
