#!/bin/bash

helm install stable/nfs-client-provisioner --set nfs.server=147.75.68.117 --set nfs.path=/exported/path
