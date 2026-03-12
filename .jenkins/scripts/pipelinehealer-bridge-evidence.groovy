def capture(String outputPath = '.pipelinehealer-log-excerpt.txt', Closure body) {
  tee(file: outputPath) {
    body()
  }
}

def writeLogExcerpt(String outputPath = '.pipelinehealer-log-excerpt.txt', int maxLines = 200, int maxChars = 20000) {
  if (fileExists(outputPath)) {
    return true
  }

  echo 'PipelineHealer bridge evidence: no captured excerpt file is available yet.'
  return false
}

return this
