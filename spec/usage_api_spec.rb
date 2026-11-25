# frozen_string_literal: true

# Reading the usage endpoint's response. Only parse is called here: fetch_usage
# would send a real request.
RSpec.describe ClaudeLimitWatch::UsageApi, '.parse' do
  let(:m) { described_class }

  def window(util, resets)
    { 'utilization' => util, 'resets_at' => resets, 'limit_dollars' => nil, 'locked_reason' => nil }
  end

  # The response's shape, trimmed: other keys are ignored.
  def body(five_hour: window(46.0, '2026-11-25T18:30:00.327206+00:00'),
    seven_day: window(85.0, '2026-11-26T17:00:00.327227+00:00'))
    JSON.generate('five_hour' => five_hour, 'seven_day' => seven_day, 'seven_day_opus' => nil,
      'extra_usage' => { 'is_enabled' => false, 'utilization' => 0.0 })
  end

  it 'reads the 5-hour and 7-day windows' do
    expect(m.parse(body)).to eq(util: 46.0, resets: Time.utc(2026, 11, 25, 18, 30, 0.327206r),
      util_7d: 85.0, resets_7d: Time.utc(2026, 11, 26, 17, 0, 0.327227r))
  end

  it 'reads a window with no reset time (none active)' do
    expect(m.parse(body(five_hour: window(0.0, nil)))).to include(util: 0.0, resets: nil)
  end

  it 'leaves out the 7-day window when the response has none' do
    [nil, {}, window(nil, nil)].each do |seven_day|
      expect(m.parse(body(seven_day: seven_day))).to include(util_7d: nil, resets_7d: nil)
    end
  end

  it 'returns an error without a 5-hour window' do
    [nil, {}, window('46', nil)].each do |five_hour|
      expect(m.parse(body(five_hour: five_hour))).to eq('no 5-hour window in response')
    end
  end
end
