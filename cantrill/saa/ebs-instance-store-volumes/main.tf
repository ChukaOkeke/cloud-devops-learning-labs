# VPC-1 in us-east-1
# Create VPC 1
resource "aws_vpc" "vpc_1" {
  provider = aws.region-1
  cidr_block           = "10.0.0.0/16"
  enable_dns_hostnames = true
  tags                 = { Name = "VPC-1" }
}

# Subnet in VPC 1 AZ A
resource "aws_subnet" "subnet_1a" {
  provider = aws.region-1
  vpc_id            = aws_vpc.vpc_1.id
  cidr_block        = "10.0.1.0/24"
  availability_zone = "us-east-1a"
  map_public_ip_on_launch = true
}

# Subnet in VPC 1 AZ B
resource "aws_subnet" "subnet_1b" {
  provider = aws.region-1
  vpc_id            = aws_vpc.vpc_1.id
  cidr_block        = "10.0.2.0/24"
  availability_zone = "us-east-1b"
  map_public_ip_on_launch = true
}

# VPC-2 in us-west-1
# Create VPC 2
resource "aws_vpc" "vpc_2" {
  provider = aws.region-2
  cidr_block           = "10.16.0.0/16"
  enable_dns_hostnames = true
  tags                 = { Name = "VPC-2" }
}

# Subnet in VPC 2 AZ A
resource "aws_subnet" "subnet_2a" {
  provider = aws.region-2
  vpc_id            = aws_vpc.vpc_2.id
  cidr_block        = "10.16.1.0/24"
  availability_zone = "us-west-1a"
  map_public_ip_on_launch = true
}


# Create Internet Gateway and attach to the custom VPC-1
resource "aws_internet_gateway" "asgard_vpc1_igw" {
  provider = aws.region-1
  vpc_id = aws_vpc.vpc_1.id  # Reference the VPC ID from the created VPC

  tags = {
    Name = "asgard-vpc1-igw"
  }
}

# Create Internet Gateway and attach to the custom VPC-2
resource "aws_internet_gateway" "asgard_vpc2_igw" {
  provider = aws.region-2
  vpc_id = aws_vpc.vpc_2.id  # Reference the VPC ID from the created VPC

  tags = {
    Name = "asgard-vpc2-igw"
  }
}

