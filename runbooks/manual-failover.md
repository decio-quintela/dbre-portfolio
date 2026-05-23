# Runbook: Manual Failover (Patroni)

**Severity:** P1 — Critical | **Response time:** 15 minutes

## Symptoms

- Primary PostgreSQL server unresponsive or unreachable
- Grafana alert: primary down or replication lag infinite
- Application returning connection errors to write endpoint
- Patroni reporting primary as unhealthy

## Diagnosis

```bash
# Check Patroni cluster status (run on any node)
patronictl -c /etc/patroni/patroni.yml list

# Expected healthy output:
# + Cluster: postgres-cluster ----+----+-----------+
# | Member    | Host        | Role   | State   | TL |
# +-----------+-------------+--------+---------+----+
# | pg-node-1 | 10.0.0.1:5432 | Leader | running | 1  |
# | pg-node-2 | 10.0.0.2:5432 | Replica| running | 1  |

# Check Patroni service status on each node
sudo systemctl status patroni

# Check PostgreSQL is actually down on primary
sudo systemctl status postgresql

# Check Patroni logs for failure reason
sudo journalctl -u patroni -n 100 --no-pager
```

```sql
-- From a replica — check if primary is reachable
SELECT pg_is_in_recovery();
-- Returns TRUE if this node is a replica
-- Returns FALSE if this node is the primary
```

## Resolution

### Option A — Automatic failover already happened (Patroni did its job)

```bash
# Verify new leader was elected
patronictl -c /etc/patroni/patroni.yml list

# Update HAProxy or application connection string if needed
# The new primary should be serving writes automatically
```

### Option B — Trigger manual failover (primary is alive but degraded)

```bash
# Graceful switchover to a specific replica
patronictl -c /etc/patroni/patroni.yml switchover \
  --master pg-node-1 \
  --candidate pg-node-2 \
  --scheduled now

# Confirm new leader
patronictl -c /etc/patroni/patroni.yml list
```

### Option C — Force failover (primary completely unreachable)

```bash
# Failover without waiting for primary confirmation
patronictl -c /etc/patroni/patroni.yml failover \
  --master pg-node-1 \
  --candidate pg-node-2 \
  --force

# Confirm new leader
patronictl -c /etc/patroni/patroni.yml list
```

### Option D — Rejoin old primary after it recovers

```bash
# On the recovered old primary node
# Patroni will automatically rejoin as replica
sudo systemctl start patroni

# Verify it joined as replica (not primary)
patronictl -c /etc/patroni/patroni.yml list
```

## Verification

```bash
# Cluster should show one Leader and remaining nodes as Replica
patronictl -c /etc/patroni/patroni.yml list

# Test write on new primary
psql -h <new-primary-ip> -U postgres -c "SELECT pg_is_in_recovery();"
-- Must return: f (false = is primary)

# Test application connectivity
curl -f http://your-app/health
```

## Post-incident checklist

- [ ] Confirm all replicas are replicating from new primary
- [ ] Update monitoring dashboards with new primary IP if static
- [ ] Investigate root cause of original primary failure
- [ ] Document timeline in incident report
- [ ] Review and adjust Patroni TTL settings if failover was too slow

## Prevention

- Set Patroni `ttl: 30` and `loop_wait: 10` for faster failure detection
- Monitor with Grafana: alert when Patroni leader changes unexpectedly
- Test failover monthly in staging environment — `patronictl switchover`
- Ensure HAProxy or connection pooler auto-routes to new primary
- Keep all nodes on same PostgreSQL version and Patroni version

## Related runbooks

- [High Replication Lag](./high-replication-lag.md)
- [Connection Pool Exhausted](./connection-exhausted.md)
- [Disk Full](./disk-full.md)