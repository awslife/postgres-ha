#!/usr/bin/bash

ansible-playbook -i postgres-ha proxmox.yaml --forks=3 \
  && ansible-playbook -i postgres-ha cluster.yaml --forks=3 \
  && ansible-playbook -i postgres-ha postgres.yaml --forks=3 \
  && ansible-playbook -i postgres-ha pgpool.yaml
