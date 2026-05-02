# Create the Asgard VPC
resource "aws_vpc" "asgard_vpc_1" {
  cidr_block       = "10.16.0.0/16"
  instance_tenancy = "default" # Default shared hardware

  # Request a /56 Amazon-provided IPv6 block
  assign_generated_ipv6_cidr_block = true

  # DNS Configuration
  enable_dns_support   = true # Enables the Amazon DNS server (169.254.169.253)
  enable_dns_hostnames = true # Allows instances to receive public/private DNS names

  tags = {
    Name = "asgard-vpc-1"
  }
}

# Output the assigned IPv6 CIDR for future subnetting
output "asgard_vpc_ipv6_cidr" {
  value = aws_vpc.asgard_vpc_1.ipv6_cidr_block
}


# Implement multi-tier VPC subnets (3 AZs, 4 tiers. 4 tiers per AZ. 3 AZs x 4 subnets = 12 subnets total)
# Use a locals block to map out the configuration for each subnet, including the IPv4 CIDR, the index for calculating the IPv6 CIDR, and the AZ. Scalably create subnets
locals {
  subnets = {
    # Availability Zone A
    "sn-reserved-A" = { ipv4 = "10.16.0.0/20",   v6_idx = 0,  az = "us-east-1a" }
    "sn-db-A"       = { ipv4 = "10.16.16.0/20",  v6_idx = 1,  az = "us-east-1a" }
    "sn-app-A"      = { ipv4 = "10.16.32.0/20",  v6_idx = 2,  az = "us-east-1a" }
    "sn-web-A"      = { ipv4 = "10.16.48.0/20",  v6_idx = 3,  az = "us-east-1a" }
    
    # Availability Zone B
    "sn-reserved-B" = { ipv4 = "10.16.64.0/20",  v6_idx = 4,  az = "us-east-1b" }
    "sn-db-B"       = { ipv4 = "10.16.80.0/20",  v6_idx = 5,  az = "us-east-1b" }
    "sn-app-B"      = { ipv4 = "10.16.96.0/20",  v6_idx = 6,  az = "us-east-1b" }
    "sn-web-B"      = { ipv4 = "10.16.112.0/20", v6_idx = 7,  az = "us-east-1b" }
    
    # Availability Zone C
    "sn-reserved-C" = { ipv4 = "10.16.128.0/20", v6_idx = 8,  az = "us-east-1c" }
    "sn-db-C"       = { ipv4 = "10.16.144.0/20", v6_idx = 9,  az = "us-east-1c" }
    "sn-app-C"      = { ipv4 = "10.16.160.0/20", v6_idx = 10, az = "us-east-1c" } # 0a in hex
    "sn-web-C"      = { ipv4 = "10.16.176.0/20", v6_idx = 11, az = "us-east-1c" } # 0b in hex
  }
}

# Create the subnets, using a for_each loop to iterate over the local.subnets map
resource "aws_subnet" "asgard_subnets" {
  for_each = local.subnets

  vpc_id            = aws_vpc.asgard_vpc_1.id # Associates all subnets with the VPC created above
  cidr_block        = each.value.ipv4
  availability_zone = each.value.az

  # Enable public IP for web subnets only
  map_public_ip_on_launch = length(regexall("web", each.key)) > 0 ? true : false

  # IPv6 Setup: Calculates the /64 from the VPC's /56
  ipv6_cidr_block                 = cidrsubnet(aws_vpc.asgard_vpc_1.ipv6_cidr_block, 8, each.value.v6_idx)
  assign_ipv6_address_on_creation = true # auto-assign IPv6 addresses to resources launched in this subnet

  tags = {
    Name = each.key
  }
}


# Configure web public subnets
# Create Internet Gateway and attach to the custom VPC
resource "aws_internet_gateway" "asgard_vpc1_igw" {
  vpc_id = aws_vpc.asgard_vpc_1.id  # Reference the VPC ID from the created VPC

  tags = {
    Name = "asgard-vpc1-igw"
  }
}

