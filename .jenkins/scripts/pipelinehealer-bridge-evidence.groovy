def trimExcerpt(String text, int maxLines = 120, int maxChars = 20000) {
  def lines = (text ?: '').readLines()
  if (maxLines > 0 && lines.size() > maxLines) {
    lines = lines.takeRight(maxLines)
  }

  def excerpt = lines.join('\n')
  if (maxChars > 0 && excerpt.length() > maxChars) {
    excerpt = excerpt.substring(excerpt.length() - maxChars)
  }

  return excerpt
}

def writeLogExcerpt(String outputPath = '.pipelinehealer-log-excerpt.txt', int maxLines = 120, int maxChars = 20000) {
  if (fileExists(outputPath)) {
    def existing = trimExcerpt(readFile(outputPath), maxLines, maxChars)
    if (existing?.trim()) {
      writeFile file: outputPath, text: existing
      return true
    }
  }

  try {
    def lines = currentBuild?.rawBuild?.getLog(maxLines) ?: []
    def excerpt = trimExcerpt(lines.join('\n'), maxLines, maxChars)
    if (!excerpt?.trim()) {
      echo "PipelineHealer bridge: Jenkins log excerpt is empty"
      return false
    }

    writeFile file: outputPath, text: excerpt
    return true
  } catch (err) {
    echo "PipelineHealer bridge: failed to capture Jenkins log excerpt: ${err}"
    return false
  }
}

return this
