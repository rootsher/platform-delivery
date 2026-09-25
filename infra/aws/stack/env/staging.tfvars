environment        = "staging"
vpc_cidr           = "10.20.0.0/16"
azs                = ["eu-central-1a", "eu-central-1b", "eu-central-1c"]
single_nat_gateway = true
kubernetes_version = "1.37"

admin_role_arns = ["arn:aws:iam::111111111111:role/platform-admin"]

node_instance_types = ["m7i.large"]
node_count          = { min = 2, desired = 3, max = 5 }

dns_zone = "staging.rootsher.dev"
