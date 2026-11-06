---
"better-supabase": minor
---

The last 15 exported types that ended in `Args`, `Settings` or `Failure` have names from their noun, with no alias. `better-supabase codemod naming` renames them in your code.

| Old               | New                 |
| ----------------- | ------------------- |
| `ActionArgs`      | `ActionParams`      |
| `Args`            | `CallParams`        |
| `AuthFailure`     | `AuthLinkError`     |
| `BlockActionArgs` | `BlockActionParams` |
| `CliArgs`         | `CliValues`         |
| `CursorPageArgs`  | `CursorPageParams`  |
| `DoctorArgs`      | `DoctorValues`      |
| `HookArgs`        | `HookParams`        |
| `ListArgs`        | `ListParams`        |
| `ReactRouterArgs` | `ReactRouterParams` |
| `RequestArgs`     | `ApiRequestParams`  |
| `RpcArgs`         | `RpcParams`         |
| `SearchArgs`      | `TextSearchParams`  |
| `Settings`        | `SettingsClient`    |
| `TableArgs`       | `TableValues`       |
