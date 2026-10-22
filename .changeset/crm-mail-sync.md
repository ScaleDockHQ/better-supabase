---
"better-supabase": minor
---

Add the `mail-sync` block (`better-supabase/blocks/mail-sync`). Members connect their own Gmail or Outlook mailbox, and `syncDue()` pulls new mail on a cron: each thread lands as an `email` engagement on the people whose addresses appear in it and, with `matchDomains`, on the companies whose domain matches. `threadsOf(record)` lists a record's mail, `send()` sends a new message or a reply and stores it on its thread, and a private mailbox stays visible only to its owner.

`gmailMail()` and `outlookMail()` call the Gmail API and Microsoft Graph over `fetch`, so no SDK is needed. Another host implements `MailProvider` (`apiVersion: 1`). Tokens come from your `CredentialProvider`, such as `vercelConnectCredentials()`, asked for the mailbox owner, and the block never stores one. The block adds the `mail.read`, `mail.connect`, `mail.send` and `mail.manage` permissions and the `mail_account.connected`, `mail_account.disconnected`, `mail_message.received` and `mail_message.sent` events. Deleting a member's data purges their mailboxes and revokes the credential reference.
