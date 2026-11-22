# frozen_string_literal: true

require 'json'
require 'net/http'
require 'open3'
require 'time'
require 'uri'

module ClaudeLimitWatch
  # Fetches the 5-hour usage from the (undocumented) endpoint Claude Code's
  # own usage display uses, with Claude Code's login.
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

    # Returns [utilization_percent, resets_at_or_nil], or an error string.
    def fetch_five_hour
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

      window = JSON.parse(res.body)['five_hour']
      return 'no 5-hour window in response' unless window.is_a?(Hash) && window['utilization'].is_a?(Numeric)

      resets = window['resets_at'] ? Time.parse(window['resets_at']) : nil
      [window['utilization'].to_f, resets]
    rescue => e
      "#{e.class}: #{e.message}"
    end
  end
end
