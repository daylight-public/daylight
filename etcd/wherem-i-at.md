So what do I have ...

3 VMs, all on one provider
Scripts to install etcd, as well as scripts to reset etcd and uninstall etcd
A template of a script to run etcd, parameterized on IP and etcd node name (maybe node name should match hostname and then everything's the same


Tasks 
- change format of templated file to use gomplate syntax. This would allow using gomplate to do the replacement, while still also being easy to use sed
- store the etcd information in a json or yaml file. The idea is that 
- write some jq one liners to get this information out of the yaml
