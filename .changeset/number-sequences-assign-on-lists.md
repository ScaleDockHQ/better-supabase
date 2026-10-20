---
"better-supabase": minor
---

`number-sequences` accepts `in` and `not in` lists of string or number literals in `assignOn`, such as `new.status in ('sent', 'overdue')`, which its comma ban refused. A comma anywhere else outside a quoted string is still refused, and so is an unterminated quote, which could only fail at migration time.
