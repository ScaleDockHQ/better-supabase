# 0166: A WOPI host for drive files

- Status: accepted
- Date: 2026-10-31

## Context

Teams that keep documents in the drive want to edit them in an office
editor (Collabora Online, Microsoft 365 for the web) without downloading a
copy. Those editors speak WOPI: the editor calls a host with a file id and
an access token. ADR 0133 added the check-out lock and left WOPI for later.

## Decision

- **A fetch handler, not an adapter per framework.** `createWopiHost`
  returns `handle(Request): Promise<Response>`, which every server adapter
  (Hono, Next.js route handlers, SvelteKit, TanStack Start, React Router)
  mounts as it is. It lives in `better-supabase/blocks/drive`, so there is no
  new subpath, and it imports no Node built-ins.
- **Signed tokens name one file and one user.** The host signs
  `{ file, user, canWrite, expiry }` with HMAC-SHA256 through WebCrypto and
  verifies it on every call. The app supplies `driveFor(claims)`, a drive
  client acting as that user, so grants, locks and audit apply unchanged.
- **The WOPI lock is the check-out lock.** `Lock` and `RefreshLock` call
  `lock()` with the note `wopi:<lock id>` and a 30 minute expiry; `Unlock`
  calls `unlock()`. A lock a person took through `lock()` has no `wopi:`
  note, so every WOPI lock call answers `409` with an empty `X-WOPI-Lock`.
- **`PutFile` is a revision.** It checks the lock id, uploads the body with
  `uploadRevision` and commits it, so versions, scans and retention apply.
  An unlocked file takes a `PutFile` only while it is empty, as WOPI says.

## Alternatives considered

- **A lock table keyed by WOPI lock id.** It duplicates the check-out lock
  and lets two lock systems disagree.
- **One handler per adapter.** The protocol is five routes over `Request`
  and `Response`; wrappers add nothing but surface to test.
- **Rely on the user's session cookie.** Editors call the host from their
  own servers, with no cookie, so a token is required.

## Consequences

The lock id is capped at 495 characters (WOPI allows 1024); longer ids get
`400`. `PutFile` buffers the body up to `maxBytes`. The host does not
implement `PutRelativeFile`, `RenameFile` or `DeleteFile`
(`SupportsUpdate` is true, the others are false).
