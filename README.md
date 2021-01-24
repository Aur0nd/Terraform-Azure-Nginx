# Terraform-Azure-Nginx
Deploy HA nginx servers on Azure (LB/AutoScaling/ScaleSet)

Terraform-Azure-Nginx
Deploy HA nginx servers on Azure (LB/AutoScaling/ScaleSet)

1: Pull the repo and cd into the file 
2: If you are on a Mac/Linux generate ssh key ssh-keygen -f mykey 
3: terraform init 4: terraform apply


NOTE: ssh to port 50000-50119 (check GUI inbound NAT rules), loadbalancer NAT will redirect the port to 22
|--------------------------------------------------------------------------------------------------------------|

NOTE: Add zones = [1,2,3] to the file terraform.tfvars and variable "zones" {\n type = string\n} to the file varaible.tf if you want MultiAZ
|--------------------------------------------------------------------------------------------------------------|
