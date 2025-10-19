terraform {
    required_providers {
        null = {
            source  = "hashicorp/null"
            version = ">= 3.1"
        }
    }

    required_version = ">= 1.3.0"
}

resource "null_resource" "preflight" {
    triggers = {
        always_run = timestamp()
    }

    connection {
        type = "ssh"
        host = var.server.ssh_server
        port = var.server.ssh_port
        user = var.server.ssh_username
        private_key = file(var.server.ssh_private_key_path)
        password = var.server.ssh_password
        timeout = "2m"
    }

    provisioner "remote-exec" {
        inline = [
            "sudo apt-get update && sudo apt-get upgrade -y",
            "sudo apt-get install -y git curl apt-transport-https ca-certificates software-properties-common",
        ]
    }

    provisioner "remote-exec" {
        inline = [
            "if [ -z \"$(git config --global --get user.name)\" ]; then",
            "    echo 'Setting Git user name...'",
            "    git config --global user.name '${var.github.username}'",
            "else",
            "    echo 'Git user name already configured: '$(git config --global --get user.name)",
            "fi",

            "if [ -z \"$(git config --global --get user.email)\" ]; then",
            "    echo 'Setting Git user email...'",
            "    git config --global user.email '${var.github.username}@users.noreply.github.com'",
            "else",
            "    echo 'Git user email already configured: '$(git config --global --get user.email)",
            "fi",

            "if [ -z \"$(git config --global --get credential.helper)\" ]; then",
            "    echo 'Setting Git credential helper...'",
            "    git config --global credential.helper store",
            "else",
            "    echo 'Git credential helper already configured: '$(git config --global --get credential.helper)",
            "fi",

            "if [ ! -f ~/.git-credentials ]; then",
            "    echo 'Setting up Git credentials...'",
            "    echo 'https://${var.github.username}:${var.github.token}@github.com' > ~/.git-credentials",
            "    chmod 600 ~/.git-credentials",
            "else",
            "    echo 'Git credentials file already exists'",
            "    chmod 600 ~/.git-credentials",
            "fi"
        ]
    }

    provisioner "remote-exec" {
        inline = [
            "if ! command -v docker >/dev/null 2>&1 && ! which docker >/dev/null 2>&1 && ! [ -x /usr/bin/docker ] && ! [ -x /usr/local/bin/docker ]; then",

            "   echo 'Docker not found. Installing Docker...'",
            "   for pkg in docker.io docker-doc docker-compose docker-compose-v2 podman-docker containerd runc; do sudo apt-get remove $pkg; done",

            "   sudo apt-get update",
            "   sudo apt-get install -y ca-certificates curl",

            "   sudo mkdir -p /etc/apt/keyrings",
            "   sudo install -m 0755 -d /etc/apt/keyrings",
            "   sudo curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc",
            "   sudo chmod a+r /etc/apt/keyrings/docker.asc",

            "   echo \"deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable\" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null",
            "   sudo apt-get update",

            "   sudo apt-get -y install docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin",

            "   sudo groupadd docker",
            "   sudo usermod -aG docker $USER",

            "   sudo systemctl start docker",
            "   sudo systemctl enable docker",

            "   echo 'Docker installation completed successfully'",
            "else",
            "   echo 'Docker is already installed. Skipping installation.'",
            "   docker --version",
            "fi"
        ]
    }

    provisioner "remote-exec" {
        inline = [
            "echo 'Checking if Kubernetes (K3s) is installed and running...'",

            "if ! command -v k3s >/dev/null 2>&1 && ! [ -f /usr/local/bin/k3s ]; then",
            "    echo 'ERROR: Kubernetes (K3s) is not installed on this system'",
            "    echo 'Please install K3s before deploying Rancher'",
            "    echo 'Run the kubernetes terraform module first'",
            "    exit 1",
            "fi",

            "if ! systemctl is-active --quiet k3s 2>/dev/null && ! systemctl is-active --quiet k3s-agent 2>/dev/null; then",
            "    echo 'ERROR: Kubernetes (K3s) is installed but not running'",
            "    echo 'Please start the K3s service before deploying Rancher'",
            "    echo 'Run: sudo systemctl start k3s (or k3s-agent for agent nodes)'",
            "    exit 1",
            "fi",

            "echo 'Kubernetes (K3s) is installed and running.'",

            "echo 'Checking Kubernetes cluster access...'",
            "export KUBECONFIG=~/.kube/config",
            "if [ ! -f ~/.kube/config ]; then",
            "    echo 'Creating kubeconfig from K3s...'",
            "    mkdir -p ~/.kube",
            "    sudo cp /etc/rancher/k3s/k3s.yaml ~/.kube/config",
            "    sudo chown $(id -u):$(id -g) ~/.kube/config",
            "    chmod 600 ~/.kube/config",
            "    echo 'Kubeconfig created successfully'",
            "fi",

            "if ! kubectl get nodes >/dev/null 2>&1; then",
            "    echo 'WARNING: Cannot access Kubernetes cluster with current kubeconfig'",
            "    echo 'Attempting to refresh kubeconfig from K3s...'",
            "    sudo cp /etc/rancher/k3s/k3s.yaml ~/.kube/config",
            "    sudo chown $(id -u):$(id -g) ~/.kube/config",
            "    chmod 600 ~/.kube/config",
            "    if ! kubectl get nodes >/dev/null 2>&1; then",
            "        echo 'ERROR: Still cannot access Kubernetes cluster after refresh'",
            "        echo 'Please check K3s installation and permissions'",
            "        exit 1",
            "    fi",
            "fi",

            "echo 'Kubernetes validation completed. Proceeding with Rancher deployment...'",
        ]
    }
}

