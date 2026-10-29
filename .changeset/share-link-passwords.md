---
"better-supabase": minor
---

Share links take a password and a download flag. `shareLinks.create(subject, { password, downloadAllowed })` stores a bcrypt hash of the password (at least 8 characters, `SHARE_LINK_PASSWORD_INVALID` otherwise) in the new `share_links.password_hash` column and the flag in `download_allowed` (default `true`). `shareLinks.resolve(token, { password })` fails with `SHARE_LINK_PASSWORD_REQUIRED` (code `28P01`) until the password matches, and `resolve` and `list` return `downloadAllowed` and `passwordRequired`. With the rate-limit block installed, 10 wrong passwords per link in 15 minutes lock it with `SHARE_LINK_RATE_LIMITED`; the `share_link_password` rule changes the limit.

`resolve_share_link` now takes `(token text, password text default null)`, and `create_share_link` takes `password` and `download_allowed` before the extra fields argument. The functions other blocks serve links through (calendar feeds, booking pages, public forms, drive links, shared AI chats and leave feeds) don't open a link that has a password.

A block's share link contribution lists the roles its links may carry (`roles`, `["view"]` unless set), and `create_share_link` refuses any other with `SHARE_LINK_ROLE_INVALID`. Public form links take `respond`. Types from `config.subjects` and `blocks["share-links"].on` keep taking any role. Run `better-supabase upgrade` and generate a migration to pick up the columns and signatures.
