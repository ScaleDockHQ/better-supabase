---
"better-supabase": minor
---

`createChain` from `better-supabase/blocks/audit` verifies, checkpoints and builds proofs for any table tagged `chain`. `verifyChainProof` checks one row against its signed checkpoint on WebCrypto alone, and `evidenceBundle` and `verifyEvidenceBundle` seal and check a record's proofs and other sections. The audit module gains `chain_heads`, `list_chain_checkpoints` and `chain_proof`; no migration step.
