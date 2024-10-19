#! /usr/bin env bash -x

apt-get update -y || echo "command failed"
printf 'DONE - apt update (%d)\n' $?
apt-get upgrade -y || echo "command failed"
printf 'DONE - apt upgrade (%d)\n' $?
