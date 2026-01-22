# Setting Up Jenkins Jobs via CLI

If the Jenkins UI is not working for you, you can create Multibranch Pipeline jobs via CLI using several methods.

## Method 1: Jenkins REST API with CSRF Token (Recommended)

### Prerequisites
1. Get your Jenkins admin password (from Key Vault secret)
2. Jenkins has CSRF protection enabled, so we need to get a CSRF token first

### Create Job via CLI (with CSRF protection)

```bash
# Set Jenkins URL and credentials
export JENKINS_URL="https://jenkins.canepro.me"
export JENKINS_USER="$(kubectl get secret jenkins-admin -n jenkins -o jsonpath='{.data.username}' | base64 -d)"
export JENKINS_PASSWORD="$(kubectl get secret jenkins-admin -n jenkins -o jsonpath='{.data.password}' | base64 -d)"

# Step 1: Get CSRF token (required when CSRF protection is enabled)
# NOTE: Some Jenkins setups bind crumbs to the HTTP session, so we keep a cookie jar.
COOKIE_JAR="$(mktemp -t jenkins-cookies.XXXXXX)"

CRUMB_JSON=$(curl -sS -u "$JENKINS_USER:$JENKINS_PASSWORD" \
  -c "$COOKIE_JAR" -b "$COOKIE_JAR" \
  "$JENKINS_URL/crumbIssuer/api/json")

CRUMB_FIELD=$(echo "$CRUMB_JSON" | grep -o '"crumbRequestField":"[^"]*"' | cut -d'"' -f4)
CRUMB_VALUE=$(echo "$CRUMB_JSON" | grep -o '"crumb":"[^"]*"' | cut -d'"' -f4)

# Step 2: Create the Multibranch Pipeline job from XML config
curl -X POST \
  -u "$JENKINS_USER:$JENKINS_PASSWORD" \
  -c "$COOKIE_JAR" -b "$COOKIE_JAR" \
  -H "$CRUMB_FIELD:$CRUMB_VALUE" \
  -H "Content-Type: application/xml" \
  --data-binary @.jenkins/job-config.xml \
  "$JENKINS_URL/createItem?name=rocketchat-k8s"

# Step 3: Trigger initial indexing (Branch Indexing)
curl -X POST \
  -u "$JENKINS_USER:$JENKINS_PASSWORD" \
  -c "$COOKIE_JAR" -b "$COOKIE_JAR" \
  -H "$CRUMB_FIELD:$CRUMB_VALUE" \
  "$JENKINS_URL/job/rocketchat-k8s/build?delay=0sec"
```

### Verify Job Created

```bash
# Check if job exists
curl -u "$JENKINS_USER:$JENKINS_PASSWORD" \
  "$JENKINS_URL/job/rocketchat-k8s/api/json"

# Trigger initial indexing
curl -X POST \
  -u "$JENKINS_USER:$JENKINS_PASSWORD" \
  "$JENKINS_URL/job/rocketchat-k8s/build?delay=0sec"
```

---

## Method 2: Using API Token (Alternative)

### Get API Token First
1. Login to Jenkins UI: `https://jenkins.canepro.me`
2. **Manage Jenkins** → **Users** → **admin** → **Configure**
3. **API Token** section → **Add new token** → Copy the token

### Create Job with API Token

```bash
export JENKINS_URL="https://jenkins.canepro.me"
export JENKINS_USER="admin"
export JENKINS_API_TOKEN="your-api-token-here"

# Get CSRF token
CRUMB=$(curl -s -u "$JENKINS_USER:$JENKINS_API_TOKEN" \
  "$JENKINS_URL/crumbIssuer/api/xml?xpath=concat(//crumbRequestField,\":\",//crumb)")

# Create job
curl -X POST \
  -u "$JENKINS_USER:$JENKINS_API_TOKEN" \
  -H "$CRUMB" \
  -H "Content-Type: application/xml" \
  --data-binary @.jenkins/job-config.xml \
  "$JENKINS_URL/createItem?name=rocketchat-k8s"

# Trigger scan
curl -X POST \
  -u "$JENKINS_USER:$JENKINS_API_TOKEN" \
  -H "$CRUMB" \
  "$JENKINS_URL/job/rocketchat-k8s/build?delay=0sec"
```

