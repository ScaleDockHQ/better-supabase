---
"better-supabase": minor
---

The generated data hooks and `RecordProvider` pause while the app is offline: reads keep their last data and show `offline` instead of an error, and writes wait for the connection. Wrap the app in `OfflineBoundary` from `better-supabase/next/offline` to feed them `useOffline()`. `createDataList`, `createDataOne` and `createRecordController` take an `offline` option and expose `setOffline`.

`powersync streams` keeps only the files of an app subject's rows when a view keeps one `subject_type`, and `gen.powersync.children` streams an app table with its parent subject, such as `job_parties` under `jobs`.
