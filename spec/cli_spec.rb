# frozen_string_literal: true

# The command line.
RSpec.describe ClaudeLimitWatch::CLI, '.main' do
  m = described_class

  ['--help', '-h', 'view --help', 'record -h', '--bogus --help'].each do |args|
    it "prints the help to stdout for: #{args}" do
      expect { m.main(args.split) }.to output(/\AUsage:.*#{Regexp.escape(ClaudeLimitWatch::VERSION_LINE)}/m).to_stdout
    end
  end

  ['--version', '-v', 'stop -v'].each do |args|
    it "prints the version for: #{args}" do
      expect { m.main(args.split) }.to output("claude-limit-watch #{ClaudeLimitWatch::VERSION}\n").to_stdout
    end
  end

  it 'prints the panel once with --once, without starting the recorder' do
    FileUtils.rm_f(ClaudeLimitWatch::History.file)
    allow(ClaudeLimitWatch::Recorder).to receive(:pid).and_return(nil)
    expect(ClaudeLimitWatch::Recorder).not_to receive(:ensure_running)
    expect { m.main(['--once']) }.to output(/C L A U D E.*No readings yet/m).to_stdout
  end

  ['bogus', 'record 0.1', 'record 5 6', 'stop now', '30 45'].each do |args|
    it "rejects: #{args}" do
      expect do
        expect { m.main(args.split) }.to raise_error(SystemExit) { |e| expect(e.status).to eq(1) }
      end.to output(/\AUsage:/).to_stderr
    end
  end
end
