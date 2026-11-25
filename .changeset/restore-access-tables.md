---
"better-supabase": patch
---

A restore also leaves out the tables that grant access in the teams, guests, approvals, access-requests, agents, share-links, oauth-server, mfa, identities, organizations, connectors and agent-checkout blocks, and the grant, member, approval and secret tables of drive, inspections, invoices, knowledge, messaging, deals, subjects, webhooks and workflow-editor. A test now fails when a block adds a tenant table that decides access without classifying it. Run `better-supabase upgrade` to regenerate the data-lifecycle module.
