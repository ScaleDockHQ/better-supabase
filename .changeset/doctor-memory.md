---
"better-supabase": patch
---

`doctor` runs within a 2 GB heap again on a project with a long migration history. It reads the migrations as code tokens one file at a time instead of keeping them all, reads SQL files one after another, keeps fewer scanned and parsed texts, and only parses the app sources that call `kept`. A cached result that `doctor` found at the start no longer fails the run with "The SQL reader has not read this text yet" when a later write drops it from the cache file.