resource "null_resource" "cert_manager_initialization" {
    depends_on = [ null_resource.preflight ]

    connection {
        type = "ssh"
        host = var.server.ssh_server
        port = var.server.ssh_port
        user = var.server.ssh_username
        private_key = file(var.server.ssh_private_key_path)
        password = var.server.ssh_password
        timeout = "2m"
    }

    provisioner "remote-exec" {
        inline = [
            "echo 'Setting up kubeconfig for cert-manager installation...'",
            "export KUBECONFIG=~/.kube/config",

            "echo 'Creating cert-manager namespace...'",
            "kubectl create namespace cert-manager || true",

            "echo 'Creating GitHub Container Registry (ghcr.io) image pull secret in cert-manager namespace...'",
            "kubectl --kubeconfig ~/.kube/config create secret docker-registry ghcr-io-secret \\",
            "  --namespace=cert-manager \\",
            "  --docker-server=ghcr.io \\",
            "  --docker-username='${var.github.username}' \\",
            "  --docker-password='${var.github.token}' \\",
            "  --docker-email='${var.github.username}@users.noreply.github.com' \\",
            "  --dry-run=client -o yaml | kubectl --kubeconfig ~/.kube/config apply -f -",
            "echo 'GitHub Container Registry secret created successfully in cert-manager namespace'",

            "echo 'Adding Jetstack Helm repository...'",
            "helm --kubeconfig ~/.kube/config repo add jetstack https://charts.jetstack.io || true",
            "helm --kubeconfig ~/.kube/config repo update",

            "echo 'Installing cert-manager...'",
            "helm --kubeconfig ~/.kube/config install cert-manager jetstack/cert-manager --namespace cert-manager --version v1.13.2 --set installCRDs=true",

            "echo 'Waiting for cert-manager pods to be ready...'",
            "sleep 60",

            "kubectl --kubeconfig ~/.kube/config wait --for=condition=ready pod -l app=cert-manager -n cert-manager --timeout=300s",
            "kubectl --kubeconfig ~/.kube/config wait --for=condition=ready pod -l app=webhook -n cert-manager --timeout=300s",
            "kubectl --kubeconfig ~/.kube/config wait --for=condition=ready pod -l app=cainjector -n cert-manager --timeout=300s",

            "echo 'cert-manager installation completed successfully'"
        ]
    }
}

