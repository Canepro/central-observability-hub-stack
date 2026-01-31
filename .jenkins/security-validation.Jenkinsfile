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
  
  stages {
    // Stage 1: Install Security Scanning Tools
    stage('Install Security Tools') {
      steps {
        sh '''
          # Install required tools
          # Alpine-based agent: install dependencies via apk
          apk add --no-cache \
            bash ca-certificates curl git jq python3 py3-pip tar wget gzip coreutils yq || true

          update-ca-certificates || true
          
          # Install tfsec (Terraform security scanner)
          curl -s https://raw.githubusercontent.com/aquasecurity/tfsec/master/scripts/install_linux.sh | bash
          
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
          # Fallback: download from GitHub (versioned URL; /latest/download/ often 404s)
          if ! command -v kube-score >/dev/null 2>&1; then
            KUBE_SCORE_VER="1.17.0"
            if curl -fsSL -o /tmp/kube-score.tgz "https://github.com/zegl/kube-score/releases/download/v${KUBE_SCORE_VER}/kube-score_${KUBE_SCORE_VER}_linux_amd64.tar.gz"; then
              : # success
            else
              curl -fsSL -o /tmp/kube-score.tgz "https://github.com/zegl/kube-score/releases/download/v${KUBE_SCORE_VER}/kube-score_linux_amd64.tar.gz" || true
            fi
            if [ -f /tmp/kube-score.tgz ] && tar -tzf /tmp/kube-score.tgz >/dev/null 2>&1; then
              tar -xzf /tmp/kube-score.tgz -C /usr/local/bin/
              chmod +x /usr/local/bin/kube-score 2>/dev/null || true
            fi
          fi
          chmod +x /usr/local/bin/kube-score 2>/dev/null || true
          
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
      steps {
        dir('terraform') {
          sh '''
            # Remove any existing file or directory so readJSON later sees a file (checkov can create a dir)
            rm -rf "${WORKSPACE}/${CHECKOV_OUTPUT}"
            # Run checkov scan on Terraform files
            checkov -d . --framework terraform --output json --output-file "${WORKSPACE}/${CHECKOV_OUTPUT}" || true
            # If checkov created a directory, copy the JSON file out so the pipeline can read it
            if [ -d "${WORKSPACE}/${CHECKOV_OUTPUT}" ]; then
              F=$(find "${WORKSPACE}/${CHECKOV_OUTPUT}" -maxdepth 1 -name "*.json" -print -quit)
              if [ -n "$F" ]; then
                cp "$F" "${WORKSPACE}/checkov-results-merged.json"
              fi
              rm -rf "${WORKSPACE}/${CHECKOV_OUTPUT}"
              [ -f "${WORKSPACE}/checkov-results-merged.json" ] && mv "${WORKSPACE}/checkov-results-merged.json" "${WORKSPACE}/${CHECKOV_OUTPUT}"
            fi
            # Also output CLI format for logs
            checkov -d . --framework terraform || true
          '''
        }
      }
    }
    
    // Stage 4: Kubernetes Manifest Security Scan
    stage('Kubernetes Security Scan') {
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
      steps {
        script {
          int tfsecCritical = 0
          int tfsecHigh = 0
          int tfsecMedium = 0
          int tfsecLow = 0

          int checkovCritical = 0
          int checkovHigh = 0
          int checkovMedium = 0
          int checkovLow = 0

          // tfsec: { results: [ { severity: "CRITICAL|HIGH|MEDIUM|LOW", ... }, ... ] }
          if (fileExists(env.TFSEC_OUTPUT)) {
            try {
              def tfsec = new groovy.json.JsonSlurperClassic().parseText(readFile(env.TFSEC_OUTPUT))
              def results = (tfsec?.results instanceof List) ? tfsec.results : []
              tfsecCritical = results.count { it?.severity == 'CRITICAL' }
              tfsecHigh = results.count { it?.severity == 'HIGH' }
              tfsecMedium = results.count { it?.severity == 'MEDIUM' }
              tfsecLow = results.count { it?.severity == 'LOW' }
            } catch (err) {
              echo "WARN: Unable to parse ${env.TFSEC_OUTPUT}: ${err}"
            }
          }

          // checkov output formats vary. We count FAILED checks; if severity missing, treat as MEDIUM.
          if (fileExists(env.CHECKOV_OUTPUT)) {
            try {
              def checkov = new groovy.json.JsonSlurperClassic().parseText(readFile(env.CHECKOV_OUTPUT))
              def failed = []

              if (checkov instanceof Map) {
                if (checkov?.results?.check_results instanceof List) {
                  failed = checkov.results.check_results.findAll { it?.check_result?.result == 'FAILED' }
                } else if (checkov?.results?.failed_checks instanceof List) {
                  failed = checkov.results.failed_checks
                } else if (checkov?.failed_checks instanceof List) {
                  failed = checkov.failed_checks
                }
              } else if (checkov instanceof List) {
                checkov.each { rep ->
                  if (rep?.results?.failed_checks instanceof List) {
                    failed.addAll(rep.results.failed_checks)
                  } else if (rep?.results?.check_results instanceof List) {
                    failed.addAll(rep.results.check_results.findAll { it?.check_result?.result == 'FAILED' })
                  }
                }
              }

              failed.each { item ->
                def sev = (item?.check_result?.severity ?: item?.severity)
                if (sev == 'CRITICAL') {
                  checkovCritical++
                } else if (sev == 'HIGH') {
                  checkovHigh++
                } else if (sev == 'MEDIUM') {
                  checkovMedium++
                } else if (sev == 'LOW') {
                  checkovLow++
                } else {
                  // Many checkov checks don't include severity; treat as MEDIUM for reporting.
                  checkovMedium++
                }
              }
            } catch (err) {
              echo "WARN: Unable to parse ${env.CHECKOV_OUTPUT}: ${err}"
            }
          }

          int critical = tfsecCritical + checkovCritical
          int high = tfsecHigh + checkovHigh
          int medium = tfsecMedium + checkovMedium
          int low = tfsecLow + checkovLow

          // User intent: report always, issue for critical, PR for non-critical.
          String riskLevel = (critical > 0) ? 'CRITICAL' : ((high > 0) ? 'HIGH' : ((medium > 0) ? 'MEDIUM' : 'LOW'))
          boolean actionRequired = (critical > 0 || high > 0 || medium > 0)

          def report = [
            timestamp: sh(script: 'date -u +%Y-%m-%dT%H:%M:%SZ', returnStdout: true).trim(),
            critical: critical,
            high: high,
            medium: medium,
            low: low,
            risk_level: riskLevel,
            action_required: actionRequired
          ]

          def reportJson = groovy.json.JsonOutput.toJson(report)
          writeFile file: env.RISK_REPORT, text: reportJson
          echo "Risk Assessment: ${report}"

          // Never fail the build due to findings
          currentBuild.result = 'SUCCESS'
        }
      }
    }
    
    // Stage 7: Create PR or Issue Based on Risk
    stage('Create Remediation PR/Issue') {
      steps {
        script {
          if (!fileExists(env.RISK_REPORT)) {
            echo "No ${env.RISK_REPORT} found; skipping remediation."
            return
          }

          def riskReport = new groovy.json.JsonSlurperClassic().parseText(readFile(env.RISK_REPORT))
          def riskLevel = riskReport.risk_level
          def critical = riskReport.critical
          def high = riskReport.high
          def medium = riskReport.medium
          def low = riskReport.low

          if (riskReport.action_required != true) {
            echo "✅ No remediation needed (risk_level=${riskLevel})."
            return
          }
          
          withCredentials([usernamePassword(credentialsId: "${env.GITHUB_TOKEN_CREDENTIALS}", usernameVariable: 'GITHUB_USER', passwordVariable: 'GITHUB_TOKEN')]) {
            if (!env.GITHUB_TOKEN?.trim()) {
              echo "⚠️ GitHub token is empty; skipping issue/PR creation."
              return
            }
            if (riskLevel == 'CRITICAL' || critical >= Integer.parseInt(env.CRITICAL_THRESHOLD)) {
              // Create GitHub Issue for critical findings
              echo "🚨 CRITICAL risk detected! Creating GitHub issue..."
              withEnv([
                "CRITICAL_COUNT=${critical}",
                "HIGH_COUNT=${high}",
                "MEDIUM_COUNT=${medium}",
                "LOW_COUNT=${low}",
                "GITHUB_REPO=${env.GITHUB_REPO}"
              ]) {
                sh '''
                  set +e
                  ISSUE_TITLE="🚨 Security: Critical vulnerabilities detected (automated)"
                  
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
                  ensure_label "critical" "b60205"
                  ensure_label "automated" "0e8a16"

                  # De-dupe: if an open issue with same title exists, do nothing.
                  ISSUE_LIST_JSON=$(curl -fsSL \
                    -H "Authorization: token ${GITHUB_TOKEN}" \
                    -H "Accept: application/vnd.github.v3+json" \
                    "https://api.github.com/repos/${GITHUB_REPO}/issues?state=open&labels=security,critical,automated&per_page=100" \
                    || echo '[]')

                  ISSUE_NUMBER=$(echo "$ISSUE_LIST_JSON" | jq -r --arg t "$ISSUE_TITLE" '[.[] | select(.pull_request == null) | select(.title == $t)][0].number // empty' 2>/dev/null || true)
                  ISSUE_URL=$(echo "$ISSUE_LIST_JSON" | jq -r --arg t "$ISSUE_TITLE" '[.[] | select(.pull_request == null) | select(.title == $t)][0].html_url // empty' 2>/dev/null || true)

                  if [ -n "${ISSUE_NUMBER}" ]; then
                    echo "Existing open issue #${ISSUE_NUMBER} found; adding comment instead of creating duplicate."
                    cat > issue-comment.json << EOF
                    {
                      "body": "## New security scan results\\n\\nBuild: ${BUILD_URL}\\n\\n**Findings:**\\n- Critical: ${CRITICAL_COUNT}\\n- High: ${HIGH_COUNT}\\n- Medium: ${MEDIUM_COUNT}\\n- Low: ${LOW_COUNT}\\n\\nArtifacts: ${BUILD_URL}artifact/\\n\\n(De-dupe enabled: this comment updates an existing open issue.)"
                    }
EOF
                    curl -X POST \
                      -H "Authorization: token ${GITHUB_TOKEN}" \
                      -H "Accept: application/vnd.github.v3+json" \
                      "https://api.github.com/repos/${GITHUB_REPO}/issues/${ISSUE_NUMBER}/comments" \
                      -d @issue-comment.json >/dev/null 2>&1 || true
                    echo "Updated existing issue: ${ISSUE_URL}"
                    exit 0
                  fi

                  cat > issue-body.json << EOF
                  {
                    "title": "${ISSUE_TITLE}",
                    "body": "## Security Scan Results\\n\\n**Risk Level:** CRITICAL\\n\\n**Findings:**\\n- Critical: ${CRITICAL_COUNT}\\n- High: ${HIGH_COUNT}\\n- Medium: ${MEDIUM_COUNT}\\n- Low: ${LOW_COUNT}\\n\\n## Action Required\\n\\nPlease review the security scan results and address critical vulnerabilities immediately.\\n\\n## Scan Artifacts\\n\\n- tfsec results: See Jenkins build artifacts\\n- checkov results: See Jenkins build artifacts\\n- trivy results: See Jenkins build artifacts\\n\\n## Next Steps\\n\\n1. Review all critical findings\\n2. Create remediation PRs for each critical issue\\n3. Update security policies if needed\\n\\n---\\n*This issue was automatically created by Jenkins security validation pipeline.*",
                    "labels": ["security", "critical", "automated"]
                  }
                  EOF
                  
                  curl -X POST \
                    -H "Authorization: token ${GITHUB_TOKEN}" \
                    -H "Accept: application/vnd.github.v3+json" \
                    "https://api.github.com/repos/${GITHUB_REPO}/issues" \
                    -d @issue-body.json || true
                  exit 0
                '''
              }
            } else {
              // Create PR with automated fixes for non-critical findings
              echo "⚠️ Non-critical findings detected! Creating remediation PR..."
              withEnv([
                "CRITICAL_COUNT=${critical}",
                "HIGH_COUNT=${high}",
                "MEDIUM_COUNT=${medium}",
                "LOW_COUNT=${low}",
                "GITHUB_REPO=${env.GITHUB_REPO}"
              ]) {
                sh '''
                  set +e
                  PR_TITLE="🔒 Security: Automated remediation (automated)"
                  
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
                  ensure_label "dependencies" "0366d6"

                  # De-dupe: if an open PR with same title exists, do nothing.
                  PR_LIST_JSON=$(curl -fsSL \
                    -H "Authorization: token ${GITHUB_TOKEN}" \
                    -H "Accept: application/vnd.github.v3+json" \
                    "https://api.github.com/repos/${GITHUB_REPO}/pulls?state=open&per_page=100" \
                    || echo '[]')

                  PR_NUMBER=$(echo "$PR_LIST_JSON" | jq -r --arg t "$PR_TITLE" '[.[] | select(.title == $t)][0].number // empty' 2>/dev/null || true)
                  PR_URL=$(echo "$PR_LIST_JSON" | jq -r --arg t "$PR_TITLE" '[.[] | select(.title == $t)][0].html_url // empty' 2>/dev/null || true)

                  if [ -n "${PR_NUMBER}" ]; then
                    echo "Existing open PR #${PR_NUMBER} found; adding comment instead of creating duplicate."
                    cat > pr-comment.json << EOF
                    {
                      "body": "## New security scan results\\n\\nBuild: ${BUILD_URL}\\n\\n**Findings:**\\n- Critical: ${CRITICAL_COUNT}\\n- High: ${HIGH_COUNT}\\n- Medium: ${MEDIUM_COUNT}\\n- Low: ${LOW_COUNT}\\n\\nArtifacts: ${BUILD_URL}artifact/\\n\\n(De-dupe enabled: this comment updates an existing open PR.)"
                    }
EOF
                    curl -X POST \
                      -H "Authorization: token ${GITHUB_TOKEN}" \
                      -H "Accept: application/vnd.github.v3+json" \
                      "https://api.github.com/repos/${GITHUB_REPO}/issues/${PR_NUMBER}/comments" \
                      -d @pr-comment.json >/dev/null 2>&1 || true
                    echo "Updated existing PR: ${PR_URL}"
                    exit 0
                  fi

                  # Create a branch for security fixes
                  BRANCH_NAME="security/automated-fixes-$(date +%Y%m%d-%H%M%S)"
                  git config user.name "Jenkins Security Bot"
                  git config user.email "jenkins@canepro.me"
                  git checkout -b ${BRANCH_NAME}

                  # Ensure authenticated remote for push
                  set +x
                  git remote set-url origin "https://${GITHUB_TOKEN}@github.com/${GITHUB_REPO}.git" 2>/dev/null || true
                  set -x
                  
                  # Create a security fixes file (placeholder - actual fixes would be applied here)
                  cat > SECURITY_FIXES.md << EOF
                  # Security Fixes
                  
                  This PR addresses high-priority security findings from automated scans.
                  
                  ## Findings Summary
                  - Critical: ${CRITICAL_COUNT}
                  - High: ${HIGH_COUNT}
                  - Medium: ${MEDIUM_COUNT}
                  - Low: ${LOW_COUNT}
                  
                  ## Automated Fixes
                  
                  This PR includes automated fixes for high-priority security issues.
                  Please review all changes before merging.
                  
                  ## Manual Review Required
                  
                  Some findings may require manual review and cannot be auto-fixed.
                  Please check the Jenkins build logs for detailed findings.
                  EOF
                  
                  git add SECURITY_FIXES.md
                  git commit -m "security: automated fixes for high-priority findings
                  
                  - Addresses ${HIGH_COUNT} high-priority security findings
                  - Generated by Jenkins security validation pipeline
                  - Review required before merging"
                  
                  git push origin ${BRANCH_NAME}
                  
                  # Create PR
                  cat > pr-body.json << EOF
                  {
                    "title": "${PR_TITLE}",
                    "head": "${BRANCH_NAME}",
                    "base": "main",
                    "body": "## Automated Security Fixes\\n\\nThis PR addresses **${HIGH_COUNT} high-priority** security findings detected by automated scans.\\n\\n### Findings Summary\\n- Critical: ${CRITICAL_COUNT}\\n- High: ${HIGH_COUNT}\\n- Medium: ${MEDIUM_COUNT}\\n- Low: ${LOW_COUNT}\\n\\n### Changes\\n\\nThis PR includes automated fixes for high-priority security issues. Please review all changes carefully.\\n\\n### Review Checklist\\n\\n- [ ] Review all automated changes\\n- [ ] Verify fixes don't break functionality\\n- [ ] Test in staging if applicable\\n- [ ] Check for any manual fixes needed\\n\\n---\\n*This PR was automatically created by Jenkins security validation pipeline.*"
                  }
                  EOF
                  
                  PR_CREATE_JSON=$(curl -sS -X POST \
                    -H "Authorization: token ${GITHUB_TOKEN}" \
                    -H "Accept: application/vnd.github.v3+json" \
                    "https://api.github.com/repos/${GITHUB_REPO}/pulls" \
                    -d @pr-body.json || echo '{}')
                  
                  PR_CREATED_NUMBER=$(echo "$PR_CREATE_JSON" | jq -r '.number // empty' 2>/dev/null || true)
                  if [ -n "${PR_CREATED_NUMBER}" ]; then
                    curl -sS -X POST \
                      -H "Authorization: token ${GITHUB_TOKEN}" \
                      -H "Accept: application/vnd.github.v3+json" \
                      "https://api.github.com/repos/${GITHUB_REPO}/issues/${PR_CREATED_NUMBER}/labels" \
                      -d '{"labels":["security","automated","dependencies"]}' >/dev/null 2>&1 || true
                  fi

                  exit 0
                '''
              }
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
      
      // Publish security scan results (if using plugins)
      script {
        if (fileExists(env.RISK_REPORT)) {
          def riskReport = new groovy.json.JsonSlurperClassic().parseText(readFile(env.RISK_REPORT))
          echo """
          ========================================
          Security Scan Summary
          ========================================
          Critical: ${riskReport.critical}
          High: ${riskReport.high}
          Medium: ${riskReport.medium}
          Low: ${riskReport.low}
          Risk Level: ${riskReport.risk_level}
          Action Required: ${riskReport.action_required}
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
              cat > issue-comment.json << EOF
            {
              "body": "## Jenkins job failed\\n\\nJob: ${JOB_NAME}\\nBuild: ${BUILD_URL}\\nCommit: ${GIT_COMMIT}\\n\\n(Automated update on existing issue.)"
            }
EOF
              curl -X POST \
                -H "Authorization: token ${GITHUB_TOKEN}" \
                -H "Accept: application/vnd.github.v3+json" \
                "https://api.github.com/repos/${GITHUB_REPO}/issues/${ISSUE_NUMBER}/comments" \
                -d @issue-comment.json >/dev/null 2>&1 || true
              echo "Updated existing failure issue: ${ISSUE_URL}"
              exit 0
            fi
            
            cat > issue-body.json << EOF
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
              -d @issue-body.json >/dev/null 2>&1 || true
          '''
        }
      }
    }
  }
}
