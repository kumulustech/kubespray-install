# your Kubernetes cluster name here
cluster_name = "packet"

# Your Packet project ID. See https://support.packet.com/kb/articles/api-integrations
packet.auth_token = "kL2v4cfAR7CndKarXNQS797PXSr4NtmF"
packet_api_key = "kL2v4cfAR7CndKarXNQS797PXSr4NtmF"
packet_project_id = "84fe4749-d08b-4042-b722-5573466f35f3"

# The public SSH key to be uploaded into authorized_keys in bare metal Packet nodes provisioned
# leave this value blank if the public key is already setup in the Packet project
# Terraform will complain if the public key is setup in Packet
public_key_path = "~/.ssh/id_rsa_k8s.pub"

# cluster location
facility = "sjc1"

# standalone etcds
number_of_etcd = 0
plan_etcd = "c1.small.x86"

# masters
number_of_k8s_masters = 1
number_of_k8s_masters_no_etcd = 0
plan_k8s_masters = "c1.small.x86"
plan_k8s_masters_no_etcd = "c1.small.x86"

# nodes
number_of_k8s_nodes = 3
plan_k8s_nodes = "c1.small.x86"
