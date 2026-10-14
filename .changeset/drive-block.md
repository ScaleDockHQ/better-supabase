---
"better-supabase": minor
---

Adds the drive block (`sql add drive`, `better-supabase/blocks/drive`): folders and files on attachments, with grants to users, teams or roles that apply to everything under a folder. The same check runs in the drive functions, the attachment policies and restrictive `storage.objects` policies. Moves and renames follow a name-conflict policy. With versions, trash and share-links installed, the drive also keeps revisions, a bin, starred and recent items and folder share links. `driveTree` shapes nodes for a tree view, and `driveSubject()` lets other blocks attach to nodes. Adopt mode runs the drive on an existing tree and grant table. A SQL module can now set `before` to render ahead of another module without renumbering the generated files, and `drive_share` takes a team id from the teams table, so an adopted uuid team column accepts it.
