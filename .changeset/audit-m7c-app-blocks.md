---
"better-supabase": minor
---

An app entity page in `gen.entityPages` can list the blocks whose screen it is with
`app: { blocks: ["deals", "pipelines"] }`. `pageCoverage` lists the page's route under each block,
so the app's coverage map no longer repeats it; a page without `blocks` writes no entry, as before.
`defineEntityPage` refuses a blank block name. Run `better-supabase gen` to rewrite
`pageCoverage`.
