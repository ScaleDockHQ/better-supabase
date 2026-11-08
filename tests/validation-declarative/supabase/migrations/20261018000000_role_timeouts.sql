-- Role settings a schema diff skips. A Data API client that leaves a
-- transaction open holds its locks until this ends it (doctor BS224). Plain
-- statements, because a do block makes the migration history unreadable to the
-- coverage rules of doctor (BS376, BS377).
alter role anon set idle_in_transaction_session_timeout = '60s';
alter role authenticated set idle_in_transaction_session_timeout = '60s';
