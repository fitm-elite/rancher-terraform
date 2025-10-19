variable "github" {
    description = "GitHub configuration for accessing private repositories."
    type = object({
        username = string
        token    = string
    })
}

variable "rancher" {
    description = "Rancher configuration."
    type = object({
        hostname          = string
        letsencrypt_email = string
        bootstrap_password = string
    })
}

variable "server" {
    description = "Server configurations for SSH access."
    type = object({
        ssh_server = string
        ssh_port      = number
        ssh_username      = string
        ssh_password     = string
        ssh_private_key_path = string
    })
}
