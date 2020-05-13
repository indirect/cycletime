require "cycletime/version"
require "pull_request"

require "yaml"
require "gqli"
require "chronic_duration"

ACCESS_TOKEN = ENV.fetch("GITHUB_ACCESS_TOKEN") do
  config_path = File.expand_path("~/.config/hub")
  config = YAML.load_file(config_path)
  token = config.dig("github.com", 0, "oauth_token") || raise("no access token!")
end

module Cycletime
  class Error < StandardError; end

  def self.fetch_pr_data(owner, repo, back_to: Date.today - 365)
    pr_data = []
    client = GQLi::Github.create(ACCESS_TOKEN, validate_query: false)

    prFields = GQLi::DSL.fragment('prFields', 'pullRequest') {
      pageInfo {
        startCursor
        hasPreviousPage
      }
      nodes {
        id
        number
        closedAt
        commits(first: 1) {
          edges {
            node {
              commit {
                authoredDate
              }
            }
          }
        }
      }
    }

    query = GQLi::DSL.query {
      repository(owner: owner, name: repo) {
        pullRequests(last: 100, states: __enum("MERGED")) {
          ___ prFields
        }
      }
    }
    response = client.execute(query)
    pr_data.unshift *response.data.dig(:repository, :pullRequests, :nodes).map(&:to_hash)
    pageInfo = response.data.dig(:repository, :pullRequests, :pageInfo)

    while pageInfo.fetch(:hasPreviousPage) && Time.parse(pr_data.first.fetch("closedAt")).to_date > back_to
      query = GQLi::DSL.query {
        repository(owner: owner, name: repo) {
          pullRequests(before: pageInfo.fetch(:startCursor), last: 100, states: __enum("MERGED")) {
            ___ prFields
          }
        }
      }
      response = client.execute(query)
      pr_data.unshift *response.data.dig(:repository, :pullRequests, :nodes).map(&:to_hash)
      pageInfo = response.data.dig(:repository, :pullRequests, :pageInfo)
    end

    pr_data
  end

  def self.run(slug)
    owner, repo = slug.split("/")

    data_file = "tmp/pr_data-#{owner}-#{repo}.yml"
    if File.exist?(data_file)
      pr_data = YAML.load_file(data_file)
    else
      pr_data = fetch_pr_data(owner, repo)
      File.write(data_file, YAML.dump(pr_data))
    end

    prs = pr_data.map{|d| PullRequest.new(d) }

    months = prs.group_by{|pr| pr.finished_at.strftime("%Y-%m") }
    keys = months.keys.sort.last(12)

    data = keys.map do |k|
      month = months[k]
      index = month.size/2
      median = month[index]
      max = month.sort_by(&:cycle_time).last
      month_name = [Date::MONTHNAMES[median.finished_at.month], median.finished_at.year].join(" ")
      [month_name, month.size, median.cycle_time, max.cycle_time]
    end

    puts "Cycle time for #{owner}/#{repo}"
    puts

    printf "% 15s   % 3s   % 10s   %s\n", "Month", "PRs", "Median", "Max"
    data.each do |d|
      month_name, count, median, max = d
      printf "% 15s | % 3d | % 4d hours | %s\n", month_name, count, median/60/60, ChronicDuration.output(max, format: :short)
    end
  end
end
