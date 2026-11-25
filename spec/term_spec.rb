# frozen_string_literal: true

require 'io/console' # term_width loads it when first called; IO.console comes from it

# The terminal's width.
RSpec.describe ClaudeLimitWatch::Term, '.term_width' do
  let(:m) { described_class }

  it "uses the terminal's columns, or 80 when they're unknown" do
    {
      [24, 120] => 120,
      [24, 0]   => 80, # some terminals report 0
      nil       => 80, # no terminal
    }.each do |winsize, width|
      allow(IO).to receive(:console).and_return(winsize && double(winsize: winsize))
      expect(m.term_width).to eq(width), "for #{winsize.inspect}"
    end
  end

  it 'uses 80 when the size can not be read' do
    allow(IO).to receive(:console).and_raise(Errno::ENOTTY)
    expect(m.term_width).to eq(80)
  end
end
