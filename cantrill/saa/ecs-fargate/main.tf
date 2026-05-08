# The ECS Cluster
resource "aws_ecs_cluster" "asgard_fargate_cluster" {
  name = "asgard-fargate-cluster"

  setting {
    name  = "containerInsights"
    value = "enabled"
  }

  tags = {
    Name = "asgard-fargate-cluster"
  }
}

# Assign Fargate Capacity Providers
resource "aws_ecs_cluster_capacity_providers" "asgard_cluster_providers" {
  cluster_name = aws_ecs_cluster.asgard_fargate_cluster.name

  capacity_providers = ["FARGATE", "FARGATE_SPOT"]

  default_capacity_provider_strategy {
    base              = 1
    weight            = 100
    capacity_provider = "FARGATE"
  }
}

# IAM role that allows the ECS service to interact with other AWS services like ECR (for images) and CloudWatch (for logs)
# Define the Trust Policy (Allows ECS to assume this role)
resource "aws_iam_role" "ecs_task_execution_role" {
  name = "asgard-ecs-task-execution-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ecs-tasks.amazonaws.com"
        }
      }
    ]
  })

  tags = {
    Name = "ecs-task-execution-role"
  }
}

# Attach the AWS Managed Policy for ECS Task Execution
resource "aws_iam_role_policy_attachment" "ecs_task_execution_role_policy" {
  role       = aws_iam_role.ecs_task_execution_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

# Security Group for ECS Tasks (Allows inbound HTTP traffic and outbound access to pull images from ECR)
resource "aws_security_group" "ecs_task_sg" {
  name        = "asgard-ecs-task-sg"
  description = "Allow HTTP inbound traffic to ECS tasks"
  vpc_id      = aws_vpc.ebs_lab_vpc.id # Ensure this matches your current VPC

  # Inbound: Allow traffic on port 80
  ingress {
    description = "HTTP from anywhere"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Outbound: Allow all traffic (Required to pull images from ECR)
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "asgard-ecs-task-sg"
  }
}