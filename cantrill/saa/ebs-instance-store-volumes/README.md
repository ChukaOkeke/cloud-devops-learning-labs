This project:
- Creates an EBS Volume and mounts it to an EC2 instance
- Migrates the volume to another EC2 instance in the same AZ
- Creates an EBS Snapshot from the volume
- Creates a new EBS Volume from the snapshot in AZ-B
- Copies the snapshot to another region
- Creates a new EBS volume from the copied snapshot in the new region
- Creates an EC2 instance with instance store volumes
- Restarts the EC2 instance to verify data persistence in EBS and instance store volumes