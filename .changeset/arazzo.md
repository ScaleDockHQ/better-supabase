---
"better-supabase": minor
---

New `better-supabase/arazzo` subpath: `createArazzo` and `arazzoFormat` render Arazzo 1.0 and 1.1 workflows from the API model, with source descriptions that point at the OpenAPI and AsyncAPI files. `defineWorkflow` types each step by the `operationId` it calls, and `paginationWorkflows`, `createThenGetWorkflows` and `authWorkflow` build common workflows from your resources' operations.
