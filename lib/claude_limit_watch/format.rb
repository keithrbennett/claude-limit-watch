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
    def clock(time, seconds: false)
      zoned(time).strftime(seconds ? '%H:%M:%S' : '%H:%M')
    end

    # The day and time, as for clock: "Thu 01:00".
    def day_clock(time)
      zoned(time).strftime('%a %H:%M')
    end

    # The date and time, as for clock: "Thu Nov 26 at 01:00".
    def date_clock(time)
      zoned(time).strftime('%a %b %-d at %H:%M')
    end

    # A short duration, rounded to the minute: "1d 03h 12m", or under a day,
    # as for dur_m: "3h 12m", "12m", "<1m".
    def dur_short(seconds)
      m = (seconds / 60.0).round
      m >= 1440 ? format('%dd %02dh %02dm', m / 1440, m / 60 % 24, m % 60) : dur_m(seconds)
    end

    # A duration in words, rounded to the minute: "1 day, 3 hours and 12
    # minutes", "5 minutes", "less than a minute".
    def dur_words(seconds)
      m = (seconds / 60.0).round
      return 'less than a minute' if m < 1

      parts = [[m / 1440, 'day'], [m / 60 % 24, 'hour'], [m % 60, 'minute']].reject { |n, _| n.zero? }
      words = parts.map { |n, unit| "#{n} #{unit}#{'s' unless n == 1}" }
      words.size > 1 ? "#{words[0...-1].join(', ')} and #{words.last}" : words.first
    end

    # A note that times are in UTC, for the text that introduces them; empty
    # for local time.
    def zone_note
      Format.utc ? ' Times are in UTC.' : ''
    end

    # Duration, rounded to the minute: "1h 12m", "58m", "<1m". On the panel,
    # that means the text (and the screen) changes only about once a minute.
    def dur_m(seconds)
      m = (seconds / 60.0).round
      return '<1m' if m < 1

      m >= 60 ? format('%dh %02dm', m / 60, m % 60) : "#{m}m"
    end

    def home_relative(path)
      path.start_with?("#{Dir.home}/") ? "~#{path[Dir.home.size..]}" : path
    end

    # The time in the zone times are shown in: local, or UTC with --utc.
    # Through UTC, since getlocal leaves a time that's already local as it is,
    # in whatever zone was local when its local fields were worked out.
    private def zoned(time)
      Format.utc ? time.getutc : time.getutc.getlocal
    end

    # Text cut to width from the left, with "..." in place of what's cut, so
    # its end (a path's file name, say) stays visible.
    def shorten_left(text, width)
      return text if text.size <= width
      return '...'[0, [width, 0].max] if width <= 3

      "...#{text[(text.size - width + 3)..]}"
    end
  end
end
