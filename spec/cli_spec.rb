# frozen_string_literal: true

# The command line.
RSpec.describe ClaudeLimitWatch::CLI, '.main' do
  let(:m) { described_class }

  ['--help', '-h', 'view --help', 'record -h', '--bogus --help'].each do |args|
    it "prints the help to stdout for: #{args}" do
      expect { m.main(args.split) }.to output(/\AUsage:.*#{Regexp.escape(ClaudeLimitWatch::VERSION_LINE)}/m).to_stdout
    end
  end

  it 'lists the view options in the help' do
    expect { m.main(['--help']) }
      .to output(/--lines.*--once.*--no-record: don't start the recorder/m).to_stdout
  end

  it 'lists --utc in the help' do
    expect { m.main(['--help']) }.to output(/record .*--utc.*--utc: +show times in UTC/m).to_stdout
  end

  it 'shows times in UTC with --utc, and in local time without it' do
    allow(ClaudeLimitWatch::Panel).to receive(:run_once)
    m.main(%w[--once --utc])
    expect(ClaudeLimitWatch::Format.utc).to be(true)
    m.main(%w[--once])
    expect(ClaudeLimitWatch::Format.utc).to be(false)
  end

  describe '--file' do
    let(:history) { ClaudeLimitWatch::History }

    it 'uses the history file it names, for any command' do
      expect(history).to receive(:file=).with('/x/h.jsonl')
      expect(ClaudeLimitWatch::Recorder).to receive(:stop)
      m.main(%w[stop --file /x/h.jsonl])
    end

    it 'takes --file=PATH too, before the command' do
      expect(history).to receive(:file=).with('/x/h.jsonl')
      expect(ClaudeLimitWatch::Recorder).to receive(:run).with(5.0)
      m.main(%w[--file=/x/h.jsonl record])
    end

    # The history file --once would show, with the real History.file, as at
    # startup (nothing has read it yet). xdg: XDG_STATE_HOME, for the default
    # file (otherwise the spec history file).
    def file_used(args, xdg: nil)
      unless xdg.nil?
        allow(ENV).to receive(:[]).and_call_original
        allow(ENV).to receive(:[]).with('XDG_STATE_HOME').and_return(xdg)
        allow(history).to receive(:default_file).and_call_original
      end
      used = nil
      allow(ClaudeLimitWatch::Panel).to receive(:run_once) { used = history.file }
      history.file = nil
      ClaudeLimitWatch::CLI.main(args)
      used
    ensure
      history.file = SPEC_HISTORY_FILE
    end

    it 'makes a relative path absolute, so it means the same file from any directory' do
      expect(file_used(%w[--once --file h.jsonl])).to eq(File.join(Dir.pwd, 'h.jsonl'))
    end

    it 'expands ~, which the shell leaves alone after =' do
      expect(file_used(%w[--once --file=~/h.jsonl])).to eq(File.join(Dir.home, 'h.jsonl'))
    end

    it 'takes a path starting with - after =' do
      expect(file_used(%w[--once --file=-x])).to eq(File.join(Dir.pwd, '-x'))
    end

    it "says so, without a backtrace, for a path it can't expand" do
      expect do
        expect { file_used(%w[--once --file=~nosuchuser/h.jsonl]) }
          .to raise_error(SystemExit) { |e| expect(e.status).to eq(1) }
      end.to output("claude-limit-watch: can't use --file ~nosuchuser/h.jsonl: " \
                    "user nosuchuser doesn't exist\n").to_stderr
    end

    it "says so for an XDG_STATE_HOME it can't expand, before any command" do
      expect(ClaudeLimitWatch::Panel).not_to receive(:run_once)
      expect do
        expect { file_used(%w[--once], xdg: '~nosuchuser/state') }
          .to raise_error(SystemExit) { |e| expect(e.status).to eq(1) }
      end.to output("claude-limit-watch: can't use the default history file " \
                    "(check HOME and XDG_STATE_HOME): user nosuchuser doesn't exist\n").to_stderr
    end

    it "says so for a HOME it can't expand, with XDG_STATE_HOME empty" do
      allow(Dir).to receive(:home).and_return('~nosuchuser')
      expect do
        expect { file_used(%w[--once], xdg: '') }.to raise_error(SystemExit) { |e| expect(e.status).to eq(1) }
      end.to output(/can't use the default history file \(check HOME and XDG_STATE_HOME\): .*nosuchuser/)
        .to_stderr
    end

    it 'shows the usage, not a --file error, for a missing path with XDG_STATE_HOME unexpandable' do
      file = Regexp.escape('~nosuchuser/state/claude-limit-watch/history.jsonl')
      expect do
        expect { file_used(%w[--once --file], xdg: '~nosuchuser/state') }
          .to raise_error(SystemExit) { |e| expect(e.status).to eq(1) }
      end.to output(/\AUsage:.*append\s+each reading to #{file}\./m).to_stderr
    end

    ['--help', '--version'].each do |arg|
      it "still takes #{arg} with XDG_STATE_HOME unexpandable" do
        expect { file_used([arg], xdg: '~nosuchuser/state') }
          .to output(/\A(Usage:|claude-limit-watch \d)/).to_stdout
      end
    end

    ['--file', '--file=', '--file --once', '--file a --file b', '--file=a --file=b --help'].each do |args|
      it "rejects a missing or repeated path: #{args}" do
        expect(history).not_to receive(:file=)
        expect do
          expect { m.main(args.split) }.to raise_error(SystemExit) { |e| expect(e.status).to eq(1) }
        end.to output(/\AUsage:/).to_stderr
      end
    end

    it 'is in the help' do
      expect { m.main(['--help']) }
        .to output(/Every command also takes:\n  --file PATH: the history file/).to_stdout
    end
  end

  it 'rejects --utc for stop, which shows no times' do
    expect(ClaudeLimitWatch::Recorder).not_to receive(:stop)
    expect do
      expect { m.main(%w[stop --utc]) }.to raise_error(SystemExit) { |e| expect(e.status).to eq(1) }
    end.to output(/\AUsage:/).to_stderr
  end

  it 'takes --utc before or after the interval, for the recorder too' do
    expect(ClaudeLimitWatch::Recorder).to receive(:run).with(2.0).twice
    [%w[record --utc 2], %w[record 2 --utc]].each do |args|
      ClaudeLimitWatch::Format.utc = nil
      m.main(args)
      expect(ClaudeLimitWatch::Format.utc).to be(true)
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

  describe 'the viewer' do
    let(:recorder) { ClaudeLimitWatch::Recorder }

    before do
      allow($stdout).to receive(:tty?).and_return(true)
      allow(m).to receive(:trap) # not the spec process's Ctrl-C
    end

    it 'exits quietly on Ctrl-C from before it starts the recorder' do
      expect(m).to receive(:trap).with('INT').ordered
      expect(recorder).to receive(:ensure_running).ordered
      allow(ClaudeLimitWatch::Panel).to receive(:run)
      m.main([])
    end

    it 'exits with status 0 on that Ctrl-C' do
      handler = nil
      allow(m).to receive(:trap).with('INT') { |*, &block| handler = block }
      allow(recorder).to receive(:ensure_running)
      allow(ClaudeLimitWatch::Panel).to receive(:run)
      m.main([])
      expect do
        expect { handler.call }.to raise_error(SystemExit) { |e| expect(e.status).to eq(0) }
      end.to output("\n").to_stdout
    end

    it 'starts the recorder, then shows the panel' do
      expect(recorder).to receive(:ensure_running).ordered.and_return([4321, 'started'])
      expect(ClaudeLimitWatch::Panel).to receive(:run).ordered.with(30.0, record: true)
      m.main([])
    end

    it "doesn't start the recorder with --no-record" do
      expect(recorder).not_to receive(:ensure_running)
      expect(ClaudeLimitWatch::Panel).to receive(:run).with(45.0, record: false)
      m.main(%w[view 45 --no-record])
    end

    it 'shows lines with what the recorder is doing' do
      allow(recorder).to receive(:ensure_running).and_return([4321, 'started'])
      expect(ClaudeLimitWatch::LinesView).to receive(:run).with(30.0, 4321, 'started', record: true)
      m.main(['--lines'])
    end

    it 'shows lines with whether a recorder is running, with --no-record' do
      expect(recorder).not_to receive(:ensure_running)
      allow(recorder).to receive(:status).and_return([nil, 'not running'])
      expect(ClaudeLimitWatch::LinesView).to receive(:run).with(30.0, nil, 'not running', record: false)
      m.main(%w[--no-record --lines])
    end

    it 'accepts --no-record with --once, which never starts the recorder' do
      expect(recorder).not_to receive(:ensure_running)
      expect(ClaudeLimitWatch::Panel).to receive(:run_once).with(30.0)
      m.main(%w[--once --no-record])
    end
  end

  ['bogus', 'record 0.1', 'record 5 6', 'stop now', '30 45',
    'record --no-record', 'stop --no-record'].each do |args|
    it "rejects: #{args}" do
      expect do
        expect { m.main(args.split) }.to raise_error(SystemExit) { |e| expect(e.status).to eq(1) }
      end.to output(/\AUsage:/).to_stderr
    end
  end
end
