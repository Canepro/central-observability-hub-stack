// Version Check Pipeline for central-observability-hub-stack
// This pipeline checks for latest versions of all Helm charts and creates PRs/issues for updates.
// Purpose: Automated dependency management for OKE Observability Hub components.
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
  - name: version-checker
    image: alpine:3.20
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
          # Alpine-based agent: install tools via apk
          apk add --no-cache curl jq git bash yq github-cli || \
            apk add --no-cache curl jq git bash yq

          # GitHub CLI is optional; log if missing
          command -v gh >/dev/null 2>&1 && gh --version || echo "gh not installed (ok)"

          # Install yq for YAML parsing (apk 'yq' preferred; fallback binary if missing)
          if ! command -v yq >/dev/null 2>&1; then
            wget -qO /usr/local/bin/yq https://github.com/mikefarah/yq/releases/latest/download/yq_linux_amd64
            chmod +x /usr/local/bin/yq || true
          fi
          
          # Install helm for repo searches
          curl -fsSL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash || true
        '''
      }
    }
    
    // Stage 2: Check Helm Chart Versions
    stage('Check Helm Chart Versions') {
      steps {
        script {
          def chartUpdates = []
          
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
          
          // Parse versions and build update list
          def components = ['GRAFANA', 'LOKI', 'PROMTAIL', 'TEMPO', 'PROMETHEUS', 'NGINX', 'METRICS_SERVER']
          def locations = [
            'GRAFANA': 'argocd/applications/grafana.yaml',
            'LOKI': 'argocd/applications/loki.yaml',
            'PROMTAIL': 'argocd/applications/promtail.yaml',
            'TEMPO': 'argocd/applications/tempo.yaml',
            'PROMETHEUS': 'argocd/applications/prometheus.yaml',
            'NGINX': 'argocd/applications/nginx-ingress.yaml',
            'METRICS_SERVER': 'argocd/applications/metrics-server.yaml'
          ]
          
          components.each { comp ->
            def current = sh(script: "grep ${comp}_CURRENT versions.env | cut -d= -f2 | tr -d '\\n'", returnStdout: true).trim()
            def latest = sh(script: "grep ${comp}_LATEST versions.env | cut -d= -f2 | tr -d '\\n'", returnStdout: true).trim()
            
            if (current && latest && current != latest) {
              def risk = isMajorVersionUpdate(current, latest) ? 'HIGH' : 'MEDIUM'
              chartUpdates.add([
                component: comp,
                current: current,
                latest: latest,
                location: locations[comp],
                risk: risk
              ])
              echo "Update available: ${comp} ${current} -> ${latest} (${risk})"
            } else if (current && latest) {
              echo "Up to date: ${comp} ${current}"
            }
          }
          
          writeJSON file: 'chart-updates.json', json: chartUpdates
        }
      }
    }
    
    // Stage 3: Assess Risk and Create PR/Issue
    stage('Create Update PRs/Issues') {
      steps {
        script {
          def chartUpdates = readJSON file: 'chart-updates.json'
          
          // Categorize by risk
          def highRiskUpdates = chartUpdates.findAll { it.risk == 'HIGH' }
          def mediumRiskUpdates = chartUpdates.findAll { it.risk == 'MEDIUM' }
          
          // Create report
          def updateReport = [
            timestamp: sh(script: 'date -u +%Y-%m-%dT%H:%M:%SZ', returnStdout: true).trim(),
            high: highRiskUpdates.size(),
            medium: mediumRiskUpdates.size(),
            updates: chartUpdates
          ]
          
          writeJSON file: "${env.UPDATE_REPORT}", json: updateReport
          
          echo "Version Check Summary:"
          echo "  High Risk Updates: ${highRiskUpdates.size()}"
          echo "  Medium Risk Updates: ${mediumRiskUpdates.size()}"
          
          if (chartUpdates.size() == 0) {
            echo "✅ All Helm charts are up to date!"
            return
          }
          
          // Create PR or Issue based on findings
          withCredentials([usernamePassword(credentialsId: "${env.GITHUB_TOKEN_CREDENTIALS}", usernameVariable: 'GITHUB_USER', passwordVariable: 'GITHUB_TOKEN')]) {
            if (highRiskUpdates.size() > 0) {
              // Create GitHub Issue for high-risk (major version) updates
              echo "⚠️ Creating GitHub issue for HIGH risk version updates..."
              
              def updateList = highRiskUpdates.collect { "- **${it.component}**: ${it.current} → ${it.latest}" }.join('\\n')
              
              sh """
                cat > issue-body.json << 'ISSUE_EOF'
{
  "title": "⚠️ Helm Chart: Major version updates available",
  "body": "## Version Update Alert\\n\\n**Risk Level:** HIGH (Major Version Updates)\\n\\n**Updates Available:**\\n${updateList}\\n\\n## Action Required\\n\\nMajor version updates detected. These may include breaking changes and require careful testing.\\n\\n## Next Steps\\n\\n1. Review release notes for each component\\n2. Check for breaking changes and migration guides\\n3. Test in staging environment if available\\n4. Update VERSION-TRACKING.md after upgrade\\n\\n---\\n*This issue was automatically created by Jenkins version check pipeline.*",
  "labels": ["dependencies", "helm", "automated", "upgrade"]
}
ISSUE_EOF
                
                curl -X POST \\
                  -H "Authorization: token \${GITHUB_TOKEN}" \\
                  -H "Accept: application/vnd.github.v3+json" \\
                  "https://api.github.com/repos/${env.GITHUB_REPO}/issues" \\
                  -d @issue-body.json || true
              """
            } else if (mediumRiskUpdates.size() >= 3) {
              // Create PR for multiple medium-risk updates
              echo "📝 Creating PR for version updates..."
              
              sh '''
                BRANCH_NAME="chore/helm-version-updates-$(date +%Y%m%d)"
                git config user.name "Jenkins Version Bot"
                git config user.email "jenkins@canepro.me"
                git checkout -b ${BRANCH_NAME} || git checkout ${BRANCH_NAME}
                
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
                if git diff --cached --quiet; then
                  echo "No changes to commit"
                  exit 0
                fi
                
                # Commit
                git commit -m "chore: update Helm chart versions

