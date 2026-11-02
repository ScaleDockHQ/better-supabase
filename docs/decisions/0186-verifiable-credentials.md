# 0186: Verifiable credentials are a pure TypeScript subpath over a store port

- Status: accepted
- Date: 2026-11-01

## Context

The `qualifications`, `courses` and `passes` blocks record facts a person may
want to carry to another party: a certificate, a completed course, an
admission. Wallets exchange such facts as verifiable credentials. The contacts
block had no card export, and the mfa block offered only TOTP and phone factors
although Supabase Auth now supports WebAuthn.

## Decision

`better-supabase/verifiable-credentials` is a subpath with no tables and no
runtime dependency. It issues SD-JWT VC (RFC 9901, `dc+sd-jwt`) and W3C VC 2.0
(`vc+jwt`) credentials through the OpenID4VCI 1.0 pre-authorized code flow,
revokes them with Token Status List and Bitstring Status List, and verifies
OpenID4VP 1.0 responses. All crypto uses WebCrypto and the existing JWS helpers.
Keys come from the `signing-keys` block through `signerFromSigningKeys`, which
refuses to sign if the key rotated after the header was built.

Sources (`qualificationSource`, `courseCompletionSource`, `passSource`) are
lookup functions the app supplies, so the subpath does not import the blocks.
Offers, tokens, nonces and status indexes live behind an `IssuanceStore` port,
with an in-memory store for tests. A pre-authorized code is burned before its
transaction code is checked, and a grant is given back when a proof or the
signing fails.

The mfa controllers gain `registerPasskey` and `verifyPasskey` over
`auth.mfa.webauthn`, and answer `MFA_PASSKEYS_UNSUPPORTED` when the client has
none. The contacts block gains vCard 4.0 (RFC 6350) writers, a parser that never
throws, and `.vcf` download helpers. Both are TypeScript only.

Pinned in `SPEC_PINS`: OpenID4VCI 1.0, OpenID4VP 1.0, RFC 9901, SD-JWT VC
draft-19, Token Status List draft-21, VC Data Model 2.0, Bitstring Status List
1.0, WebAuthn Level 3 and RFC 6350.

## Consequences

- An app can issue and verify credentials today by implementing `IssuanceStore`
  over a table of its own.
- The Postgres-backed `verifiable-credentials` block (tables, RLS, events and
  permissions) is deferred, because its SQL needs the local stack to verify. The
  store port is its seam.
- Drafts (SD-JWT VC, Token Status List) can change; the pins and the conformance
  tests show what moved when they are bumped.
- mdoc, JSON-LD data integrity proofs and the authorization code flow are not
  supported.
