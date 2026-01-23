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
    
    // Stage 3: Plan Generation
    // Generates execution plan with detailed exit codes
    // -detailed-exitcode: returns 2 if plan would make changes (useful for CI)
    stage('Terraform Plan') {
      steps {
        dir('terraform') {
          // Initialize with backend (needed for plan)
          sh 'terraform init'
          
          // Download terraform.tfvars from Azure Storage Account using Key Vault credentials
          // Configuration via Jenkins environment variables:
          // - AZURE_KEY_VAULT_NAME: Name of Key Vault containing Storage Account key
          // - AZURE_STORAGE_ACCOUNT_NAME: Storage Account name
          // - AZURE_STORAGE_CONTAINER_NAME: Container name
          // - AZURE_STORAGE_BLOB_PATH: (Optional) Blob path, defaults to 'terraform.tfvars'
          // - AZURE_STORAGE_KEY_SECRET_NAME: (Optional) Key Vault secret name, defaults to 'storage-account-key'
          script {
            def tfvarsDownloaded = false
            
            // Try to download terraform.tfvars from Azure Storage using Key Vault
            if (env.AZURE_KEY_VAULT_NAME && env.AZURE_STORAGE_ACCOUNT_NAME && env.AZURE_STORAGE_CONTAINER_NAME) {
              try {
                echo "Downloading terraform.tfvars from Azure Storage Account via Key Vault..."
                def blobPath = env.AZURE_STORAGE_BLOB_PATH ?: 'terraform.tfvars'
                def secretName = env.AZURE_STORAGE_KEY_SECRET_NAME ?: 'storage-account-key'
                
                // Install Azure CLI if not available (for terraform container)
                sh '''
                  # NOTE: Jenkins "terraform" container is hashicorp/terraform (Alpine, minimal).
                  # It often lacks curl/bash, and using the Debian installer won't work anyway.
                  # For CI we treat Azure download as best-effort and fall back if unavailable.
                  if ! command -v az &> /dev/null; then
                    echo "Azure CLI not found (expected in minimal terraform image). Skipping Azure download step."
                    exit 127
                  fi
                '''
                
                // Authenticate to Azure (supports multiple methods)
                // Priority: Workload Identity > Service Principal > Managed Identity
                sh '''
                  # Try to authenticate using available method
                  # Method 1: Workload Identity (if Jenkins service account is configured)
                  # Method 2: Service Principal (if credentials are set)
                  # Method 3: Managed Identity (if running on Azure VM)
                  
                  if [ -n "$AZURE_CLIENT_ID" ] && [ -n "$AZURE_TENANT_ID" ] && [ -n "$AZURE_CLIENT_SECRET" ]; then
                    echo "Authenticating with Service Principal..."
                    az login --service-principal \
                      --username "$AZURE_CLIENT_ID" \
                      --password "$AZURE_CLIENT_SECRET" \
                      --tenant "$AZURE_TENANT_ID" || true
                  elif [ -n "$AZURE_CLIENT_ID" ] && [ -n "$AZURE_TENANT_ID" ] && [ -n "$AZURE_FEDERATED_TOKEN_FILE" ]; then
                    echo "Authenticating with Workload Identity..."
                    az login --federated-token "$(cat $AZURE_FEDERATED_TOKEN_FILE)" \
                      --service-principal \
                      --username "$AZURE_CLIENT_ID" \
                      --tenant "$AZURE_TENANT_ID" || true
                  else
                    echo "Attempting Managed Identity authentication..."
                    az login --identity || echo "Managed Identity authentication failed"
                  fi
                '''
                
                // Retrieve Storage Account key from Key Vault and download terraform.tfvars
                sh """
                  echo "Retrieving Storage Account key from Key Vault: ${env.AZURE_KEY_VAULT_NAME}"
                  STORAGE_KEY=\$(az keyvault secret show \
                    --vault-name ${env.AZURE_KEY_VAULT_NAME} \
                    --name ${secretName} \
                    --query value -o tsv)
                  
                  if [ -z "\$STORAGE_KEY" ]; then
                    echo "ERROR: Failed to retrieve Storage Account key from Key Vault"
                    exit 1
                  fi
                  
                  echo "✅ Successfully retrieved Storage Account key from Key Vault"
                  
                  # Download terraform.tfvars using the key
                  az storage blob download \
                    --account-name ${env.AZURE_STORAGE_ACCOUNT_NAME} \
                    --account-key "\$STORAGE_KEY" \
                    --container-name ${env.AZURE_STORAGE_CONTAINER_NAME} \
                    --name ${blobPath} \
                    --file terraform.tfvars
                """
                
                // Check if file was downloaded successfully
                if (fileExists('terraform.tfvars')) {
                  echo "✅ Successfully downloaded terraform.tfvars from Azure Storage"
                  tfvarsDownloaded = true
                } else {
                  echo "⚠️ terraform.tfvars not found after download attempt, using fallback"
                }
              } catch (Exception e) {
                echo "⚠️ Failed to download terraform.tfvars from Azure Storage: ${e.getMessage()}"
                echo "   Falling back to environment variables or dummy values"
              }
            } else {
              echo "ℹ️ Azure Storage Account/Key Vault not configured, using environment variables or dummy values"
              echo "   Required: AZURE_KEY_VAULT_NAME, AZURE_STORAGE_ACCOUNT_NAME, AZURE_STORAGE_CONTAINER_NAME"
            }
            
            // If terraform.tfvars was downloaded, terraform will use it automatically
            // Otherwise, provide variables via environment variables or dummy values
            if (!tfvarsDownloaded) {
              def compartmentId = env.TF_VAR_compartment_id ?: 'ocid1.compartment.oc1..dummy'
              def sshKey = env.TF_VAR_ssh_public_key ?: 'ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABgQC7vbqajDhA... dummy-key-for-validation-only'
              
              // Export as environment variables for terraform
              withEnv([
                "TF_VAR_compartment_id=${compartmentId}",
                "TF_VAR_ssh_public_key=${sshKey}"
              ]) {
                sh 'terraform plan -detailed-exitcode -no-color'
              }
            } else {
              // terraform.tfvars is present, terraform will use it automatically
              sh 'terraform plan -detailed-exitcode -no-color'
            }
          }
        }
      }
    }
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
