# 0124: Knowledge collections with grants; system documents without a tenant

- Status: accepted
- Date: 2026-10-28

## Context

Knowledge documents were scoped to an organization, an agent, a project, a
chat or a user. Apps want to group documents (a handbook, HR policies), hide
some groups from most members, rank some above others, and ship product help
once for every tenant instead of copying it into each one.

## Decision

`knowledge_collections` holds a name, a visibility (`automatic`,
`restricted` or `disabled`) and a priority per tenant, and
`knowledge_collection_grants` grants a restricted collection to users or,
with the teams block, to teams. A document joins one collection through
`collection_id`. `knowledge_collection_readable` decides whether the caller
reads a collection's documents (a grant, the manage permission or the
service role), the document and chunk policies call it, and search ranks
chunks by collection priority before the fused score and takes a
`collections` filter.

A collection or document without a tenant is a system row: only the service
role writes it, and every tenant reads it. System documents use the
organization scope and have no owner, enforced by a check constraint. The
knowledge block moves to version 3.

## Alternatives considered

- Tags on documents instead of collections. Rejected: grants and priority
  need a row to hang on, and tags already exist as a block for records.
- Copying system documents into each tenant. Rejected: every product help
  edit would fan out to every tenant and re-embed there.

## Consequences

`KnowledgeDocument.organizationId` and `ownerId` can be undefined now, so
code that reads them handles a system document. Restricted collections add
a policy check per document read. Removing a collection keeps its documents
without a collection.