resource "null_resource" "rancher_initialization" {
    depends_on = [ null_resource.cert_manager_initialization ]

    connection {
        type = "ssh"
        host = var.server.ssh_server
        port = var.server.ssh_port
        user = var.server.ssh_username
        private_key = file(var.server.ssh_private_key_path)
        password = var.server.ssh_password
        timeout = "2m"
    }

    provisioner "remote-exec" {
        inline = [
            "echo 'Setting up kubeconfig for Rancher installation...'",
            "export KUBECONFIG=~/.kube/config",

            "echo 'Creating cattle-system namespace...'",
            "kubectl create namespace cattle-system || true",

            "echo 'Creating GitHub Container Registry (ghcr.io) image pull secret in cattle-system namespace...'",
            "kubectl --kubeconfig ~/.kube/config create secret docker-registry ghcr-io-secret \\",
            "  --namespace=cattle-system \\",
            "  --docker-server=ghcr.io \\",
            "  --docker-username='${var.github.username}' \\",
            "  --docker-password='${var.github.token}' \\",
            "  --docker-email='${var.github.username}@users.noreply.github.com' \\",
            "  --dry-run=client -o yaml | kubectl --kubeconfig ~/.kube/config apply -f -",
            "echo 'GitHub Container Registry secret created successfully in cattle-system namespace'",

            "echo 'Adding Rancher Helm repository...'",
            "helm --kubeconfig ~/.kube/config repo add rancher-latest https://releases.rancher.com/server-charts/latest || true",
            "helm --kubeconfig ~/.kube/config repo update",

            "echo 'Installing Rancher...'",
            "helm --kubeconfig ~/.kube/config install rancher rancher-latest/rancher --namespace cattle-system --set hostname=${var.rancher.hostname} --set bootstrapPassword=${var.rancher.bootstrap_password} --set replicas=1 --set ingress.tls.source=letsEncrypt --set letsEncrypt.email=${var.rancher.letsencrypt_email} --set letsEncrypt.environment=production",

            "echo 'Waiting for Rancher deployment to be ready...'",
            "sleep 120",

            "kubectl --kubeconfig ~/.kube/config -n cattle-system rollout status deploy/rancher --timeout=600s",

            "echo 'Rancher installation completed successfully'"
        ]
    }
}

resource "null_resource" "rancher_termination" {
    triggers = {
        initialization_id = null_resource.rancher_initialization.id
        ssh_server = var.server.ssh_server
        ssh_port = var.server.ssh_port
        ssh_username = var.server.ssh_username
        ssh_password = var.server.ssh_password
        ssh_private_key_path = var.server.ssh_private_key_path
    }

    connection {
        type = "ssh"
        host = self.triggers.ssh_server
        port = self.triggers.ssh_port
        user = self.triggers.ssh_username
        private_key = file(self.triggers.ssh_private_key_path)
        password = self.triggers.ssh_password
        timeout = "2m"
    }

    provisioner "remote-exec" {
        when = destroy
        inline = [
            "echo 'Setting up kubeconfig for Rancher removal...'",
            "export KUBECONFIG=~/.kube/config",

            "echo 'Checking if Rancher is deployed...'",
            "if helm --kubeconfig ~/.kube/config list -n cattle-system | grep -q rancher; then",
            "    echo 'Uninstalling Rancher...'",
            "    helm --kubeconfig ~/.kube/config uninstall rancher --namespace cattle-system",
            "    kubectl --kubeconfig ~/.kube/config delete all --all -n cattle-system",
            "    kubectl --kubeconfig ~/.kube/config delete namespace cattle-system",
            "    echo 'Rancher deployment and namespace deleted successfully'",
            "else",
            "    echo 'No Rancher deployment found. Skipping deletion.'",
            "fi"
        ]
        on_failure = continue
    }
}

resource "null_resource" "cert_manager_termination" {
    triggers = {
        initialization_id = null_resource.cert_manager_initialization.id
        ssh_server = var.server.ssh_server
        ssh_port = var.server.ssh_port
        ssh_username = var.server.ssh_username
        ssh_password = var.server.ssh_password
        ssh_private_key_path = var.server.ssh_private_key_path
    }

    connection {
        type = "ssh"
        host = self.triggers.ssh_server
        port = self.triggers.ssh_port
        user = self.triggers.ssh_username
        private_key = file(self.triggers.ssh_private_key_path)
        password = self.triggers.ssh_password
        timeout = "2m"
    }

    provisioner "remote-exec" {
        when = destroy
        inline = [
            "echo 'Setting up kubeconfig for cert-manager removal...'",
            "export KUBECONFIG=~/.kube/config",

            "echo 'Checking if cert-manager is deployed...'",
            "if helm --kubeconfig ~/.kube/config list -n cert-manager | grep -q cert-manager; then",
            "    echo 'Uninstalling cert-manager...'",
            "    helm --kubeconfig ~/.kube/config uninstall cert-manager --namespace cert-manager",
            "    kubectl --kubeconfig ~/.kube/config delete all --all -n cert-manager",
            "    kubectl --kubeconfig ~/.kube/config delete namespace cert-manager",
            "    echo 'cert-manager deployment and namespace deleted successfully'",
            "else",
            "    echo 'No cert-manager deployment found. Skipping deletion.'",
            "fi"
        ]
        on_failure = continue
    }
}

output "rancher_url" {
  description = "URL to access Rancher UI"
  value       = "https://${var.rancher.hostname}"
}

output "rancher_hostname" {
  description = "Rancher hostname"
  value       = var.rancher.hostname
}

output "rancher_bootstrap_password" {
  description = "Rancher bootstrap password"
  value       = var.rancher.bootstrap_password
}
