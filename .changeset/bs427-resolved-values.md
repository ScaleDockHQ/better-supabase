---
"better-supabase": minor
---

Make doctor BS427 compare resolved values. A provider value written with another key order, another order of `active` values, other white space or another case in an unquoted SQL template is now reported as restated, and `codemod config --prune` removes it. A `blocks.permissions.activeTenant` of `"resolver"` (the default) is reported too. The BS409 message now names the provider's `tokenHook.activeOrganizationFrom`, and the docs say `"resolver"` means the request.
