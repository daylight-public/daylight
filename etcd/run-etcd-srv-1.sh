#! /usr/bin/env bash

ip0=135.148.149.141
ip1=135.148.26.33
ip2=51.81.81.98
ipMe=$ip1
name=hello1

/opt/etcd/etcd \
        --name "$name" \
        --discovery-srv hello.dylt.dev \
 	--initial-advertise-peer-urls http://$ipMe:2380 \
 	--initial-cluster-token hello \
 	--initial-cluster-state new \
 	--advertise-client-urls http://$ipMe:2379 \
 	--listen-client-urls http://$ipMe:2379,http://127.0.0.1:2379 \
 	--listen-peer-urls http://$ipMe:2380 \
	--data-dir /var/lib/etcd/
 
