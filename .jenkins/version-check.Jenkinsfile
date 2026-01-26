// Version Check Pipeline for rocketchat-k8s
// This pipeline checks for latest versions of all components and creates PRs/issues for updates.
// Purpose: Automated dependency management with risk-based PR/Issue creation.
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
    GITHUB_REPO = 'Canepro/rocketchat-k8s'
    GITHUB_TOKEN_CREDENTIALS = 'github-token'
    VERSIONS_FILE = 'VERSIONS.md'
    UPDATE_REPORT = 'version-updates.json'
  }
  
  stages {
    // Stage 1: Install Tools
    stage('Install Tools') {
      steps {
        sh '''
          # Alpine-based agent: install tools via apk
          apk add --no-cache curl jq git bash python3 py3-pip wget yq github-cli || \
            apk add --no-cache curl jq git bash python3 py3-pip wget yq

          # GitHub CLI is optional (pipeline uses curl for API calls); log if missing
          command -v gh >/dev/null 2>&1 && gh --version || echo "gh not installed (ok)"

          # Install yq for YAML parsing (apk 'yq' preferred; fallback binary if missing)
          if ! command -v yq >/dev/null 2>&1; then
            wget -qO /usr/local/bin/yq https://github.com/mikefarah/yq/releases/latest/download/yq_linux_amd64
            chmod +x /usr/local/bin/yq || true
          fi
        '''
      }
    }
    
    // Stage 2: Check Terraform Provider Versions
    stage('Check Terraform Versions') {
      steps {
        script {
          def terraformVersions = [:]
          
          // Check Azure Provider version
          sh '''
            # Get current version from main.tf
            CURRENT_AZURERM=$(grep -A2 "azurerm = {" terraform/main.tf | grep "version" | sed 's/.*version = "\\(.*\\)".*/\\1/' | tr -d ' ')
            echo "Current Azure Provider: ${CURRENT_AZURERM}"
            
            # Get latest version from Terraform Registry API
            LATEST_AZURERM=$(curl -s https://registry.terraform.io/v1/providers/hashicorp/azurerm/versions | jq -r '.versions[] | .version' | grep -E "^[0-9]+\\.[0-9]+\\.[0-9]+$" | sort -V | tail -1)
            echo "Latest Azure Provider: ${LATEST_AZURERM}"
            
            echo "AZURERM_CURRENT=${CURRENT_AZURERM}" >> versions.env
            echo "AZURERM_LATEST=${LATEST_AZURERM}" >> versions.env
          '''
          
          def azurermCurrent = sh(script: 'grep AZURERM_CURRENT versions.env | cut -d= -f2', returnStdout: true).trim()
          def azurermLatest = sh(script: 'grep AZURERM_LATEST versions.env | cut -d= -f2', returnStdout: true).trim()
          
          terraformVersions['azurerm'] = [
            current: azurermCurrent,
            latest: azurermLatest,
            needsUpdate: azurermCurrent != azurermLatest
          ]
          
          writeJSON file: 'terraform-versions.json', json: terraformVersions
        }
      }
    }
    
    // Stage 3: Check Container Image Versions
    stage('Check Container Image Versions') {
      steps {
        script {
          def imageUpdates = []
          
          // Check RocketChat version
          sh '''
            CURRENT_RC=$(grep "tag:" values.yaml | head -1 | sed 's/.*tag: "\\(.*\\)".*/\\1/')
            echo "Current RocketChat: ${CURRENT_RC}"
            
            # Get latest from GitHub Releases API
            LATEST_RC=$(curl -s https://api.github.com/repos/RocketChat/Rocket.Chat/releases/latest | jq -r '.tag_name' | sed 's/^v//')
            echo "Latest RocketChat: ${LATEST_RC}"
            
            echo "RC_CURRENT=${CURRENT_RC}" >> versions.env
            echo "RC_LATEST=${LATEST_RC}" >> versions.env
          '''
          
          def rcCurrent = sh(script: 'grep RC_CURRENT versions.env | cut -d= -f2', returnStdout: true).trim()
          def rcLatest = sh(script: 'grep RC_LATEST versions.env | cut -d= -f2', returnStdout: true).trim()
          
          if (rcCurrent != rcLatest) {
            imageUpdates.add([
              component: 'RocketChat',
              current: rcCurrent,
              latest: rcLatest,
              location: 'values.yaml',
              risk: isMajorVersionUpdate(rcCurrent, rcLatest) ? 'HIGH' : 'MEDIUM'
            ])
          }
          
          // Check other images from ops/manifests/
          sh '''
            # Extract all image tags from manifests
            grep -r "image:" ops/manifests/*.yaml | grep -v "#" | sed 's/.*image: \\(.*\\)/\\1/' | sort -u > image-list.txt
          '''
          
          writeJSON file: 'image-updates.json', json: imageUpdates
        }
      }
    }
    
    // Stage 4: Check Helm Chart Versions
    stage('Check Helm Chart Versions') {
      steps {
        script {
          def chartUpdates = []
          
          // Check RocketChat Helm chart version
          sh '''
            # Get current chart version from ArgoCD app or values.yaml comment
            CURRENT_CHART=$(grep "Chart:" values.yaml | head -1 | sed 's/.*Chart:.*\\([0-9]\\+\\.[0-9]\\+\\.[0-9]\\+\\).*/\\1/')
            echo "Current RocketChat Chart: ${CURRENT_CHART}"
            
            # Get latest from Helm chart repository
            LATEST_CHART=$(helm search repo rocketchat/rocketchat --versions 2>/dev/null | head -2 | tail -1 | awk '{print $2}' || echo "unknown")
            echo "Latest RocketChat Chart: ${LATEST_CHART}"
            
            echo "CHART_CURRENT=${CURRENT_CHART}" >> versions.env
            echo "CHART_LATEST=${LATEST_CHART}" >> versions.env
          '''
          
          writeJSON file: 'chart-updates.json', json: chartUpdates
        }
      }
    }
    
    // Stage 5: Assess Update Risk and Create PR/Issue
    stage('Create Update PRs/Issues') {
      steps {
        script {
          // Aggregate all updates
          def allUpdates = [:]
          def terraformVersions = readJSON file: 'terraform-versions.json'
          def imageUpdates = readJSON file: 'image-updates.json'
          def chartUpdates = readJSON file: 'chart-updates.json'
          
          allUpdates['terraform'] = terraformVersions
          allUpdates['images'] = imageUpdates
          allUpdates['charts'] = chartUpdates
          
          // Categorize by risk
          def criticalUpdates = []
          def highRiskUpdates = []
          def mediumRiskUpdates = []
          
          imageUpdates.each { update ->
            if (update.risk == 'CRITICAL') {
              criticalUpdates.add(update)
            } else if (update.risk == 'HIGH') {
              highRiskUpdates.add(update)
            } else {
              mediumRiskUpdates.add(update)
            }
          }
          
          // Create report
          def updateReport = [
            timestamp: sh(script: 'date -u +%Y-%m-%dT%H:%M:%SZ', returnStdout: true).trim(),
            critical: criticalUpdates.size(),
            high: highRiskUpdates.size(),
            medium: mediumRiskUpdates.size(),
            updates: allUpdates
          ]
          
          writeJSON file: "${env.UPDATE_REPORT}", json: updateReport
          
          // Create PR or Issue based on risk
          withCredentials([usernamePassword(credentialsId: "${env.GITHUB_TOKEN_CREDENTIALS}", usernameVariable: 'GITHUB_USER', passwordVariable: 'GITHUB_TOKEN')]) {
            if (criticalUpdates.size() > 0) {
              // Create Issue for critical updates
              echo "🚨 Creating GitHub issue for CRITICAL version updates..."
              sh """
                cat > issue-body.json << 'ISSUE_EOF'
                {
                  "title": "🚨 Critical: Major version updates available",
                  "body": "## Version Update Alert\\n\\n**Risk Level:** CRITICAL\\n\\n**Updates Available:**\\n${criticalUpdates.join('\\n')}\\n\\n## Action Required\\n\\nMajor version updates detected. These require careful testing before deployment.\\n\\n## Next Steps\\n\\n1. Review breaking changes in release notes\\n2. Test in staging environment\\n3. Create upgrade plan\\n4. Schedule maintenance window if needed\\n\\n---\\n*This issue was automatically created by Jenkins version check pipeline.*",
                  "labels": ["dependencies", "critical", "automated", "upgrade"]
                }
                ISSUE_EOF
                
                curl -X POST \\
                  -H "Authorization: token \${GITHUB_TOKEN}" \\
                  -H "Accept: application/vnd.github.v3+json" \\
                  "https://api.github.com/repos/${env.GITHUB_REPO}/issues" \\
                  -d @issue-body.json
              """
            } else if (highRiskUpdates.size() > 0 || mediumRiskUpdates.size() >= 5) {
              // Create PR for high/medium risk updates
              echo "⚠️ Creating PR for version updates..."
              
              // Write updates to JSON for shell script processing
              def updatesToApply = [
                high: highRiskUpdates,
                medium: mediumRiskUpdates,
                terraform: terraformVersions
              ]
              writeJSON file: 'updates-to-apply.json', json: updatesToApply
              
              sh '''
                BRANCH_NAME="chore/version-updates-$(date +%Y%m%d)"
                git config user.name "Jenkins Version Bot"
                git config user.email "jenkins@canepro.me"
                git checkout -b ${BRANCH_NAME}
                
                # Process updates and apply to VERSIONS.md and code files
                echo "Applying version updates to files..."
                
                # Update images from high/medium risk updates
                jq -r '.high[] + .medium[] | select(.component != null) | "\\(.component)|\\(.current)|\\(.latest)|\\(.location)"' updates-to-apply.json 2>/dev/null | while IFS='|' read -r component current latest location; do
                  if [ -n "$component" ] && [ -n "$latest" ] && [ "$current" != "$latest" ]; then
                    echo "Updating $component: $current → $latest in $location"
                    
                    # Update VERSIONS.md (handle different table formats)
                    # Avoid backtick-escaping (Groovy+shell) by not matching/printing backticks.
                    # Replace the component row's version cell(s) using a loose table-cell match.
                    sed -i "s/| \\*\\*${component}\\*\\* | [^|]* |/| **${component}** | ${latest} |/g" VERSIONS.md || true
                    sed -i "s/| \\*\\*${component}\\*\\* | [^|]* | [^|]* |.*⚠️/| **${component}** | ${latest} | ${latest} | ✅ **Up to date**/g" VERSIONS.md || true
                    
                    # Update actual code files
                    if [ -f "$location" ]; then
                      case "$location" in
                        values.yaml)
                          sed -i "s/tag: \"${current}\"/tag: \"${latest}\"/g" "$location" || true
                          ;;
                        terraform/main.tf)
                          sed -i "s/version = \"~> ${current}\"/version = \"~> ${latest}\"/g" "$location" || true
                          ;;
                        ops/manifests/*.yaml)
                          sed -i "s/:${current}/:${latest}/g" "$location" || true
                          ;;
                      esac
                    fi
                  fi
                done
                
                # Update Terraform provider if needed
                if [ "$(jq -r '.terraform.azurerm.needsUpdate // false' updates-to-apply.json 2>/dev/null)" = "true" ]; then
                  CURRENT_TF=$(jq -r '.terraform.azurerm.current' updates-to-apply.json 2>/dev/null | sed 's/~>//' | tr -d ' ')
                  LATEST_TF=$(jq -r '.terraform.azurerm.latest' updates-to-apply.json 2>/dev/null)
                  if [ -n "$CURRENT_TF" ] && [ -n "$LATEST_TF" ] && [ "$CURRENT_TF" != "$LATEST_TF" ]; then
                    echo "Updating Terraform Azure Provider: $CURRENT_TF → $LATEST_TF"
                    sed -i "s/| \\*\\*Azure Provider\\*\\* | [^|]* |/| **Azure Provider** | ~> ${LATEST_TF} |/g" VERSIONS.md || true
                    sed -i "s/version = \"~> ${CURRENT_TF}\"/version = \"~> ${LATEST_TF}\"/g" terraform/main.tf || true
                  fi
                fi
                
                # Create update summary
                HIGH_COUNT=$(jq '.high | length' updates-to-apply.json 2>/dev/null || echo "0")
                MEDIUM_COUNT=$(jq '.medium | length' updates-to-apply.json 2>/dev/null || echo "0")
                
                cat > VERSION_UPDATES.md << EOF
                # Version Updates
                
                This PR includes automated version updates detected by Jenkins.
                
                ## Updates Summary
                - High Risk: ${HIGH_COUNT}
                - Medium Risk: ${MEDIUM_COUNT}
                
                ## Files Updated
                - **VERSIONS.md**: Version tracking automatically updated
                - **Code files**: Actual version numbers updated (values.yaml, terraform/main.tf, etc.)
                
                ## Review Checklist
                - [ ] Review all version changes in VERSIONS.md
                - [ ] Verify code file changes are correct
                - [ ] Check release notes for breaking changes
                - [ ] Test in staging if applicable
                EOF
                
                # Stage all changes
                git add VERSIONS.md VERSION_UPDATES.md values.yaml terraform/main.tf ops/manifests/*.yaml 2>/dev/null || true
                
                # Commit with detailed message
                git commit -m "chore: automated version updates

                - High risk: ${HIGH_COUNT}
                - Medium risk: ${MEDIUM_COUNT}
                - Updated VERSIONS.md automatically
                - Updated code files with new versions
                - Generated by Jenkins version check pipeline" || echo "No changes to commit"
                
                git push origin ${BRANCH_NAME}
                
                # Create PR
                cat > pr-body.json << EOF
                {
                  "title": "⬆️ Version Updates: ${HIGH_COUNT} high, ${MEDIUM_COUNT} medium",
                  "head": "${BRANCH_NAME}",
                  "base": "master",
                  "body": "## Automated Version Updates\\n\\nThis PR includes version updates detected by automated checks.\\n\\n### Updates Summary\\n- High Risk: ${HIGH_COUNT}\\n- Medium Risk: ${MEDIUM_COUNT}\\n\\n### Files Updated\\n- **VERSIONS.md**: Automatically updated with new versions\\n- **Code files**: Version numbers updated in values.yaml, terraform/main.tf, etc.\\n\\n### Review Required\\n\\nPlease review all changes and test before merging.\\n\\n---\\n*This PR was automatically created by Jenkins version check pipeline.*",
                  "labels": ["dependencies", "automated", "upgrade"]
                }
                EOF
                
                curl -X POST \\
                  -H "Authorization: token ${GITHUB_TOKEN}" \\
                  -H "Accept: application/vnd.github.v3+json" \\
                  "https://api.github.com/repos/${GITHUB_REPO}/pulls" \\
                  -d @pr-body.json
              '''
            } else {
              echo "✅ All versions are up to date or updates are low risk"
            }
          }
        }
      }
    }
  }
  
  post {
    always {
      archiveArtifacts artifacts: '*.json,*.md', allowEmptyArchive: true
    }
  }
}

// Helper function to determine if version update is major
def isMajorVersionUpdate(current, latest) {
  def currentMajor = current.split('\\.')[0].toInteger()
  def latestMajor = latest.split('\\.')[0].toInteger()
  return latestMajor > currentMajor
}
