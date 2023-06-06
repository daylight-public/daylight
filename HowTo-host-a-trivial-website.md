Even trivial Websites need https.
So you're going to need a LetsEncrypt cert.
So you're going to need a domain name.
So start there.
Go to the admin page of a domain you own -- or buy a domain -- and set up DNS to a point at a host you control -- or buy a host

Do that and come back.

Ok. With that out of the way, lets look at some broad strokes for hosting a trivial web site

### some broad strokes
It's good to conceptualize things starting with the outside, aka an end-user looking at a browser, and going all the way to the end, eg one or more services running on a VM. And then, when it's time to implement it's good to start at that lowest level, and then work back to the user and their browser.

The User's Journey looks a little like this ...

- Resolvable DNS name
- That resolves to a VM
- Which proxies to an lxd container
- Which is running nginx
- that proxies a domain to a java web app
  + uses a certbot cert to supprt https
- that is running as a systemd service
  + that is updated and builds via Github Actions + SHR

Going the other direction for implementation looks like this ...
- Create an LXD VM
- Create an http proxy into the container
- Install nginx, create a simple static web site
- Check that the proxy works by hitting a static route
- Using an access token, download the target repo
  - Create access tokens using `create-access-tokens.sh`
  - Install pullboy and shrboy in desired repo; otherwise the tokens won't work
  - Enable ssh on the `lxd` VM
  - scp local access tokens to the VM
  - use the access token to do a `git clone`
- Build the web app using maven
= Run the Web app; visit it locally
- Connect nginx to the Web app using proxy_pass; visit it locally on port 80
- Create a cert using certbot
- Configure nginx to use the new cert
- Hit the cert fronted Web-app in a browser
- Create a systemd unit file to run the web app on startup, & bounce the container
- Set up the container as a SHR
- Create a github workflow to build the web app + copy it to where the systemd unit file is expecting it

THEN
- build the VM again from scratch, using daylight.sh functions for all the above steps

THEN
- build a cloud-config for the above, using daylight.sh commands

That's it!

** `daylight.sh` functions to steal from **
|script|de-script-ion | 
|-|-|
|`init-nginx`|An empty function but some decent comments describe a decent intent.
|`create-flask-app`|Working example of genning nginx stuff including certbot cert refs. Also includes a `certbot` invocations to generate the certs themselves. Very useful.
|`create-static-website`|Similar to `create-flask-app` but for static content. Also contains a `certbot` invocation.
|`add-ssh-to-container`|`lxc config` incantation necessary to set an ssh proxy to a container on a specified port.
|`gen-nginx-static`|`nginx` snippet for setting up a server on a Unix domain, and proxying an https:/domain to it (basically a 2-liner server block associating a `.sock` file with a path of content; 
|`prep-vm-host.sh`|Magical magic that creates a GitHub access token and a GitHub SHR token, and does plenty of other useful stuff
