# 0709: Name the fields and the words of a block error

- Status: accepted
- Date: 2026-11-12

## Context

A block error carried a `hint` code and a message, and nothing a form could
place next to a field. The example's "Check the highlighted fields" sentence
hid the broken rule in EX-803, EX-806, EX-809 and EX-913 (EX-1235). The hint
catalog had codes and no messages, so the app wrote `use-error-message.ts`
with one sentence per error kind (EX-1236). Only ten blocks mention a locale
and block error messages are English, with no way to carry the user's locale
into the block context (EX-1317).

## Decision

`invalid_input` errors get an optional `fields: [{ path, code, message }]`.
`invalidInput(message, fields)` builds one in TypeScript, and a SQL check
raises the same list as JSON in the `DETAIL` of an `22xxx` error, which
`mapDbError` reads. `toProblem` and `fromProblem` carry `fields` as an
extension member, so the Problem Details body keeps them.

`pnpm catalog` generates `src/blocks/messages/hint-messages.generated.ts`
from the block SQL: one default English message per hint code, taken from
the message the SQL raises the code with, or the code in words when that
message has a placeholder or the code comes from a client. The new
`better-supabase/blocks/messages` entry exports it as `BLOCK_HINT_MESSAGES`
(the code is the next-intl key) with `hintMessage`, `blockErrorMessage` and
`fieldMessages`. It is a separate entry because the table is about 110 KB.

`BlockOptions` gets `locale` and `hintMessages`. `createBlocks` adds a last error
mapper that rewords the message of an error raised in SQL through `hintMessages`
and never changes its `kind`, `hint` or `status`. `better-supabase/react`
gets `ErrorMessagesProvider` and `useErrorMessage`, so the example's
`use-error-message.ts` is gone and its translated kind sentences live in one
provider.

The client field codes are also hint codes, so the generator reads `code:
"UPPER_CASE"` literals from block clients next to `hint:` ones.

## Alternatives considered

- Put the messages in `better-supabase/blocks`: every consumer of the entry
  would carry 110 KB of text.
- Rewrite every block's TypeScript errors with the locale: 226 call sites for
  a result the mapper gives for SQL errors; TypeScript errors keep English and
  `blockErrorMessage` words them.
- Generate one catalog per locale: the library has no translations to ship, so
  it ships the default and the key.

## Consequences

Forms can show a message per field, and apps translate block errors by code
with one namespace. Only the tags block fills `fields` today; the other
blocks adopt `invalidInput` as their input checks move to it. The hint
catalog grew by the codes the clients raise. A message with a placeholder is
the code in words until its SQL names the value.
