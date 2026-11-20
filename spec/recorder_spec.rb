# frozen_string_literal: true

# Finding and stopping the recorder (without starting one).
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
end
