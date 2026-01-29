// Terraform Validation Pipeline for central-observability-hub-stack
// This pipeline validates Terraform infrastructure code for the OKE Hub cluster.
// Uses OCI API Key authentication for terraform plan.
pipeline {
  parameters {
    // NOTE: Keep these identifiers OUT of git. Configure them in the Jenkins job (or via shared library).
    // These are identifiers (not secrets), but are still environment-specific and shouldn’t be hardcoded in a public repo.
    string(name: 'OCI_TENANCY_OCID', defaultValue: '', description: 'OCI Tenancy OCID')
    string(name: 'OCI_USER_OCID', defaultValue: '', description: 'OCI User OCID (matches the API key owner)')
    string(name: 'OCI_FINGERPRINT', defaultValue: '', description: 'OCI API key fingerprint')
    string(name: 'OCI_REGION', defaultValue: 'us-ashburn-1', description: 'OCI region')
    string(name: 'TF_VAR_compartment_id', defaultValue: '', description: 'OCI Compartment OCID for Terraform (TF_VAR_compartment_id)')
  }

  agent {
    kubernetes {
      label 'terraform-oci'
      defaultContainer 'terraform'
      yaml """
apiVersion: v1
kind: Pod
metadata:
  labels:
    jenkins/agent-type: terraform-oci
spec:
  containers:
  - name: terraform
    image: hashicorp/terraform:latest
    command: ['sleep', '3600']
    resources:
      requests:
        memory: "256Mi"
        cpu: "200m"
      limits:
        memory: "512Mi"
        cpu: "500m"
"""
    }
  }

  stages {
    // Stage 1: Setup OCI Authentication (skipped when OCI params not set, e.g. PR validation)
    stage('Setup') {
      when { expression { return params.OCI_TENANCY_OCID?.trim() && params.OCI_USER_OCID?.trim() && params.OCI_FINGERPRINT?.trim() && params.TF_VAR_compartment_id?.trim() } }
      steps {
        withCredentials([
          file(credentialsId: 'oci-api-key', variable: 'OCI_KEY_FILE')
        ]) {
          sh '''
            mkdir -p ~/.oci
            cp "$OCI_KEY_FILE" ~/.oci/oci_api_key.pem
            chmod 600 ~/.oci/oci_api_key.pem
            cat > ~/.oci/config << EOF
[DEFAULT]
user=${OCI_USER_OCID}
fingerprint=${OCI_FINGERPRINT}
tenancy=${OCI_TENANCY_OCID}
region=${OCI_REGION}
key_file=~/.oci/oci_api_key.pem
EOF
            chmod 600 ~/.oci/config
            echo "OCI configuration created"
            terraform version
          '''
        }
      }
    }

    // Stage 2: Format Check
    stage('Terraform Format') {
      steps {
        dir('terraform') {
          sh 'terraform fmt -check -recursive'
        }
      }
    }

    // Stage 3: Initialize and Validate (no backend when OCI params unset, so PR builds pass without creds)
    stage('Terraform Validate') {
      steps {
        script {
          def ociParamsSet = params.OCI_TENANCY_OCID?.trim() && params.TF_VAR_compartment_id?.trim()
          if (ociParamsSet) {
            withCredentials([
              string(credentialsId: 'oci-s3-access-key', variable: 'S3_ACCESS_KEY'),
              string(credentialsId: 'oci-s3-secret-key', variable: 'S3_SECRET_KEY')
            ]) {
              dir('terraform') {
                sh '''
                  terraform init \
                    -backend-config="access_key=${S3_ACCESS_KEY}" \
                    -backend-config="secret_key=${S3_SECRET_KEY}"
                  terraform validate
                '''
              }
            }
          } else {
            dir('terraform') {
              sh '''
                echo "OCI parameters not set; running init -backend=false and validate (no plan)."
                terraform init -backend=false
                terraform validate
              '''
            }
          }
        }
      }
    }

    // Stage 4: Terraform Plan (skipped when OCI params not set)
    stage('Terraform Plan') {
      when { expression { return params.OCI_TENANCY_OCID?.trim() && params.TF_VAR_compartment_id?.trim() } }
      steps {
        withCredentials([
          file(credentialsId: 'oci-api-key', variable: 'OCI_KEY_FILE'),
          string(credentialsId: 'oci-s3-access-key', variable: 'S3_ACCESS_KEY'),
          string(credentialsId: 'oci-s3-secret-key', variable: 'S3_SECRET_KEY'),
          string(credentialsId: 'oci-ssh-public-key', variable: 'SSH_PUBLIC_KEY')
        ]) {
          dir('terraform') {
            sh '''
              # Export Terraform vars (SSH key doesn't have S3 signature issues)
              export TF_VAR_ssh_public_key="$SSH_PUBLIC_KEY"
              
              # Ensure OCI key is in place
              cp "$OCI_KEY_FILE" ~/.oci/oci_api_key.pem
              chmod 600 ~/.oci/oci_api_key.pem
              
              # Run terraform plan
              # Note: Backend already initialized in previous stage with credentials
              terraform plan \
                -no-color \
                -input=false \
                -out=tfplan \
                -detailed-exitcode || PLAN_EXIT=$?
              
              # Exit codes: 0 = no changes, 1 = error, 2 = changes present
              if [ "${PLAN_EXIT:-0}" = "1" ]; then
                echo "Terraform plan failed"
                exit 1
              elif [ "${PLAN_EXIT:-0}" = "2" ]; then
                echo "Changes detected in plan"
              else
                echo "No changes detected"
              fi
            '''
          }
        }
      }
    }
  }

  post {
    always {
      // NOTE: Do not archive tfplan output by default; plan output can contain sensitive resource attributes.
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
