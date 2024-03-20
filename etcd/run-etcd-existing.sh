#! /usr/bin/env bash

# /opt/etcd/etcd \
# 	--name hello1 \
#  	--initial-advertise-peer-urls http://135.148.26.33:2380 \
#  	--listen-peer-urls http://135.148.26.33:2380 \
#  	--listen-client-urls http://135.148.26.33:2379,http://127.0.0.1:2379 \
#  	--advertise-client-urls http://135.148.26.33:2379 \
#  	--initial-cluster-token hello \
#  	--initial-cluster hello1=http://135.148.26.33:2380,hello0=http://158.69.25.215:2380 \
#  	--initial-cluster-state existing
 
/opt/etcd/etcd \
	--name hello1 \
 	--initial-advertise-peer-urls http://135.148.26.33:2380 \
 	--listen-peer-urls http://135.148.26.33:2380 \
 	--listen-client-urls http://135.148.26.33:2379,http://127.0.0.1:2379 \
 	--advertise-client-urls http://135.148.26.33:2379 \
 	--initial-cluster-token hello2 \
  	--initial-cluster hello1=http://135.148.26.33:2380,hello0=http://158.69.25.215:2380 \
 	--initial-cluster-state existing \
	--data-dir /var/lib/etcd
 
