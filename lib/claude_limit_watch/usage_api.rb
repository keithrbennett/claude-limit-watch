# frozen_string_literal: true

require 'json'
require 'net/http'
require 'open3'
require 'time'
require 'uri'

module ClaudeLimitWatch
  # Fetches the 5-hour and 7-day usage from the (undocumented) endpoint
  # Claude Code's own usage display uses, with Claude Code's login.
  module UsageApi
    extend self

    URL = URI('https://api.anthropic.com/api/oauth/usage')

    def macos?
      RUBY_PLATFORM.include?('darwin')
    end

    def access_token
      raw =
        if macos?
          out, status = Open3.capture2('security', 'find-generic-password',
            '-s', 'Claude Code-credentials', '-w')
          status.success? ? out : nil
        else
          path = File.join(Dir.home, '.claude', '.credentials.json')
          File.exist?(path) ? File.read(path) : nil
        end
      raw && JSON.parse(raw).dig('claudeAiOauth', 'accessToken')
    rescue JSON::ParserError
      nil
    end

    # Returns { util:, resets:, util_7d:, resets_7d: } (utilization percents,
    # and reset times or nil; the 7-day ones are nil when the response has no
    # 7-day window), or an error string. A response without a 5-hour window
    # is an error.
    def fetch_usage
      token = access_token or return 'no Claude Code credentials found'
      req = Net::HTTP::Get.new(URL)
      req['Authorization'] = "Bearer #{token}"
      req['anthropic-beta'] = 'oauth-2025-04-20'
      req['Accept'] = 'application/json'
      req['User-Agent'] = 'claude-limit-watch'
      res = Net::HTTP.start(URL.host, URL.port, use_ssl: true,
        open_timeout: 10, read_timeout: 10) { |http| http.request(req) }
      if res.code == '401'
        return 'token expired (refreshes when a Claude Code session next runs)'
      end
      return 'rate-limited by the usage endpoint (HTTP 429); try a longer interval' if res.code == '429'
      return "HTTP #{res.code} from usage endpoint" unless res.is_a?(Net::HTTPSuccess)

      parse(res.body)
    rescue => e
      "#{e.class}: #{e.message}"
    end

    # The usage in a response body, as fetch_usage returns it.
    def parse(body)
      json = JSON.parse(body)
      util, resets = window(json['five_hour'])
      return 'no 5-hour window in response' unless util

      util_7d, resets_7d = window(json['seven_day'])
      { util: util, resets: resets, util_7d: util_7d, resets_7d: resets_7d }
    end

    # [utilization, reset time or nil] for a window in the response, or nil.
    private def window(json)
      return unless json.is_a?(Hash) && json['utilization'].is_a?(Numeric)

      [json['utilization'].to_f, json['resets_at'] && Time.parse(json['resets_at'])]
    end
  end
end
