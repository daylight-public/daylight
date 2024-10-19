#! /usr/bin/env bash

mkdir -p /home/ubuntu/.ssh/
chmod 700 /home/ubuntu/.ssh/
touch /home/ubuntu/.ssh/authorized_keys
chmod 600 /home/ubuntu/.ssh/authorized_keys
cat /home/ubuntu/.ssh/ubuntu.pem.pub >> /home/ubuntu/.ssh/authorized_keys
chown -R ubuntu:ubuntu /home/ubuntu/
systemctl restart ssh
