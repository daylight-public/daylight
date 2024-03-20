#! /usr/bin/env bash

discoverySrv=hello.dylt.dev
ip=51.81.81.98
name=hello2

/opt/etcd/etcd \
    --name "$name" \
    --discovery-srv "$discoverySrv" \
 	--initial-advertise-peer-urls http://$ip:2380 \
 	--initial-cluster-token hello \
 	--initial-cluster-state new \
 	--advertise-client-urls http://$ip:2379 \
 	--listen-client-urls http://$ip:2379,http://127.0.0.1:2379 \
 	--listen-peer-urls http://$ip:2380 \
	--data-dir /var/lib/etcd/
 
