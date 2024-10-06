There are 2 main VM setup files to look at: `prep-host-vm.sh` and `create-lxd-vm.sh`

## `prep-host-vm.sh` ##
- Update the host VM
- Create a staging folder of files to upload to the host VM - per-service and per-VM
    - This might only be `on-commit.sh` and `on-install.sh`
    - rsync the staging folder to the host
    - run `create-lxd-host.sh` on the host
    - ssh into the host and then lxc shell to hop into the container!

## `create-lxd-vm.sh` ##
- Lots of lxd VM creation stuff
- Push GH tokens and VM-level config files to the VM (maybe sharing a volume between host and vm would help)
- Set up each service
    - Create service-specific staging folder
    - Push on-commit.sh
    - Push on-install.sh
    - Clone service's repo using access token
    - Run on-install.sh
    - Run on-commit.sh

## VM-level setup

We seem to be seeing the same files repeatedly: `on-install.sh` and `on-commit.sh`. Let's have a look.

#### `on-install.sh`
Designed to be run once per service.
Basically this installs a GH SHR. This means confirming a valid SHR token exists, and that the daylight.sh script is present to do the installation.
Maybe this is so standard that it could just go away, and be part of a `create-service` script

#### `on-commit.sh`
- Service installation boilerplate
- Copy all the files needed to create the container into the svc folder
    - This might mean all the source for the project.
    - It might be better to build the container in a tmp folder

## Service-level setup

Services have config files to support service creation
- `.service` unit file
- `bin/run.sh`
- `env.container`

#### `.service` unit file
Boiler plate; common for all services

#### `bin/run.sh`
Pretty much derived from the service repo's `run-in-podman.sh` script

#### `env.container`
Possible the same envvars for running locally
Possibly different, eg for a web app accessible from public Internet
(Although that might be handled by nginx so maybe not)

So what's a possible approach?

- Create conf folder
- Create boilerplate unit file
- Create `bin/run.sh` from `run-in-podman.sh` (mostly this means removing the sourcing of env.container ... hmmm ...)
- Create the svc's env.container, dervied as approrpriate from the local env.container
- Create boilerplate `on-install.sh``
- Create semi-boilerplate `on-commit.sh``
- Add svc-specific section to `prep-host-vm.sh`
- Add svc-specific section to `create-lxd-vm.sh`
- Add VM-specific stuff to `prep-host-vm.sh` if necessary, eg the service requires VM level changes
  (note -- a truly self-contained service might not need VM-level changes)
- Add VM-specific stuff to `create-lxd-vm.sh` if necessary, eg the service requires VM level changes
  (note -- a truly self-contained service might not need VM-level changes)
- Copy boilerplate GHA file to .github/workflows
- Go into user settings + Applications and add pull-boy and shr-boy as github apps to the necessary repo(s) *(It would be very nice to script this part, but I haven't been able to get it to work)*

The part that may require some iteration and care, is getting `on-commit.sh` right, so it sets up the
service folder as needed. I'm not sure of a clean way to do this. Part of a clean approach would mean
documenting all the sources of possible extra stuff required by `run.sh`. `run.sh` might directly have
requirements of its own, in terms of files and paths. It might also indirectly have requirements in the
Dockerfile, which `run.sh` uses to build the image. Inspecting `run.sh` and the Dockerfile might be sufficient.

If all goes well, the following will be true
- An SHR will be setup under `/opt/action-runners/$svcName`
- A service will be installed under `/opt/svc/$svcName`
- The service will include a .service unit file, env.container, and bin/run.sh
- The service will have started successfully (unless it's timed)
- Testing the service should be possible (I actually don't think I have a good testing scenario -- maybe add bin/test.sh to go with bin/run.sh)

## Public-facing Web sites

Supporting a public-facing Web app takes a little more care. Public-facing apps require X.509 certs,
and certs mean certbot / letsencrypt setup. All this complexity has been figured out and works
well. But there's one trick: certbot rate limits free cert creation. During development, it's 
possible to go end-to-end frequently enough that too many certs get generated and LetsEncrypt will refuse to 
create more. This is complicated by the fact that a complete run is needed to create a cert in the first place.

So a startup process might look this ...
- Do all the setup including setting up nginx for the public Web site
- Allow cert generation to happen
- Bundle up letsencrypt files, as well as the nginx site file that letsencrypt edits
- `lxd file pull`ing those files off the VM onto the host
- put those files in source control
- make setup of those files part of `create-lxd-host.sh`, so that future runs use existing files

There's actually some Googlage on this, from folks trying to do exactly the same thing. Among the suggestions from the certbot team
was "don't use certbot", which is amusing but also reasonable, the idea being that certbot works how it works, and if you have another model of cert usage then maybe certbot isn't the right tool.

But certbot is good at 3 things:
1. Creating a browser-friendly cert
2. Updating an nginx file to use the cert
3. Renewing certs in perpetuity

While it might make sense to remove certbot from VM creation, it does make sense to have certbot in the mix.

So maybe -- and yes, it hurts a little -- but maybe the move is to figure out how to have a one-off certbot effort once and for all. Where adding a public facing service, and thus a domain, requires a one-off effort.

This could eventually be hidden behind a small -- and free? -- hosted service. That'd be chill and/or lit. But for now, this is getting scripted. It'll be a little clunky, but it'll get the job done.

This is a lot!

Here's another idea: Do things manually at first.
What's that look like ...
1. Creating some nginx files locally, and scp them up
1. Create DNS entries
1. Try and run certbot locally
1. See if everything is good and wired up

Update - I did it! But how?
Something like ...
- Made a cloud-init config limited to nginx, certbot, and not much else
- Stopped scim, started a new VM based on the cloud cfg -- and called it `certy`
- Got certy listening on 80 instead of scim (which was stopped now), so the certbot ACME challenge could work
- Manually gen'd an nginx service file locally using `gomplator`
- On VM - ran certbot
- On VM - tarred up /etc/letsencrypt/live, archive, renewal, plus top level encryption params, plus nginx service file
- lxc file pulled those files down to the host VM
- Stopped certy, started scim
- lxc file pushed tar files to scim
- restarted nginx on scim (important!)
That's it! How easy is that

Pretty easy. Now let's level up.

