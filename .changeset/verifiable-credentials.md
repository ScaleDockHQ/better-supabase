---
"better-supabase": minor
---

New subpath `better-supabase/verifiable-credentials` issues SD-JWT VC and W3C VC 2.0 credentials
through the OpenID4VCI 1.0 pre-authorized code flow and verifies OpenID4VP 1.0 presentations
(`SPEC_PINS.openid4vci`, `SPEC_PINS.openid4vp`, `SPEC_PINS.sdJwt`, `SPEC_PINS.sdJwtVc`,
`SPEC_PINS.vcDataModel`). `createCredentialIssuer` takes sources (`qualificationSource`,
`courseCompletionSource`, `passSource`) and an `IssuanceStore`; `signerFromSigningKeys` signs with
the `signing-keys` block. `StatusList` revokes credentials as a Token Status List or a Bitstring
Status List. The `mfa` controllers gain `registerPasskey` and `verifyPasskey` over Supabase Auth's
WebAuthn support, and the `contacts` block gains vCard 4.0 import and export with `.vcf` download
helpers (`SPEC_PINS.rfc6350`, `SPEC_PINS.webauthn`).
