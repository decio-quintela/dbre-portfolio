# Runbook: Lock Contention

**Severity:** P1 — Critical | **Response time:** 15 minutes

## Symptoms

- Application hanging or timing out on writes
- Grafana alert: long-running transactions > 5 minutes
- PostgreSQL log: `ERROR: deadlock detected`
- Users reporting slow or frozen application

## Diagnosis

```sql
-- Find all blocked queries and who is blocking them
SELECT
    blocked.pid                AS blocked_pid,
    blocked.usename            AS blocked_user,
    blocked.query              AS blocked_query,
    blocked.state              AS blocked_state,
    blocking.pid               AS blocking_pid,
    blocking.usename           AS blocking_user,
    blocking.query             AS blocking_query,
    NOW() - blocked.query_start AS blocked_duration
FROM pg_stat_activity blocked
JOIN pg_stat_activity blocking
    ON blocking.pid = ANY(pg_blocking_pids(blocked.pid))
WHERE cardinality(pg_blocking_pids(blocked.pid)) > 0
ORDER BY blocked_duration DESC;

-- Find long-running transactions (potential lock holders)
SELECT pid, usename, state,
       NOW() - query_start AS duration,
       query
FROM pg_stat_activity
WHERE state != 'idle'
AND query_start < NOW() - INTERVAL '2 minutes'
ORDER BY duration DESC;

-- Show all active locks
SELECT relation::regclass, mode, granted, pid
FROM pg_locks
WHERE relation IS NOT NULL
ORDER BY relation, granted;
```

## Resolution

1. Identify the blocking PID from the diagnosis query above

2. Check what the blocking query is doing — is it safe to kill?
```sql
SELECT pid, query, state, usename
FROM pg_stat_activity
WHERE pid = <blocking_pid>;
```

3. Cancel the blocking query (soft kill — lets transaction rollback cleanly):
```sql
SELECT pg_cancel_backend(<blocking_pid>);
```

4. If cancel does not work after 30 seconds, force terminate:
```sql
SELECT pg_terminate_backend(<blocking_pid>);
```

5. Verify all blocked queries resumed:
```sql
SELECT count(*) FROM pg_stat_activity
WHERE cardinality(pg_blocking_pids(pid)) > 0;
-- Should return 0
```

## Verification

- Blocked queries count returns to 0
- Application responding normally
- No new deadlock errors in PostgreSQL log:
```bash
tail -50 /var/log/postgresql/postgresql-*.log | grep -i deadlock
```

## Prevention

- Set `lock_timeout = '30s'` in postgresql.conf (queries fail fast instead of hanging)
- Set `idle_in_transaction_session_timeout = '5min'` (kills forgotten open transactions)
- Set Grafana alert: transactions running > 5 minutes
- Review application code for missing COMMIT or long-held transactions
- Avoid DDL operations (ALTER TABLE, CREATE INDEX) during peak hours
- Use `CREATE INDEX CONCURRENTLY` to avoid table locks

## Related runbooks

- [Connection Pool Exhausted](./connection-exhausted.md)
- [Manual Failover (Patroni)](./manual-failover.md)