\# Runbook: Connection Pool Exhausted



\*\*Severity:\*\* P1 — Critical | \*\*Response time:\*\* 15 minutes



\## Symptoms

\- Application returning "too many connections" or "connection refused"

\- Grafana alert: active connections > 90% of max\_connections

\- PostgreSQL log: `FATAL: remaining connection slots are reserved`



\## Diagnosis

```sql

\-- Check current connections vs limit

SELECT count(\*) AS total,

&#x20;      max\_conn,

&#x20;      count(\*) \* 100 / max\_conn AS pct\_used

FROM pg\_stat\_activity,

&#x20;    (SELECT setting::int AS max\_conn FROM pg\_settings

&#x20;     WHERE name = 'max\_connections') s

GROUP BY max\_conn;



\-- Find who is consuming connections

SELECT usename, application\_name, state, count(\*)

FROM pg\_stat\_activity

GROUP BY usename, application\_name, state

ORDER BY count(\*) DESC;



\-- Find idle connections wasting slots

SELECT count(\*) FROM pg\_stat\_activity

WHERE state = 'idle'

AND state\_change < NOW() - INTERVAL '10 minutes';

```



\## Resolution

1\. Kill idle connections immediately:

```sql

SELECT pg\_terminate\_backend(pid)

FROM pg\_stat\_activity

WHERE state = 'idle'

AND state\_change < NOW() - INTERVAL '5 minutes'

AND pid <> pg\_backend\_pid();

```

2\. If pgBouncer is installed, check pool status:

```bash

psql -p 6432 -U pgbouncer pgbouncer -c "SHOW POOLS;"

```

3\. If pgBouncer is NOT installed — install it (see ha-cluster/README.md)

4\. Increase `max\_connections` temporarily if critical (requires restart):

```bash

\# Edit postgresql.conf

max\_connections = 300   # increase from current value

\# Then restart (causes brief downtime)

sudo systemctl restart postgresql

```



\## Verification

```sql

SELECT count(\*) FROM pg\_stat\_activity;

\-- Should be well below max\_connections

```

Application errors resolved and new connections accepted.



\## Prevention

\- Install and configure pgBouncer in transaction mode

\- Set Grafana alert at 80% of max\_connections

\- Set `idle\_in\_transaction\_session\_timeout = '5min'` in postgresql.conf

\- Review application connection pool settings (min/max pool size)



\## Related runbooks

→ \[Disk Full](./disk-full.md)

→ \[Lock Contention](./lock-contention.md)

