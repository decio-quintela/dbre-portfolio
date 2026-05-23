# Runbook: High Replication Lag

**Severity:** P2 — High | **Response time:** 30 minutes

## Symptoms

- Grafana alert: replication lag > 30 seconds
- Replica returning stale data (reads behind primary)
- PostgreSQL log: `replication terminated by primary server`

## Diagnosis

```sql
-- Check replication lag on primary
SELECT client_addr,
       application_name,
       state,
       pg_size_pretty(pg_wal_lsn_diff(pg_current_wal_lsn(), sent_lsn))  AS sent_lag,
       pg_size_pretty(pg_wal_lsn_diff(pg_current_wal_lsn(), replay_lsn)) AS replay_lag,
       write_lag,
       flush_lag,
       replay_lag AS time_lag
FROM pg_stat_replication;

-- Check replication slots (WAL accumulation risk)
SELECT slot_name, active, pg_size_pretty(
       pg_wal_lsn_diff(pg_current_wal_lsn(), restart_lsn)) AS retained_wal
FROM pg_replication_slots;
```

```bash
# Check network between primary and replica
ping <replica-ip>

# Check disk I/O on replica (replica may be struggling to apply WAL)
iostat -x 1 5
```

## Resolution

1. Check if replica process is running:
```bash
sudo systemctl status postgresql
```

2. Check replica logs for errors:
```bash
tail -100 /var/log/postgresql/postgresql-*.log | grep -i error
```

3. If