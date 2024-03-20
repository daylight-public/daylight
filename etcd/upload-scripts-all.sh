#! /usr/bin/env bash

main ()
{
	./upload-scripts.sh "$ip_ovh_vps0"
	./upload-scripts.sh "$ip_ovh_vps1"
	./upload-scripts.sh "$ip_ovh_vps2"
}

main $@

