---
"better-supabase": minor
---

The `ai-files` SQL module and `createAiFiles` in `better-supabase/blocks/ai-files` store files for AI chats in a private Storage bucket: a two-step upload (`reserve_ai_file`, then `confirm_ai_file` after the client uploads to the signed URL), storage policies that follow the file row, generated files stored with the service role, cached provider file references with their expiry, and a purge of stale uploads, expired files and files of deleted chats. The module also adds versioned documents with optimistic concurrency, rollback and suggested edits.

`better-supabase/ai-sdk/files` connects the files to the AI SDK: `aiFileDownload` resolves `supabase-storage://` file parts as the caller for `experimental_download`, `saveGeneratedFiles` stores model output as file parts, and `providerFile` uploads a file to a provider once and reuses the reference.
