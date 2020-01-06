#!/bin/bash

export SCRIPT_PATH="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"
export PYTHON_BIN=/usr/bin/python
export ANSIBLE_CONFIG=$SCRIPT_PATH/ansible.cfg

cd $SCRIPT_PATH

VAR_HOST="$1"
VAR_MYSQL_VERSION="$2"

### Ping host ####
ansible -i $SCRIPT_PATH/hosts -m ping $VAR_HOST -v

### mysql install ####
ansible-playbook -v -i $SCRIPT_PATH/hosts -e "{mysql_version: '$VAR_MYSQL_VERSION'}" $SCRIPT_PATH/playbook/mysql_install.yml -l $VAR_HOST