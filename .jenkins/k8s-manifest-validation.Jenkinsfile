// Kubernetes Manifest Validation Pipeline for central-observability-hub-stack
// This pipeline validates ArgoCD apps, Helm charts, and raw K8s manifests.
// Purpose: CI validation only - ensures all manifests are valid before GitOps sync.
// Agent routing (Phase 3): OKE-only — runs on OKE (label helm). For Azure jobs use label 'aks-agent'.
pipeline {
  // Use the 'helm' Kubernetes agent (has Helm, kubeconform). OKE/CRI-O requires fully qualified image names.
  agent {
    kubernetes {
      label 'helm'
      defaultContainer 'helm'
      yaml """
apiVersion: v1
kind: Pod
spec:
  containers:
  - name: jnlp
    image: docker.io/jenkins/inbound-agent:3355.v388858a_47b_33-8-jdk21
    resources:
      requests:
        memory: "256Mi"
        cpu: "100m"
      limits:
        memory: "512Mi"
        cpu: "500m"
  - name: helm
    image: docker.io/alpine:3.20
    command: ['sleep', '3600']
    resources:
      requests:
        memory: "256Mi"
        cpu: "100m"
      limits:
        memory: "512Mi"
        cpu: "500m"
"""
    }
  }
  
  stages {
    // Stage 0: Install helm and kubeconform (Alpine image does not include them)
    stage('Install Tools') {
      steps {
        sh '''
          apk add --no-cache curl openssl tar gzip
          # Helm (needs openssl for checksum verification)
          curl -fsSL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | sh || true
          # kubeconform
          KUBECONFORM_VERSION="v0.6.3"
          ARCH="$(uname -m)"
          case "$ARCH" in
            x86_64) KUBECONFORM_ARCH="amd64" ;;
            aarch64|arm64) KUBECONFORM_ARCH="arm64" ;;
            *) KUBECONFORM_ARCH="amd64" ;;
          esac
          KUBECONFORM_TGZ="/tmp/kubeconform-${KUBECONFORM_VERSION}.tgz"
          curl -fsSL -o "$KUBECONFORM_TGZ" "https://github.com/yannh/kubeconform/releases/download/${KUBECONFORM_VERSION}/kubeconform-linux-${KUBECONFORM_ARCH}.tar.gz" || true
          if [ -f "$KUBECONFORM_TGZ" ]; then
            tar -xzf "$KUBECONFORM_TGZ" -C /usr/local/bin kubeconform || true
            chmod +x /usr/local/bin/kubeconform || true
          fi
          helm version || true
          kubeconform -v || true
        '''
      }
    }
    // Stage 1: ArgoCD Application Validation
    // Validates ArgoCD Application CRDs (the GitOps control plane manifests)
    // These define what ArgoCD should deploy and from where
    stage('ArgoCD App Validation') {
      steps {
        sh '''
          # Validate each ArgoCD Application manifest
          # These are the GitOps control plane definitions
          for app in argocd/applications/*.yaml; do
            if [ -f "$app" ]; then
              # AppProject/Application are CRDs; allow missing schemas unless CRDs are provided explicitly
              kubeconform -strict -ignore-missing-schemas "$app" || exit 1
            fi
          done
        '''
      }
    }
    
    // Stage 2: Helm Chart Validation
    // Renders and validates all Helm charts in the helm/ directory
    // Ensures Helm templates produce valid Kubernetes manifests
    stage('Helm Chart Validation') {
      steps {
        dir('helm') {
          sh '''
            # Find all Helm chart directories with values.yaml
            for chart_dir in */; do
              if [ -f "${chart_dir}values.yaml" ]; then
                chart_name=$(basename "$chart_dir")
                # Render Helm chart to raw Kubernetes manifests
                helm template "$chart_name" "$chart_dir" -f "${chart_dir}values.yaml" > /tmp/"$chart_name"-manifests.yaml
                # Validate rendered manifests against K8s schema
                kubeconform -strict /tmp/"$chart_name"-manifests.yaml || exit 1
              fi
            done
          '''
        }
      }
    }
    
    // Stage 3: Raw Kubernetes Manifest Validation
    // Validates raw Kubernetes manifests in k8s/ directory
    // These are non-Helm manifests (Ingress, ConfigMaps, etc.)
    stage('K8s Manifest Validation') {
      steps {
        sh '''
          # Validate raw Kubernetes manifests (non-Helm)
          # These are typically Ingress, ConfigMaps, Secrets, etc.
          if [ -d "k8s" ]; then
            for manifest in k8s/**/*.yaml; do
              if [ -f "$manifest" ]; then
                # Validate each manifest against K8s API schema
                kubeconform -strict -ignore-missing-schemas "$manifest" || exit 1
              fi
            done
          fi
        '''
      }
    }
    
    // Stage 4: YAML Linting
    // Checks YAML syntax, indentation, and style consistency
    // Catches formatting issues before they reach the cluster
    stage('YAML Lint') {
      steps {
        sh '''
          # Install yamllint if not available
          apk add --no-cache yamllint || true
          
          # Lint ArgoCD Application manifests
          yamllint -c .yamllint.yaml argocd/
          
          # Lint Helm values files
          yamllint -c .yamllint.yaml helm/
          
          # Lint raw Kubernetes manifests
          yamllint -c .yamllint.yaml k8s/
          # || true: warnings don't fail build, only errors
        '''
      }
    }
  }
  
  post {
    always {
      // Only clean workspace when we ran on an agent; otherwise MissingContextVariableException (no FilePath).
      script { if (env.WORKSPACE?.trim()) { cleanWs() } }
    }
    success {
      echo '✅ Kubernetes manifest validation passed'
    }
    failure {
      echo '❌ Kubernetes manifest validation failed'
    }
  }
}