---

## Method 3: Jenkins Configuration as Code (JCasC)

Add this to your `jenkins-values.yaml` under `controller.JCasC.configScripts`:

```yaml
controller:
  JCasC:
    configScripts:
      # ... existing configs ...
      
      # Multibranch Pipeline Job for rocketchat-k8s
      rocketchat-k8s-job: |
        jobs:
          - multibranch:
              name: "rocketchat-k8s"
              description: "CI validation pipeline for rocketchat-k8s repository"
              sources:
                - github:
                    id: "github-rocketchat-k8s"
                    credentialsId: "github-token"
                    repoOwner: "Canepro"
                    repository: "rocketchat-k8s"
                    traits:
                      - branchDiscovery:
                          strategyId: 1  # Exclude branches that are also filed as PRs
                      - originPullRequestDiscovery:
                          strategyId: 1  # The current pull request revision
                      - forkPullRequestDiscovery:
                          strategyId: 1  # The current pull request revision
                          trust: "Contributors"
              scriptPath: ".jenkins/terraform-validation.Jenkinsfile"
              orphanedItemStrategy:
                pruneDeadBranches: true
```

**Note**: JCasC job configuration syntax may vary by plugin versions. If this doesn't work, use Method 1 or 2.

---

## Method 4: Using kubectl exec (Direct Access)

If you have kubectl access to the Jenkins pod:

```bash
# Get Jenkins pod name
kubectl get pods -n jenkins

# Get admin password
kubectl get secret jenkins-admin -n jenkins -o jsonpath='{.data.password}' | base64 -d

# Create job via CLI inside pod
kubectl exec -n jenkins jenkins-0 -c jenkins -- \
  java -jar /usr/share/jenkins/jenkins.war \
  -s https://jenkins.canepro.me \
  -auth admin:PASSWORD \
  create-job rocketchat-k8s < .jenkins/job-config.xml
```

---

## Quick Setup Script

Save this as `setup-jenkins-job.sh`:

```bash
#!/bin/bash
set -e

# Configuration
JENKINS_URL="${JENKINS_URL:-https://jenkins.canepro.me}"
JOB_NAME="${JOB_NAME:-rocketchat-k8s}"
CONFIG_FILE="${CONFIG_FILE:-.jenkins/job-config.xml}"

# Get credentials
echo "Enter Jenkins admin username (default: admin):"
read -r JENKINS_USER
JENKINS_USER="${JENKINS_USER:-admin}"

echo "Enter Jenkins admin password (or API token):"
read -rs JENKINS_PASSWORD

# Get CSRF token (required when CSRF protection is enabled)
echo "Getting CSRF token..."
CRUMB=$(curl -s -u "$JENKINS_USER:$JENKINS_PASSWORD" \
  "$JENKINS_URL/crumbIssuer/api/xml?xpath=concat(//crumbRequestField,\":\",//crumb)")

if [ -z "$CRUMB" ] || [[ "$CRUMB" == *"Error"* ]]; then
  echo "❌ Failed to get CSRF token. Check credentials."
  exit 1
fi

echo "CSRF Token obtained: ${CRUMB%%:*}"  # Show only the field name, not the value

# Create job
echo "Creating job: $JOB_NAME"
RESPONSE=$(curl -s -w "\n%{http_code}" -X POST \
  -u "$JENKINS_USER:$JENKINS_PASSWORD" \
  -H "$CRUMB" \
  -H "Content-Type: application/xml" \
  --data-binary @"$CONFIG_FILE" \
  "$JENKINS_URL/createItem?name=$JOB_NAME")

HTTP_CODE=$(echo "$RESPONSE" | tail -n1)

if [ "$HTTP_CODE" = "200" ] || [ "$HTTP_CODE" = "201" ]; then
  echo "✅ Job created successfully!"
  
  # Trigger scan
  echo "Triggering initial scan..."
  curl -X POST \
    -u "$JENKINS_USER:$JENKINS_PASSWORD" \
    -H "$CRUMB" \
    "$JENKINS_URL/job/$JOB_NAME/scan"
  
  echo "✅ Initial scan triggered!"
  echo "Check job status at: $JENKINS_URL/job/$JOB_NAME"
else
  echo "❌ Failed to create job. HTTP Status: $HTTP_CODE"
  echo "Response: $(echo "$RESPONSE" | head -n-1)"
  exit 1
fi
```

