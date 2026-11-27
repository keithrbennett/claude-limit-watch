# frozen_string_literal: true

# Times and durations as text.
RSpec.describe ClaudeLimitWatch::Format do
  let(:m) { described_class }

  describe '.clock' do
    it 'shows local time, by default' do
      in_zone('Asia/Singapore') { expect(m.clock(NOW)).to eq('16:00') }
    end

    it 'converts a time worked out while another zone was local' do
      t = Time.at(NOW.to_i)
      t.strftime('%H:%M') # its local fields are now worked out, in UTC
      in_zone('Asia/Singapore') { expect(m.clock(t)).to eq('16:00') }
    end

    it 'shows UTC with --utc' do
      m.utc = true
      in_zone('Asia/Singapore') { expect(m.clock(NOW)).to eq('08:00') }
    end

    it 'shows seconds when asked' do
      expect(m.clock(NOW + 15, seconds: true)).to eq('08:00:15')
    end

    it 'shows a time from the history file in this zone, not the one it was recorded in' do
      recorded = Time.parse('2027-01-15T16:00:00+08:00')
      expect(m.clock(recorded)).to eq('08:00') # the specs' local time is UTC
      m.utc = true
      in_zone('America/New_York') { expect(m.clock(recorded)).to eq('08:00') }
    end

    it "doesn't change the time it's given" do
      t = Time.parse('2027-01-15T16:00:00+08:00')
      m.clock(t)
      expect(t.utc_offset).to eq(8 * 3600)
    end
  end

  describe '.zone_note' do
    it 'says times are in UTC only with --utc' do
      expect(m.zone_note).to eq('')
      m.utc = true
      expect(m.zone_note).to eq(' Times are in UTC.')
    end
  end

  describe '.day_clock and .date_clock' do
    it 'show the day (and date) in local time, or UTC with --utc' do
      in_zone('Asia/Singapore') do
        expect([m.day_clock(NOW), m.date_clock(NOW)]).to eq(['Fri 16:00', 'Fri Jan 15 at 16:00'])
        m.utc = true
        expect([m.day_clock(NOW + (17 * 3600)), m.date_clock(NOW + (17 * 3600))])
          .to eq(['Sat 01:00', 'Sat Jan 16 at 01:00'])
      end
    end
  end

  describe '.pct' do
    it 'rounds to a whole percentage, right-aligned to 3 digits' do
      expect([0.0, 8.4, 59.5, 100.0].map { |u| m.pct(u) }).to eq(['  0%', '  8%', ' 60%', '100%'])
    end
  end

  describe '.dur_short' do
    it 'shows days, hours and minutes, or under a day as dur_m does' do
      { 29 => '<1m', 720 => '12m', 3600 + 300 => '1h 05m', 86_400 + (3 * 3600) + 720 => '1d 03h 12m',
        (7 * 86_400) - 60 => '6d 23h 59m' }.each do |seconds, text|
        expect(m.dur_short(seconds)).to eq(text), "for #{seconds}s"
      end
    end
  end

  describe '.dur_words' do
    it 'spells out days, hours and minutes, leaving out zeros' do
      {
        0                         => 'less than a minute',
        29                        => 'less than a minute',
        60                        => '1 minute',
        (5 * 60) + 29             => '5 minutes',
        3600                      => '1 hour',
        (2 * 3600) + 60           => '2 hours and 1 minute',
        86_400                    => '1 day',
        86_400 + (3 * 3600) + 720 => '1 day, 3 hours and 12 minutes',
        (2 * 86_400) + 300        => '2 days and 5 minutes',
      }.each do |seconds, words|
        expect(m.dur_words(seconds)).to eq(words), "for #{seconds}s"
      end
    end
  end

  describe '.shorten_left' do
    it 'cuts text from the left, with "..." in place of what is cut' do
      {
        ['~/a/b/history.jsonl', 30] => '~/a/b/history.jsonl', # fits
        ['~/a/b/history.jsonl', 19] => '~/a/b/history.jsonl', # just fits
        ['~/a/b/history.jsonl', 18] => '...b/history.jsonl',
        ['~/a/b/history.jsonl', 4]  => '...l',
        ['~/a/b/history.jsonl', 3]  => '...',
        ['~/a/b/history.jsonl', 2]  => '..',
        ['~/a/b/history.jsonl', 0]  => '',
      }.each do |(text, width), expected|
        expect(m.shorten_left(text, width)).to eq(expected), "at width #{width}"
      end
    end
  end
end