# Create Custom Route Table that points to the Internet Gateway in VPC-1
resource "aws_route_table" "asgard_vpc1_rt_web" {
  provider = aws.region-1
  vpc_id = aws_vpc.vpc_1.id  # Reference the VPC ID from the created VPC

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

# Associate the Route Table with both subnets in VPC-1
# Associate the Route Table with subnet-1A
resource "aws_route_table_association" "web_1a" {
  provider = aws.region-1
  subnet_id      = aws_subnet.subnet_1a.id 
  route_table_id = aws_route_table.asgard_vpc1_rt_web.id
}

# Associate the Route Table with subnet-1B
resource "aws_route_table_association" "web_1b" {
  provider = aws.region-1
  subnet_id      = aws_subnet.subnet_1b.id
  route_table_id = aws_route_table.asgard_vpc1_rt_web.id
}

# Create Custom Route Table that points to the Internet Gateway in VPC-2
resource "aws_route_table" "asgard_vpc2_rt_web" {
  provider = aws.region-2
  vpc_id = aws_vpc.vpc_2.id  # Reference the VPC ID from the created VPC-2

  route {
    cidr_block = "0.0.0.0/0"  # Default Route to route all IPv4 traffic
    gateway_id = aws_internet_gateway.asgard_vpc2_igw.id # Target the created Internet Gateway
  }

  # Route for IPv6 traffic
  route {
    ipv6_cidr_block = "::/0"  # Default Route to route all IPv6 traffic
    gateway_id      = aws_internet_gateway.asgard_vpc2_igw.id
  }

  tags = {
    Name = "asgard-vpc2-rt-web"
  }
}

# Associate the Route Table with the subnet in VPC-2
# Associate the Route Table with subnet-2A
resource "aws_route_table_association" "web_2a" {
  provider = aws.region-2
  subnet_id      = aws_subnet.subnet_2a.id 
  route_table_id = aws_route_table.asgard_vpc2_rt_web.id
}


# Create an EBS Volume in AZ 1A
resource "aws_ebs_volume" "asgard_vol_1a" {
  provider = aws.region-1
  availability_zone = "us-east-1a"
  size              = 10 # Volume size in GB
  type              = "gp3"
  tags              = { Name = "AsgardVol-1A" }
}

# Create a Security Group in VPC-1 to allow all SSH traffic
resource "aws_security_group" "ec2_vpc1_sg" {
  provider = aws.region-1
  name        = "ec2-vpc1-sg"
  description = "Allow SSH inbound traffic"
  vpc_id      = aws_vpc.vpc_1.id # Reference the VPC created above

  # Inbound: Allow SSH from everywhere (0.0.0.0/0)
  ingress {
    description = "SSH from anywhere"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Outbound: Allow all traffic
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
  }

  tags = { Name = "Asgard-EBS-EC2-1_SG" }

}

# Dynamically fetch the latest Amazon Linux 2023 AMI
data "aws_ami" "amazon_linux_2023_1" {
  provider = aws.region-1
  most_recent = true
  owners      = ["amazon"]
  filter {
    name   = "name"
    values = ["al2023-ami-*-x86_64"]
  }
}

# Launch EBS Instance in AZ 1A and Mount Volume
resource "aws_instance" "ec2_1a_1" {
  provider = aws.region-1
  ami           = data.aws_ami.amazon_linux_2023_1.id
  instance_type = "t2.micro"
  subnet_id     = aws_subnet.subnet_1a.id
  vpc_security_group_ids      = [aws_security_group.ec2_vpc1_sg.id]
  key_name      = "ec2-key-pair" # Replace with your key name
  
  tags = { Name = "Asgard-EBS-EC2-1A_1" }
}

# # Stop the EC2 instance
# resource "aws_ec2_instance_state" "ec2_1a_1_state" {
#   provider = aws.region-1
#   instance_id = aws_instance.ec2_1a_1.id
#   state      = "stopped"
# }

# resource "aws_volume_attachment" "ebs_att_1a_1" {
#   provider = aws.region-1
#   device_name = "/dev/sdh"
#   volume_id   = aws_ebs_volume.asgard_vol_1a.id
#   instance_id = aws_instance.ec2_1a_1.id
# }

# resource "aws_instance" "ec2_1a_2" {
#   provider = aws.region-1
#   ami           = data.aws_ami.amazon_linux_2023_1.id
#   instance_type = "t2.micro"
#   subnet_id     = aws_subnet.subnet_1a.id
#   key_name      = "ec2-key-pair" # Replace with your key name
#   vpc_security_group_ids      = [aws_security_group.ec2_vpc1_sg.id]

#   tags = { Name = "Asgard-EBS-EC2-1A_2" }
# }

# # Stop the EC2 instance
# resource "aws_ec2_instance_state" "ec2_1a_2_state" {
#   provider = aws.region-1
#   instance_id = aws_instance.ec2_1a_2.id
#   state      = "stopped"
# }

# resource "aws_volume_attachment" "ebs_att_1a_2" {
#   provider = aws.region-1
#   device_name = "/dev/sdh"
#   volume_id   = aws_ebs_volume.asgard_vol_1a.id
#   instance_id = aws_instance.ec2_1a_2.id
# }

# Create EBS Snapshot of the volume created in AZ 1A (This will be used to create a new volume in AZ 2A)
# resource "aws_ebs_snapshot" "vol_snapshot" {
#   provider = aws.region-1
#   volume_id   = aws_ebs_volume.asgard_vol_1a.id
#   tags        = { Name = "AsgardVolSnapshot" }
# }


# # Create new volume in AZ 1B from Snapshot
# resource "aws_ebs_volume" "asgard_vol_1b" {
#   provider = aws.region-1
#   availability_zone = "us-east-1b"
#   snapshot_id       = aws_ebs_snapshot.vol_snapshot.id
#   size              = 10
#   tags              = { Name = "AsgardVol-1B" }
# }

# # Launch EBS Instance in AZ 1B and Mount Volume created from Snapshot
# resource "aws_instance" "ec2_1b" {
#   provider = aws.region-1
#   ami           = data.aws_ami.amazon_linux_2023_1.id
#   instance_type = "t2.micro"
#   subnet_id     = aws_subnet.subnet_1b.id
#   key_name      = "ec2-key-pair" # Replace with your key name
#   vpc_security_group_ids      = [aws_security_group.ec2_vpc1_sg.id]
#   tags = { Name = "Asgard-EBS-EC2-1B" }
# }

# # Stop the EC2 instance
# resource "aws_ec2_instance_state" "ec2_1b_state" {
#   provider = aws.region-1
#   instance_id = aws_instance.ec2_1b.id
#   state      = "stopped"
# }

# resource "aws_volume_attachment" "ebs_att_1b" {
#   provider = aws.region-1
#   device_name = "/dev/sdh"
#   volume_id   = aws_ebs_volume.asgard_vol_1b.id
#   instance_id = aws_instance.ec2_1b.id
# }


# Copy snapshot to another region (e.g., us-west-2)
# resource "aws_ebs_snapshot_copy" "vol_snap_copy" {
#   provider = aws.region-2
#   source_snapshot_id = aws_ebs_snapshot.vol_snapshot.id
#   source_region      = "us-east-1"
#   tags               = { Name = "AsgardVolSnapshot-Copy" }
# }

# Create new volume in AZ 2A from copied Snapshot
# resource "aws_ebs_volume" "asgard_vol_2a" {
#   provider = aws.region-2
#   availability_zone = "us-west-2a"
#   snapshot_id       = aws_ebs_snapshot_copy.vol_snap_copy.id
#   size              = 1
#   tags              = { Name = "AsgardVol-2A" }
# }

# # Create a Security Group in VPC-2 to allow all SSH traffic
# resource "aws_security_group" "ec2_vpc2_sg" {
#   provider = aws.region-2
#   name        = "ec2-vpc2-sg"
#   description = "Allow SSH inbound traffic"
#   vpc_id      = aws_vpc.vpc_2.id # Reference the VPC created above

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

#   tags = { Name = "Asgard-EBS-EC2-2_SG" }

# }

# # Launch EBS Instance in AZ 2A and Mount Volume from copied snapshot
# # Dynamically fetch the latest Amazon Linux 2023 AMI
# data "aws_ami" "amazon_linux_2023_2" {
#   provider = aws.region-2
#   most_recent = true
#   owners      = ["amazon"]
#   filter {
#     name   = "name"
#     values = ["al2023-ami-*-x86_64"]
#   }
# }

# resource "aws_instance" "ec2_2a" {
#   provider = aws.region-2
#   ami           = data.aws_ami.amazon_linux_2023_2.id
#   instance_type = "t2.micro"
#   subnet_id     = aws_subnet.subnet_2a.id
#   key_name      = "ec2-key-pair-2" # Replace with your key name
#   vpc_security_group_ids      = [aws_security_group.ec2_vpc2_sg.id]
#   tags = { Name = "Asgard-EBS-EC2-2A" }
# }

# resource "aws_volume_attachment" "ebs_att_2a" {
#   provider = aws.region-2
#   device_name = "/dev/sdh"
#   volume_id   = aws_ebs_volume.asgard_vol_2a.id
#   instance_id = aws_instance.ec2_2a.id
# }


# Launch the EC2 Instance with instance store volumes (e.g., m5d.large) in AZ 1A
resource "aws_instance" "asgard_instance_store" {
  provider = aws.region-1
  # m5d.large comes with 1 x 75 GB NVMe SSD
  instance_type = "m5d.large" 
  ami           = data.aws_ami.amazon_linux_2023_1.id
  subnet_id     = aws_subnet.subnet_1a.id
  key_name      = "ec2-key-pair"

  vpc_security_group_ids = [aws_security_group.ec2_vpc1_sg.id]

  # Explicitly mapping the instance store (often virtualized as /dev/sdb)
  ephemeral_block_device {
    device_name  = "/dev/sdb"
    virtual_name = "ephemeral0"
  }

  tags = {
    Name = "Asgard-InstanceStore-Demo"
  }
}