# PostgreSQL 12 Streaming Replication with PGPool 4.2

최근 많이 사용되는 PostgreSQL Database의 Streaming Replication 구성 방법에 대해서 정리해보았다. 9 버전에서 도입된 Streaming Replication 구성 방법이 12에서는 조금 달리 설정되어야 하지만 구글에서 검색되는 자료의 대부분이 9버전 기준으로 정리된게 많았고 잘못된 구성은 나중에 어떤 문제가 생길지 모르기 때문에 12 버전에 최적화된 설정을 찾기 위해 읽어보았던 내용을 중심으로 정리하였다.

모든 구성은 PostgreSQL 12와 Pgpool-II 4.2에서 테스트되었다.

# prerequisite

- [Proxmox](https://www.proxmox.com/en/) 
- [Ansible](https://www.ansible.com/)
- Virtual Machine X 3ea

# PostgreSQL 12 HA Architecture

PostgreSQL HA 구성은 [Reference](#Reference)의 Pgpool-II + Watchdog Setup Example를 참고하여 구성하였다.
전체 구성은 아래 이미지와 같다.
![Cluster System Configuration](https://www.pgpool.net/docs/42/en/html/cluster_40.gif "Cluster System Configuration")

# PostgreSQL Cluster Configuration Variables

## Hostname and IP address

| Hostname | IP Address | Virtual IP Address |
|:-:|:-:|:-:|
| postgres1 | 10.0.0.181 |  |
| postgres2 | 10.0.0.182 | 10.0.0.180 |
| postgres3 | 10.0.0.183 |  |

## PostgreSQL version and Configuration

| Item | Value | Detail |
|:-|:-:|:-:|
| PostgreSQL | 12 |  |
| Port | 5432 |  |
| $PGDATA | /data1/pgsql/12/data |  |
| Archive mode | On | |
| Replication Slots | Enable | - |
| Start automatically | Enable | - |

## Pgpool-II version and Configuration

| Item | Value | Detail |
|:-|:-:|:-:|
| Pgpool-II Version | 4.2 |  |
| Port | 9999 | Pgpool-II accepts connections |
| | 9898 | PCP process accepts connections |
| | 9000 | watchdog accepts connections |
| | 9694 | UDP port for receiving Watchdog's heartbeat signal |
| Config file | /etc/pgpool-II/pgpool.conf | Pgpool-II config file |
| Pgpool-II start user | postgres (Pgpool-II 4.1 or later) | Pgpool-II 4.0 or before, the default startup user is root |
| Running mode | streaming replication mode | - |
| Watchdog | On | Life check method: heartbeat |
| Start | automatically Enable | - |

# Installation

## PostgreSQL 설치

PostgreSQL 설치는 rpm을 사용하여 설치하였다. 설치전에 PostgreSQL Repository를 연결해주도록 하자.

```bash
# yum install -y https://download.postgresql.org/pub/repos/yum/reporpms/EL-7-x86_64/pgdg-redhat-repo-latest.noarch.rpm
# yum install -y postgresql12-server
```

## 방화벽 등록

PostgreSQL Port를 방화벽에 등록한다.

```bash
# firewall-cmd --add-service=postgresql --permanent
# firewall-cmd --reload
```

## PostgreSQL 초기화

PostgreSQL 서버를 초기화한다. PGDATA 경로를 변경하고 싶다면 반드시 초기화 전에 PGDATA 경로 생성하고 PGSETUP_INITDB_OPTIONS 환경 변수에 설정할 경로를 지정한다. PGDATA 경로를 기본값으로 사용하고 싶다면 3번째 명령만 실행하면 된다.

```bash
# mkdir -p /data1/pgsql/12/data && chown -R postgres:postgres /data1/pgsql/12
# export PGSETUP_INITDB_OPTIONS="-D /data1/pgsql/12/data"
# /usr/pgsql-12/bin/postgresql-12-setup initdb
```

## PostgreSQL 서비스 경로 변경

PostgreSQL 초기화가 완료되면 service 파일에서 PostgreSQL 설치 경로를 변경합니다. (위에서 PGDATA 경로를 변경하지 않았다면 서비스 경로 변경은 해주지 않아도 된다.)

```bash
# sed -i 's/^Environment=PGDATA=\/var\/lib\/pgsql\/12\/data\//Environment=PGDATA=\/data1\/pgsql\/12\/data\//g' /usr/lib/systemd/system/postgresql-12.service
```

## PostgreSQL 설정값 변경

Streaming Replication을 위한 설정값을 변경해주도록 한다. PGDATA 경로의 postgresql.conf 파일에서 아래 설정값을 찾아서 변경해주도록 하자. (자세한 내용은 PostgreSQL 홈페이지를 참조하자.)

- listen_address 값을 '*'로 변경하여 호스트에 할당된 모든 아이피로 서비스 가능하도록 변경하자.
- archive_mode 값을 on으로 변경하여 archive 모드를 활성화 하자.
- archive_command 값을 'cp %p /data1/pgsql/12/archive/%f'로 설정하자. (PGDATA를 변경하지 않았다면 /var/lib/pgsql/에서 archive 경로를 확인하여 입력하자.)
- max_wal_sender 값을 10으로 설정하자.
- max_replication_slots 값을 10으로 설정하자.
- wal_level 값을 replica로 설정하자.
- hot_standby 값을 on으로 설정하자.
- wal_log_hints 값을 on으로 설정하자.
- autovacuum 값을 on으로 설정하자. (autovacuum 값을 옵션이며 성능과 기능을 확인 후 설정하도록 하자.)

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

# Reference

[Pgpool-II + Watchdog Setup Example](https://www.pgpool.net/docs/42/en/html/example-cluster.html)