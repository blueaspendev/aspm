terraform {
  required_providers {
    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.12.0"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.24.0"
    }
  }
}

provider "helm" {
  kubernetes {
    config_path    = "~/.kube/config"
    config_context = "docker-desktop"
  }
}

provider "kubernetes" {
  config_path    = "~/.kube/config"
  config_context = "docker-desktop"
}

# Create namespace
resource "kubernetes_namespace" "security_stack" {
  metadata {
    name = "security-stack"
  }
}

# Helm repository configurations
locals {
  helm_repositories = {
    aqua = "https://aquasecurity.github.io/helm-charts/"
    gatekeeper = "https://open-policy-agent.github.io/gatekeeper/charts"
    falcosecurity = "https://falcosecurity.github.io/charts"
    prometheus = "https://prometheus-community.github.io/helm-charts"
    elastic = "https://helm.elastic.co"
    fluent = "https://fluent.github.io/helm-charts"
    harbor = "https://helm.goharbor.io"
  }

  # Component configurations
  components = {
    trivy = {
      repository = local.helm_repositories.aqua
      chart      = "trivy"
      version    = "0.5.0"
      values = {
        resources = {
          requests = {
            memory = "256Mi"
            cpu    = "250m"
          }
        }
      }
    }
    

    
    gatekeeper = {
      repository = local.helm_repositories.gatekeeper
      chart      = "gatekeeper"
      version    = "3.14.0"
      values = {
        podSecurityPolicy = {
          enabled = false
        }
        auditInterval = 60
        constraintViolationsLimit = 100
      }
    }
    
    falco = {
      repository = local.helm_repositories.falcosecurity
      chart      = "falco"
      version    = "3.0.0"
      values = {
        jsonOutput = true
        httpOutput = {
          enabled = true
          url     = "http://falcosidekick:2801/"
        }
      }
    }
    
    prometheus = {
      repository = local.helm_repositories.prometheus
      chart      = "kube-prometheus-stack"
      version    = "45.0.0"
      values = {
        grafana = {
          enabled = true
          persistence = {
            enabled = true
            size    = "10Gi"
          }
        }
      }
    }
    
    elasticsearch = {
      repository = local.helm_repositories.elastic
      chart      = "elasticsearch"
      version    = "8.5.1"
      values = {
        persistence = {
          enabled = true
          size    = "30Gi"
        }
      }
    }
    
    fluentd = {
      repository = local.helm_repositories.fluent
      chart      = "fluentd"
      version    = "0.5.0"
      values = {
        podSecurityPolicy = {
          enabled = false
        }
      }
    }
    
    kibana = {
      repository = local.helm_repositories.elastic
      chart      = "kibana"
      version    = "8.5.1"
      values = {
        cleanupOnFail = true
        force = true
        serviceAccount = {
          create = true
          name = "kibana"
        }
      }
    }
    
    harbor = {
      repository = local.helm_repositories.harbor
      chart      = "harbor"
      version    = "1.12.0"
      values = {
        persistence = {
          enabled = true
          size    = "50Gi"
        }
        expose = {
          type = "ingress"
          tls  = {
            enabled = true
          }
        }
      }
    }
  }
}

# Deploy components
resource "helm_release" "cnaspm_components" {
  for_each = local.components

  name       = replace(each.key, "_", "-")
  repository = each.value.repository
  chart      = each.value.chart
  version    = each.value.version
  namespace  = kubernetes_namespace.security_stack.metadata[0].name

  values = [
    try(yamlencode(each.value.values), "")
  ]

  depends_on = [kubernetes_namespace.security_stack]

  # Add timeout and wait for resources to be ready
  timeout = 1800
  wait    = true

  # Add basic retry logic
  lifecycle {
    ignore_changes = [
      values,
      version,
    ]
  }
}

# Outputs
output "deployed_components" {
  description = "List of deployed CNASPM components"
  value = {
    for name, release in helm_release.cnaspm_components : name => {
      status  = release.status
      version = release.version
    }
  }
} 