# Create Custom Route Table that points to the Internet Gateway
resource "aws_route_table" "asgard_vpc1_rt_web" {
  vpc_id = aws_vpc.asgard_vpc_1.id  # Reference the VPC ID from the created VPC

  route {
    cidr_block = "0.0.0.0/0"  # Default Route to route all IPv4 traffic
    gateway_id = aws_internet_gateway.asgard_vpc1_igw.id # Target the created Internet Gateway
  }

  # Route for IPv6 traffic
  route {
    ipv6_cidr_block = "::/0"  # Default Route to route all IPv6 traffic
    gateway_id      = aws_internet_gateway.asgard_vpc1_igw.id
  }

  tags = {
    Name = "asgard-vpc1-rt-web"
  }
}

# Associate the Route Table to the web subnets
# Associate the Route Table with sn-web-A
resource "aws_route_table_association" "web_a" {
  subnet_id      = aws_subnet.asgard_subnets["sn-web-A"].id # Reference the web subnets using their keys
  route_table_id = aws_route_table.asgard_vpc1_rt_web.id
}

# Associate the Route Table with sn-web-B
resource "aws_route_table_association" "web_b" {
  subnet_id      = aws_subnet.asgard_subnets["sn-web-B"].id
  route_table_id = aws_route_table.asgard_vpc1_rt_web.id
}

# Associate the Route Table with sn-web-C
resource "aws_route_table_association" "web_c" {
  subnet_id      = aws_subnet.asgard_subnets["sn-web-C"].id
  route_table_id = aws_route_table.asgard_vpc1_rt_web.id
}


# # Launch a bastion host in the web subnet (sn-web-A) to serve as a jumpbox for accessing resources in private subnets.
# # Create a Security Group to allow all SSH traffic
# resource "aws_security_group" "bastion_sg" {
#   name        = "bastion-sg"
#   description = "Allow SSH inbound traffic"
#   vpc_id      = aws_vpc.asgard_vpc_1.id # Reference the VPC created above

#   # Inbound: Allow SSH from everywhere (0.0.0.0/0)
#   ingress {
#     description = "SSH from anywhere"
#     from_port   = 22
#     to_port     = 22
#     protocol    = "tcp"
#     cidr_blocks = ["0.0.0.0/0"]
#   }

#   # Outbound: Allow all traffic
#   egress {
#     from_port   = 0
#     to_port     = 0
#     protocol    = "-1"
#     cidr_blocks = ["0.0.0.0/0"]
#     ipv6_cidr_blocks = ["::/0"]
#   }

#   tags = { Name = "bastion-sg" }

# }

# # Dynamically fetch the latest Amazon Linux 2023 AMI
# data "aws_ami" "amazon_linux_2023" {
#   most_recent = true
#   owners      = ["amazon"]
#   filter {
#     name   = "name"
#     values = ["al2023-ami-*-x86_64"]
#   }
# }

# # Create EC2 instance in the web subnet (sn-web-A) to serve as a jumpbox/bastion host
# resource "aws_instance" "asgard_bastion" {
#   ami                         = data.aws_ami.amazon_linux_2023.id
#   instance_type               = "t2.micro" # Free-tier friendly
#   subnet_id                   = aws_subnet.asgard_subnets["sn-web-A"].id
#   vpc_security_group_ids      = [aws_security_group.bastion_sg.id]
#   associate_public_ip_address = true
#   key_name = "ec2-key-pair" # Created key pair in the AWS Console for SSH access

#   tags = {
#     Name = "asgard-bastion"
#   }
# }

# # Output the public IP so you can SSH in immediately
# output "bastion_public_ip" {
#   value = aws_instance.asgard_bastion.public_ip
# }


# Provide HA private outbound-only internet access for private subnets using NAT Gateways in the web subnets in all AZs
locals {
  az_list = ["A", "B", "C"]
}

# Create Elastic IPs for the NAT Gateways
resource "aws_eip" "nat_eip" {
  for_each = toset(local.az_list)
  domain   = "vpc"

  tags = { Name = "asgard-nat-eip-${each.key}" }
}

