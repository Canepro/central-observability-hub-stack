// Security Validation Pipeline for central-observability-hub-stack
// This pipeline performs security scanning and risk assessment, then creates PRs/issues based on findings.
// Purpose: Automated security checks with risk-based remediation workflows.
// Agent routing (Phase 3): OKE-only — runs on OKE (label security). For Azure/Key Vault use label 'aks-agent'.
pipeline {
  // Use a Kubernetes agent with security scanning tools
  agent {
    kubernetes {
      label 'security'
      defaultContainer 'security-scanner'
      yaml """
apiVersion: v1
kind: Pod
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
  - name: security-scanner
    image: docker.io/alpine:3.19
    command: ['sleep', '3600']
    resources:
      requests:
        memory: "256Mi"
        cpu: "100m"
      limits:
        memory: "1Gi"
        cpu: "500m"
"""
    }
  }
  
  // Environment variables for risk thresholds and GitHub integration
  environment {
    // Risk thresholds (adjust based on your security posture)
    CRITICAL_THRESHOLD = '10'  // Number of critical findings to trigger issue
    HIGH_THRESHOLD = '20'      // Number of high findings to trigger PR
    MEDIUM_THRESHOLD = '50'    // Number of medium findings to create issue
    
    // GitHub configuration (from Jenkins credentials)
    GITHUB_REPO = 'Canepro/central-observability-hub-stack'
    GITHUB_TOKEN_CREDENTIALS = 'github-token'
    
    // Output files for findings
    TFSEC_OUTPUT = 'tfsec-results.json'
    CHECKOV_OUTPUT = 'checkov-results.json'
    TRIVY_OUTPUT = 'trivy-results.json'
    RISK_REPORT = 'risk-assessment.json'
  }

  triggers {
    cron('H H * * *')
  }
  
  stages {
    // Stage 1: Install Security Scanning Tools
    stage('Install Security Tools') {
      when {
        branch 'main'
      }
      steps {
        sh '''
          # Install required tools
          # Alpine-based agent: install dependencies via apk
          apk add --no-cache \
            bash ca-certificates curl git jq python3 py3-pip tar wget gzip coreutils yq || true

          update-ca-certificates || true
          
          # Install tfsec (Terraform security scanner) - use direct binary (Alpine + ARM)
          ARCH="$(uname -m)"
          case "$ARCH" in
            aarch64|arm64) TFSEC_ARCH="arm64" ;;
            x86_64|amd64) TFSEC_ARCH="amd64" ;;
            *) TFSEC_ARCH="amd64" ;;
          esac
          curl -sfL "https://github.com/aquasecurity/tfsec/releases/latest/download/tfsec-linux-${TFSEC_ARCH}" -o /usr/local/bin/tfsec || true
          chmod +x /usr/local/bin/tfsec || true
          
          # Install checkov (Infrastructure as Code security scanner)
          # Alpine uses PEP-668 "externally managed" Python; install into a venv.
          python3 -m venv /tmp/checkov-venv || true
          if [ -f /tmp/checkov-venv/bin/activate ]; then
            . /tmp/checkov-venv/bin/activate
            pip install --quiet --no-cache-dir checkov || true
            deactivate || true
            ln -sf /tmp/checkov-venv/bin/checkov /usr/local/bin/checkov || true
          fi
          
          # Install trivy (Container image scanner)
          curl -sfL https://raw.githubusercontent.com/aquasecurity/trivy/main/contrib/install.sh | sh -s -- -b /usr/local/bin
          
          # Install kube-score (Kubernetes manifest security scanner)
          mkdir -p /usr/local/bin
          # Prefer Alpine package if available
          apk add --no-cache kube-score 2>/dev/null || true
          # Fallback: download from GitHub for correct arch
          if ! command -v kube-score >/dev/null 2>&1; then
            KUBE_SCORE_VER="1.17.0"
            ARCH="$(uname -m)"
            case "$ARCH" in
              aarch64|arm64) KUBE_SCORE_ARCH="arm64" ;;
              x86_64|amd64) KUBE_SCORE_ARCH="amd64" ;;
              *) KUBE_SCORE_ARCH="amd64" ;;
            esac
            curl -fsSL -o /tmp/kube-score.tgz "https://github.com/zegl/kube-score/releases/download/v${KUBE_SCORE_VER}/kube-score_${KUBE_SCORE_VER}_linux_${KUBE_SCORE_ARCH}.tar.gz" || true
            if [ -f /tmp/kube-score.tgz ] && tar -tzf /tmp/kube-score.tgz >/dev/null 2>&1; then
              tar -xzf /tmp/kube-score.tgz -C /usr/local/bin/ >/dev/null 2>&1 || true
              chmod +x /usr/local/bin/kube-score 2>/dev/null || true
            fi
          fi
          
          # Verify installations
          tfsec --version || echo "tfsec not installed"
          checkov --version || echo "checkov not installed"
          trivy --version || echo "trivy not installed"
          kube-score version || echo "kube-score not installed"
        '''
      }
    }
    
    // Stage 2: Terraform Security Scan (tfsec)
    stage('Terraform Security Scan (tfsec)') {
      when {
        branch 'main'
      }
      steps {
        dir('terraform') {
          sh '''
            # Run tfsec scan and output JSON results
            tfsec . --format json --out ${WORKSPACE}/${TFSEC_OUTPUT} || true
            
            # Also output human-readable format for logs
            tfsec . --format default || true
          '''
        }
      }
    }
    
    // Stage 3: Infrastructure Security Scan (checkov)
    stage('Infrastructure Security Scan (checkov)') {
      when {
        branch 'main'
      }
      steps {
        dir('terraform') {
          sh '''
            # Remove any existing file or directory so readJSON later sees a file (checkov can create a dir)
            rm -rf "${WORKSPACE}/${CHECKOV_OUTPUT}"
            # Run checkov scan on Terraform files
            checkov -d . --framework terraform --output json --output-file "${WORKSPACE}/${CHECKOV_OUTPUT}" || true
            # If checkov created a directory, copy the JSON file out so the pipeline can read it
            if [ -d "${WORKSPACE}/${CHECKOV_OUTPUT}" ]; then
              F=$(find "${WORKSPACE}/${CHECKOV_OUTPUT}" -type f -name "*.json" -print -quit)
              if [ -n "$F" ]; then
                cp -f "$F" "${WORKSPACE}/checkov-results-merged.json" || true
              fi
              rm -rf "${WORKSPACE}/${CHECKOV_OUTPUT}" || true
              [ -f "${WORKSPACE}/checkov-results-merged.json" ] && mv "${WORKSPACE}/checkov-results-merged.json" "${WORKSPACE}/${CHECKOV_OUTPUT}" || true
            fi
            # Also output CLI format for logs
            checkov -d . --framework terraform || true
          '''
        }
      }
    }
    
    // Stage 4: Kubernetes Manifest Security Scan
    stage('Kubernetes Security Scan') {
      when {
        branch 'main'
      }
      steps {
        sh '''
          # Scan Kubernetes manifests in ops/manifests/
          if [ -d "ops/manifests" ] && command -v kube-score >/dev/null 2>&1; then
            kube-score score ops/manifests/*.yaml --output-format json > kube-score-results.json || true
            kube-score score ops/manifests/*.yaml || true
          elif [ -d "ops/manifests" ]; then
            echo "kube-score not installed; skipping Kubernetes manifest scan"
          fi
          
          # Also scan Helm-rendered manifests if available
          if [ -f "/tmp/manifests.yaml" ]; then
            kube-score score /tmp/manifests.yaml --output-format json > helm-kube-score-results.json || true
          fi
        '''
      }
    }
    
    // Stage 5: Container Image Security Scan (Trivy)
    stage('Container Image Security Scan') {
      when {
        branch 'main'
      }
      steps {
        script {
          // Extract container images from values.yaml
          def images = sh(
            script: '''
              set -e

              # Preferred: yq (robust YAML parsing)
              if command -v yq >/dev/null 2>&1; then
                REPO="$(yq -r '.image.repository // ""' values.yaml 2>/dev/null | sed 's/#.*$//' | xargs || true)"
                TAG="$(yq -r '.image.tag // ""' values.yaml 2>/dev/null | sed 's/#.*$//' | xargs || true)"
                [ "$REPO" = "null" ] && REPO=""
                [ "$TAG" = "null" ] && TAG=""
              else
                # Fallback: grep/sed (strip inline comments)
                REPO="$(grep -E '^\\s*repository:' values.yaml | head -1 | sed 's/.*repository:\\s*//' | sed 's/#.*$//' | xargs || true)"
                TAG="$(grep -E '^\\s*tag:' values.yaml | head -1 | sed 's/.*tag:\\s*\"\\{0,1\\}\\([^\"#]*\\)\"\\{0,1\\}.*/\\1/' | sed 's/#.*$//' | xargs || true)"
              fi

              if [ -n "$REPO" ] && [ -n "$TAG" ]; then
                echo "${REPO}:${TAG}"
              fi
            ''',
            returnStdout: true
          ).trim()
          
          if (images) {
            echo "Found container images to scan:"
            echo images
            
            // Scan each image
            images.split('\n').each { line ->
              if (line.contains(':')) {
                def image = line.trim()
                sh """
                  echo "Scanning image: ${image}"
                  trivy image --format json --output ${WORKSPACE}/trivy-${image.replaceAll('[/: ]', '-')}.json ${image} || true
                  trivy image ${image} || true
                """
              }
            }
          } else {
            echo "No container images found in values.yaml"
          }
        }
      }
    }
    
    // Stage 6: Risk Assessment
    stage('Risk Assessment') {
      when {
        branch 'main'
      }
      steps {
        script {
          sh '''
            python3 - <<'PY'
import json, os, datetime

def load_json(path):
    try:
        with open(path, 'r') as f:
            return json.load(f)
    except Exception:
        return None

def count_tfsec(data):
    counts = {"CRITICAL":0,"HIGH":0,"MEDIUM":0,"LOW":0}
    if isinstance(data, dict):
        for item in data.get("results", []) or []:
            sev = item.get("severity")
            if sev in counts:
                counts[sev] += 1
    return counts

def iter_failed_checkov(data):
    failed = []
    if isinstance(data, dict):
        if isinstance(data.get("results", {}).get("check_results"), list):
            failed = [x for x in data["results"]["check_results"] if x.get("check_result", {}).get("result") == "FAILED"]
        elif isinstance(data.get("results", {}).get("failed_checks"), list):
            failed = data["results"]["failed_checks"]
        elif isinstance(data.get("failed_checks"), list):
            failed = data["failed_checks"]
    elif isinstance(data, list):
        for rep in data:
            if isinstance(rep.get("results", {}).get("failed_checks"), list):
                failed.extend(rep["results"]["failed_checks"])
            elif isinstance(rep.get("results", {}).get("check_results"), list):
                failed.extend([x for x in rep["results"]["check_results"] if x.get("check_result", {}).get("result") == "FAILED"])
    return failed

def count_checkov(data):
    counts = {"CRITICAL":0,"HIGH":0,"MEDIUM":0,"LOW":0}
    for item in iter_failed_checkov(data):
        sev = (item.get("check_result", {}).get("severity") or item.get("severity") or "MEDIUM").upper()
        if sev not in counts:
            sev = "MEDIUM"
        counts[sev] += 1
    return counts

tfsec_path = os.environ.get("TFSEC_OUTPUT", "")
checkov_path = os.environ.get("CHECKOV_OUTPUT", "")
risk_path = os.environ.get("RISK_REPORT", "risk-assessment.json")

tfsec = load_json(tfsec_path) if tfsec_path and os.path.exists(tfsec_path) else None
checkov = load_json(checkov_path) if checkov_path and os.path.exists(checkov_path) else None

tf_counts = count_tfsec(tfsec)
ck_counts = count_checkov(checkov)

critical = tf_counts["CRITICAL"] + ck_counts["CRITICAL"]
high = tf_counts["HIGH"] + ck_counts["HIGH"]
medium = tf_counts["MEDIUM"] + ck_counts["MEDIUM"]
low = tf_counts["LOW"] + ck_counts["LOW"]

if critical > 0:
    risk_level = "CRITICAL"
elif high > 0:
    risk_level = "HIGH"
elif medium > 0:
    risk_level = "MEDIUM"
else:
    risk_level = "LOW"

action_required = bool(critical or high or medium)

report = {
    "timestamp": datetime.datetime.utcnow().strftime("%Y-%m-%dT%H:%M:%SZ"),
    "critical": critical,
    "high": high,
    "medium": medium,
    "low": low,
    "risk_level": risk_level,
    "action_required": action_required,
}

with open(risk_path, "w") as f:
    json.dump(report, f)

with open("risk-counts.env", "w") as f:
    f.write(f"CRITICAL={critical}\\nHIGH={high}\\nMEDIUM={medium}\\nLOW={low}\\nRISK_LEVEL={risk_level}\\nACTION_REQUIRED={'true' if action_required else 'false'}\\n")

print("Risk Assessment:", report)
PY
          '''

          // Never fail the build due to findings
          currentBuild.result = 'SUCCESS'
        }
      }
    }
    
    // Stage 7: Create or update GitHub issue for findings (no PRs; remediation via manual PRs)
    stage('Create/Update Security Findings Issue') {
      when {
        branch 'main'
      }
      steps {
        script {
          if (!fileExists(env.RISK_REPORT)) {
            echo "No ${env.RISK_REPORT} found; skipping remediation."
            return
          }

          def riskLevel = sh(script: "jq -r '.risk_level' ${env.RISK_REPORT}", returnStdout: true).trim()
          def critical = sh(script: "jq -r '.critical' ${env.RISK_REPORT}", returnStdout: true).trim().toInteger()
          def high = sh(script: "jq -r '.high' ${env.RISK_REPORT}", returnStdout: true).trim().toInteger()
          def medium = sh(script: "jq -r '.medium' ${env.RISK_REPORT}", returnStdout: true).trim().toInteger()
          def low = sh(script: "jq -r '.low' ${env.RISK_REPORT}", returnStdout: true).trim().toInteger()
          def actionRequired = sh(script: "jq -r '.action_required' ${env.RISK_REPORT}", returnStdout: true).trim()

          if (actionRequired != "true") {
            echo "✅ No remediation needed (risk_level=${riskLevel})."
            return
          }
          
          withCredentials([usernamePassword(credentialsId: "${env.GITHUB_TOKEN_CREDENTIALS}", usernameVariable: 'GITHUB_USER', passwordVariable: 'GITHUB_TOKEN')]) {
            if (!env.GITHUB_TOKEN?.trim()) {
              echo "⚠️ GitHub token is empty; skipping issue/PR creation."
              return
            }
            // Single flow: create or update one GitHub issue for any findings (critical/high/medium/low). No PRs.
            echo "Security findings detected (risk_level=${riskLevel}). Creating or updating GitHub issue..."
            withEnv([
              "CRITICAL_COUNT=${critical}",
              "HIGH_COUNT=${high}",
              "MEDIUM_COUNT=${medium}",
              "LOW_COUNT=${low}",
              "RISK_LEVEL=${riskLevel}",
              "GITHUB_REPO=${env.GITHUB_REPO}"
            ]) {
              sh '''
                set +e
                WORKDIR="${WORKSPACE:-$(pwd)}"
                ISSUE_TITLE="Security: automated scan findings"

                ensure_label() {
                  LABEL_NAME="$1"
                  LABEL_COLOR="$2"
                  LABEL_JSON=$(jq -n --arg name "$LABEL_NAME" --arg color "$LABEL_COLOR" '{name:$name,color:$color}')
                  curl -fsSL \
                    -H "Authorization: token ${GITHUB_TOKEN}" \
                    -H "Accept: application/vnd.github.v3+json" \
                    "https://api.github.com/repos/${GITHUB_REPO}/labels/${LABEL_NAME}" >/dev/null 2>&1 && return 0
                  curl -fsSL -X POST \
                    -H "Authorization: token ${GITHUB_TOKEN}" \
                    -H "Accept: application/vnd.github.v3+json" \
                    "https://api.github.com/repos/${GITHUB_REPO}/labels" \
                    -d "$LABEL_JSON" >/dev/null 2>&1 || true
                }

                ensure_label "security" "d73a4a"
                ensure_label "automated" "0e8a16"
                ensure_label "critical" "b60205"

                # De-dupe: find open issue with canonical title (daily runs update same issue)
                ISSUE_LIST_JSON=$(curl -fsSL \
                  -H "Authorization: token ${GITHUB_TOKEN}" \
                  -H "Accept: application/vnd.github.v3+json" \
                  "https://api.github.com/repos/${GITHUB_REPO}/issues?state=open&labels=security,automated&per_page=100" \
                  || echo '[]')

                ISSUE_NUMBER=$(echo "$ISSUE_LIST_JSON" | jq -r --arg t "$ISSUE_TITLE" '[.[] | select(.pull_request == null) | select(.title == $t)][0].number // empty' 2>/dev/null || true)
                ISSUE_URL=$(echo "$ISSUE_LIST_JSON" | jq -r --arg t "$ISSUE_TITLE" '[.[] | select(.pull_request == null) | select(.title == $t)][0].html_url // empty' 2>/dev/null || true)

                TS=$(date -u +%Y-%m-%dT%H:%M:%SZ)
                if [ -n "${ISSUE_NUMBER}" ]; then
                  echo "Existing open issue #${ISSUE_NUMBER} found; adding comment (daily update)."
                  COMMENT_BODY="## Security scan results

**Time:** ${TS}
**Risk level:** ${RISK_LEVEL}

**Findings:**
- Critical: ${CRITICAL_COUNT}
- High: ${HIGH_COUNT}
- Medium: ${MEDIUM_COUNT}
- Low: ${LOW_COUNT}

**Build:** ${BUILD_URL}
**Artifacts:** ${BUILD_URL}artifact/

Remediation: create PR(s) manually to fix. This issue is updated on each run."
                  jq -n --arg body "$COMMENT_BODY" '{body: $body}' > "${WORKDIR}/issue-comment.json"
                  if ! curl -sS -X POST \
                    -H "Authorization: token ${GITHUB_TOKEN}" \
                    -H "Accept: application/vnd.github.v3+json" \
                    "https://api.github.com/repos/${GITHUB_REPO}/issues/${ISSUE_NUMBER}/comments" \
                    -d @"${WORKDIR}/issue-comment.json" >/dev/null 2>&1; then
                    echo "⚠️ WARNING: Failed to add comment to issue #${ISSUE_NUMBER}. Manual review required."
                  fi
                  echo "Updated existing issue: ${ISSUE_URL}"
                  exit 0
                fi

                # Create issue once; future runs will find it and comment
                if [ "${RISK_LEVEL}" = "CRITICAL" ]; then ISSUE_LABELS='["security","automated","critical"]'; else ISSUE_LABELS='["security","automated"]'; fi
                ISSUE_BODY="## Security Scan Findings

**Risk level:** ${RISK_LEVEL}

**Findings:**
- Critical: ${CRITICAL_COUNT}
- High: ${HIGH_COUNT}
- Medium: ${MEDIUM_COUNT}
- Low: ${LOW_COUNT}

**Build:** ${BUILD_URL}
**Artifacts:** ${BUILD_URL}artifact/

## Suggested next steps

1. Review Jenkins build logs and artifacts (tfsec, checkov, trivy, kube-score).
2. Create PR(s) manually to fix findings.
3. This issue is updated on each daily run with new results.

---
*This issue was automatically created by Jenkins security validation pipeline.*"
                jq -n --arg title "$ISSUE_TITLE" --arg body "$ISSUE_BODY" --argjson labels "$ISSUE_LABELS" \
                  '{title: $title, body: $body, labels: $labels}' > "${WORKDIR}/issue-body.json"
                if ! curl -sS -X POST \
                  -H "Authorization: token ${GITHUB_TOKEN}" \
                  -H "Accept: application/vnd.github.v3+json" \
                  "https://api.github.com/repos/${GITHUB_REPO}/issues" \
                  -d @"${WORKDIR}/issue-body.json" >/dev/null 2>&1; then
                  echo "⚠️ WARNING: Failed to create GitHub issue for security findings. Manual review required."
                fi
                exit 0
              '''
            }
          }
        }
      }
    }
  }
  
  // Post-build actions
  post {
    always {
      // Archive security scan results
      archiveArtifacts artifacts: '*.json,*.md', allowEmptyArchive: true
      
      // Publish security scan results (avoid Groovy JSON sandbox)
      script {
        if (fileExists(env.RISK_REPORT)) {
          def critical = sh(script: "jq -r '.critical' ${env.RISK_REPORT}", returnStdout: true).trim()
          def high = sh(script: "jq -r '.high' ${env.RISK_REPORT}", returnStdout: true).trim()
          def medium = sh(script: "jq -r '.medium' ${env.RISK_REPORT}", returnStdout: true).trim()
          def low = sh(script: "jq -r '.low' ${env.RISK_REPORT}", returnStdout: true).trim()
          def riskLevel = sh(script: "jq -r '.risk_level' ${env.RISK_REPORT}", returnStdout: true).trim()
          def actionReq = sh(script: "jq -r '.action_required' ${env.RISK_REPORT}", returnStdout: true).trim()
          echo """
          ========================================
          Security Scan Summary
          ========================================
          Critical: ${critical}
          High: ${high}
          Medium: ${medium}
          Low: ${low}
          Risk Level: ${riskLevel}
          Action Required: ${actionReq}
          ========================================
          """
        } else {
          echo "Security Scan Summary: ${env.RISK_REPORT} not generated (earlier stage failed or was skipped)"
        }
      }
    }
    success {
      echo '✅ Security validation completed'
    }
    failure {
      echo '❌ Security validation failed'
      script {
        withCredentials([usernamePassword(credentialsId: "${env.GITHUB_TOKEN_CREDENTIALS}", usernameVariable: 'GITHUB_USER', passwordVariable: 'GITHUB_TOKEN')]) {
          if (!env.GITHUB_TOKEN?.trim()) {
            echo "⚠️ GitHub token is empty; skipping failure notification."
            return
          }
          sh '''
            set +e
            WORKDIR="${WORKSPACE:-$(pwd)}"
            ISSUE_TITLE="CI Failure: ${JOB_NAME}"
            
            ensure_label() {
              LABEL_NAME="$1"
              LABEL_COLOR="$2"
              LABEL_JSON=$(jq -n --arg name "$LABEL_NAME" --arg color "$LABEL_COLOR" '{name:$name,color:$color}')
              curl -fsSL \
                -H "Authorization: token ${GITHUB_TOKEN}" \
                -H "Accept: application/vnd.github.v3+json" \
                "https://api.github.com/repos/${GITHUB_REPO}/labels/${LABEL_NAME}" >/dev/null 2>&1 && return 0
              curl -fsSL -X POST \
                -H "Authorization: token ${GITHUB_TOKEN}" \
                -H "Accept: application/vnd.github.v3+json" \
                "https://api.github.com/repos/${GITHUB_REPO}/labels" \
                -d "$LABEL_JSON" >/dev/null 2>&1 || true
            }
            
            ensure_label "ci" "6a737d"
            ensure_label "jenkins" "5319e7"
            ensure_label "failure" "b60205"
            ensure_label "automated" "0e8a16"
            
            ISSUE_LIST_JSON=$(curl -fsSL \
              -H "Authorization: token ${GITHUB_TOKEN}" \
              -H "Accept: application/vnd.github.v3+json" \
              "https://api.github.com/repos/${GITHUB_REPO}/issues?state=open&labels=ci,jenkins,failure,automated&per_page=100" \
              || echo '[]')
            
            ISSUE_NUMBER=$(echo "$ISSUE_LIST_JSON" | jq -r --arg t "$ISSUE_TITLE" '[.[] | select(.pull_request == null) | select(.title == $t)][0].number // empty' 2>/dev/null || true)
            ISSUE_URL=$(echo "$ISSUE_LIST_JSON" | jq -r --arg t "$ISSUE_TITLE" '[.[] | select(.pull_request == null) | select(.title == $t)][0].html_url // empty' 2>/dev/null || true)
            
            if [ -n "${ISSUE_NUMBER}" ]; then
              cat > "${WORKDIR}/issue-comment.json" << EOF
            {
              "body": "## Jenkins job failed\\n\\nJob: ${JOB_NAME}\\nBuild: ${BUILD_URL}\\nCommit: ${GIT_COMMIT}\\n\\n(Automated update on existing issue.)"
            }
EOF
              curl -X POST \
                -H "Authorization: token ${GITHUB_TOKEN}" \
                -H "Accept: application/vnd.github.v3+json" \
                "https://api.github.com/repos/${GITHUB_REPO}/issues/${ISSUE_NUMBER}/comments" \
                -d @"${WORKDIR}/issue-comment.json" >/dev/null 2>&1 || true
              echo "Updated existing failure issue: ${ISSUE_URL}"
              exit 0
            fi
            
            cat > "${WORKDIR}/issue-body.json" << EOF
            {
              "title": "${ISSUE_TITLE}",
              "body": "## Jenkins job failed\\n\\nJob: ${JOB_NAME}\\nBuild: ${BUILD_URL}\\nCommit: ${GIT_COMMIT}\\n\\nPlease check Jenkins logs for details.\\n\\n---\\n*This issue was automatically created by Jenkins.*",
              "labels": ["ci", "jenkins", "failure", "automated"]
            }
EOF
            
            curl -X POST \
              -H "Authorization: token ${GITHUB_TOKEN}" \
              -H "Accept: application/vnd.github.v3+json" \
              "https://api.github.com/repos/${GITHUB_REPO}/issues" \
              -d @"${WORKDIR}/issue-body.json" >/dev/null 2>&1 || true
          '''
        }
      }
    }
  }
}
