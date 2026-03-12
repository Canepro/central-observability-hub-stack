def writeLogExcerpt(String outputPath = '.pipelinehealer-log-excerpt.txt', int maxLines = 200, int maxChars = 20000) {
  def rawBuild = currentBuild?.rawBuild
  if (rawBuild == null) {
    echo 'PipelineHealer bridge evidence: raw build is unavailable; skipping log capture.'
    return false
  }

  List<String> lines
  try {
    lines = rawBuild.getLog(Math.max(maxLines, 1)) ?: []
  } catch (err) {
    echo "PipelineHealer bridge evidence: failed to read Jenkins log tail: ${err}"
    return false
  }

  def excerpt = lines.join('\n').trim()
  if (!excerpt) {
    echo 'PipelineHealer bridge evidence: Jenkins log tail is empty; skipping log capture.'
    return false
  }

  if (excerpt.length() > maxChars) {
    excerpt = excerpt.substring(excerpt.length() - maxChars)
  }

  writeFile file: outputPath, text: "${excerpt}\n"
  return true
}

return this
