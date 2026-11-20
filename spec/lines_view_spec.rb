# frozen_string_literal: true

# The --lines output.
RSpec.describe ClaudeLimitWatch::LinesView do
  m = described_class

  describe '.format_line' do
    def fields(util, rate, reset_min)
      history = (5..60).step(5).map { |min| { t: NOW - (min * 60), util: util - (min * rate) } }
      p = ClaudeLimitWatch::Projection.project(history, NOW, util, NOW + (reset_min * 60), rate_window: 30)
      ClaudeLimitWatch::LinesView.format_line(NOW, p).split('|').map(&:strip)
    end

    it 'formats an OK line' do
      expect(fields(50.0, 0.2, 100))
        .to eq(['08:00', 'OK', '3:20 of 5:00', '09:40', '50%', '12.0%/h (avg 15.0)', '0.4x', '~30% left at reset'])
    end

    it 'formats a WARN line' do
      f = fields(50.0, 0.6, 100)
      expect(f[1]).to eq('WARN')
      expect(f[7]).to eq('LIMIT at 09:23 (in 1:23), 0:17 before reset')
    end

    it 'formats a line at the limit' do
      f = fields(100.0, 0.5, 30)
      expect(f[1]).to eq('URGENT')
      expect(f[7]).to eq('AT LIMIT, resets in 0:30')
    end
  end

  describe '.header' do
    it 'names the rate window' do
      expect(m.header(45)).to include('45m Burn Rate')
    end
  end
end
