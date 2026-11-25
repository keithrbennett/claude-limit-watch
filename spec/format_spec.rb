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
