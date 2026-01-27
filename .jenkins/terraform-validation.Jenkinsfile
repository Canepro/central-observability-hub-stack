// Terraform Validation Pipeline for central-observability-hub-stack
// This pipeline validates Terraform infrastructure code for the OKE Hub cluster.
// Uses OCI API Key authentication for terraform plan.
pipeline {
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

  environment {
    // OCI Configuration
    OCI_TENANCY_OCID = 'ocid1.tenancy.oc1..aaaaaaaadeivc3duoyx3pffmgzkcv2zo2gyuq2ftxybicrpianpnmeccgeba'
    OCI_USER_OCID = 'ocid1.user.oc1..aaaaaaaazvirssisy5xeic6gr64i37ffnk54bhsq7q424wpj4pqy2hzedxzq'
    OCI_FINGERPRINT = '09:a3:e2:dc:12:56:ff:a2:20:4f:55:f8:77:18:9c:f4'
    OCI_REGION = 'us-ashburn-1'
    
    // OCI Object Storage (S3-compatible) for Terraform state backend
    OCI_NAMESPACE = 'iducrocaj9h2'
    
    // Terraform variables (non-sensitive)
    TF_VAR_compartment_id = 'ocid1.tenancy.oc1..aaaaaaaadeivc3duoyx3pffmgzkcv2zo2gyuq2ftxybicrpianpnmeccgeba'
  }

  stages {
    // Stage 1: Setup OCI Authentication
    stage('Setup') {
      steps {
        // OCI API Key from Jenkins credentials
        withCredentials([
          file(credentialsId: 'oci-api-key', variable: 'OCI_KEY_FILE'),
          string(credentialsId: 'oci-s3-access-key', variable: 'AWS_ACCESS_KEY_ID'),
          string(credentialsId: 'oci-s3-secret-key', variable: 'AWS_SECRET_ACCESS_KEY'),
          string(credentialsId: 'oci-ssh-public-key', variable: 'TF_VAR_ssh_public_key')
        ]) {
          sh '''
            # Create OCI config directory
            mkdir -p ~/.oci
            
            # Copy the API key
            cp "$OCI_KEY_FILE" ~/.oci/oci_api_key.pem
            chmod 600 ~/.oci/oci_api_key.pem
            
            # Create OCI config file
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

    // Stage 3: Initialize and Validate
    stage('Terraform Validate') {
      steps {
        withCredentials([
          string(credentialsId: 'oci-s3-access-key', variable: 'AWS_ACCESS_KEY_ID'),
          string(credentialsId: 'oci-s3-secret-key', variable: 'AWS_SECRET_ACCESS_KEY')
        ]) {
          dir('terraform') {
            sh '''
              # Initialize with OCI Object Storage backend
              terraform init \
                -backend-config="access_key=${AWS_ACCESS_KEY_ID}" \
                -backend-config="secret_key=${AWS_SECRET_ACCESS_KEY}"
              
              terraform validate
            '''
          }
        }
      }
    }

    // Stage 4: Terraform Plan
    stage('Terraform Plan') {
      steps {
        withCredentials([
          file(credentialsId: 'oci-api-key', variable: 'OCI_KEY_FILE'),
          string(credentialsId: 'oci-s3-access-key', variable: 'AWS_ACCESS_KEY_ID'),
          string(credentialsId: 'oci-s3-secret-key', variable: 'AWS_SECRET_ACCESS_KEY'),
          string(credentialsId: 'oci-ssh-public-key', variable: 'TF_VAR_ssh_public_key')
        ]) {
          dir('terraform') {
            sh '''
              # Ensure OCI key is in place
              cp "$OCI_KEY_FILE" ~/.oci/oci_api_key.pem
              chmod 600 ~/.oci/oci_api_key.pem
              
              # Run terraform plan
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
      dir('terraform') {
        sh 'terraform show -no-color tfplan > tfplan.txt 2>/dev/null || true'
        archiveArtifacts artifacts: 'tfplan.txt', allowEmptyArchive: true
      }
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
