# Setup Custom VPC and Subnet Architecture for Asgard
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


# Create RDS Instances
# Create Subnet Group with 3 subnets (one in each AZ) for high availability
resource "aws_db_subnet_group" "asgard_db_group" {
  name       = "asgard-cuisines-subnet-group"
  subnet_ids = [
    aws_subnet.asgard_subnets["sn-db-A"].id, 
    aws_subnet.asgard_subnets["sn-db-B"].id, 
    aws_subnet.asgard_subnets["sn-db-C"].id
  ]

  tags = {
    Name = "AsgardCuisinesDBSubnetGroup"
  }
}

# Create Security Group for the RDS
resource "aws_security_group" "rds_sg" {
  name        = "asgard-rds-sg"
  description = "Allow MySQL traffic"
  vpc_id      = aws_vpc.asgard_vpc_1.id

  # Allow inbound traffic to MySQL port from the App Server's CIDR (or Security Group in a real setup)
  ingress {
    from_port   = 3306
    to_port     = 3306
    protocol    = "tcp"
    # Best practice: Limit this to your App Server's Security Group ID later
    cidr_blocks = ["10.16.0.0/16"] 
  }

  # Allow all outbound traffic (or restrict as needed)
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# Create the RDS database
resource "aws_db_instance" "asgard_db" {
  identifier           = "asgardcuisines"
  engine               = "mysql"
  engine_version       = "8.0"
  instance_class       = "db.t3.micro"
  allocated_storage     = 20
  
  # Credentials
  username             = "asgard"
  password             = "ekwu5555"
  
  # Network & Security
  db_subnet_group_name   = aws_db_subnet_group.asgard_db_group.name
  vpc_security_group_ids = [aws_security_group.rds_sg.id]
  publicly_accessible    = false # Standard for backend database safety

  # Storage Settings
  max_allocated_storage = 0 # Disables storage autoscaling as requested
  
  # Final Housekeeping
  skip_final_snapshot    = true # Use only for labs; set to false in production
  
  tags = {
    Project = "AsgardCuisines"
  }
}

# Take snapshot on the RDS instance
resource "aws_db_snapshot" "asgard_manual_snapshot" {
  db_instance_identifier = aws_db_instance.asgard_db.identifier
  db_snapshot_identifier = "asgardcuisines-manual-backup-${timestamp()}"
}

# Restore snapshot to new DB instance
resource "aws_db_instance" "asgard_db_restored" {
  identifier           = "asgardcuisines-restored"
  instance_class       = "db.t3.micro"
  snapshot_identifier  = "asgard-backup-before-migration"
  
  # Ensure it stays in your custom VPC
  db_subnet_group_name   = aws_db_subnet_group.asgard_db_group.name
  vpc_security_group_ids = [aws_security_group.rds_sg.id]
  skip_final_snapshot    = true
}