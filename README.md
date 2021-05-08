# postgres-ha

Postgres-HA

# Replication Test

## Check status of pool_nodes

```bash
-bash-4.2$ psql -h 10.0.0.180 -p 9999 -U pgpool postgres -c "show pool_nodes"
Password for user pgpool:
 node_id | hostname  | port | status | lb_weight |  role   | select_cnt | load_balance_node | replication_delay | replication_state | replication_sync_state | last_status_change
---------+-----------+------+--------+-----------+---------+------------+-------------------+-------------------+-------------------+------------------------+---------------------
 0       | postgres1 | 5432 | up     | 0.333333  | standby | 0          | false             | 67108960          |                   |                        | 2021-05-08 23:25:28
 1       | postgres2 | 5432 | up     | 0.333333  | primary | 0          | true              | 0                 |                   |                        | 2021-05-08 23:24:15
 2       | postgres3 | 5432 | up     | 0.333333  | standby | 0          | false             | 96                |                   |                        | 2021-05-08 23:26:31
(3 rows)

-bash-4.2$
```

## Stop primary node

```bash
[awslife@postgres2 ~]$ sudo su - postgres -c '/usr/pgsql-12/bin/pg_ctl -D /data1/pgsql/12/data -m immediate stop'
waiting for server to shut down.... done
server stopped
[awslife@postgres2 ~]$
```

## Check status of primary node

```bash
-bash-4.2$ psql -h 10.0.0.180 -p 9999 -U pgpool postgres -c "show pool_nodes"
Password for user pgpool:
 node_id | hostname  | port | status | lb_weight |  role   | select_cnt | load_balance_node | replication_delay | replication_state | replication_sync_state | last_status_change
---------+-----------+------+--------+-----------+---------+------------+-------------------+-------------------+-------------------+------------------------+---------------------
 0       | postgres1 | 5432 | up     | 0.333333  | primary | 0          | true              | 0                 |                   |                        | 2021-05-08 23:29:21
 1       | postgres2 | 5432 | down   | 0.333333  | standby | 0          | false             | 0                 |                   |                        | 2021-05-08 23:29:21
 2       | postgres3 | 5432 | down   | 0.333333  | standby | 0          | false             | 96                |                   |                        | 2021-05-08 23:29:21
(3 rows)

-bash-4.2$
```

## Check watchdog

```bash
-bash-4.2$ pcp_watchdog_info -h 10.0.0.180 -p 9898 -U pgpool
Password:
3 YES postgres1:9999 Linux postgres1 postgres1

postgres1:9999 Linux postgres1 postgres1 9999 9000 4 LEADER
postgres2:9999 Linux postgres2 postgres2 9999 9000 7 STANDBY
postgres3:9999 Linux postgres3 postgres3 9999 9000 7 STANDBY
-bash-4.2$
```

## Check recovery status

```bash
-bash-4.2$ psql -h postgres1 -p 5432 -U pgpool postgres -c "select pg_is_in_recovery()"
 pg_is_in_recovery
-------------------
 f
(1 row)

-bash-4.2$ psql -h postgres2 -p 5432 -U pgpool postgres -c "select pg_is_in_recovery()"
psql: error: could not connect to server: Connection refused
	Is the server running on host "postgres2" (10.0.0.182) and accepting
	TCP/IP connections on port 5432?
-bash-4.2$ psql -h postgres3 -p 5432 -U pgpool postgres -c "select pg_is_in_recovery()"
 pg_is_in_recovery
-------------------
 t
(1 row)
```

## Recovery down node

```bash
-bash-4.2$ pcp_recovery_node -h 10.0.0.180 -p 9898 -U pgpool -n 1
Password:
pcp_recovery_node -- Command Successful
-bash-4.2$
```

## Check status of nodes

```bash
-bash-4.2$ psql -h 10.0.0.180 -p 9999 -U pgpool postgres -c "show pool_nodes"
Password for user pgpool:
 node_id | hostname  | port | status | lb_weight |  role   | select_cnt | load_balance_node | replication_delay | replication_state | replication_sync_state | last_status_change
---------+-----------+------+--------+-----------+---------+------------+-------------------+-------------------+-------------------+------------------------+---------------------
 0       | postgres1 | 5432 | up     | 0.333333  | primary | 0          | false             | 0                 |                   |                        | 2021-05-08 23:29:21
 1       | postgres2 | 5432 | up     | 0.333333  | standby | 0          | true              | 8096              |                   |                        | 2021-05-08 23:32:07
 2       | postgres3 | 5432 | down   | 0.333333  | standby | 0          | false             | 96                |                   |                        | 2021-05-08 23:29:21
(3 rows)

-bash-4.2$
```

## Recovery down node

```bash
-bash-4.2$ pcp_recovery_node -v -h 10.0.0.180 -p 9898 -U pgpool -n 2
Password:
pcp_recovery_node -- Command Successful
-bash-4.2$
```

## Check status of nodes

```bash
-bash-4.2$ psql -h 10.0.0.180 -p 9999 -U pgpool postgres -c "show pool_nodes"
Password for user pgpool:
 node_id | hostname  | port | status | lb_weight |  role   | select_cnt | load_balance_node | replication_delay | replication_state | replication_sync_state | last_status_change
---------+-----------+------+--------+-----------+---------+------------+-------------------+-------------------+-------------------+------------------------+---------------------
 0       | postgres1 | 5432 | up     | 0.333333  | primary | 0          | false             | 0                 |                   |                        | 2021-05-08 23:29:21
 1       | postgres2 | 5432 | up     | 0.333333  | standby | 0          | false             | 167772256         |                   |                        | 2021-05-08 23:32:07
 2       | postgres3 | 5432 | up     | 0.333333  | standby | 0          | true              | 0                 |                   |                        | 2021-05-08 23:34:12
(3 rows)

-bash-4.2$
```