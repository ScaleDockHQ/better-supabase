---
"better-supabase": minor
---

`leave`, `qualifications`, `donations` and `expenses` can restore what they
archive, and record the change. Each new method needs the permission its
`archive*` twin needs.

| Block            | Archive           | New restore       | Events                                                   |
| ---------------- | ----------------- | ----------------- | -------------------------------------------------------- |
| `leave`          | `archiveType`     | `restoreType`     | `leave_type.archived`, `leave_type.restored`             |
| `qualifications` | `archiveType`     | `restoreType`     | `qualification_type.restored` (archived existed)         |
| `donations`      | `archiveFund`     | `restoreFund`     | `donation_fund.archived`, `donation_fund.restored`       |
| `expenses`       | `archiveCategory` | `restoreCategory` | `expense_category.archived`, `expense_category.restored` |

Run `better-supabase upgrade` and apply the migration. The SQL functions are
`restore_leave_type`, `restore_qualification_type`, `restore_donation_fund`
and `restore_expense_category`.
