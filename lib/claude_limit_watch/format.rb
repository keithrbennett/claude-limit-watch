# frozen_string_literal: true

module ClaudeLimitWatch
  # Numbers, durations and times as text.
  module Format
    extend self

    class << self
      # Whether times are shown in UTC (--utc) rather than local time.
      attr_accessor :utc
    end

    # Minutes for display: "5", "2.5".
    def num(minutes)
      minutes == minutes.round ? minutes.round.to_s : minutes.to_s
    end

    # Duration in minutes as h:mm.
    def hm(min)
      min = [min.round, 0].max
      format('%d:%02d', min / 60, min % 60)
    end

    # A compact duration label, in minutes: "50m", "1h50m".
    def span_label(min)
      m = min.round
      m < 60 ? "#{m}m" : format('%dh%02dm', m / 60, m % 60)
    end

    # A time of day, in local time or (with --utc) UTC: "08:00", or with
    # seconds, "08:00:15".
    # Through UTC, since getlocal leaves a time that's already local as it is,
    # in whatever zone was local when its local fields were worked out.
    def clock(time, seconds: false)
      t = Format.utc ? time.getutc : time.getutc.getlocal
      t.strftime(seconds ? '%H:%M:%S' : '%H:%M')
    end

    # A note that times are in UTC, for the text that introduces them; empty
    # for local time.
    def zone_note
      Format.utc ? ' Times are in UTC.' : ''
    end

    # Duration in seconds, in unambiguous units: "1h 12m", "58m", "3m 48s", "48s".
    def dur(seconds)
      s = [seconds.round, 0].max
      if s >= 3600 then format('%dh %02dm', s / 3600, (s % 3600) / 60)
      elsif s >= 600 then "#{s / 60}m"
      elsif s >= 60 then format('%dm %02ds', s / 60, s % 60)
      else "#{s}s"
      end
    end

    # Duration to the minute, so the panel's text (and the screen) changes only
    # about once a minute: "1h 12m", "58m", "<1m".
    def dur_m(seconds)
      m = (seconds / 60.0).round
      return '<1m' if m < 1

      m >= 60 ? format('%dh %02dm', m / 60, m % 60) : "#{m}m"
    end

    def home_relative(path)
      path.start_with?("#{Dir.home}/") ? "~#{path[Dir.home.size..]}" : path
    end
  end
end
