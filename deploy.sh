#!/usr/bin/env bash

### Dependency checker

# check for curl 

if ! curl --version >/dev/null 2>&1; then
  echo "curl not found"
  exit 1
fi

# check for ansible

if ! ansible --version >/dev/null 2>&1; then
  echo "Ansible not found"
  echo "To install Ansible goto http://docs.ansible.com/ansible/intro_installation.html"
  exit 1
fi

# check for vagrant

if ! vagrant --version >/dev/null 2>&1; then
  echo "Vagrant not found"
  echo "To install Vagrant goto http://www.vagrantup.com/downloads"
  exit 1
fi

# check for openssl

if ! openssl version >/dev/null 2>&1; then
  echo "Openssl not found, which is required for file hash validation"
  exit 1
fi

# vagrant file exist and file hash validation to make sure nothing changed

echo "Checking if Vagrantfile exist"
if ! test -f Vagrantfile; then
  echo "Vagrantfile is missing"
  exit 1
fi

VF_HASH=$(cat Vagrantfile | openssl md5)

echo "Checking if Vagrantfile has correct hash"
if [ ! $VF_HASH = "4927d149435c40e8aae3b8d8a7f6cdec" ]; then
  echo "Something has changed with Vagrantfile. Halting operations"
  exit 1
fi

### Provision VM on vagrant

echo "Provisioning VM on vagrant"
if ! vagrant up; then
  echo "Vagrant provisioning failed."
else
  echo "Provisioning completed."
fi

### Validate VM
# set ansible host checking to false
export ANSIBLE_HOST_KEY_CHECKING=False

# set variables for ansible
SSH_KEY=$(vagrant ssh-config | grep IdentityFile | awk '{print $2}')
USER=$(vagrant ssh-config | grep -w User | awk '{print $2}')
IP=$(vagrant ssh-config | grep HostName | awk '{print $2}')
PORT=$(vagrant ssh-config | grep Port | awk '{print $2}')
TMP=`mktemp`
# create temp host file for ansible
echo "
[localhost]
${IP}:${PORT}
" > $TMP

### Start deployment & testing

# Pre-testing
# ping VM
echo "Start Infrastructure Test"
echo "Ping VM using ansible ping module"
ansible localhost --user=${USER} --private-key=${SSH_KEY} -i $TMP -m ping

# check if docker is started
echo "Validating Docker Daemon is started"
ansible localhost --user=${USER} --private-key=${SSH_KEY} -i $TMP -m service -a "name=docker state=started"

# Deployment 
# deploy docker container dbhakta/testapp:latest
echo "Deploying docker container dbhakta/testapp:latest"
ansible localhost --user=${USER} --private-key=${SSH_KEY} -i $TMP -m command -a "docker run -d --name testapp -p 8080:80 dbhakta/testapp:latest" -s

# Post testing
# check docker image dbhakta/testapp:latest history
echo "Checking if dbhakta/testapp image exist"
ansible localhost --user=${USER} --private-key=${SSH_KEY} -i $TMP -m command -a "docker history dbhakta/testapp:latest" -s

# check if docker container is started
echo "Checking if dbhakta/testapp docker container is running"
ansible localhost --user=${USER} --private-key=${SSH_KEY} -i $TMP -m command -a "docker ps -f name=testapp" -s

# check docker ports are set
echo "Checking docker port configuration"
ansible localhost --user=${USER} --private-key=${SSH_KEY} -i $TMP -m command -a "docker port testapp" -s

# check webpage output on curl
echo "Smoketesting webpage response"
ansible localhost --user=${USER} --private-key=${SSH_KEY} -i $TMP -m command -a "curl -sX GET http://localhost:8080" -s

# check web app logs from test
echo "Checking logs"
ansible localhost --user=${USER} --private-key=${SSH_KEY} -i $TMP -m command -a "docker logs testapp" -s

# smoketest outside VM for status code 200
echo "Checking webpage outside VM"
SMOKE=$(curl -Is http://${IP}:8080 | grep HTTP/1.1 | awk '{print $2}')
if [ $SMOKE = 200 ]; then
  echo "Smoketest passed"
else
  echo "Smoketest to http://${IP}:8080 failed"
  exit 1
fi

echo -e ".\n.\n.\n"

# echo browser URL to user
echo "Browse to http://${IP}:8080"

