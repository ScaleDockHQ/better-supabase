# 0184: Courses verify LTI 1.3 launches, write xAPI statements and export unsigned Open Badges

- Status: accepted
- Date: 2026-11-01

## Context

Courses connect to learning platforms (LTI 1.3), learning record stores (xAPI) and credential wallets (Open Badges 3.0). None of it needs a table, so SQL that cannot be checked without the local stack is unnecessary.

## Decision

`better-supabase/blocks/courses` gains three TypeScript modules: `verifyLtiLaunch` (RS256 `id_token` checks returning a `Result` with `LTI_*` hints), `xapiStatement` with `sendXapiStatements` (account actors, validated IRIs, UUIDs and scores), and `openBadgeCredential` with `courseCertificateBadge`. The pins `lti`, `xapi` and `openBadges` are in `SPEC_PINS`. This work is based on `main`, not on `feat/verifiable-credentials` (PR #682), so the badge has no `proof`; a `signer` callback adds one, and `better-supabase/verifiable-credentials` can be wired in once it ships. ADR numbers 0182 and 0183 are used by both #681 and #682, so this track starts at 0184; the two PRs need one of them renumbered.

## Alternatives considered

Basing on the verifiable credentials branch (rejected: it would stack this PR on an unmerged one). A signing implementation here (rejected: it duplicates #682). A new subpath (rejected: the helpers belong to the block).

## Consequences

Badges are usable as JSON now and become verifiable credentials through the `signer`. LTI Advantage services (grades, names and roles) and dynamic registration are not covered.
