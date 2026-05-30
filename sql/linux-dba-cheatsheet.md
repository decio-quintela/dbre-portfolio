# Linux DBA Cheatsheet
> Quick reference for PostgreSQL database administration on Linux.
> Environment: Ubuntu 22.04 · PostgreSQL 16 · Vagrant VM (192.168.56.10)

---

## 1. Emergency Response — First Commands in Any Incident

```bash
# Step 1 — CPU: who is consuming?
top -u postgres

# Step 2 — Disk: full or slow?
df -h
iostat -x 1 3

# Step 3 — Network: port open? too many connections?
ss -tulnp | grep 5432

# Step 4 — Logs: what did PostgreSQL record?
tail -50 /var/log/postgresql/*.log | grep -i error
```

> Rule: always run these 4 steps before doing anything else.
> Takes 60 seconds and eliminates 80% of possibilities.

---

## 2. Process Management — ps, top, htop, kill

### ps — process snapshot
```bash
ps aux | grep postgres                   # see all PG processes
ps aux --sort=-%cpu | grep postgres      # highest CPU first
ps aux --sort=-%mem | grep postgres      # highest memory first
ps aux --sort=-rss | grep postgres       # highest real RAM usage (RSS)
ps axjf | grep -A 20 "postgres -D"      # process tree: postmaster → children
ps -p <PID> -f                          # confirm what a PID is — ALWAYS before kill
ps aux | grep "postgres:.*\[" | wc -l   # count open connections
```

### STAT field — process state
| State | Meaning | DBA context |
|---|---|---|
| `R` | Running — executing on CPU | Backend with R = active query |
| `S` | Sleeping — waiting for event | Normal for idle backends |
| `D` | Uninterruptible sleep — waiting for disk I/O | Many in D = disk is bottleneck |
| `Z` | Zombie — finished but parent didn't read exit code | Indicates bug in PostgreSQL |

### VSZ vs RSS
- **VSZ** = virtual memory reserved — unrealistic, kernel lazy allocation
- **RSS** = real physical RAM used — this is the number that matters

### top — live monitor
```bash
top -u postgres              # filtered for postgres user
top -d 1 -u postgres         # update every 1 second
top -b -n 1 -u postgres > /tmp/snapshot-$(date +%H%M).txt  # save snapshot
```

| Key | Action inside top |
|---|---|
| `P` | Sort by CPU |
| `M` | Sort by memory |
| `1` | Show each CPU core separately |
| `k` | Kill a process |
| `q` | Quit |

### top header — what to watch
| Field | Alert threshold |
|---|---|
| load average | If load / number of CPUs > 1.0 for 5+ minutes = saturated |
| `wa` (I/O wait) | Above 10% = disk is bottleneck. Above 30% = critical |
| `id` (idle) | Below 20% = immediate attention needed |
| `st` (stolen) | Above 5% in cloud = instance throttled |

### htop — visual monitor
```bash
sudo apt install htop -y
htop -u postgres
```

| Key | Action inside htop |
|---|---|
| `F5` | Tree mode — see postmaster → children |
| `F6` | Sort by column (choose PERCENT_CPU) |
| `F9` | Kill process — choose signal |
| `F4` | Filter by process name |
| `q` | Quit |

### Memory bar colors in htop
| Color | Meaning |
|---|---|
| Green | Used by processes — watch if reaches 90% without blue |
| Blue | Kernel buffer/cache — can be freed, not a problem |
| Yellow | Swap in use — any swap in PostgreSQL = latency spikes |

### kill — sending signals
```bash
# Always prefer SQL when possible
sudo -u postgres psql -c "SELECT pg_cancel_backend(<PID>);"    # 1st choice
sudo -u postgres psql -c "SELECT pg_terminate_backend(<PID>);" # 2nd choice
kill -2 <PID>    # SIGINT  — cancel query, keep connection
kill -15 <PID>   # SIGTERM — graceful shutdown of backend
kill -9 <PID>    # SIGKILL — NEVER use on postmaster
```

| Signal | Number | PostgreSQL behavior | SQL equivalent |
|---|---|---|---|
| SIGINT | 2 | Cancels current query. Connection stays open. | `pg_cancel_backend(pid)` |
| SIGTERM | 15 | Ends backend gracefully with rollback. | `pg_terminate_backend(pid)` |
| SIGHUP | 1 | Reloads postgresql.conf without restart. | `pg_reload_conf()` |
| SIGKILL | 9 | Kernel kills immediately — no cleanup. NEVER on postmaster. | None |

> **Warning:** SIGKILL on postmaster kills all child backends instantly,
> without checkpoint. Next startup requires crash recovery from WAL.

### CPU incident flow
```bash
# 1. Find process with high CPU
ps aux --sort=-%cpu | grep postgres | head -5

# 2. Confirm it is a backend, not the postmaster
ps -p <PID> -f
# Must show: postgres: user dbname SELECT — not the postmaster

# 3. Identify the query
sudo -u postgres psql -c "
SELECT pid,
  ROUND(EXTRACT(EPOCH FROM NOW()-query_start)::numeric,1) AS seconds,
  LEFT(query, 60) AS query
FROM pg_stat_activity
WHERE state != 'idle'
ORDER BY query_start;"

# 4. Cancel
sudo -u postgres psql -c "SELECT pg_cancel_backend(<PID>);"

# 5. Confirm resolved
ps aux --sort=-%cpu | grep postgres | head -5
```

---

## 3. Disk & I/O — df, du, iostat, iotop

