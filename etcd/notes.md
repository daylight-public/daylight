`etcd` feels loose and mushy at the moment. There are a number of concepts floating around that make things confusing for me. Maybe that's because they are unimplemented ideas. That'd make sense.

Setting up a single host with etcd isn't too bad. etcd needs to be installed, and then a few arguments need to be passed, and then a 1 node 'cluster' is up and going, and reachable from the outside world.

Supposably these cmdline args can be set up as envvars.

These commands, and the envvars, can be put into a systemd unit file, and then we have a service.

Here's where I'm stuck. I am not sure how joining the cluster happens, or what it means. It's possible to declaratively start a cluster up, and specify the other hosts in the cluster. But what if this is done dynamically. Do envvars change? How does the cluster 'know' what other hosts are in the cluster? How does it survive a restart?

There appear to be two ways of starting a cluster
1. Start up a cluster with one node, and then dynamically add other nodes to them as they come online
1. Create a bunch of initial nodes, and then start them all up in a cluster at once. Not really sure how this works, unless 'running etcd' and 'being in a cluster' are different things. Can a host running etcd be in more than one cluster?

etcd doomsday: Permanent Quorum Loss
Recovery is done via a data dir

Manually adding an etcd node is a 2 step process
- Request to join
- Join, upon request approval

There is such a thing as Learner Mode. A Learner node doesn't vote. It just gets updates.
One possible approach to adding a new node is to add it as a Learner, wait for it to catch up and synch up with other nodes, and then make it a voter

There are a few ways to start up all at once

- static startup files, with config flags all loaded up with known IPs etc
- using etcd as a discovery service
- using DNS SRV records as a discovery service

The obvious answer is DNS.
Why?
Because this is architectural heaven
DNS is the ultimate distributed data store. And other people run it. Pretty much for free.