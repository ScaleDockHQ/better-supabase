---
"better-supabase": minor
---

`better-supabase/ai-sdk` keeps the AI SDK 7 tool fields when it converts messages, and the canonical AI message format moves to version 2 (`schemas/ai-message-v2.json`, `SPEC_PINS.aiMessage` is `"2"`). Version 1 messages stay valid and `ai-message-v1.json` stays published.

| Part            | New field                                                                     | AI SDK 7 field                                                                               |
| --------------- | ----------------------------------------------------------------------------- | -------------------------------------------------------------------------------------------- |
| `tool-call`     | `dynamic`, `title`, `toolMetadata`, `rawInput`, `inputEncoding`, `state`      | `dynamic-tool` part, `title`, `toolMetadata`, `rawInput`, `inputEncoding`, `input-streaming` |
| `tool-result`   | `preliminary`                                                                 | `preliminary`                                                                                |
| `tool-approval` | `signature`, `isAutomatic`, `requestReason`, `descriptor`, `inputSchemaInput` | the same names on `approval`                                                                 |

A call the SDK reported as dynamic now comes back from `toUIMessage` as a `dynamic-tool` part instead of `tool-<name>`, and an `input-streaming` call comes back as `input-streaming` instead of `input-available`. `toUIMessage`, `toUIMessages`, `fromUIMessage`, `validUIMessages` and `UIMessageSchemas` take your `UIMessage` type as a type argument.
