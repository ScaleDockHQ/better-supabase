---
"better-supabase": minor
---

Drive nodes take access requests. With `driveSubject({ accessRequests: true })` and the
access-requests block installed, `drive.requestAccess(nodeId, { action, reason, duration })` asks
for access and `drive.accessRequests(nodeId)` lists the requests. The node's owners approve, and
an approved request becomes a node grant that ends with the request. The access-requests client
gains `records(subjectType, subjectId)`, and reaches the drive through the new `recordAccess`
port.

`drive.transferOwnership(organizationId, fromUserId, toUserId)` hands a member's owned items to
another member and records `drive.node_ownership_transferred` and `drive.ownership_transferred`.
`driveOffboardingSink` runs it from the outbox when a member leaves.

With the settings block installed, the `drive.sharing` organization setting (`driveSettings`)
turns guest grants off and limits share links to `organization` or `none`, failing with
`DRIVE_SHARING_DISABLED`. Apply the new migration with `better-supabase upgrade`.
