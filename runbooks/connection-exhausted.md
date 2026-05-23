# Runbook: Connection Pool Exhausted

**Severity:** P1 — Critical | **Response time:** 15 minutes

## Symptoms

- Application returning "too many connections" or "connection refused"
- Grafana alert: active connections > 90% of max_connections
- PostgreSQL log: `FATAL: remaining connection slots are reserved`

## Diagnosis

```sql
-- Current connections vs limit
SELECT count(*) AS active,
       max_conn,
       count(*) * 100 / max_conn AS pct_used
FROM pg_stat_activity,
     (SELECT setting::int AS max_conn
      FROM pg_settings WHERE name = 'max_connections') s
GROUP BY max_conn;

-- Who is consuming connections
SELECT usename, application_name, state, count(*)
FROM pg_stat_activity
GROUP BY usename, application_name, state
ORDER BY count(*) DESC;

-- Idle connections wasting slots
SELECT count(*) FROM pg_stat_activity
WHERE state = 'idle'
AND state_change < NOW() - INTERVAL '10 minutes';
```

## Resolution

1. Kill idle connections immediately:

```sql
SELECT pg_terminate_backend(pid)
FROM pg_stat_activity
WHERE state = 'idle'
AND state_change < NOW() - INTERVAL '5 minutes'
AND pid <> pg_backend_pid();
```

2. Check pgBouncer pool status (if installed):

```bash
psql -p 6432 -U pgbouncer pgbouncer -c "SHOW POOLS;"
```

3. Increase `max_connections` temporarily if still critical:

```bash
# Edit postgresql.conf
max_connections = 300
# Restart required — causes brief downtime
sudo systemctl restart postgresql
```

## Verification

```sql
SELECT count(*) FROM pg_stat_activity;
-- Should be well below max_connections
```

Application accepting new connections without errors.

## Prevention

- Install pgBouncer in transaction mode (see ha-cluster/README.md)
- Set Grafana alert at 80% of max_connections
- Add to postgresql.conf: `idle_in_transaction_session_timeout = '5min'`
- Review application connection pool settings (min/max pool size)

## Related runbooks

- [Disk Full](./disk-full.md)
- [Lock Contention](./lock-contention.md)
- [High Replication Lag](./high-replication-lag.md)