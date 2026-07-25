environment = "prod"
vpc_cidr    = "10.30.0.0/16"
azs         = ["eu-central-1a", "eu-central-1b", "eu-central-1c"]
# One NAT gateway per zone: losing a zone must not cut the others off.
single_nat_gateway = false
kubernetes_version = "1.36"

admin_role_arns = ["arn:aws:iam::222222222222:role/platform-admin"]

node_instance_types = ["m7i.xlarge", "m6i.xlarge"]
node_count          = { min = 3, desired = 3, max = 9 }

dns_zone = "rootsher.dev"