- Updated via automated version check
- Review VERSION-TRACKING.md for details
- Generated by Jenkins version check pipeline"
                
                # Push
                git remote set-url origin "https://${GITHUB_TOKEN}@github.com/${GITHUB_REPO}.git" 2>/dev/null || true
                git push -u origin ${BRANCH_NAME} || true
                
                # Create PR
                UPDATES_SUMMARY=$(jq -r '.[] | "- \\(.component): \\(.current) → \\(.latest)"' chart-updates.json | tr '\\n' ' ')
                cat > pr-body.json << EOF
{
  "title": "⬆️ Helm Chart Updates Available",
  "head": "${BRANCH_NAME}",
  "base": "main",
  "body": "## Automated Helm Chart Updates\\n\\nThis PR includes version updates detected by automated checks.\\n\\n### Updates\\n${UPDATES_SUMMARY}\\n\\n### Review Checklist\\n\\n- [ ] Review release notes for each updated component\\n- [ ] Verify no breaking changes\\n- [ ] Test ArgoCD sync after merge\\n- [ ] Update VERSION-TRACKING.md if needed\\n\\n---\\n*This PR was automatically created by Jenkins version check pipeline.*"
}
EOF
                
                curl -X POST \
                  -H "Authorization: token ${GITHUB_TOKEN}" \
                  -H "Accept: application/vnd.github.v3+json" \
                  "https://api.github.com/repos/${GITHUB_REPO}/pulls" \
                  -d @pr-body.json || true
              '''
            } else {
              echo "✅ Only minor updates available (${mediumRiskUpdates.size()}). No action needed."
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
