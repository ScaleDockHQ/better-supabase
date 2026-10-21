---
"better-supabase": minor
---

Structured, non-throwing design APIs, a provider-neutral OAuth subpath, deploy records and a doctor rule for dropped library functions. See [From 0.11 to 0.12](https://bettersupabase.com/docs/migration/0.11-to-0.12).

- `parseDesign`, `decodeDesign`, `designFileSource` and `readDesignFile` in `better-supabase/preset` throw a `DesignParseError` with a stable `code` and a JSON Pointer `path`. `safeParseDesign` and `safeDesignFileSource` return `{ ok: false, issues }` instead of throwing. `DesignTooLongError` is a `DesignParseError` with the code `too_long`.
- `DesignIssue` from `checkDesign` gains `code` and `path`, and a successful `DesignCheck` gains `fitsUrl`.
- `designSchema` is `parseDesign` as a Standard Schema, and `schemas/design-v1.json` publishes the design as JSON Schema.
- `DEFAULT_PRESET_NAME`, `defaultPreset()` and `defaultPresetCode()` name the preset Create and `init` start from.
- `better-supabase/create/oauth` holds PKCE, sealed cookies and an `OAuthSession` shape for any OAuth provider. `seal` and `unseal` take an optional HKDF `info`. `better-supabase/create/supabase` re-exports them, and `SupabaseSession` and `isSession` stay as aliases.
- `newDeployId()`, `deployQuery(files, { id })` and `DeployRecord` in `better-supabase/create` let a host app match a project to the preset it deployed. `DeployResponse` gains `id`, `preset` and `design`.
- Doctor's BS235 warns when an unapplied migration drops a `better_supabase` function without creating it again with the same number of arguments, as a schema diff did for `audit()` in 0.11.
