variable "regiao" {
  description = "Região AWS (Learner Lab usa us-east-1)"
  type        = string
  default     = "us-east-1"
}

variable "ip_admin" {
  description = "CIDR do IP do time para SSH/Grafana/Prometheus (ex.: 203.0.113.10/32). Sem default de propósito: nunca abrir admin para 0.0.0.0/0."
  type        = string

  validation {
    condition     = var.ip_admin != "0.0.0.0/0"
    error_message = "ip_admin não pode ser 0.0.0.0/0 — portas administrativas são restritas ao IP do time."
  }
}

variable "chave_ssh" {
  description = "Key pair da EC2 (no Learner Lab a 'vockey' já existe)"
  type        = string
  default     = "vockey"
}

variable "tipo_instancia" {
  description = "Tipo da instância (t3.small aguenta app + Prometheus + Grafana)"
  type        = string
  default     = "t3.small"
}
