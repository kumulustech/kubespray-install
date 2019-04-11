#!/bin/bash

helm install stable/nfs-client-provisioner --set nfs.server=10.142.15.203  --name nfs-pv --set nfs.path=/home/public --namespace nfs-pv

