#!/usr/bin/env bash

ansible-playbook -i postgres-ha proxmox.yaml -t 'stop'
