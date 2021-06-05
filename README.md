# PostgreSQL 13 Streaming Replication with PGPool 4.2

최근 많이 사용되는 PostgreSQL Database의 Streaming Replication 구성 방법에 대해서 정리해보았다. 9버전에서 도입된 Streaming Replication 구성 방법이 13에서는 조금 달리 설정되어야 하지만 구글에서 검색되는 자료의 대부분이 9버전 기준으로 정리된게 많았고 잘못된 구성은 나중에 어떤 문제가 생길지 모르기 때문에 13 버전에 최적화된 설정을 찾기 위해 읽어보았던 내용을 중심으로 정리하였다.

모든 구성은 PostgreSQL 13과 Pgpool-II 4.2에서 테스트되었다.

## prerequisite

- [Proxmox](https://www.proxmox.com/en/) 
- [Ansible](https://www.ansible.com/)
- Virtual Machine X 3ea

## PostgreSQL 13 HA Architecture

PostgreSQL HA 구성은 [Reference](#Reference)의 Pgpool-II + Watchdog Setup Example를 참고하여 구성하였다.
전체 구성은 아래 이미지와 같다.
![Cluster System Configuration](https://www.pgpool.net/docs/42/en/html/cluster_40.gif "Cluster System Configuration")

## PostgreSQL Cluster Configuration Variables

### Hostname and IP address

| Hostname | IP Address | Virtual IP Address |
|:-:|:-:|:-:|
| postgres1 | 10.0.0.181 |  |
| postgres2 | 10.0.0.182 | 10.0.0.180 |
| postgres3 | 10.0.0.183 |  |

### PostgreSQL version and Configuration

| Item | Value | Detail |
|:-|:-:|:-:|
| PostgreSQL | 13 |  |
| Port | 5432 |  |
| $PGDATA | /data1/pgsql/13/data |  |
| Archive mode | On | |
| Replication Slots | Enable | - |
| Start automatically | Enable | - |

### Pgpool-II version and Configuration

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

## PostgreSQL 설치

### Installation

PostgreSQL 설치는 rpm을 사용하여 설치하였다. 설치전에 PostgreSQL Repository를 연결해주도록 하자.

```bash
# yum install -y https://download.postgresql.org/pub/repos/yum/reporpms/EL-7-x86_64/pgdg-redhat-repo-latest.noarch.rpm
# yum install -y postgresql13-server
```

### 방화벽 등록

PostgreSQL Port를 방화벽에 등록한다.

```bash
# firewall-cmd --add-service=postgresql --permanent
# firewall-cmd --reload
```

### PostgreSQL 초기화

PostgreSQL 서버를 초기화한다. PGDATA 경로를 변경하고 싶다면 반드시 초기화 전에 PGDATA 경로 생성하고 PGSETUP_INITDB_OPTIONS 환경 변수에 설정할 경로를 지정한다. PGDATA 경로를 기본값으로 사용하고 싶다면 3번째 명령만 실행하면 된다.

```bash
# mkdir -p /data1/pgsql/13/data && chown -R postgres:postgres /data1/pgsql/13
# export PGSETUP_INITDB_OPTIONS="-D /data1/pgsql/13/data"
# /usr/pgsql-13/bin/postgresql-13-setup initdb
```

### PostgreSQL 서비스 경로 변경 (Optional)

PostgreSQL 초기화가 완료되면 service 파일에서 PostgreSQL 설치 경로를 변경한다. (위에서 PGDATA 경로를 변경하지 않았다면 서비스 경로 변경은 해주지 않아도 된다.) systemdctl을 사용한 postgresql 시작/종료는 PGPool에서의 시작과 종료와 충돌이 발생할 염려가 있으므로 가능하다면 Postgresql 시작/종료는 pg_ctl 명령을 사용하여 시작 또는 종료하도록 하자.

```bash
# sed -i 's/^Environment=PGDATA=\/var\/lib\/pgsql\/13\/data\//Environment=PGDATA=\/data1\/pgsql\/13\/data\//g' /usr/lib/systemd/system/postgresql-13.service
```

### PostgreSQL 설정값 변경

Streaming Replication을 위한 설정값을 변경해주도록 한다. PGDATA 경로의 postgresql.conf 파일에서 아래 설정값을 찾아서 변경해주도록 하자. (자세한 내용은 PostgreSQL 홈페이지를 참조하자.)

- listen_address 값을 '*'로 변경하여 호스트에 할당된 모든 아이피로 서비스 가능하도록 변경하자.
- archive_mode 값을 on으로 변경하여 archive 모드를 활성화 하자.
- archive_command 값을 'cp %p /data1/pgsql/13/archive/%f'로 설정하자. (PGDATA를 변경하지 않았다면 /var/lib/pgsql/에서 archive 경로를 확인하여 입력하자.)
- max_wal_sender 값을 10으로 설정하자.
- max_replication_slots 값을 10으로 설정하자.
- wal_level 값을 replica로 설정하자.
- hot_standby 값을 on으로 설정하자.
- wal_log_hints 값을 on으로 설정하자.
- autovacuum 값을 on으로 설정하자. (autovacuum 값을 옵션이며 성능과 기능을 확인 후 설정하도록 하자.)

### PostgreSQL 시작

PostgreSQL 설정이 완료되면 pg_ctl 명령으로 PostgreSQL을 시작한다.

```bash
# pg_ctl -D /data1/pgsql/13/data start
```

### PostgreSQL 사용자 생성

postgres 사용자 패스워드 변경 및 HA 구성에 필요한 필수 사용자를 생성하고 초기화 한다.

```bash
# psql -c "SET password_encryption = 'scram-sha-256'; ALTER USER postgres WITH PASSWORD 'ChangeMe';"
# psql -c "SET password_encryption = 'scram-sha-256'; DROP ROLE IF EXISTS repl; CREATE ROLE repl WITH REPLICATION LOGIN PASSWORD 'ChangeMe';"
# psql -c "SET password_encryption = 'scram-sha-256'; DROP ROLE IF EXISTS pgpool; CREATE ROLE pgpool WITH LOGIN PASSWORD 'ChangeMe';"
```

### 추가 권한 수정

HA 구성에 필요한 권한을 수정한다.

```bash
# psql -c "GRANT pg_monitor TO pgpool;"
```

### PostgreSQL 접속 관리

PostgreSQL 접속 관리를 위해 pg_hba.conf 파일을 수정한다. pg_hba.conf 파일에 아래 내용을 추가 한다.

```ini
host    all            all     samenet    scram-sha-256
host    replication    all     samenet    scram-sha-256
```

### Config Reload

변경된 PostgreSQL 설정 적용을 위해 환경을 다시 읽어들이도록 한다.

```bash
# psql -c "SELECT pg_reload_conf();"
```

### pgpass 파일 생성

접속 편의를 위해 .pgpass 파일을 생성하고 접속 정보를 입력한다.

```ini
postgres1:5432:replication:repl:ChangeMe
postgres1:5432:postgres:postgres:ChangeMe
postgres1:5432:postgres:pgpool:ChangeMe
postgres2:5432:replication:repl:ChangeMe
postgres2:5432:postgres:postgres:ChangeMe
postgres2:5432:postgres:pgpool:ChangeMe
postgres3:5432:replication:repl:ChangeMe
postgres3:5432:postgres:postgres:ChangeMe
postgres3:5432:postgres:pgpool:ChangeMe
```

### Backup 수행

대기 서버에서 베이스 백업을 수행하여 마스터 서버의 데이터를 복제한다. 백업은 마스터 서버를 제외한 대기 서버 2대에서 각각 실행하도록 한다.

postgres2 서버
```bash
# pg_basebackup -h postgres1 -D /data1/pgsql/13/data -U repl -P -v -R -X stream -C -S postgres2
```

postgres3 서버
```bash
# pg_basebackup -h postgres1 -D /data1/pgsql/13/data -U repl -P -v -R -X stream -C -S postgres3
```

### PostgreSQL 서비스 시작

대기 서버에서 백업이 정상적으로 수행되었으면 pg_ctl 명령을 이용하여 서비스를 시작한다.

postgres2 서버
```bash
# pg_ctl -D /data1/pgsql/13/data start
```

postgres3 서버
```bash
# pg_ctl -D /data1/pgsql/13/data start
```

## PGPool 구성

PGPool은 Connection Pooling와 Automated fail over를 제공하는 소프트웨어로 Postgres에서는 PGBouncer와 PGPool을 많이 사용한다. PGBouncer는 성능이 우수하지만 자체적으로 watchdog 같은 HA를 제공해주지 않아 해당 기능을 위해 추가 구성을 해야한다. 이에 반해 PGPool은 PGBouncer에 비해 성능은 떨어지지만 HA와 Active-Standby(Active-Readonly)를 제공해 주어 해당 DB의 요구 사항에 따라 2개의 소프트웨어를 골라 구성하면 된다. Meta Database 구성이 필요하여 PGPool을 선택하여 구성하는 방법을 정리하였다.

### PGPool 설치

PGPool 설치를 위해서 pgpool repository 관련 rpm 패키지를 설치한다. 패키지는 아래의 주소에서 다운로드 가능하며 yum 명령으로 바로 설치 가능하다.

- https://download.postgresql.org/pub/repos/yum/reporpms/EL-7-x86_64/pgdg-redhat-repo-latest.noarch.rpm
- https://www.pgpool.net/yum/rpms/4.2/redhat/rhel-7-x86_64/pgpool-II-release-4.2-1.noarch.rpm

yum으로 PGPool 관련 repository가 구성 완료되었으면 pgpool과 pgpool-extension 패키지를 설치한다.

- pgpool-II-pg13
- pgpool-II-pg13-extensions

### PGPool 방화벽 설정

PGPool에서는 총 4개의 포트를 사용한다. 각각의 포트는 아래와 같다. firewall-cmd 명령으로 아래 4개 포트를 영구적으로 오픈하도록 하자.

- 9999/tcp
- 9898/tcp
- 9000/tcp
- 9694/tcp

### ssh key 생성 및 key 복사

PGPool 관련 명령은 script에서 ssh를 이용하여 remote 명령을 수행하므로 패스워드 입력 없이 원격 명령 수행이 필요하다. 이를 위해서는 사전에 key 생성과 접속하려는 서버에 key 복제가 이루어져 있어야 한다. key 생성 및 key 복사는 모든 서버에서 실행한다.

```bash
# ssh-keygen -q -t rsa -N '' -f $HOME/.ssh/id_rsa_pgpool
# ssh-copy-id -o StrictHostKeyChecking=no \
    -i $HOME/.ssh/id_rsa_pgpool \
    -f postgres@postgres1
# ssh-copy-id -o StrictHostKeyChecking=no \
    -i $HOME/.ssh/id_rsa_pgpool \
    -f postgres@postgres2
# ssh-copy-id -o StrictHostKeyChecking=no \
    -i $HOME/.ssh/id_rsa_pgpool \
    -f postgres@postgres3
```

### PGPool node id 설정

pgpool의 node id를 설정한다. 각각의 서버에 id를 순서대로 지정한다.

postgres1
```bash
# echo "0" > /etc/pgpool-II/pgpool_node_id
```

postgres2
```bash
# echo "1" > /etc/pgpool-II/pgpool_node_id
```

postgres3
```bash
# echo "2" > /etc/pgpool-II/pgpool_node_id
```

### backend connection 설정

PGPool에서 PostgreSQL 서버 Health 체크를 위한 설정을 진행한다. 설정은 /etc/pgpool-II/pgpool.conf 파일에 설정하며 3대 모두 동일한 설정이 이루어져야 한다.

```ini
backend_hostname0 = postgres1
backend_port0 = 5432
backend_weight0 = 1
backend_data_directory0 = /data1/pgsql/13/data
backend_flag0 = 'ALLOW_TO_FAILOVER'
backend_application_name0 = postgres1

backend_hostname1 = postgres2
backend_port1 = 5432
backend_weight1 = 1
backend_data_directory1 = /data1/pgsql/13/data
backend_flag1 = 'ALLOW_TO_FAILOVER'
backend_application_name1 = postgres2

backend_hostname2 = postgres3
backend_port2 = 5432
backend_weight2 = 1
backend_data_directory2 = /data1/pgsql/13/data
backend_flag2 = 'ALLOW_TO_FAILOVER'
backend_application_name2 = postgres3
```

### failover shell 설정

failover를 위한 sample shell을 복사 후 세부 설정을 진행한다.

```bash
# cp /etc/pgpool-II/failover.sh{.sample,}
# cp /etc/pgpool-II/follow_primary.sh{.sample,}
```

### pgpool password 설정

pgpool 접속시 사용할 패스워드를 설정한다.

```bash
# echo "localhost:9898:pgpool:ChangeMe" >> $HOME/.pcppass
# echo "10.0.0.180:9898:pgpool:ChangeMe" >> $HOME/.pcppass
```

### online recovery 설정

online recovery shell 파일을 복사 후 세부 설정을 진행한다.

```bash
# cp /etc/pgpool-II/recovery_1st_stage.sample /data1/pgsql/13/data/recovery_1st_stage
# cp /etc/pgpool-II/pgpool_remote_start.sample /data1/pgsql/13/data/pgpool_remote_start
```

recovery_1st_stage 파일에서 ARCHIVEDIR 디렉토리를 변경된 archivedir로 지정한다.
ex) /var/lib/pgsql/archivedir --> /data1/pgsql/13/archive

### recovery extension 생성

postgres에서 pgpool_recovery extension을 생성한다. extension은 master 서버에서만 수행하면 된다.

```bash
# psql template1 -c "CREATE EXTENSION pgpool_recovery"
```

### PGPool 접속을 위한 pool_hba.conf 설정

PGPool 접속 제한을 위한 pool_hba.conf 설정을 진행한다. /etc/pgpool-II/pool_hba.conf 파일을 수정하면 된다.

```init
host    all            pgpool                         0.0.0.0/0    scram-sha-256
host    all            postgres                       0.0.0.0/0    scram-sha-256
```

### PGPool pass 설정

PGPool 접속시 사용할 계정의 패스워드를 설정한다.

```bash
# rm -f /etc/pgpool-II/pool_passwd && touch /etc/pgpool-II/pool_passwd
# echo "postgres:`pg_md5 ChangeMe`" >> /etc/pgpool-II/pool_passwd
# echo "pgpool:`pg_md5 ChangeMe`" >> /etc/pgpool-II/pool_passwd
```

### Watchdog 설정

watchdog 설정을 진행한다. 3대 모두 동일한 설정으로 구성한다.

```ini
hostname0 = postgres1
wd_port0 = 9000
pgpool_port0 = 9999
hostname1 = postgres2
wd_port1 = 9000
pgpool_port1 = 9999
hostname2 = postgres3
wd_port2 = 9000
pgpool_port2 = 9999
```

### Heartbeat 설정

Heartbeat 설정을 진행한다. 3대 모두 동일한 설정으로 구성한다.

```ini
heartbeat_hostname0 = postgres1
heartbeat_port0 = 9694
heartbeat_device0 = ''
heartbeat_hostname1 = postgres2
heartbeat_port1 = 9694
heartbeat_device1 = ''
heartbeat_hostname2 = postgres3
heartbeat_port2 = 9694
heartbeat_device2 = ''
```

### escalation 설정

escalation script을 복사 후 세부 설정을 진행한다. 3대 모두 동일한 설정으로 구성한다.

```bash
# cp -p /etc/pgpool-II/escalation.sh{.sample,}
# chown postgres:postgres /etc/pgpool-II/escalation.sh
```

- server1 server2 server3을 호스트 이름으로 변경한다.
- VIP=192.168.137.150을 VIP=10.0.0.180 (VIP)로 변경한다.
- DEVICE=enp0s8을 실제 NIC ID로 변경한다.

### Log 설정

pgpool 로그 설정을 진행한다. /var/log/pgpool 디렉토리 생성 후 세부 설정을 진행한다.

```bash
# sudo mkdir -p /var/log/pgpool && sudo chown postgres:postgres /var/log/pgpool
```

- /etc/sysconfig/pgpool 파일의 OPTS=" -n" 항목을 OPTS=" -D -n"으로 변경한다.

### PGPool 서비스 시작

PGPool 구성이 완료되었으면 PGPool 서비스를 시작한다.

```bash
# sudo systemctl start pgpool
```

## Replication Test

### Check status of pool_nodes

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

### Stop primary node

```bash
[awslife@postgres2 ~]$ sudo su - postgres -c '/usr/pgsql-13/bin/pg_ctl -D /data1/pgsql/13/data -m immediate stop'
waiting for server to shut down.... done
server stopped
[awslife@postgres2 ~]$
```

### Check status of primary node

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

### Check watchdog

```bash
-bash-4.2$ pcp_watchdog_info -h 10.0.0.180 -p 9898 -U pgpool
Password:
3 YES postgres1:9999 Linux postgres1 postgres1

postgres1:9999 Linux postgres1 postgres1 9999 9000 4 LEADER
postgres2:9999 Linux postgres2 postgres2 9999 9000 7 STANDBY
postgres3:9999 Linux postgres3 postgres3 9999 9000 7 STANDBY
-bash-4.2$
```

### Check recovery status

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

### Recovery down node

```bash
-bash-4.2$ pcp_recovery_node -h 10.0.0.180 -p 9898 -U pgpool -n 1
Password:
pcp_recovery_node -- Command Successful
-bash-4.2$
```

### Check status of nodes

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

### Recovery down node

```bash
-bash-4.2$ pcp_recovery_node -v -h 10.0.0.180 -p 9898 -U pgpool -n 2
Password:
pcp_recovery_node -- Command Successful
-bash-4.2$
```

### Check status of nodes

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

## Reference

[Pgpool-II + Watchdog Setup Example](https://www.pgpool.net/docs/42/en/html/example-cluster.html)
