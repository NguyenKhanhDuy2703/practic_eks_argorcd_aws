resource "helm_release" "argocd" {
  name             = "argocd"
  repository       = "https://argoproj.github.io/argo-helm"
  chart            = "argo-cd"
  version          = "7.7.5"
  namespace        = "argocd"
  create_namespace = true
  wait             = true

  # Ensure the cluster is ready before installing ArgoCD
  depends_on = [var.cluster_id]

  values = [
    <<-EOT
    server:
      # Expose argocd server for convenience if needed, or leave it ClusterIP
      service:
        type: ClusterIP
    EOT
  ]
}

resource "helm_release" "argocd_apps" {
  name       = "argocd-apps"
  repository = "https://argoproj.github.io/argo-helm"
  chart      = "argocd-apps"
  version    = "2.0.2"
  namespace  = "argocd"

  # We must wait for ArgoCD to be installed and CRDs established
  depends_on = [helm_release.argocd]

  values = [
    <<-EOT
    applications:
      tf1-root-app:
        namespace: argocd
        project: default
        source:
          repoURL: https://github.com/NguyenKhanhDuy2703/practic_eks_argorcd_aws.git
          path: tf1-triage-hub/cd/argocd-apps
          targetRevision: main
        destination:
          server: https://kubernetes.default.svc
          namespace: argocd
        syncPolicy:
          automated:
            prune: true
            selfHeal: true
          syncOptions:
            - CreateNamespace=true
    EOT
  ]
}
