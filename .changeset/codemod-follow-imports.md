---
"better-supabase": patch
---

Let `codemod prune`, `declared-rows`, `adopt-names` and `extra-columns` edit config values that the config imports from other files when `typescript` 7.1 or newer is installed, and list those files for review. Import merging in the account calls codemod uses one shared helper.
