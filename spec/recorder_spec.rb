# frozen_string_literal: true

# Finding, starting and stopping the recorder. Process.spawn and Process.kill
# are stubbed: no real recorder is started or signalled.
RSpec.describe ClaudeLimitWatch::Recorder do
  m = described_class

  before { FileUtils.rm_f(ClaudeLimitWatch::History.lock_file) }

  it 'finds no recorder without a lock file' do
    expect(m.pid).to be_nil
  end

  it 'finds no recorder when nothing holds the lock' do
    File.write(ClaudeLimitWatch::History.lock_file, '99999')
    expect(m.pid).to be_nil
  end

  it 'finds the recorder holding the lock' do
    File.open(ClaudeLimitWatch::History.lock_file, File::RDWR | File::CREAT) do |lock|
      lock.write('4321')
      lock.flush
      # flock locks are per open file, so a second open (as pid does) sees it.
      lock.flock(File::LOCK_EX)
      expect(m.pid).to eq(4321)
    end
  end

  it 'says so when asked to stop with no recorder running' do
    expect { m.stop }.to output("No recorder is running.\n").to_stdout
  end

  it 'stops the running recorder' do
    allow(m).to receive(:pid).and_return(4321, 4321, nil)
    allow(m).to receive(:sleep)
    expect(Process).to receive(:kill).with('TERM', 4321)
    expect { m.stop }.to output("Stopped the recorder (pid 4321).\n").to_stdout
  end

  it 'starts the recorder in the background, on this history file' do
    history = ClaudeLimitWatch::History
    expect(Process).to receive(:spawn)
      .with({ 'CLAUDE_LIMIT_WATCH_FILE' => history.file }, 'nohup', RbConfig.ruby,
            ClaudeLimitWatch::EXECUTABLE, 'record',
            in: File::NULL, out: [history.log_file, 'a'], err: [:child, :out], pgroup: true)
      .and_return(999)
    expect(Process).to receive(:detach).with(999)
    allow(m).to receive(:sleep)
    allow(m).to receive(:pid).and_return(nil, 999)
    expect(m.start).to eq(999)
  end

  it "reports a recorder that doesn't come up" do
    allow(Process).to receive_messages(spawn: 999, detach: nil)
    allow(m).to receive(:sleep)
    allow(m).to receive(:pid).and_return(nil)
    expect(m.ensure_running)
      .to eq([nil, "Couldn't start the recorder; see #{ClaudeLimitWatch::History.log_file}"])
  end
end
