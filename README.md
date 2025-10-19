# Rancher Terraform

Automated Rancher deployment on K3s Kubernetes cluster using Terraform with remote SSH provisioning.

## Configuration

Copy the example configuration file:

```bash
cp terraform.tfvars.example terraform.tfvars
```

Edit `terraform.tfvars` with your server and Rancher configuration:

```hcl
github = {
    username = "your-github-username"
    token    = "your-github-token"
}

server = {
    ssh_server           = "192.168.1.10"
    ssh_port             = 22
    ssh_username         = "root"
    ssh_password         = ""
    ssh_private_key_path = "~/.ssh/id_ed25519"
}

rancher = {
    hostname           = "rancher.yourdomain.com"
    letsencrypt_email  = "your-email@example.com"
    bootstrap_password = "your-secure-password"
}
```

## Terraform Commands

```bash
# Initialize Terraform
terraform init

# Preview changes
terraform plan

# Deploy Rancher
terraform apply

# Destroy Rancher
terraform destroy
```
