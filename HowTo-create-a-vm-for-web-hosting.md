### How To Create a VM for Web Hosting

- Have a binary for a Web app handy, as well as a simple script to run it
- lxc file push the web app to the vm

- shell into the vm
- run the pushed webapp
- (alternately, create a simple web app on the VM eg node, docker, etc)
- test using curl or netcat

- Install nginx
- curl localhost:80
- install the web site
- run the web site
- curl localhost:website port
- nginx proxy to the local web app
- curl localhost:proxy:port

- shell out to VM
- create lxd proxy to nginx
- curl:lostlhost:proxy port

- shell into VM
- setup systemd service for web app
- start/stop web app with systemd
- check if it works

-- shell out to VM
-- try lxc exec systemctl to start/stop web app

At this point the web app works. Now we need to secure it.

