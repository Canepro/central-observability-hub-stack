// Terraform Validation Pipeline for central-observability-hub-stack
// This pipeline validates Terraform infrastructure code for the OKE Hub cluster.
// Purpose: CI validation only - complements existing GitHub Actions for redundancy.
pipeline {
  // Use the 'terraform' Kubernetes agent (Hashicorp Terraform image)
  agent {
    kubernetes {
      label 'terraform'
      defaultContainer 'terraform'
    }
  }

  // Environment variables for Azure Storage and Key Vault access
  // For better security, sensitive values (Client ID, Tenant ID) should use Jenkins credentials
  // Resource names are non-sensitive but can be overridden in Jenkins UI if needed
  environment {
    // Azure Key Vault and Storage Account configuration (non-sensitive resource names)
    AZURE_KEY_VAULT_NAME = 'aks-canepro-kv-e8d280'
    AZURE_STORAGE_ACCOUNT_NAME = 'tfcaneprostate1'
    AZURE_STORAGE_CONTAINER_NAME = 'tfstate'
    AZURE_STORAGE_BLOB_PATH = 'terraform.tfvars'
    AZURE_STORAGE_KEY_SECRET_NAME = 'storage-account-key'

    // Azure authentication (using ESO identity)
    // SECURITY NOTE: For public repos, use Jenkins credentials instead:
    //   AZURE_CLIENT_ID = credentials('azure-client-id')
    //   AZURE_TENANT_ID = credentials('azure-tenant-id')
    // For private repos, hardcoded values are acceptable but not best practice
    AZURE_CLIENT_ID = 'fe3d3d95-fb61-4a42-8d82-ec0852486531'
    AZURE_TENANT_ID = 'c3d431f1-3e02-4c62-a825-79cd8f9e2053'

    // Note: AZURE_CLIENT_SECRET is not needed if using Workload Identity
    // The Jenkinsfile will automatically detect and use Workload Identity if configured
  }

  stages {
    // Stage 1: Format Check
    // Ensures all Terraform files follow consistent formatting standards
    stage('Terraform Format Check') {
      steps {
        dir('terraform') {
          // -check: only check, don't modify files
          // -recursive: check all subdirectories
          sh 'terraform fmt -check -recursive'
        }
      }
    }

    // Stage 2: Syntax Validation
    // Validates Terraform configuration syntax and basic consistency
    stage('Terraform Validate') {
      steps {
        dir('terraform') {
          // -backend=false: no state file needed for validation
          sh 'terraform init -backend=false'
          // Validate configuration syntax
          sh 'terraform validate'
        }
      }
    }

    // Stage 3: Plan Generation (SKIPPED in CI)
    // Plan generation requires OCI authentication which is not available in CI.
    // Format and Validate stages are sufficient for CI validation.
    // Real planning/apply happens in Cloud Shell with proper OCI authentication.
    //
    // NOTE: Plan stage is commented out because:
    // - OCI provider requires proper tenancy/user/fingerprint/key configuration
    // - Jenkins Terraform container is minimal (no OCI CLI/config available)
    // - Format + Validate stages provide sufficient CI validation
    // - Actual planning/apply happens in Cloud Shell with proper OCI auth
    //
    // stage('Terraform Plan') {
    //   steps {
    //     dir('terraform') {
    //       sh 'terraform init'
    //       script {
    //         // ... entire plan stage commented out ...
    //         // OCI authentication required but not available in CI
    //       }
    //     }
    //   }
    // }
  }

  post {
    always {
      cleanWs()
    }
    success {
      echo '✅ Terraform validation passed'
    }
    failure {
      echo '❌ Terraform validation failed'
    }
  }
}
