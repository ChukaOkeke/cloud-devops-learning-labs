# Create VPC 
resource "aws_vpc" "asgard_vpc" {
  cidr_block           = "10.16.0.0/16"
  enable_dns_hostnames = true
  tags                 = { Name = "Asgard-VPC" }
}

# Subnet in VPC AZ A
resource "aws_subnet" "subnet_1" {
  vpc_id            = aws_vpc.asgard_vpc.id
  cidr_block        = "10.16.1.0/24"
  availability_zone = "us-east-1a"
  map_public_ip_on_launch = true
}

# Create Internet Gateway and attach to the custom VPC
resource "aws_internet_gateway" "asgard_vpc_igw" {
  vpc_id = aws_vpc.asgard_vpc.id  # Reference the VPC ID from the created VPC

  tags = {
    Name = "asgard-vpc-igw"
  }
}

# Create Custom Route Table that points to the Internet Gateway for the VPC
resource "aws_route_table" "asgard_vpc_rt_web" {
  vpc_id = aws_vpc.asgard_vpc.id  # Reference the VPC ID from the created VPC

  route {
    cidr_block = "0.0.0.0/0"  # Default Route to route all IPv4 traffic
    gateway_id = aws_internet_gateway.asgard_vpc_igw.id # Target the created Internet Gateway
  }

  # Route for IPv6 traffic
  route {
    ipv6_cidr_block = "::/0"  # Default Route to route all IPv6 traffic
    gateway_id      = aws_internet_gateway.asgard_vpc_igw.id
  }

  tags = {
    Name = "asgard-vpc-rt-web"
  }
}

# Associate the Route Table with the subnet
resource "aws_route_table_association" "web_rt_assoc" {
  subnet_id      = aws_subnet.subnet_1.id 
  route_table_id = aws_route_table.asgard_vpc_rt_web.id
}


# Create a Security Group in the VPC to allow all SSH, HTTP, and HTTPS traffic
resource "aws_security_group" "ec2_vpc_sg" {
  name        = "ec2-vpc-sg"
  description = "Allow SSH, HTTP, and HTTPS inbound traffic"
  vpc_id      = aws_vpc.asgard_vpc.id # Reference the VPC created above

  # Inbound: Allow SSH from everywhere (0.0.0.0/0)
  ingress {
    description = "SSH from anywhere"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # # Outbound: Allow all traffic
  # egress {
  #   from_port   = 0
  #   to_port     = 0
  #   protocol    = "-1"
  #   cidr_blocks = ["0.0.0.0/0"]
  #   ipv6_cidr_blocks = ["::/0"]
  # }

  # Inbound: Allow HTTP and HTTPS from everywhere (0.0.0.0/0)
  ingress {
    description = "HTTP from anywhere"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"] 
    ipv6_cidr_blocks = ["::/0"]
  }

  ingress {
    description = "HTTPS from anywhere"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
  }

  tags = { Name = "Allow-Web-Traffic" }

}

# Dynamically fetch the latest Amazon Linux 2023 AMI
data "aws_ami" "amazon_linux_2023_1" {
  most_recent = true
  owners      = ["amazon"]
  filter {
    name   = "name"
    values = ["al2023-ami-*-x86_64"]
  }
}

# Launch EC2 Instance in AZ A
resource "aws_instance" "asgard_ec2" {
  ami           = data.aws_ami.amazon_linux_2023_1.id
  instance_type = "t2.micro"
  subnet_id     = aws_subnet.subnet_1.id
  vpc_security_group_ids      = [aws_security_group.ec2_vpc_sg.id]
  key_name      = "ec2-key-pair" # Replace with your key name
  
  tags = { Name = "Asgard-EC2" }
}

# Stop the EC2 instance to ensure file system consistency before creating the AMI
resource "aws_ec2_instance_state" "ec2_state" {
  instance_id = aws_instance.asgard_ec2.id
  state      = "stopped"
}

# Create an AMI from the EC2 instance
resource "aws_ami_from_instance" "asgard_golden_image" {
  name               = "asgard-web-v1"
  source_instance_id = aws_instance.asgard_ec2.id
  
  # Best Practice: set to false to ensure file system consistency
  snapshot_without_reboot = false 

  tags = {
    Name = "AsgardGoldenImage"
  }
}

# Launch new EC2 Instance in AZ A from custom AMI
resource "aws_instance" "asgard_ec2" {
  ami           = aws_ami_from_instance.asgard_golden_image.id
  instance_type = "t2.micro"
  subnet_id     = aws_subnet.subnet_1.id
  vpc_security_group_ids      = [aws_security_group.ec2_vpc_sg.id]
  key_name      = "ec2-key-pair" # Replace with your key name
  
  tags = { Name = "Asgard-EC2-Custom-AMI" }
}

# Copy the AMI to another region (e.g., eu-west-1) for multi-region deployment
resource "aws_ami_copy" "asgard_uk_image" {
  name              = "asgard-web-uk-v1"
  description       = "Multi-region copy of the Asgard web server"
  source_ami_id     = aws_ami_from_instance.asgard_golden_image.id
  source_ami_region = "us-east-1"
  
  # Crucial for security compliance in professional environments
  encrypted         = true

  # Provider for the new region (e.g., eu-west-1)
  # provider          = aws.uk

  tags = {
    Name = "Asgard-UK-AMI"
  }
}

# Grant launch permission to another Account ID to share AMI
resource "aws_ami_launch_permission" "share_asgard_ami" {
  image_id   = aws_ami_from_instance.asgard_golden_image.id
  account_id = data.terraform_remote_state.foundation.outputs.prod_account_id # The ID of the target AWS account
}

# Sharing the underlying snapshot
resource "aws_snapshot_create_volume_permission" "share_snapshot" {
  snapshot_id = aws_ebs_snapshot.asgard_snapshot.id
  account_id  = data.terraform_remote_state.foundation.outputs.prod_account_id
}