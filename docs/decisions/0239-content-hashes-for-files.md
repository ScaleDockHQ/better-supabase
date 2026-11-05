# 0239: Hash file bytes on attachments and versions

- Status: accepted
- Date: 2026-11-05

## Context

An attachment row names a storage object, and a version row hashed its content
and the storage path. Neither proved which bytes were stored, so a file
replaced behind the same path left no trace.

## Decision

Attachments (module version 9) and their history gain `sha256` and
`hash_verified_at`. Only `set_attachment_status`, which the service role calls
from the scanner, sets them, and the scanner hashes the Blob it downloaded
with WebCrypto. Versions (module version 2) gain `file_hash` and
`hash_version`. `version_insert` and `snapshot_version` take `file_sha256`;
`snapshot_version` accepts it only from the service role. A version with a file
hash hashes its content and that hash (`hash_version` 2); older versions keep
the content and path formula (`hash_version` 1), so signatures over them still
verify.

## Alternatives considered

- Trusting a hash from the client. A user could then claim any bytes.
- Rehashing every version. It would change signed hashes.

## Consequences

`set_attachment_status`, `version_insert` and `snapshot_version` gain a
trailing argument, and the old signatures are dropped. Callers that do not
pass a hash keep working through the defaults.
