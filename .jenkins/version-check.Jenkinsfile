// Version Check Pipeline for central-observability-hub-stack
// This pipeline checks for latest versions of all Helm charts and creates PRs/issues for updates.
// Purpose: Automated dependency management for OKE Observability Hub components.
// Agent routing (Phase 3): OKE-only — runs on OKE (label version-checker). For Azure/Key Vault use label 'aks-agent'.
pipeline {
  agent {
    kubernetes {
      label 'version-checker'
      defaultContainer 'version-checker'
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
  - name: version-checker
    image: docker.io/alpine:3.20
    command: ['sleep', '3600']
    resources:
      requests:
        memory: "256Mi"
        cpu: "100m"
      limits:
        memory: "512Mi"
        cpu: "250m"
"""
    }
  }
  
  environment {
    GITHUB_REPO = 'Canepro/central-observability-hub-stack'
    GITHUB_TOKEN_CREDENTIALS = 'github-token'
    VERSIONS_FILE = 'VERSION-TRACKING.md'
    UPDATE_REPORT = 'version-updates.json'
  }
  
  stages {
    // Stage 1: Install Tools
    stage('Install Tools') {
      steps {
        sh '''
          # Alpine-based agent: install tools via apk (openssl required for Helm install script checksum)
          apk add --no-cache curl jq git bash yq openssl github-cli || \
            apk add --no-cache curl jq git bash yq openssl

          # GitHub CLI is optional; log if missing
          command -v gh >/dev/null 2>&1 && gh --version || echo "gh not installed (ok)"

          # Install yq for YAML parsing (apk 'yq' preferred; fallback binary if missing)
          if ! command -v yq >/dev/null 2>&1; then
            wget -qO /usr/local/bin/yq https://github.com/mikefarah/yq/releases/latest/download/yq_linux_amd64
            chmod +x /usr/local/bin/yq || true
          fi
          
          # Install helm for repo searches (openssl above enables checksum verification)
          curl -fsSL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash || true
        '''
      }
    }
    
    // Stage 2: Check Helm Chart Versions
    stage('Check Helm Chart Versions') {
      steps {
        script {
          sh '''
            # Add Helm repositories
            helm repo add argo https://argoproj.github.io/argo-helm 2>/dev/null || true
            helm repo add grafana https://grafana.github.io/helm-charts 2>/dev/null || true
            helm repo add prometheus-community https://prometheus-community.github.io/helm-charts 2>/dev/null || true
            helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx 2>/dev/null || true
            helm repo add metrics-server https://kubernetes-sigs.github.io/metrics-server/ 2>/dev/null || true
            helm repo update 2>/dev/null || true
            
            # Initialize versions file
            echo "" > versions.env
            
            # Function to extract targetRevision from ArgoCD app manifest
            extract_version() {
              local file=$1
              local component=$2
              if [ -f "$file" ]; then
                VERSION=$(yq -r '.spec.source.targetRevision // .spec.sources[0].targetRevision // ""' "$file" 2>/dev/null | head -1)
                echo "${component}_CURRENT=${VERSION}" >> versions.env
              else
                echo "${component}_CURRENT=" >> versions.env
              fi
            }
            
            # Extract current versions from ArgoCD app manifests
            extract_version "argocd/applications/grafana.yaml" "GRAFANA"
            extract_version "argocd/applications/loki.yaml" "LOKI"
            extract_version "argocd/applications/promtail.yaml" "PROMTAIL"
            extract_version "argocd/applications/tempo.yaml" "TEMPO"
            extract_version "argocd/applications/prometheus.yaml" "PROMETHEUS"
            extract_version "argocd/applications/nginx-ingress.yaml" "NGINX"
            extract_version "argocd/applications/metrics-server.yaml" "METRICS_SERVER"
            
            # Get latest versions from Helm repos
            echo "GRAFANA_LATEST=$(helm search repo grafana/grafana --versions 2>/dev/null | grep -v NAME | head -1 | awk '{print $2}' || echo '')" >> versions.env
            echo "LOKI_LATEST=$(helm search repo grafana/loki --versions 2>/dev/null | grep -v NAME | head -1 | awk '{print $2}' || echo '')" >> versions.env
            echo "PROMTAIL_LATEST=$(helm search repo grafana/promtail --versions 2>/dev/null | grep -v NAME | head -1 | awk '{print $2}' || echo '')" >> versions.env
            echo "TEMPO_LATEST=$(helm search repo grafana/tempo --versions 2>/dev/null | grep -v NAME | head -1 | awk '{print $2}' || echo '')" >> versions.env
            echo "PROMETHEUS_LATEST=$(helm search repo prometheus-community/prometheus --versions 2>/dev/null | grep -v NAME | head -1 | awk '{print $2}' || echo '')" >> versions.env
            echo "NGINX_LATEST=$(helm search repo ingress-nginx/ingress-nginx --versions 2>/dev/null | grep -v NAME | head -1 | awk '{print $2}' || echo '')" >> versions.env
            echo "METRICS_SERVER_LATEST=$(helm search repo metrics-server/metrics-server --versions 2>/dev/null | grep -v NAME | head -1 | awk '{print $2}' || echo '')" >> versions.env
            
            cat versions.env
          '''
          
          // Build update list and reports in shell (avoid Groovy JSON sandbox restrictions)
          sh '''
            set -e
            components="GRAFANA LOKI PROMTAIL TEMPO PROMETHEUS NGINX METRICS_SERVER"
            updates='[]'

            major_of() {
              echo "$1" | cut -d. -f1 | sed 's/[^0-9].*$//' | tr -d '\\n'
            }

            for comp in $components; do
              current=$(grep "${comp}_CURRENT" versions.env | cut -d= -f2 | tr -d '\\n')
              latest=$(grep "${comp}_LATEST" versions.env | cut -d= -f2 | tr -d '\\n')
              if [ -n "$current" ] && [ -n "$latest" ] && [ "$current" != "$latest" ]; then
                cur_major=$(major_of "$current")
                lat_major=$(major_of "$latest")
                if [ -n "$cur_major" ] && [ -n "$lat_major" ] && [ "$lat_major" -gt "$cur_major" ]; then
                  risk="HIGH"
                else
                  risk="MEDIUM"
                fi

                case "$comp" in
                  GRAFANA) location="argocd/applications/grafana.yaml" ;;
                  LOKI) location="argocd/applications/loki.yaml" ;;
                  PROMTAIL) location="argocd/applications/promtail.yaml" ;;
                  TEMPO) location="argocd/applications/tempo.yaml" ;;
                  PROMETHEUS) location="argocd/applications/prometheus.yaml" ;;
                  NGINX) location="argocd/applications/nginx-ingress.yaml" ;;
                  METRICS_SERVER) location="argocd/applications/metrics-server.yaml" ;;
                  *) location="" ;;
                esac

                updates=$(printf '%s' "$updates" | jq \
                  --arg comp "$comp" \
                  --arg current "$current" \
                  --arg latest "$latest" \
                  --arg location "$location" \
                  --arg risk "$risk" \
                  '. + [{component:$comp,current:$current,latest:$latest,location:$location,risk:$risk}]')

                echo "Update available: ${comp} ${current} -> ${latest} (${risk})"
              elif [ -n "$current" ] && [ -n "$latest" ]; then
                echo "Up to date: ${comp} ${current}"
              fi
            done

            echo "$updates" > chart-updates.json

            high_count=$(jq '[.[] | select(.risk=="HIGH")] | length' chart-updates.json)
            medium_count=$(jq '[.[] | select(.risk=="MEDIUM")] | length' chart-updates.json)
            total_count=$(jq 'length' chart-updates.json)

            cat > update-counts.env <<EOF
HIGH_COUNT=${high_count}
MEDIUM_COUNT=${medium_count}
TOTAL_COUNT=${total_count}
EOF

            jq -r '.[] | "- **\\(.component)**: \\(.current) → \\(.latest) (\\(.risk))"' chart-updates.json > update-list-all.txt
            jq -r '.[] | select(.risk=="HIGH") | "- **\\(.component)**: \\(.current) → \\(.latest)"' chart-updates.json > update-list-high.txt

            jq -n \
              --arg ts "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
              --argjson high "$high_count" \
              --argjson medium "$medium_count" \
              --argjson total "$total_count" \
              --argjson updates "$(cat chart-updates.json)" \
              '{timestamp:$ts, high:$high, medium:$medium, total:$total, updates:$updates}' \
              > "${UPDATE_REPORT}"
          '''
        }
      }
    }
    
    // Stage 3: Assess Risk and Create PR/Issue
    stage('Create Update PRs/Issues') {
      steps {
        script {
          def highCount = sh(script: "grep HIGH_COUNT update-counts.env | cut -d= -f2", returnStdout: true).trim()
          def mediumCount = sh(script: "grep MEDIUM_COUNT update-counts.env | cut -d= -f2", returnStdout: true).trim()
          def totalCount = sh(script: "grep TOTAL_COUNT update-counts.env | cut -d= -f2", returnStdout: true).trim()

          echo "Version Check Summary:"
          echo "  High Risk Updates: ${highCount}"
          echo "  Medium Risk Updates: ${mediumCount}"
          
          if (totalCount == "0") {
            echo "✅ All Helm charts are up to date!"
            return
          }
          
          def mediumCountInt = mediumCount ? mediumCount.toInteger() : 0

          // Create PR or Issue based on findings
          withCredentials([usernamePassword(credentialsId: "${env.GITHUB_TOKEN_CREDENTIALS}", usernameVariable: 'GITHUB_USER', passwordVariable: 'GITHUB_TOKEN')]) {
            if (!env.GITHUB_TOKEN?.trim()) {
              echo "⚠️ GitHub token is empty; skipping issue/PR creation."
              return
            }
            if (highCount != "0") {
              // Create GitHub Issue for high-risk (major version) updates
              echo "⚠️ Creating GitHub issue for HIGH risk version updates..."
              
              // Use REAL newlines so GitHub markdown renders bullet lists correctly
              def updateList = readFile('update-list-high.txt').trim()
              
              withEnv(["UPDATE_LIST=${updateList}"]) {
                sh '''
                  set +e
                  ISSUE_TITLE="⚠️ Helm Chart: Major version updates available"
                  
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
                  
                  ensure_label "dependencies" "0366d6"
                  ensure_label "helm" "0e8a16"
                  ensure_label "automated" "0e8a16"
                  ensure_label "upgrade" "fbca04"
                  
                  # De-duplicate: if an open issue with same title exists, comment on it instead
                  ISSUE_LIST_JSON=$(curl -fsSL \
                    -H "Authorization: token ${GITHUB_TOKEN}" \
                    -H "Accept: application/vnd.github.v3+json" \
                    "https://api.github.com/repos/${GITHUB_REPO}/issues?state=open&labels=dependencies,helm,automated,upgrade&per_page=100" \
                    || echo '[]')
                  
                  EXISTING_ISSUE_NUMBER=$(echo "$ISSUE_LIST_JSON" | jq -r --arg t "$ISSUE_TITLE" '[.[] | select(.pull_request == null) | select(.title == $t)][0].number // empty' 2>/dev/null || true)
                  EXISTING_ISSUE_URL=$(echo "$ISSUE_LIST_JSON" | jq -r --arg t "$ISSUE_TITLE" '[.[] | select(.pull_request == null) | select(.title == $t)][0].html_url // empty' 2>/dev/null || true)
                  
                  if [ -n "${EXISTING_ISSUE_NUMBER}" ]; then
                    echo "Existing open issue #${EXISTING_ISSUE_NUMBER} found; adding comment instead of creating duplicate."
                    printf "%s" "${UPDATE_LIST}" > update-list.md
                    TS=$(date -u +%Y-%m-%dT%H:%M:%SZ)
                    COMMENT_JSON=$(jq -n --rawfile updates update-list.md --arg ts "$TS" --arg build "${BUILD_URL:-}" \
                      '{body:("## New version updates detected\n\nTime: " + $ts + ( ($build|length)>0 ? ("\nBuild: " + $build) : "" ) + "\n\n**Updates Available:**\n" + $updates)}')
                    curl -X POST \
                      -H "Authorization: token ${GITHUB_TOKEN}" \
                      -H "Accept: application/vnd.github.v3+json" \
                      "https://api.github.com/repos/${GITHUB_REPO}/issues/${EXISTING_ISSUE_NUMBER}/comments" \
                      -d "$COMMENT_JSON" >/dev/null 2>&1 || true
                    echo "Updated existing issue: ${EXISTING_ISSUE_URL}"
                    exit 0
                  fi
                  
                  # Build JSON with jq so newlines are escaped correctly
                  printf "%s" "${UPDATE_LIST}" > update-list.md
                  ISSUE_BODY_JSON=$(jq -n \
                    --arg title "${ISSUE_TITLE}" \
                    --rawfile updates update-list.md \
                    '{title:$title, body:("## Version Update Alert\n\n**Risk Level:** HIGH (Major Version Updates)\n\n**Updates Available:**\n" + $updates + "\n\n## Action Required\n\nMajor version updates detected. These may include breaking changes and require careful testing.\n\n## Next Steps\n\n1. Review release notes for each component\n2. Check for breaking changes and migration guides\n3. Test in staging environment if available\n4. Update VERSION-TRACKING.md after upgrade\n\n---\n*This issue was automatically created by Jenkins version check pipeline.*"), labels:["dependencies","helm","automated","upgrade"]}')
                  echo "$ISSUE_BODY_JSON" > issue-body.json
                  
                  curl -X POST \
                    -H "Authorization: token ${GITHUB_TOKEN}" \
                    -H "Accept: application/vnd.github.v3+json" \
                    "https://api.github.com/repos/${GITHUB_REPO}/issues" \
                    -d @issue-body.json || true
                '''
              }
            } else if (mediumCountInt >= 3) {
              // Create PR for multiple medium-risk updates
              echo "📝 Creating PR for version updates..."
              
              sh '''
                set +e
                PR_TITLE="⬆️ Helm Chart Updates Available"
                
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
                
                ensure_label "dependencies" "0366d6"
                ensure_label "helm" "0e8a16"
                ensure_label "automated" "0e8a16"
                ensure_label "upgrade" "fbca04"
                
                # De-duplicate: re-use an existing open PR if present
                PR_LIST_JSON=$(curl -fsSL \
                  -H "Authorization: token ${GITHUB_TOKEN}" \
                  -H "Accept: application/vnd.github.v3+json" \
                  "https://api.github.com/repos/${GITHUB_REPO}/issues?state=open&labels=dependencies,helm,automated,upgrade&per_page=100" \
                  || echo '[]')
                EXISTING_PR_NUMBER=$(echo "$PR_LIST_JSON" | jq -r '[.[] | select(.pull_request != null) | select(.title | startswith("⬆️ Helm Chart Updates"))][0].number // empty' 2>/dev/null || true)
                if [ -n "${EXISTING_PR_NUMBER}" ]; then
                  PR_JSON=$(curl -fsSL \
                    -H "Authorization: token ${GITHUB_TOKEN}" \
                    -H "Accept: application/vnd.github.v3+json" \
                    "https://api.github.com/repos/${GITHUB_REPO}/pulls/${EXISTING_PR_NUMBER}" \
                    || echo '{}')
                  BRANCH_NAME=$(echo "$PR_JSON" | jq -r '.head.ref // empty' 2>/dev/null || true)
                  echo "Found existing version update PR #${EXISTING_PR_NUMBER} on branch ${BRANCH_NAME}; will update it."
                fi
                BRANCH_NAME="${BRANCH_NAME:-chore/helm-version-updates-$(date +%Y%m%d)}"
                if [ "${BRANCH_NAME}" = "main" ]; then
                  BRANCH_NAME="chore/helm-version-updates-$(date +%Y%m%d)"
                fi
                # Ensure git operations are allowed in this workspace
                git config --global --add safe.directory "${WORKSPACE}"

                
                git config user.name "Jenkins Version Bot"
                git config user.email "jenkins@canepro.me"
                
                # Check out existing remote branch if it exists
                git fetch origin "${BRANCH_NAME}" 2>/dev/null || true
                if git show-ref --verify --quiet "refs/remotes/origin/${BRANCH_NAME}"; then
                  git checkout -B "${BRANCH_NAME}" "origin/${BRANCH_NAME}"
                else
                  git checkout -b "${BRANCH_NAME}"
                fi
                
                # Read updates and apply them
                jq -r '.[] | "\\(.component)|\\(.current)|\\(.latest)|\\(.location)"' chart-updates.json 2>/dev/null | while IFS='|' read -r component current latest location; do
                  if [ -n "$component" ] && [ -n "$latest" ] && [ -f "$location" ]; then
                    echo "Updating $component: $current → $latest in $location"
                    # Update targetRevision in ArgoCD app manifest
                    yq -i ".spec.source.targetRevision = \\"${latest}\\"" "$location" 2>/dev/null || \
                    yq -i ".spec.sources[0].targetRevision = \\"${latest}\\"" "$location" 2>/dev/null || true
                  fi
                done
                
                # Update VERSION-TRACKING.md with today's date
                TODAY=$(date +%Y-%m-%d)
                sed -i "s/\\*\\*Last Updated\\*\\*: [0-9-]*/\\*\\*Last Updated\\*\\*: ${TODAY}/" VERSION-TRACKING.md || true
                
                # Stage changes
                git add argocd/applications/*.yaml VERSION-TRACKING.md 2>/dev/null || true
                
                # Check if there are changes to commit
                if [ -z "$(git status --porcelain)" ]; then
                  echo "No changes to commit"
                  if [ -n "${EXISTING_PR_NUMBER}" ]; then
                    echo "No new changes; existing PR #${EXISTING_PR_NUMBER} is up to date."
                  fi
                  exit 0
                fi
                
                # Commit
                git commit -m "chore: update Helm chart versions

- Updated via automated version check
- Review VERSION-TRACKING.md for details
- Generated by Jenkins version check pipeline"
                
                # Ensure authenticated remote for push
                set +x
                git remote set-url origin "https://${GITHUB_TOKEN}@github.com/${GITHUB_REPO}.git" 2>/dev/null || true
                set -x
                
                # Re-enable fail-fast so git push failures surface
                set -e
                git push origin "${BRANCH_NAME}"
                
                # Create PR if it doesn't exist, or add comment if it does
                UPDATES_SUMMARY=$(jq -r '.[] | "- \\(.component): \\(.current) → \\(.latest)"' chart-updates.json | tr '\\n' ' ')
                if [ -n "${EXISTING_PR_NUMBER}" ]; then
                  TS=$(date -u +%Y-%m-%dT%H:%M:%SZ)
                  COMMENT_JSON=$(jq -n --arg ts "$TS" --arg build "${BUILD_URL:-}" --arg summary "$UPDATES_SUMMARY" \
                    '{body:("## PR updated by Jenkins\n\nTime: " + $ts + ( ($build|length)>0 ? ("\nBuild: " + $build) : "" ) + "\n\nUpdates:\n" + $summary)}')
                  curl -fsSL -X POST \
                    -H "Authorization: token ${GITHUB_TOKEN}" \
                    -H "Accept: application/vnd.github.v3+json" \
                    "https://api.github.com/repos/${GITHUB_REPO}/issues/${EXISTING_PR_NUMBER}/comments" \
                    -d "$COMMENT_JSON" >/dev/null 2>&1 || true
                  echo "Updated existing PR #${EXISTING_PR_NUMBER} with new changes"
                else
                  cat > pr-body.json << EOF
{
  "title": "${PR_TITLE}",
  "head": "${BRANCH_NAME}",
  "base": "main",
  "body": "## Automated Helm Chart Updates\\n\\nThis PR includes version updates detected by automated checks.\\n\\n### Updates\\n${UPDATES_SUMMARY}\\n\\n### Review Checklist\\n\\n- [ ] Review release notes for each updated component\\n- [ ] Verify no breaking changes\\n- [ ] Test ArgoCD sync after merge\\n- [ ] Update VERSION-TRACKING.md if needed\\n\\n---\\n*This PR was automatically created by Jenkins version check pipeline.*"
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
                      -d '{"labels":["dependencies","helm","automated","upgrade"]}' >/dev/null 2>&1 || true
                  fi
                fi
              '''
            } else {
              echo "✅ Only minor updates available (${mediumCount}). No action needed."
            }
          }
        }
      }
    }
  }
  
  post {
    always {
      archiveArtifacts artifacts: '*.json,*.env', allowEmptyArchive: true
    }
    success {
      echo '✅ Version check completed'
    }
    failure {
      echo '❌ Version check failed'
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

// Helper function to determine if version update is major
def isMajorVersionUpdate(String current, String latest) {
  try {
    if (!current || !latest) return false
    def currentMajor = current.split('\\.')[0].replaceAll('[^0-9]', '').toInteger()
    def latestMajor = latest.split('\\.')[0].replaceAll('[^0-9]', '').toInteger()
    return latestMajor > currentMajor
  } catch (Exception e) {
    return false
  }
}
