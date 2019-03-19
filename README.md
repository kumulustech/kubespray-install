## Step 1. Deploy Kubernetes
(source: https://github.com/kubernetes-sigs/kubespray)
Prequisites:
Virtual or Physical machines with direct "open" L3 access.  I.e. there should be no firewall access restrictions between nodes, and at a minimum ports 80, 443, and preferably ports from 30-65K are available at a minimum.
A "launch" node, or a laptop with:
git
python (3) + ansible (2.7)
kubectl (1.12)

Git clone the kubespray repository:
```
git clone https://github.com/kubespray/kubespray
```

Create an inventory directory for the ansible play:
```
cp -r kubespray/inventory/sample project/
```

update the project/hosts.ini file with the the target machine information.

hostname ansible_host={publicL3} ansible_user={osUser}

publicL3 is the address that ansible will access the host with
osUser is the default user for the OS, often ubuntu for Ubuntu nodes, centos for Centos nodes, cloud-user for Rhel

Copy the hostname into the appropriate group based on role, and the normal model is to
separate master, etcd and nodes. But it is also common to run etcd on the master node(s), and also
to run all resources on the all nodes depending on scale.

Unless one has already checked remote ssh login access to the nodes, you'll often want to bypass the ssh-host key validation:

```
export ANSIBLE_HOST_KEY_CHECKING=False
```
Or, add the following to the project/group_vars/all/all.yml

```
ansible_ssh_extra_args: '-o StrictHostKeyChecking=no'
```

In order to allow the local host to communicate with the deployed kubernetes enviornment
we'll also want to add:

```
kubeconfig_localhost: true
```` to the all group_vars

Now we should be able to deploy our Kubernetes environment:

```
ansible-playbook -i dev/hosts.ini kubespray/cluster.yml
```

Once the deployment completes, install and configure kubectl with:
(source: https://kubernetes.io/docs/tasks/tools/install-kubectl/)

```
curl -LO https://storage.googleapis.com/kubernetes-release/release/$(curl -s https://storage.googleapis.com/kubernetes-release/release/stable.txt)/bin/linux/amd64/kubectl
mv kubectl /usr/local/bin/kubectl
chmod +x /usr/local/bin/kubectl

export KUBECONFIG=${PWD}/dev/artifacts/admin.conf
```

## Step 2.  Add helm
(source: https://helm.sh/docs/using_helm/)

```
kubectl create serviceaccount tiller -n kube-system

kubectl create clusterrolebinding --clusterrole=cluster-admin --serviceaccount=kube-system:tiller tiller-deploy

helm init --service-account=tiller
```

## Step 3. Add NFS for PV backend
(source: https://github.com/kubernetes-incubator/external-storage/tree/master/nfs-client)

helm install stable/nfs-client-provisioner --name nfs --set nfs.server={SERVER_IP} --set nfs.path={NFS_EXPORT_PATH}

Test your claim by creating a claim-test.yml document:

```
---
kind: PersistentVolumeClaim
apiVersion: v1
metadata:
  name: test-claim
  annotations:
    volume.beta.kubernetes.io/storage-class: "nfs-client"
spec:
  accessModes:
    - ReadWriteMany
  resources:
    requests:
      storage: 1Mi
---
kind: Pod
apiVersion: v1
metadata:
  name: test-pod
spec:
  containers:
  - name: test-pod
    image: gcr.io/google_containers/busybox:1.24
    command:
      - "/bin/sh"
    args:
      - "-c"
      - "touch /mnt/SUCCESS && exit 0 || exit 1"
    volumeMounts:
      - name: nfs-pvc
        mountPath: "/mnt"
  restartPolicy: "Never"
  volumes:
    - name: nfs-pvc
      persistentVolumeClaim:
        claimName: test-claim
```

Then apply the document:

kubectl apply -f test-claim.yml

This will create a SUCCESS file in the PVC-named directory

## Step 4.