```bash
# Check disk usage
df -h                                              # all partitions
df -h /var/lib/postgresql                          # PostgreSQL partition only

# Find what is consuming space
du -sh /var/lib/postgresql/* | sort -rh | head -10 # largest directories
du -sh /var/lib/postgresql/16/main/pg_wal/         # WAL files size
du -sh /var/log/postgresql/                        # log files size

# I/O performance
sudo apt install sysstat -y
iostat -x 1 5                                      # I/O per device every 1 second

# Which process is using disk
sudo apt install iotop -y
sudo iotop -o                                      # only processes with active I/O
```

| iostat field | Alert threshold |
|---|---|
| `%util` | Near 100% = disk saturated |
| `await` | Above 20ms (HDD) or 5ms (SSD) = slow disk |
| `w/s` high | Many writes = checkpoint or heavy vacuum |

---

## 4. Network & Ports — ss, netstat, curl

```bash
# Check if port 5432 is open and listening
ss -tulnp | grep 5432

# Count open connections to PostgreSQL
ss -tnp | grep 5432 | wc -l

# Test port without psql
curl -v telnet://192.168.56.10:5432

# Test server reachability
ping -c 4 192.168.56.10

# Check if pg_hba.conf is blocking connections
sudo tail -20 /var/log/postgresql/*.log | grep -i "authentication\|connection"
```

---

## 5. Logs & Text — tail, grep, awk

```bash
# Follow log in real time
tail -f /var/log/postgresql/postgresql-16-main.log
tail -100 /var/log/postgresql/postgresql-16-main.log

# Filter critical errors
grep -i "error\|fatal\|panic" /var/log/postgresql/*.log

# Find slow queries (requires log_min_duration_statement)
grep "duration:" /var/log/postgresql/*.log | sort -t: -k3 -rn | head -20

# Filter by specific hour
grep "^2025-05-24 14:" /var/log/postgresql/*.log

# Count errors by type
grep "ERROR" /var/log/postgresql/*.log \
  | awk '{print $NF}' | sort | uniq -c | sort -rn | head -10

# Enable slow query logging
sudo -u postgres psql -c "
ALTER SYSTEM SET log_min_duration_statement = 1000;
ALTER SYSTEM SET log_line_prefix = '%t [%p] %u@%d ';
SELECT pg_reload_conf();"
```

---

## 6. Service Control — systemctl, journalctl

```bash
# Check service status — first command in any incident
systemctl status postgresql

# Control the service
sudo systemctl start postgresql
sudo systemctl stop postgresql
sudo systemctl restart postgresql      # brief downtime
sudo systemctl reload postgresql       # no downtime — reloads config

# Enable auto-start on reboot
sudo systemctl enable postgresql

# Logs via systemd
sudo journalctl -u postgresql -f          # follow live
sudo journalctl -u postgresql -n 50       # last 50 lines
sudo journalctl -u postgresql --since "2025-05-24 14:00"  # specific period
```

---

## 7. Terminal & Bash — shortcuts, history, sudo

### Essential shortcuts
| Shortcut | What it does |
|---|---|
| `Ctrl+R` | Interactive history search |
| `Ctrl+C` | Cancel running command |
| `Ctrl+L` | Clear screen |
| `Ctrl+A` | Move cursor to beginning of line |
| `Ctrl+E` | Move cursor to end of line |
| `TAB` | Autocomplete |
| `!!` | Repeat last command |
| `sudo !!` | Repeat last command with sudo |

### Help and documentation
| Command | What it does |
|---|---|
| `man ps` | Full manual. Navigate with arrows, search with `/`, quit with `q` |
| `tldr ps` | Practical examples — faster than man |
| `type ls` | Shows if command is built-in, alias or executable |
| `apropos process` | Search commands by keyword |

### Bash history
```bash
history | grep postgres    # find postgres commands in history
history | tail -20         # last 20 commands
# Ctrl+R → type "postgres" → Enter to execute
```

### sudo and postgres user
```bash
sudo -u postgres psql -c "SELECT version();"  # run as postgres without switching
sudo su - postgres                             # fully switch to postgres user
sudo -l                                        # list what current user can do with sudo
whoami                                         # show current user
id                                             # show user, UID, GID and groups
```

---

## 8. Key PostgreSQL Views — queries for diagnosis

```sql
-- All active queries with duration
SELECT pid, usename, state,
  ROUND(EXTRACT(EPOCH FROM NOW()-query_start)::numeric,1) AS seconds,
  LEFT(query, 60) AS query
FROM pg_stat_activity
WHERE state != 'idle'
ORDER BY seconds DESC;

-- Who is blocking who
SELECT
  blocked.pid        AS blocked_pid,
  blocked.query      AS blocked_query,
  blocking.pid       AS blocking_pid,
  blocking.query     AS blocking_query
FROM pg_stat_activity blocked
JOIN pg_stat_activity blocking
  ON blocking.pid = ANY(pg_blocking_pids(blocked.pid));

-- Database sizes
SELECT datname,
  pg_size_pretty(pg_database_size(datname)) AS size
FROM pg_database
ORDER BY pg_database_size(datname) DESC;

-- Largest tables
SELECT schemaname, tablename,
  pg_size_pretty(pg_total_relation_size(schemaname||'.'||tablename)) AS total_size
FROM information_schema.tables
WHERE table_schema NOT IN ('pg_catalog','information_schema')
ORDER BY pg_total_relation_size(schemaname||'.'||tablename) DESC
LIMIT 10;

-- Current connections vs limit
SELECT count(*) AS active,
  (SELECT setting::int FROM pg_settings WHERE name='max_connections') AS max,
  count(*) * 100 /
  (SELECT setting::int FROM pg_settings WHERE name='max_connections') AS pct_used
FROM pg_stat_activity;
```

---

*Last updated: 2025 | github.com/decio-quintela/dbre-portfolio*