# Create NAT Gateways in each Web (Public) Subnet for outbound-only internet access from private subnets. Each NAT Gateway is associated with an Elastic IP for a stable public IP address.
resource "aws_nat_gateway" "nat_gw" {
  for_each      = toset(local.az_list)
  allocation_id = aws_eip.nat_eip[each.key].id  # Attach the corresponding Elastic IP to each NAT Gateway
  subnet_id     = aws_subnet.asgard_subnets["sn-web-${each.key}"].id # Reference the web subnets using their keys

  tags = { Name = "asgard-nat-gw-${each.key}" }
}

# Create Private Route Tables (one per AZ) that point to the NAT Gateway in their AZ for outbound internet access. This ensures that if one AZ goes down, only the private subnets in that AZ lose internet access, while the others remain unaffected.
resource "aws_route_table" "private_rt" {
  for_each = toset(local.az_list)
  vpc_id   = aws_vpc.asgard_vpc_1.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.nat_gw[each.key].id
  }

  tags = { Name = "asgard-private-rt-${each.key}" }
}

# Associate the Route Tables with the Private Subnets
# We associate app, db, and reserved subnets to their local AZ's route table
locals {
  # List of private tier prefixes
  private_tiers = ["app", "db", "reserved"]

  # Generate a map of all private subnet-to-route-table associations
  private_assoc_map = merge([
    for az in local.az_list : {
      for tier in local.private_tiers : 
        "sn-${tier}-${az}" => az
    }
  ]...)
}

resource "aws_route_table_association" "private_associations" {
  for_each = local.private_assoc_map

  subnet_id      = aws_subnet.asgard_subnets[each.key].id
  route_table_id = aws_route_table.private_rt[each.value].id
}


# Launch a private EC2 instance in the app subnet (sn-app-A) to demonstrate that it can access the internet via the NAT Gateway, but is not directly accessible from the internet. This instance will be used for testing connectivity using AWS Systems Manager (SSM) Session Manager. This is a more secure and modern approach than bastion hosts for managing instances in private subnets.
# Create the IAM Role for Systems Manager (SSM) that allows the EC2 service to communicate with the SSM backend
resource "aws_iam_role" "app_ssm_role" {
  name = "AsgardAppSSMRole"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
    }]
  })
}

# Attach the required managed policy for SSM
resource "aws_iam_role_policy_attachment" "ssm_managed" {
  role       = aws_iam_role.app_ssm_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

# Create the Instance Profile that EC2 will use
resource "aws_iam_instance_profile" "app_instance_profile" {
  name = "AsgardAppInstanceProfile"
  role = aws_iam_role.app_ssm_role.name
}

# Create a Security Group to allow all SSH traffic
resource "aws_security_group" "app_sg" {
  name        = "asgard-app-sg"
  description = "Security Group for internal app tier"
  vpc_id      = aws_vpc.asgard_vpc_1.id # Reference the VPC created above

  # Allow all outbound traffic (needed for SSM and updates)
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "asgard-app-sg" }

}

# Dynamically fetch the latest Amazon Linux 2023 AMI
data "aws_ami" "amazon_linux_2023" {
  most_recent = true
  owners      = ["amazon"]
  filter {
    name   = "name"
    values = ["al2023-ami-*-x86_64"]
  }
}

# Create a private EC2 instance in the app subnet (sn-app-A)
resource "aws_instance" "asgard_app_server" {
  ami                         = data.aws_ami.amazon_linux_2023.id
  instance_type               = "t3.micro" # More cost effective for modern apps
  subnet_id                   = aws_subnet.asgard_subnets["sn-app-A"].id
  iam_instance_profile = aws_iam_instance_profile.app_instance_profile.name
  vpc_security_group_ids      = [aws_security_group.app_sg.id]
  associate_public_ip_address = false # No public IP for private instance
  # key_name = "ec2-key-pair" # Created key pair in the AWS Console for SSH access

  tags = {
    Name = "asgard-app-ec2"
  }
}