** Prerequisites **

Ansible 2.7
Python netaddr module

To install ansible and netaddr it is recommended to use a virtual environment:

```
virtualenv ~/ansible
. ~/ansible/bin/activate
pip install ansible
pip install netaddr
```

git needs to be installed and a copy of the kubespray-install repository
should be cloned:

```
git clone https://github.com/kumulustech/kubespray-install
```

In addition a kubectl binary and helm binary are required for further configurations:

Follow the instructions here to get kubectl for your build machine:
https://kubernetes.io/docs/tasks/tools/install-kubectl/

or on a Linux host:

```
curl -LO https://storage.googleapis.com/kubernetes-release/release/$(curl -s https://storage.googleapis.com/kubernetes-release/release/stable.txt)/bin/linux/amd64/kubectl
chmod +x ./kubectl
sudo mv ./kubectl /usr/local/bin/kubectl
```

Also, we'll need the helm tools.  Again, instructions here here:
https://helm.sh/docs/using_helm/#installing-helm

or On a Linux machine:

```
curl -sLO https://storage.googleapis.com/kubernetes-helm/helm-v2.13.1-linux-amd64.tar.gz
tar xfz helm-v2.13.1-linux-amd64.tar.gz
sudo mv linux-amd64/helm /usr/local/bin/helm
```

** Create an inventory **

The inventory for kubespray is both an inventory and a set of group variables.
If you leverage the one included here, you'll need to update the ip addresses of the
three (3) master nodes, and the ip addresses of the worker nodes (assumes a minimum of 1 node)

edit the default/hosts.ini for the default inventory and update:
 the external and internal IP addresses for the master, haproxy, nfs (if separate) and worker nodes

You should not need to modify the rest of the document.

Note that this model assumes one node as haproxy and nfs service if this is not the case, modify
the haproxy and nfs host targets as appropraite

It is possible to use the haproxy node as the ansible install node as well, though
it is necessary to configure passwordless ssh access to the other nodes (as is standard
for ansible deployemnts).  There is an ssh.yml ansible script that can be used to copy a known
id_rsa and id_rsa.pub file to all the nodes in the inventory. This will need to be done from
a machine with ssh access (and ansible) to all of the nodes.  I recommend deploying from a
management node (like the cloud-shell from GCP) that is consistent and has the appropriate
ssh keys installed.

```
cd kubespay-install
ansible-playbook -i default/hosts.ini ssh.yml
```

**(Optional) Set up HAProxy SLB for testing**
---------------------------------------------

You should not need to modify any of the configurations to support
the deployment against the master node.  Additional configuration is
not currently implemented

`ansible-playbook -i inventory haproxy.yml`

**Step 1. Prepare Kubespray**
-----------------------------

