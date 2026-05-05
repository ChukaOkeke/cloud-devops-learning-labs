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