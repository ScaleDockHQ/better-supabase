---
"better-supabase": minor
---

Creating, posting and cancelling a payment batch now checks the banking block's `manage` key instead of `reconcile`, so a role that only reconciles bank transactions can no longer pay out supplier bills. Set `permissions.createBatch`, `permissions.postBatch` and `permissions.cancelBatch` to grant each operation to a key of your own, such as a finance role's. Run `better-supabase upgrade` to regenerate the banking module, and give the batch key to the roles that pay bills.
