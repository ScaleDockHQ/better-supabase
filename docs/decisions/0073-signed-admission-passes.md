# 0073: Admission passes carry a signed token; the database keeps the nonce

- Status: accepted
- Date: 2026-10-22

## Context

Bookings had seats and capacity but nothing to show at the door. Events,
gyms, venues and visitor desks need a code a phone or a card can carry: a QR
code or an NFC tag. A random code alone works only online and says nothing
about who holds it; a signed token can be read offline, but a token alone
can't be revoked or used up. Signing per ADR 0033 runs in TypeScript with
WebCrypto and the private key never leaves Vault, so the SQL module can't
sign.

## Decision

The `passes` module stores each pass with a random `nonce` and logs every
scan. The client signs a compact JWS with the signing-keys block
(`typ: vnd.pass+jwt`), carrying the pass id as `sub` and the nonce as `jti`,
with an `exp` no later than the pass's end or 30 days. A scanner verifies the
signature and `exp` against the published JWKS, then calls `check_in_pass`
with the id and nonce. The database decides admission under a row lock: the
nonce, status, validity window, uses, the booking's state and check-in window,
and for a pass without a booking the resource's capacity, counting confirmed
bookings, live holds and drop-ins under an advisory lock per resource. Each
scan writes a `pass_check_ins` row and a `pass.admitted` or `pass.rejected`
event without an audit entry.

The nonce is stored as is, not hashed, so a pass can be re-signed whenever its
holder opens a wallet; only the holder and managers read it through
`get_pass` and `my_passes`. The block ships no QR or NFC library: the token is
a string, and the app renders it.

## Consequences

- A forged or expired token never reaches the database; a revoked or used-up
  pass is turned away even with a valid signature.
- Rotating a signing key doesn't strand tokens: `exp` keeps the retired key
  in the JWKS until the last token expires.
- Fully offline admission is out of scope: a scanner can read the claims
  without a connection, but only the database spends a use or counts a seat.
- The signature is checked in the scanner, not in SQL: `check_in_pass` trusts
  a caller with `passes.check_in`, who can check a holder in manually anyway.
- A leaked token admits until it is used, expires or the pass is revoked.
