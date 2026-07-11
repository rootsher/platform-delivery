mock_provider "aws" {}

variables {
  name            = "test"
  cidr            = "10.20.0.0/16"
  azs             = ["eu-central-1a", "eu-central-1b", "eu-central-1c"]
  log_kms_key_arn = "arn:aws:kms:eu-central-1:111111111111:key/test"
}

run "one_private_and_one_public_subnet_per_zone" {
  command = plan

  assert {
    condition     = length(aws_subnet.private) == 3 && length(aws_subnet.public) == 3
    error_message = "Expected one private and one public subnet in each of the three zones."
  }

  assert {
    condition     = length(distinct(aws_subnet.private[*].availability_zone)) == 3
    error_message = "Private subnets must be spread over distinct zones."
  }

  assert {
    condition     = alltrue([for s in aws_subnet.private : endswith(s.cidr_block, "/19")])
    error_message = "Private subnets must be /19: the VPC CNI gives every pod an address."
  }

  assert {
    condition     = alltrue([for s in aws_subnet.private : !s.map_public_ip_on_launch])
    error_message = "Nothing in a private subnet may get a public address."
  }

  assert {
    condition     = alltrue([for s in aws_subnet.public : s.tags["kubernetes.io/role/elb"] == "1"])
    error_message = "Public subnets need the elb role tag, or the load balancer controller will not find them."
  }
}

run "a_nat_gateway_per_zone_by_default" {
  command = plan

  assert {
    condition     = length(aws_nat_gateway.this) == 3
    error_message = "Without single_nat_gateway every zone needs its own NAT gateway."
  }
}

run "single_nat_gateway_when_asked" {
  command = plan

  variables {
    single_nat_gateway = true
  }

  assert {
    condition     = length(aws_nat_gateway.this) == 1
    error_message = "single_nat_gateway should create exactly one NAT gateway."
  }
}

run "rejects_a_vpc_too_small_for_pod_addresses" {
  command = plan

  variables {
    cidr = "10.20.0.0/20"
  }

  expect_failures = [var.cidr]
}
