class PullRequest
  def initialize(node)
    @node = node
  end
  
  def commits
    @commits ||= @node.dig("commits", "edges").map{|e| e.fetch("node").fetch("commit") }
  end
  
  def started_at
    @started_at ||= Time.parse commits.first.fetch("authoredDate")
  end
  
  def finished_at
    @finished_at ||= Time.parse @node.fetch("closedAt")
  end
  
  def cycle_time
    finished_at && started_at && finished_at - started_at
  end
  
  def number
    @node.fetch("number")
  end
  
  def inspect
    "<PR ##{number} #{ChronicDuration.output(cycle_time, keep_zero: true)}>"
  end
end