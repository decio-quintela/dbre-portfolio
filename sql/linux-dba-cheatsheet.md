# Linux Cheatsheet for DBA

Quick reference for day-to-day PostgreSQL operations on Linux.

---

## CPU Incident Flow

**Symptom:** High CPU on database server

```bash
# Step 1 — Find which postgres process is consuming CPU
docker exec pg-lab ps aux --sort=-%cpu | grep postgres

# Step 2 — Identify the query in PostgreSQL
docker exec -it pg-lab psql -U postgres -c "
SELECT pid, state,
       ROUND(EXTRACT(EPOCH FROM (NOW()-query_start))::numeric,1) AS seconds,
       LEFT(query, 60) AS query
FROM pg_stat_activity
WHERE state != 'idle'
ORDER BY query_start;"

# Step 3 — Cancel the offending query (use PID from above)
docker exec -it pg-lab psql -U postgres -c "
SELECT pg_cancel_backend(<PID>);"

# Step 4 — Confirm it's gone
docker exec -it pg-lab psql -U postgres -c "
SELECT pid, state FROM pg_stat_activity WHERE state != 'idle';"
```

---

## Process Commands

| Command | When to use |
|---|---|
| `ps aux \| grep postgres` | See all PG processes |
| `ps aux --sort=-%cpu \| grep postgres` | Find highest CPU consumer |
| `ps aux --sort=-%mem \| grep postgres` | Find highest memory consumer |
| `pstree -p $(pgrep postgres \| head -1)` | See process hierarchy |

---

## Real-time Monitoring

| Command | When to use |
|---|---|
| `top -u postgres` | Live monitor — all postgres processes |
| `htop -u postgres` | Visual live monitor |
| `top -b -n 1 -u postgres > /tmp/snapshot.txt` | Save snapshot for incident report |

---

## Service Control (native install)

| Command | When to use |
|---|---|
| `systemctl status postgresql` | First command in any incident |
| `systemctl reload postgresql` | Apply postgresql.conf — no downtime |
| `systemctl restart postgresql` | Full restart — brief downtime |
| `journalctl -u postgresql -f` | Watch live logs |

---

## Docker Lab Commands

| Command | When to use |
|---|---|
| `docker exec pg-lab ps aux \| grep postgres` | See PG processes inside container |
| `docker exec -it pg-lab psql -U postgres` | Connect to PG inside container |
| `docker stats pg-lab` | CPU and memory of the container |

---

## Key PostgreSQL Views

```sql
-- All active queries with duration
SELECT pid, usename, state,
       ROUND(EXTRACT(EPOCH FROM (NOW()-query_start))::numeric,1) AS seconds,
       query
FROM pg_stat_activity
WHERE state != 'idle'
ORDER BY seconds DESC;

-- Who is blocking who
SELECT blocked.pid, blocked.query, blocking.pid AS blocking_pid, blocking.query
FROM pg_stat_activity blocked
JOIN pg_stat_activity blocking
  ON blocking.pid = ANY(pg_blocking_pids(blocked.pid));
```

---

## Kill — Signals for PostgreSQL

| Signal | Command | Effect on PostgreSQL |
|---|---|---|
| SIGINT (2) | `kill -2 <PID>` | Cancel current query — keep connection |
| SIGTERM (15) | `kill -15 <PID>` | Graceful shutdown of backend |
| SIGKILL (9) | `kill -9 <PID>` | Force kill — NEVER use on postmaster |

**Always prefer SQL when possible:**
- Cancel query: `SELECT pg_cancel_backend(PID);`
- End connection: `SELECT pg_terminate_backend(PID);`

**Find PID before killing:**
```bash
ps aux --sort=-%cpu | grep postgres   # highest CPU first
pgrep -x postgres | head -1           # postmaster PID — never kill this
ps -p <PID> -f                        # confirm what a PID is
```

---

*Updated as I learn — part of [dbre-portfolio](https://github.com/decio-quintela/dbre-portfolio)*