# frozen_string_literal: true

# Shared conformance examples mirroring the behaviors Rails exercises for
# built-in adapters. Include with a `client` double in scope:
#
#   include_examples 'an ActiveJob::Temporal conforming adapter'
RSpec.shared_examples 'an ActiveJob::Temporal conforming adapter' do
  it 'sets provider_job_id on enqueue' do
    job = TestJob.new
    adapter.enqueue(job)
    expect(job.provider_job_id).to be_present
  end

  it 'round-trips queue and priority through job.serialize' do
    job = PriorityJob.new
    serialized = job.serialize
    expect(serialized['queue_name']).to eq(job.queue_name)
    expect(serialized['priority']).to eq(10)
  end

  it 'marks jobs successfully enqueued via perform_later through the adapter' do
    ActiveJob::Base.queue_adapter = adapter
    job = QueuedJob.perform_later('x')
    expect(job.provider_job_id).to be_present
  end
end
