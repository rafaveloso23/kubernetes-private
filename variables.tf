/* variable "tags-worker" {
  type = map(any)
  default = {
    "KubernetesRole" = "worker"
  }
}

variable "tags-master" {
  type = map(any)
  default = {
    "KubernetesRole" = "control-plane"
  }
} */

variable "tags" {
  type = map(any)
  default = {
    "cliente" = "teste"
  }
}