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

ip1=135.148.149.141
ip2=135.148.26.33
ip3=51.81.81.98
ipMe=135.148.149.141

/opt/etcd/etcd \
	--name hello0 \
 	--initial-advertise-peer-urls http://$ipMe:2380 \
 	--listen-peer-urls http://$ipMe:2380 \
 	--listen-client-urls http://$ipMe:2379,http://127.0.0.1:2379 \
 	--advertise-client-urls http://$ipMe:2379 \
 	--initial-cluster-token hello2 \
  	--initial-cluster hello0=http://$ip1:2380,hello1=http://$ip2:2380,hello2=http://$ip3:2380 \
 	--initial-cluster-state new \
	--data-dir /var/lib/etcd/
 