**Usage**:
```bash
chmod +x setup-jenkins-job.sh
./setup-jenkins-job.sh
```

---

## Troubleshooting

### Windows Line Endings (CRLF) Error
If you see `$'\r': command not found` errors, the script has Windows line endings.

**Fix**:
```bash
# Option 1: Use dos2unix (if installed)
dos2unix .jenkins/create-job.sh

# Option 2: Use sed (works in WSL)
sed -i 's/\r$//' .jenkins/create-job.sh

# Option 3: Use tr
tr -d '\r' < .jenkins/create-job.sh > .jenkins/create-job.sh.tmp && mv .jenkins/create-job.sh.tmp .jenkins/create-job.sh

# Option 4: Run fix script
bash .jenkins/fix-line-endings.sh
```

### 401 Unauthorized Error
If you get 401 even with CSRF token, test authentication first:

```bash
# Run the test script
bash .jenkins/test-auth.sh
```

**Common causes**:
1. **CSRF token not parsed correctly**: Check if `CRUMB_FIELD` and `CRUMB_VALUE` are set
   ```bash
   echo "Field: $CRUMB_FIELD"
   echo "Value: $CRUMB_VALUE"
   ```
2. **Password incorrect**: Verify password from secret
   ```bash
   kubectl get secret jenkins-admin -n jenkins -o jsonpath='{.data.password}' | base64 -d
   ```
3. **CSRF token expired**: Get a fresh token for each request

### Job Already Exists
If the job already exists, delete it first:
```bash
# Get CSRF token first
CRUMB_JSON=$(curl -s -u "admin:$JENKINS_PASSWORD" "$JENKINS_URL/crumbIssuer/api/json")
CRUMB_FIELD=$(echo "$CRUMB_JSON" | grep -o '"crumbRequestField":"[^"]*"' | cut -d'"' -f4)
CRUMB_VALUE=$(echo "$CRUMB_JSON" | grep -o '"crumb":"[^"]*"' | cut -d'"' -f4)

# Delete job
curl -X POST \
  -u "admin:$JENKINS_PASSWORD" \
  -H "$CRUMB_FIELD:$CRUMB_VALUE" \
  "$JENKINS_URL/job/rocketchat-k8s/doDelete"
```

### Invalid Credentials
Make sure you're using:
- Username + Password for basic auth (works with CSRF token)
- API Token can also be used, but still requires CSRF token

Get API token: **Manage Jenkins** → **Users** → **Your User** → **Configure** → **API Token**

### XML Validation Errors
The XML config may need adjustment based on your Jenkins plugin versions. Check Jenkins logs:
```bash
kubectl logs -n jenkins jenkins-0 -c jenkins --tail=50
```

---

## Next Steps After Creating Job

1. **Verify job exists**: Check Jenkins UI or via API
2. **Trigger scan**: Job will auto-scan, or trigger manually
3. **Check discovered branches**: Should see `master` branch and any PRs
4. **Test with PR**: Create a test PR to verify validation runs
