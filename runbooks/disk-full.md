\# Runbook: PostgreSQL — Disk Full



Severity: P1 — Critical  |  Response time: 15 minutes  |  Last updated: 2025



\## Symptoms



\- Application returning 500 errors or "could not write to file" messages

\- Grafana alert: disk usage > 90%

\- PostgreSQL log: ERROR: could not extend file "base/...": No space left on device



\## Diagnosis



df -h — confirm which partition is full

du -sh /var/lib/postgresql/\* | sort -rh | head -10 — find biggest directory

Run biggest tables query in psql (see queries/disk-usage.sql)

SELECT \* FROM pgstattuple('schema.table') — check bloat percentage



\## Resolution (in order)



1\. Remove old log files older than 7 days: find pg\_log/ -mtime +7 -delete

2\. Run VACUUM VERBOSE schema.table on bloated table (no lock)

3\. If space still critical: run pg\_repack -t schema.table (no downtime)

4\. If table growing fast: implement retention policy (DELETE WHERE created\_at < NOW() - INTERVAL '90 days')



\## Verification



df -h — disk usage below 70%

SELECT pg\_size\_pretty(pg\_total\_relation\_size('schema.table')) — table size reduced

Application errors resolved



\## Prevention



\- Grafana alert at 80% disk usage (critical at 90%)

\- Tune autovacuum per table: autovacuum\_vacuum\_scale\_factor = 0.01

\- Implement table partitioning for high-growth tables

\- Set log retention policy: keep 7 days only



\## Related runbooks



→ Runbook: High Replication Lag

→ Runbook: Connection Pool Exhausted

→ Runbook: Long-Running Queries / Lock Contention

