// Terraform Validation Pipeline for central-observability-hub-stack
// This pipeline validates Terraform infrastructure code for the OKE Hub cluster.
// Uses OCI API Key authentication for terraform plan.
// Agent routing (Phase 3): OCI-only — runs on OKE (label terraform-oci). For Azure Terraform use label 'aks-agent'.
pipeline {
  environment {
    GITHUB_REPO = 'Canepro/central-observability-hub-stack'
    PIPELINEHEALER_BRIDGE_URL_CREDENTIALS = 'pipelinehealer-bridge-url'
    PIPELINEHEALER_BRIDGE_SECRET_CREDENTIALS = 'pipelinehealer-bridge-secret'
  }

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
  - name: jnlp
    image: docker.io/jenkins/inbound-agent:3355.v388858a_47b_33-8-jdk21
    resources:
      requests:
        memory: "128Mi"
        cpu: "50m"
      limits:
        memory: "512Mi"
        cpu: "500m"
  - name: terraform
    image: docker.io/hashicorp/terraform:latest
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
    // Resolve OCI config: use Build Parameters if set, else use Jenkins credentials (Secret text) under this folder
    stage('Resolve OCI config') {
      steps {
        script {
          if (params.OCI_TENANCY_OCID?.trim()) {
            env.OCI_TENANCY_OCID = params.OCI_TENANCY_OCID.trim()
            env.OCI_USER_OCID = params.OCI_USER_OCID?.trim() ?: ''
            env.OCI_FINGERPRINT = params.OCI_FINGERPRINT?.trim() ?: ''
            env.OCI_REGION = params.OCI_REGION?.trim() ?: 'us-ashburn-1'
            env.TF_VAR_compartment_id = params.TF_VAR_compartment_id?.trim() ?: ''
          } else {
            // Secret text creds under GrafanaLocal folder: tenancy OCID, user OCID, API key fingerprint, region, compartment OCID
            withCredentials([
              string(credentialsId: 'oci-tenancy-ocid', variable: 'OCI_TENANCY_OCID'),       // root tenancy OCID
              string(credentialsId: 'oci-user-ocid', variable: 'OCI_USER_OCID'),               // user that owns API key
              string(credentialsId: 'oci-fingerprint', variable: 'OCI_FINGERPRINT'),            // matches oci-api-key PEM
              string(credentialsId: 'oci-region', variable: 'OCI_REGION'),                    // e.g. us-ashburn-1
              string(credentialsId: 'tf-var-compartment-id', variable: 'TF_VAR_compartment_id') // compartment for OKE
            ]) {
              env.OCI_TENANCY_OCID = (env.OCI_TENANCY_OCID ?: '').trim()
              env.OCI_USER_OCID = (env.OCI_USER_OCID ?: '').trim()
              env.OCI_FINGERPRINT = (env.OCI_FINGERPRINT ?: '').trim()
              env.OCI_REGION = (env.OCI_REGION?.trim()) ? env.OCI_REGION.trim() : 'us-ashburn-1'
              env.TF_VAR_compartment_id = (env.TF_VAR_compartment_id ?: '').trim()
            }
          }
        }
      }
    }

    // Stage 2: Setup OCI Authentication (skipped when OCI not resolved, e.g. PR validation)
    stage('Setup') {
      when { expression { return env.OCI_TENANCY_OCID?.trim() && env.OCI_USER_OCID?.trim() && env.OCI_FINGERPRINT?.trim() && env.TF_VAR_compartment_id?.trim() } }
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

            # Helm provider uses exec auth via `oci ce cluster generate-token`.
            # The terraform container may not ship with the OCI CLI, so install it if missing.
            if ! command -v oci >/dev/null 2>&1; then
              echo "Installing OCI CLI (required for Helm provider auth)..."
              apk add --no-cache bash curl ca-certificates python3 py3-pip >/dev/null 2>&1 || true
              update-ca-certificates >/dev/null 2>&1 || true
              python3 -m venv /tmp/oci-cli-venv >/dev/null 2>&1 || true
              if [ -f /tmp/oci-cli-venv/bin/activate ]; then
                . /tmp/oci-cli-venv/bin/activate
                pip install --no-cache-dir oci-cli
                deactivate || true
                ln -sf /tmp/oci-cli-venv/bin/oci /usr/local/bin/oci || true
              fi
            fi
            command -v oci >/dev/null 2>&1 && oci --version || echo "WARN: OCI CLI not available; Helm provider may treat releases as missing."

            terraform version
          '''
        }
      }
    }

    // Stage 3: Format Check
    stage('Terraform Format') {
      steps {
        sh '''
          cat <<'SCRIPT' | sh .jenkins/scripts/capture-pipelinehealer-bridge-excerpt.sh "${WORKSPACE}/.pipelinehealer-log-excerpt.txt"
          cd terraform
          terraform fmt -check -recursive
SCRIPT
        '''
      }
    }

    // Stage 4: Initialize and Validate (no backend when OCI not resolved, so PR builds pass without creds)
    stage('Terraform Validate') {
      steps {
        script {
          def ociParamsSet = env.OCI_TENANCY_OCID?.trim() && env.TF_VAR_compartment_id?.trim()
          if (ociParamsSet) {
            withCredentials([
              string(credentialsId: 'oci-s3-access-key', variable: 'S3_ACCESS_KEY'),
              string(credentialsId: 'oci-s3-secret-key', variable: 'S3_SECRET_KEY')
            ]) {
              sh '''
                cat <<'SCRIPT' | sh .jenkins/scripts/capture-pipelinehealer-bridge-excerpt.sh "${WORKSPACE}/.pipelinehealer-log-excerpt.txt"
                cd terraform
                terraform init \
                  -backend-config="access_key=${S3_ACCESS_KEY}" \
                  -backend-config="secret_key=${S3_SECRET_KEY}"
                echo "--- Backend state list (verify Jenkins sees same state as local) ---"
                terraform state list || true
                terraform validate
SCRIPT
              '''
            }
          } else {
            sh '''
              cat <<'SCRIPT' | sh .jenkins/scripts/capture-pipelinehealer-bridge-excerpt.sh "${WORKSPACE}/.pipelinehealer-log-excerpt.txt"
              cd terraform
              echo "OCI parameters not set; running init -backend=false and validate (no plan)."
              terraform init -backend=false
              terraform validate
SCRIPT
            '''
          }
        }
      }
    }

    // Stage 5: Terraform Plan (skipped when OCI not resolved)
    stage('Terraform Plan') {
      when { expression { return env.OCI_TENANCY_OCID?.trim() && env.TF_VAR_compartment_id?.trim() } }
      steps {
        withCredentials([
          file(credentialsId: 'oci-api-key', variable: 'OCI_KEY_FILE'),
          string(credentialsId: 'oci-s3-access-key', variable: 'S3_ACCESS_KEY'),
          string(credentialsId: 'oci-s3-secret-key', variable: 'S3_SECRET_KEY'),
          string(credentialsId: 'oci-ssh-public-key', variable: 'SSH_PUBLIC_KEY')
        ]) {
          sh '''
            cat <<'SCRIPT' | sh .jenkins/scripts/capture-pipelinehealer-bridge-excerpt.sh "${WORKSPACE}/.pipelinehealer-log-excerpt.txt"
            cd terraform
            export TF_VAR_ssh_public_key="$SSH_PUBLIC_KEY"
            cp "$OCI_KEY_FILE" ~/.oci/oci_api_key.pem
            chmod 600 ~/.oci/oci_api_key.pem
            terraform plan \
              -no-color \
              -input=false \
              -out=tfplan \
              -detailed-exitcode || PLAN_EXIT=$?

            if [ "${PLAN_EXIT:-0}" = "1" ]; then
              echo "Terraform plan failed"
              exit 1
            elif [ "${PLAN_EXIT:-0}" = "2" ]; then
              echo "Changes detected in plan"
            else
              echo "No changes detected"
            fi
SCRIPT
          '''
        }
      }
    }
  }

  post {
    cleanup {
      // NOTE: Do not archive tfplan output by default; plan output can contain sensitive resource attributes.
      // Only clean workspace when we ran on an agent; otherwise MissingContextVariableException (no FilePath).
      script { if (env.WORKSPACE?.trim()) { cleanWs() } }
    }
    success {
      echo '✅ Terraform validation passed'
    }
    failure {
      echo '❌ Terraform validation failed'
      script {
        sh '''
          set +e
          if [ -f .jenkins/scripts/prepare-failure-tooling.sh ]; then
            sh .jenkins/scripts/prepare-failure-tooling.sh || true
          fi
        '''
        try {
          withCredentials([
            string(credentialsId: "${env.PIPELINEHEALER_BRIDGE_URL_CREDENTIALS}", variable: 'PH_BRIDGE_URL'),
            string(credentialsId: "${env.PIPELINEHEALER_BRIDGE_SECRET_CREDENTIALS}", variable: 'PH_BRIDGE_SECRET'),
          ]) {
            if (fileExists('.jenkins/scripts/send-pipelinehealer-bridge.sh')) {
              sh '''
                set +e
                export PH_REPOSITORY="${GITHUB_REPO}"
                export PH_JOB_NAME="${JOB_NAME}"
                export PH_JOB_URL="${BUILD_URL}"
                export PH_BUILD_NUMBER="${BUILD_NUMBER}"
                export PH_BRANCH="${GIT_BRANCH:-${BRANCH_NAME:-unknown}}"
                export PH_COMMIT_SHA="${GIT_COMMIT:-}"
                export PH_FAILURE_STAGE="terraform-validation"
                export PH_FAILURE_SUMMARY="Jenkins Terraform validation failed"
                export PH_RESULT="FAILURE"
                if [ -f "${WORKSPACE}/.pipelinehealer-log-excerpt.txt" ]; then
                  export PH_LOG_EXCERPT_FILE="${WORKSPACE}/.pipelinehealer-log-excerpt.txt"
                fi
                bash .jenkins/scripts/send-pipelinehealer-bridge.sh >/dev/null || \
                  echo "⚠️ WARNING: Failed to notify PipelineHealer bridge"
              '''
            } else {
              echo '⚠️ PipelineHealer bridge script unavailable in workspace; skipping bridge notification.'
            }
          }
        } catch (err) {
          echo "⚠️ PipelineHealer bridge credentials not configured; skipping bridge notification."
        }
      }
    }
  }
}
