#! /usr/bin env bash -x

apt update -y || echo "command failed"
echo "MEAT 1"
apt upgrade -y </dev/null || echo "command failed"
echo "MEAT 2"
adduser --shell /bin/bash --uid 1000 --disabled-password --gecos -'' ubuntu || echo "command failed"
echo "MEAT 3"
adduser ubuntu sudo || echo "command failed"
echo "MEAT 4"
chown -R ubuntu:ubuntu /home/ubuntu/ || echo "command failed"
echo "MEAT 5"
systemctl restart ssh || echo "command failed"
echo "MEAT 6"
timedatectl set-timezone America/Chicago || echo "command failed"
echo "MEAT 7"
hostnamectl hostname ionos-vps2 || echo "command failed"
echo "MEAT 8"
reboot
