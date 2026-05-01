This project:
- Creates a custom VPC
- Implements multi-tier VPC subnets
- Configures the web subnets as public using an Internet Gateway, Route table, and Routes
- Launches a Jumpbox/Bastion host (EC2 instance) in the A AZ web subnet to serve as an entry point to private resources.