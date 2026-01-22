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
          // Generate plan with detailed exit codes
          // Exit code 0: no changes, 1: error, 2: changes detected
          sh 'terraform plan -detailed-exitcode -no-color'
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