(source:
[*https://github.com/kubernetes-sigs/kubespray*](https://github.com/kubernetes-sigs/kubespray))

Git clone the kubespray repository:

`git clone https://github.com/kubespray/kubespray`

Currently it is assumed that we can log in directly as root via ssh. If this
is not the case, update the hosts.ini ansible_user parameter. The default user
for the OS, often ubuntu for Ubuntu nodes, centos for Centos nodes, cloud-user for Rhel,
ec2-user for amazon

Note: the total number of etcd nodes must be an odd number or the
kubespray playbook will fail

If we have more than one master, and are using haproxy to frontend the cluster, we will need to update the 

[*https://github.com/kubernetes-sigs/kubespray/blob/master/docs/ha-mode.md*](https://github.com/kubernetes-sigs/kubespray/blob/master/docs/ha-mode.md)


If kubespray is generating your api-server certificates (via kubeadm),
you will also need to add the address of your SLB/ELB to the
supplementary_addresses_in_ssl_keys array in
default/group_vars/all/all.yml

**Step 2. Enable Helm**
-----------------------

If you've not already done so, install Helm natively. First get the helm client,
the simplest method is to run the following curl/bash:

`curl https://raw.githubusercontent.com/helm/helm/master/scripts/get |
bash`

Create a service account and then bind the cluster-admin role to the
service account:
```
kubectl create serviceaccount tiller --namespace kube-system
kubectl create clusterrolebinding tiller-deploy --clusterrole cluster-admin --serviceaccount kube-system:tiller
```
And finally install tiller:

`helm init --service-account tiller`

**Step 3. Enable Ingress Controller Deployment**
------------------------------------------------

Nginx docs: [*https://github.com/kubernetes/ingress-nginx/blob/master/docs/deploy/baremetal.md*](https://github.com/kubernetes/ingress-nginx/blob/master/docs/deploy/baremetal.md)

Kubespray addon repo (its readme.md is an outdated copy of ingress-nginx install docs that has no relation to enabling the addon even though the repo is for the add-on code): [*https://github.com/kubernetes-sigs/kubespray/tree/master/roles/kubernetes-apps/ingress\_controller/ingress\_nginx*](https://github.com/kubernetes-sigs/kubespray/tree/master/roles/kubernetes-apps/ingress_controller/ingress_nginx)

Install within kubespray playbooks:

In project/group_vars/k8s-cluster/addons.yml set
ingress_nginx_enabled to true and uncomment the lines following it:
```
# Nginx ingress controller deployment
ingress_nginx_enabled: true
ingress_nginx_host_network: false
ingress_nginx_nodeselector:
  node-role.kubernetes.io/node: ""
```

To enable the nodePort custom setting, we must alter the ingress service
template within our kubespray directory to reflect the following:

```
## kubespray/roles/kubernetes-apps/ingress-controller/ingress-nginx/templates/svc-default-backend.yml.j2
---
apiVersion: v1
kind: Service
metadata:
  name: default-backend
  namespace: {{ ingress_nginx_namespace }}
  labels:
    app.kubernetes.io/name: ingress-nginx
    app.kubernetes.io/part-of: ingress-nginx
spec:
  type: NodePort
  ports:
    - port: 80
      targetPort: 80
  selector:
    app.kubernetes.io/name: ingress-nginx
    app.kubernetes.io/part-of: ingress-nginx
```

Note:

-   targetPort changed from 8080 to 80

-   Selector app.kubernetes.io/name changed from ‘default-backend’ to ‘ingress-nginx’

After these updates, you can rerun the ansible cluster.yml playbook to
update you cluster

**Step 4. Configure OpenID connect on cluster for dex/ldap**
------------------------------------------------------------

In project/group_vars/k8s-cluster/k8s-cluster.yml, uncomment the line
\#kube_oidc_auth: false and set it to true then uncomment configure
the following

Note:
-   If using NodePort ingress, the issuer url for oidc tokens must include the port number
-   The API server configured with OpenID Connect flags doesn't require dex to be available upfront. Other authenticators, such as client certs, can still be used.)
-   The CA file which was used to sign the SSL certificates for Dex needs to be copied to a location where the API server can locate it with the --oidc-ca-file flag
    -   The following config looks for the CA file in /etc/kubernetes/pki/ca.pem but this can be modified to suit your needs so long as the CA exists at the new setting
    -   If you don’t have a CA available for testing, see the gencert.sh script here, modify it to reflect your DNS setup, then execute it and install the resulting ca.pem on the master node at /etc/kubernetes/pki/ca.pem:
        -   [*https://github.com/krishnapmv/k8s-ldap*](https://github.com/krishnapmv/k8s-ldap)
    -   NOTE: If the CA file is not found in the location specified on the master host, the kube-apiserver will fail to start

```
## Variables for OpenID Connect Configuration https://kubernetes.io/docs/admin/authentication/
## To use OpenID you have to deploy additional an OpenID Provider (e.g Dex, Keycloak, ...)

kube_oidc_url: https://dex.k8s.example.com:32000
kube_oidc_client_id: loginapp
## Optional settings for OIDC
kube_oidc_ca_file: "{{ kube_cert_dir }}/ca.pem"
kube_oidc_username_claim: name
# kube_oidc_username_prefix: oidc:
kube_oidc_groups_claim: groups
# kube_oidc_groups_prefix: oidc:
```

**Step 5. Deploy Kubernetes**
-----------------------------

Now we should be able to deploy our Kubernetes environment:

`ansible-playbook -i default/hosts.ini kubespray/cluster.yml`

Once the deployment completes, install and configure kubectl with:
(source:
[*https://kubernetes.io/docs/tasks/tools/install-kubectl/*](https://kubernetes.io/docs/tasks/tools/install-kubectl/))

```
curl -LO
https://storage.googleapis.com/kubernetes-release/release/\$(curl -s
https://storage.googleapis.com/kubernetes-release/release/stable.txt)/bin/linux/amd64/kubectl

mv kubectl /usr/local/bin/kubectl

chmod +x /usr/local/bin/kubectl

export KUBECONFIG=\${PWD}/default/artifacts/admin.conf
```

NOTE:  You must change the ip address in the default/artifacts/admin.conf
to point to your load balancer address if using the HAproxy configuration,
or to the external address of your master node if only using a single
master, or the service will not work.

Run `kubectl get pods -n kube-system` to verify cluster related pods are
all ready. In some cases, certain pods will be stuck in a status of
ContainerCreating. Such cases can be rectified by running the playbook
again.

`ansible-playbook -i dev/hosts.ini kubespray/cluster.yml`

**Step 6. Add NFS for PV backend**
----------------------------------

(source:
[*https://github.com/kubernetes-incubator/external-storage/tree/master/nfs-client*](https://github.com/kubernetes-incubator/external-storage/tree/master/nfs-client))

`helm install stable/nfs-client-provisioner --name nfs --set nfs.server={SERVER_IP} --set nfs.path=/home/public`

On any node where a PVC/PV may be created, you will need to ensure that
the nfs-common (Debian/Ubuntu) or nfs-utils (Rhel/Centos) packages are
installed.

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

`kubectl apply -f test-claim.yml`

This will create a SUCCESS file in the PVC-named directory

**Step 7. Add Prometheus and resource alerts**
----------------------------------------------

Create the file prom-values.yaml and populate it with the following:

```
additionalPrometheusRules:
  - name: cpu-alerts.rules
    groups:
      - name: Resource Alerts
        rules:
        - alert: HighCpuUsage
          expr: 100 * (1 - avg by(instance)(irate(node_cpu{mode='idle'}[5m]))) > 85
        - alert: HighMemUsage
          expr: (sum(node_memory_MemTotal) - sum(node_memory_MemFree + node_memory_Buffers + node_memory_Cached) ) / sum(node_memory_MemTotal) * 100 > 85
```

Then pass it into the helm chart during install:

`$ helm install -f prom-values.yaml stable/prometheus-operator`

Note: default admin password is “prom-operator” instead of the grafana
default of “admin”

**(Optional) Install OpenLDAP helm chart for testing Dex LDAP integration**
---------------------------------------------------------------------------

Download the values yml file for the openldap helm chart from the
kubespray-install repo

`wget https://raw.githubusercontent.com/kumulustech/kubespray-install/master/openldap-helm-vals.yml`

Run the following to install the OpenLDAP helm chart with said values
(NOTE: --name is important since it is referenced in later configs):

`$ helm install --name dex-test -f openldap-helm-vals.yml stable/openldap`

The customised values passed to openldap seeds the directory with a
couple of test users and groups as well as setting admin password to
match k8s-ldap configs in the next section

**Step 8. Install LDAP Authentication Server (Dex)**
----------------------------------------------------

(source:
[*https://github.com/krishnapmv/k8s-ldap*](https://github.com/krishnapmv/k8s-ldap))

For this example setup, the following is assumed (note: if SLB and Cert
manager are available, the kube-oidc helm chart may be better suited for
this task):

-   An LDAP server is available at ldap.k8s.example.com:389 (if using openldap, then it would be dex-test-openldap.default.svc.cluster.local:389).
-   Certificates are generated manually (example uses self signed)
    -   We already installed the CA on the master node in a previous step as it must be present prior to running kubespray or the kube-apiserver will fail to deploy
-   The following DNS entries exist independent of other applications and point to the public IP address of at least one cluster node:
    -   dex.k8s.example.com --&gt; Dex OIDC provider
    -   login.k8s.example.com --&gt; Custom Login Application

Git clone the k8s-ldap repository

`git clone https://github.com/krishnapmv/k8s-ldap`

Modify k8s-ldap/ca-cm.yml config map to contain your CA.

Modify k8s-ldap/dex-cm.yml and update issuer so that it contains the
port number like such:

`https://dex.k8s.example.org:32000/dex`

Also within k8s-ldap/dex-cm.yml are the settings to configure dex’s
connection to your ldap instance located under the key “connectors”.
Configure the connectors section to suit your environment if necessary.
If you’re using the OpenLDAP chart referenced previously, you will need
to modify it to reflect the following:

```
      connectors:
      - type: ldap
        # Required field for connector id.
        id: ldap
        # Required field for connector name.
        name: LDAP
        config:
          # Host and optional port of the LDAP server in the form "host:port".
          # If the port is not supplied, it will be guessed based on "insecureNoSSL",
          # and "startTLS" flags. 389 for insecure or StartTLS connections, 636
          # otherwise.
          host: dex-test-openldap.default.svc.cluster.local:389

          # Following field is required if the LDAP host is not using TLS (port 389).
          # Because this option inherently leaks passwords to anyone on the same network
          # as dex, THIS OPTION MAY BE REMOVED WITHOUT WARNING IN A FUTURE RELEASE.
          #
          insecureNoSSL: true
          # If a custom certificate isn't provide, this option can be used to turn on
          # TLS certificate checks. As noted, it is insecure and shouldn't be used outside
          # of explorative phases.
          #
          insecureSkipVerify: true
          # When connecting to the server, connect using the ldap:// protocol then issue
          # a StartTLS command. If unspecified, connections will use the ldaps:// protocol
          #
          # startTLS: true
          # Path to a trusted root certificate file. Default: use the host's root CA.
          #rootCA: /etc/dex/ldap.ca
          # A raw certificate file can also be provided inline.
          #rootCAData:
          # The DN and password for an application service account. The connector uses
          # these credentials to search for users and groups. Not required if the LDAP
          # server provides access for anonymous auth.
          # Please note that if the bind password contains a `$`, it has to be saved in an
          # environment variable which should be given as the value to `bindPW`.
          bindDN: cn=admin,dc=example,dc=org
          bindPW: admin

          # User search maps a username and password entered by a user to a LDAP entry.
          userSearch:
            # BaseDN to start the search from. It will translate to the query
            # "(&(objectClass=person)(uid=<username>))".
            baseDN: ou=People,dc=example,dc=org
            # Optional filter to apply when searching the directory.
            filter: "(objectClass=person)"
            # username attribute used for comparing user entries. This will be translated
            # and combine with the other filter as "(<attr>=<username>)".
            username: mail
            # The following three fields are direct mappings of attributes on the user entry.
            # String representation of the user.
            idAttr: DN
            # Required. Attribute to map to Email.
            emailAttr: mail
            # Maps to display name of users. No default value.
            nameAttr: cn

          # Group search queries for groups given a user entry.
          groupSearch:
            # BaseDN to start the search from. It will translate to the query
            # "(&(objectClass=group)(member=<user uid>))".
            baseDN: ou=Groups,dc=example,dc=org
            # Optional filter to apply when searching the directory.
            filter: "(objectClass=groupOfNames)"
            # Following two fields are used to match a user to a group. It adds an additional
            # requirement to the filter that an attribute in the group must match the user's
            # attribute value.
            userAttr: DN
            groupAttr: member
            # Represents group name.
            nameAttr: cn
```

Create the auth namespace

`kubectl create ns auth`

Create secrets to contain certs for dex and the loginapp
```
kubectl create secret tls login.k8s.example.org.tls --cert=\[cert.pem location here\] --key=\[key.pem location here\] -n auth
kubectl create secret tls dex.k8s.example.org.tls --cert=\[cert.pem location here\] --key=\[key.pem location here\] -n auth
```

Create loginapp resources
```
# CA configmap containing your CA
kubectl create -f ca-cm.yml
# Login App configuration
kubectl create -f loginapp-cm.yml
# Login App NodePort (32002) service
kubectl create -f loginapp-ing-svc.yml
# Login App Deployment
kubectl create -f loginapp-deploy.yml
```

Create dex’s custom resource definitions:
```
Create dex resources
# Dex configuration
kubectl create -f dex-cm.yml
# Dex NodePort (32000) service
kubectl create -f dex-ing-svc.yml
# Dex deployment
kubectl create -f dex-deploy.yml
```

If all went well, you should see two pods running in the auth namespace
for dex and loginapp by running the following:

`kubectl get pods -n auth`

In many cases, the loginapp will be in a CrashLoopBackoff state due to
being unable to connect to the non-existent dex resources. If you find
that is the case, scale the loginapp deployment to 0 replicas then back
to 1 to create a new pod for it:
```
kubectl scale deployments loginapp -n auth --replicas=0
kubectl scale deployments loginapp -n auth --replicas=1
```
You should now be able to connect to
[*https://login.k8s.example.com:32002*](https://login.k8s.example.com:32002)
and see a webpage with a “Request Token” button. Click the button and
enter the ldap credentials for the desired user (with openldap it will
be janedoe@example.com / foo )

After logging in, you will be given a block of text representing a
kubeconfig user including the newly generated id token used to
authenticate against the kubernetes api.

You can test this user with the following:
-   Copy a working admin.conf file for the cluster to your local host’s .kube/config
-   Add the block of user text from the loginapp to the end of the config file’s ‘users’ block
-   Modify the ‘context’ block for the cluster to reference the new user instead of kubernetes-admin. Eg.
```
contexts:
- context:
    cluster: kubernetes
    user: jane
  name: janedoe@example.org
```

Once done, you can run kubectl commands against the cluster from your
localhost with the identity of Jane. However, that identity has no
permissions currently. You can grant cluster-admin to the ldap group
‘admins’ by running the following:

`kubectl create -f rbac.yml`

Considerations in using LDAP with Dex:
1.  The **id\_token** can’t be revoked, it’s like a certificate so it should be short-lived (only a few minutes) so it can be very annoying to have to get a new token every few minutes.
    a.  Use short lifetimes, ensure refresh token is properly configured
2.  Security considerations
    a.  Dex attempts to bind with the backing LDAP server using the end user's plain text password. Though some LDAP implementations allow passing hashed passwords, dex doesn't support hashing and instead strongly recommends that all administrators just use TLS. This can often be achieved by using port 636 instead of 389, and administrators that choose 389 are actively leaking passwords. Dex currently allows insecure connections because the project is still verifying that dex works with the wide variety of LDAP implementations. However, dex may remove this transport option, and users who configure LDAP login using 389 are not covered by any compatibility guarantees with future releases.

**Step 9. Deploy Elastic and configure K8s to direct logs**
-----------------------------------------------------------

(source:
[*https://github.com/komljen/helm-charts/tree/master/efk*](https://github.com/komljen/helm-charts/tree/master/efk))

This guide assumes you have set up the nfs provisioner client referenced
previously. If that is not the case, please update the storage config in
a values.yaml file and pass it during the installation (see
[*https://github.com/kumulustech/kubespray-install/blob/master/efk-default-values.yaml*](https://github.com/kumulustech/kubespray-install/blob/master/efk-default-values.yaml)
for default values)

Install elastic search operator helm chart:
```
helm repo add es-operator https://raw.githubusercontent.com/upmc-enterprises/elasticsearch-operator/master/charts/
helm install --set rbac.enabled=true --name es-operator --namespace logging es-operator/elasticsearch-operator
```
Get the custom helm umbrella chart for the EFK configuration and install
with the following:
```
wget https://raw.githubusercontent.com/kumulustech/kubespray-install/master/efk-0.0.1.tgz
helm install --name efk --namespace logging efk-0.0.1.tgz
```
After a few minutes, querying the pods in the logging namespace should
result in something similar to the following:
```
kubectl get pods -n logging
NAME READY STATUS RESTARTS AGE
efk-fluent-bit-ldp55 1/1 Running 0 9m1s
efk-fluent-bit-s9n4q 1/1 Running 0 9m1s
efk-kibana-5f9c56d576-h6qmc 1/1 Running 0 9m1s
elasticsearch-operator-6b4f5c57dd-g9vlr 1/1 Running 0 81m
es-client-efk-cluster-6c96b94d7d-54qcv 1/1 Running 0 8m16s
es-data-efk-cluster-nfs-client-0 1/1 Running 0 8m16s
es-master-efk-cluster-nfs-client-0 1/1 Running 0 8m16s
```

Once the elastic pods are running, copy admin.conf from
kubespray/inventory/{project}/artifacts/ to your .kube/config on local
host (if not already there) then port forward the kibana pod:

`kubectl port-forward {efk-kibana pod name} 5601 -n logging`

Open your web browser at http://localhost:5601 and you should see the
Kibana dashboard. Then, go to the ‘Discover’ menu item, configure the
index to ‘kubernetes\_cluster\*’, click next step, choose the value
‘@timestamp’ and Kibana is ready. You should see all the logs from all
namespaces in your Kubernetes cluster.
