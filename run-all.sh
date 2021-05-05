#!/usr/bin/bash

ansible-playbook -i postgres-ha proxmox.yaml --forks=4 \
  && ansible-playbook -i postgres-ha cluster.yaml --forks=4 \
  && ansible-playbook -i postgres-ha postgres.yaml --forks=2
