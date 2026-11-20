# frozen_string_literal: true

module ClaudeLimitWatch
  # Colors, and the terminal's size.
  module Term
    extend self

    # 256-color codes: terminal themes often remap the 16 basic colors (yellow
    # showing as orange, say), but generally leave these alone.
    COLORS = { ok: '38;5;114', projected: '38;5;220', urgent: '38;5;196' }.freeze # green, yellow, red
    WARN = COLORS[:projected] # warnings: yellow, as for a rate that runs out
    # Secondary text. The one 16-color code, on purpose: themes remap bright
    # black too, but to their own muted text color, which suits this text.
    GRAY = 90
    ANSI_RE = /\e\[[0-9;?]*[A-Za-z]/.freeze

    # Text in the given SGR codes, or plain when colors are off or output
    # isn't a terminal.
    def paint(text, *codes)
      return text if ENV['NO_COLOR'].to_s != '' || codes.empty? || !$stdout.tty?

      "\e[#{codes.join(';')}m#{text}\e[0m"
    end

    # Truncate to a visible width, leaving ANSI escapes intact.
    def fit(str, width)
      out = +''
      visible = 0
      str.scan(/#{ANSI_RE}|./mo) do |tok|
        if tok.start_with?("\e")
          out << tok
        elsif visible < width
          out << tok
          visible += 1
        end
      end
      out
    end

    # The terminal's [rows, columns] (either may be 0 if unknown), or nil.
    def term_size
      require 'io/console'
      IO.console&.winsize
    rescue StandardError
      nil
    end

    def term_width
      cols = term_size&.last.to_i
      cols.positive? ? cols : 80
    end

    # Terminal rows, or nil if unknown.
    def term_height
      rows = term_size&.first.to_i
      rows.positive? ? rows : nil
    end
  end
end
