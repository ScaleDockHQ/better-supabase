---
"better-supabase": minor
---

Pages the admin blocks by the block list contract (ADR 1077). `option-sets`
gains `setPage` and `getSet`, `impersonation` gains `sessionPage` and
`getSession`, `consents` gains `purposePage` and `getPurpose`, `compliance`
gains `frameworkPage`, `evidenceTaskPage` and `policyPage` with a `get` for
each, `data-lifecycle` gains `subjectRequestPage` and `getSubjectRequest`, and
`sequences` gains `enrollmentPage` and `getEnrollment`, each with facets and a
count. Every list takes sorts, array filters and a keyset cursor, `q` where the
entity searches text, and a `get` for an unknown id returns a `not_found`
error. The SQL adds `page_option_sets`, `get_option_set`,
`page_support_sessions`, `get_support_session`, `page_consent_purposes`,
`get_consent_purpose`, `page_control_frameworks`, `get_control_framework`,
`page_evidence_tasks`, `get_evidence_task`, `page_compliance_policies`,
`get_compliance_policy`, `page_data_subject_requests`,
`get_data_subject_request`, `page_sequence_enrollments` and
`get_sequence_enrollment`, and the generated schema files need `better-supabase
upgrade`. The array methods keep working and are deprecated. Entity lists can
now omit the tenant, which the platform-wide `impersonation` list uses.

| Old                                 | New                                |
| ----------------------------------- | ---------------------------------- |
| `optionSets.list`                   | `optionSets.setPage`               |
| `impersonation.list`                | `impersonation.sessionPage`        |
| `consents.purposes`                 | `consents.purposePage`             |
| `compliance.frameworks`             | `compliance.frameworkPage`         |
| `compliance.evidenceTasks`          | `compliance.evidenceTaskPage`      |
| `compliance.policies`               | `compliance.policyPage`            |
| `dataLifecycle.dataSubjectRequests` | `dataLifecycle.subjectRequestPage` |
| `sequences.enrollments`             | `sequences.enrollmentPage`         |
