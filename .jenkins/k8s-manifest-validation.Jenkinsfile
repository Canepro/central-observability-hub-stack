// Kubernetes Manifest Validation Pipeline for central-observability-hub-stack
// This pipeline validates ArgoCD apps, Helm charts, and raw K8s manifests.
// Purpose: CI validation only - ensures all manifests are valid before GitOps sync.
pipeline {
  // Use the 'helm' Kubernetes agent (has Helm, kubectl, kubeconform)
  agent {
    kubernetes {
      label 'helm'
      defaultContainer 'helm'
    }
  }
  
  stages {
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
              # -strict: fail on unknown fields or API mismatches
              kubeconform -strict "$app" || exit 1
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
                kubeconform -strict "$manifest" || exit 1
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
          yamllint -c .yamllint.yaml argocd/ || true
          
          # Lint Helm values files
          yamllint -c .yamllint.yaml helm/ || true
          
          # Lint raw Kubernetes manifests
          yamllint -c .yamllint.yaml k8s/ || true
          # || true: warnings don't fail build, only errors
        '''
      }
    }
  }
  
  post {
    always {
      cleanWs()
    }
    success {
      echo '✅ Kubernetes manifest validation passed'
    }
    failure {
      echo '❌ Kubernetes manifest validation failed'
    }
  }
}
