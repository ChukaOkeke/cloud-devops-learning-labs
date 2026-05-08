# Setup Custom VPC
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
data "aws_ami" "amazon_linux_2023" {
  most_recent = true
  owners      = ["amazon"]
  filter {
    name   = "name"
    values = ["al2023-ami-*-x86_64"]
  }
}

# Dynamically fetch the latest Ubuntu 24.04 LTS (Noble Numbat) AMI
data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"] # Canonical's Official AWS Account ID

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd-gp3/ubuntu-noble-24.04-amd64-server-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }

  filter {
    name   = "architecture"
    values = ["x86_64"] # Use "arm64" if using Graviton instances (t4g, m7g, etc.)
  }
}

# # Bootstrap EC2 Instance in AZ A procedurally with User Data + Script
# resource "aws_instance" "asgard_ec2" {
#   ami           = data.aws_ami.amazon_linux_2023.id
#   instance_type = "t2.micro"
#   subnet_id     = aws_subnet.subnet_1.id
#   vpc_security_group_ids      = [aws_security_group.ec2_vpc_sg.id]
#   key_name      = "ec2-key-pair" # Replace with your key name
  
#   user_data = <<-EOF
#               #!/bin/bash
#               dnf update -y
#               dnf install nano -y
#               EOF

#   tags = { Name = "Asgard-EC2" }
# }

# Bootstrap EC2 Instance in AZ A using desired state with User Data + Config (cloud-init/cloud-config)
# Inline method - This is the fastest way to test a configuration. You use a "Heredoc" (<<-EOT) to write the YAML directly inside your .tf file.
resource "aws_instance" "asgard_ec2" {
  ami           = data.aws_ami.amazon_linux_2023.id
  instance_type = "t2.micro"
  subnet_id     = aws_subnet.subnet_1.id
  vpc_security_group_ids      = [aws_security_group.ec2_vpc_sg.id]
  key_name      = "ec2-key-pair" # Replace with your key name
  
  # The first line MUST be #cloud-config. If user data is to be encoded, you would use the user_data_base64 attribute and the base64encode() function.
  user_data = <<-EOT
    #cloud-config
    package_update: true
    packages:
      - nginx
    
    write_files:
      - content: |
          <h1>Asgard Web Server</h1>
          <p>Provisioned via Cloud-Init and Terraform</p>
        path: /usr/share/nginx/html/index.html

    runcmd:
      - [ systemctl, enable, nginx ]
      - [ systemctl, start, nginx ]
  EOT

  # This acts like your CreationPolicy. Wait till cloud-init software configurations are done before declaring the status of the resource as "created". If cloud-init fails, Terraform will know the instance is not ready and can retry or alert you to the failure.
  provisioner "remote-exec" {
    inline = [
      "cloud-init status --wait" # Blocks until cloud-init is done
    ]

    connection {
      type        = "ssh"
      user        = "ec2-user" # Default user for Amazon Linux 2023. Use "ubuntu" for Ubuntu AMIs.
      private_key = file("~/code/aws/keys/ec2/ec2-key-pair.pem")
      host        = self.public_ip
    }
  }

  tags = { Name = "Asgard-EC2" }
}

# # File method (Static): As your configurations get more complex, keeping YAML inside HCL (HashiCorp Configuration Language) becomes messy. You can store your config in a separate file like scripts/init.yml and read it in.
# resource "aws_instance" "asgard_ec2" {
#   ami           = data.aws_ami.amazon_linux_2023.id
#   instance_type = "t2.micro"
#   subnet_id     = aws_subnet.subnet_1.id
#   vpc_security_group_ids      = [aws_security_group.ec2_vpc_sg.id]
#   key_name      = "ec2-key-pair" # Replace with your key name
  
#   # Reads the file and passes the content as a string
#   user_data = file("${path.module}/scripts/init.yml")
  
#   tags = { Name = "Asgard-EC2" }
# }

# #Template Method (Dynamic): In professional DevOps workflows, you often need to inject Terraform variables (like a Database endpoint or an Environment name) into your cloud-config. This is where templatefile() shines.
# # File: templates/cloud-init.tftpl

# # #cloud-config
# # write_files:
# #   - path: /var/www/html/index.html
# #     content: |
# #       <h1>Environment: ${env_name}</h1>
# #       <p>App Version: ${app_version}</p>

# # runcmd:
# #   - echo "Connecting to database at ${db_endpoint}" >> /var/log/app_init.log

# resource "aws_instance" "asgard_ec2" {
#   ami           = data.aws_ami.amazon_linux_2023.id
#   instance_type = "t2.micro"
#   subnet_id     = aws_subnet.subnet_1.id
#   vpc_security_group_ids      = [aws_security_group.ec2_vpc_sg.id]
#   key_name      = "ec2-key-pair" # Replace with your key name
  
#   # Reads the file and passes the content as a string
#   user_data = templatefile("${path.module}/templates/cloud-init.tftpl", {
#     env_name    = "Development"
#     app_version = "v1.0.4"
#     db_endpoint = "asgard-db.cluster-c123.us-east-1.rds.amazonaws.com"
#   })
  
#   tags = { Name = "Asgard-EC2" }
# }