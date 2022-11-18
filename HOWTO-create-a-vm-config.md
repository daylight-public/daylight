# HOWTO Create a VM config

lxd VM configurations are based on lxd's support of cloud-init for VM initialization.

cloud-init support initialization via scripts that packaged with a cloud-init tool called make-mime. The steps are basically
1. Create your initialization scripts - either per instance, or per boot, or both
1. Use `make-mime` to package the scripts into cloud-init package
1. Invoke an lxd command to initialize an lxd VM with a cloud-init package

Because sometimes tasks need to happen after a VM is actually up and running, there's one more

4. Run a script on the started VM to perform final initialization

There are three conventions to follow regarding names ...
- `init-instance.sh` for a script that runs when creating the instance
- `init-boot.sh` for a script that runs on every startup
- `finishing-touches.sh` for a script that runs after everything is done

In a few config folder there is another file ...
- `config.json` for a file that contains lxd-specific information like the name of a base image 

And there are a few config folders with files like this ...
- `lt.json` or `lt-xxxx.json` for launch template files, used by AWS to configure cloud-init

It seems as though the `config-json` files and the `lt.json` and `lt-xxxx.json` files have the same purpose: they are influencing the creation of the image itself, possibly by specifying a base image. I wonder if these could be united, so that there's a common idiom for creating Cloud Provider VMs and lxd VMs.

But in any case, defining a VM specification seems pretty straightforward: create an init-instance.sh script, and possibly an init-boot.sh script and/or a finishing-touches.sh script, and you're done.

Next, let's look at what to do with these files once you've created them.

_note - it looks like `finishing-touches.sh` actually performs actions on the container from outside of the container. Stuff like adding users and making sure they have the same uid, which would be hard to do from inside the container.It's possible but it's more convenient to do it outside of the container._

## What to do with a VM config once you've created it

There's a turnkey daylight.sh function called `pull-vm`. It's all you need

|  |  | |
| --- | --- | --- |
| `pull-vm` | `$name` | Download a VM config file (`download-vm`)
| | | install the VM into lxd (`install-vm`) |
| | | start the VM and perform any last stops (`activate-vm`) ||
| 
| `download-vm` | `$name` | Download the VM config tarball from AWS S3 |
| | | Untar it to a temp folder | 
| | | Print the path of the new temp folder |
|
| `install-vm` | `$image $srcFolder` | Parse the `$image` arg into name or repo:name |
| | | Create the lxd user data (`get-lxd-user-data`) 
| | | Create an instance using the base image name and the user data, giving the instance a temp name so it does not overwrite anything |
| | | Start the new instance
| | | Wait for it to finish startup
| | | Stop the new instance
| | | Publish the new instance, giving it the image name as an alias. This creates the new image in lxd, which can be used to launch instances
| | | Delete the instance
|
| `activate-vm` | `$name $srcFolder [$instanceName]` | launch the instance, aliasing it if an `$instanceName` is provided
| | | source `finishishing-touches.sh` to configure the running instance
|
| `create-lxd-user-data` | `$vmConfigData` | Call `cloud-init devel make-mime` to create the user-data package
| | | Add the custom shellscript handlers (this will not be necessary once they are part of the cloud-init release)
| | | Build the user-data package using `init-instance.sh`, or `init-boot.sh`, or both, depending on what's available