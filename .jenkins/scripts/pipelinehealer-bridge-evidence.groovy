def fetchConsoleText(String outputPath, int maxLines, int maxChars, String authArg = '') {
  return sh(returnStatus: true, script: """
    set +e
    EXCERPT_TMP='${outputPath}.tmp'
    HTTP_CODE=\$(curl -sS ${authArg} -o "\$EXCERPT_TMP" -w '%{http_code}' "\${BUILD_URL}consoleText" 2>/dev/null)
    if [ "\$HTTP_CODE" = "200" ] && [ -s "\$EXCERPT_TMP" ]; then
      tail -n ${maxLines} "\$EXCERPT_TMP" | sed 's/\\x1b\\[[0-9;]*m//g; s/\\*\\{4,\\}/****/g' | tail -c ${maxChars} > '${outputPath}'
      rm -f "\$EXCERPT_TMP"
      echo "PipelineHealer bridge evidence: captured \$(wc -c < '${outputPath}') bytes via consoleText API"
      exit 0
    fi
    rm -f "\$EXCERPT_TMP"
    echo "PipelineHealer bridge evidence: consoleText API returned HTTP \$HTTP_CODE"
    exit 1
  """) == 0
}

def writeLogExcerpt(String outputPath = '.pipelinehealer-log-excerpt.txt', int maxLines = 120, int maxChars = 20000) {
  echo "PipelineHealer bridge evidence: writeLogExcerpt called (outputPath=${outputPath})"

  if (fileExists(outputPath)) {
    def existing = readFile(outputPath).trim()
    if (existing) {
      echo "PipelineHealer bridge evidence: reusing existing excerpt (${existing.length()} chars)"
      return true
    }
  }

  echo 'PipelineHealer bridge evidence: fetching console text via BUILD_URL API...'

  def captured = false
  try {
    withCredentials([usernamePassword(
      credentialsId: 'jenkins-api-token',
      usernameVariable: 'JENKINS_API_USER',
      passwordVariable: 'JENKINS_API_TOKEN',
    )]) {
      captured = fetchConsoleText(outputPath, maxLines, maxChars, '-u "$JENKINS_API_USER:$JENKINS_API_TOKEN"')
    }
  } catch (err) {
    echo "PipelineHealer bridge evidence: jenkins-api-token credential not configured (${err}); trying unauthenticated..."
    captured = fetchConsoleText(outputPath, maxLines, maxChars)
  }

  if (captured) {
    return true
  }

  echo 'PipelineHealer bridge evidence: all excerpt capture methods failed.'
  return false
}

return this
