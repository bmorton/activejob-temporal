# frozen_string_literal: true

require 'spec_helper'

RSpec.describe ActiveJob::Temporal::ExecutionActivity do
  it 'is registered under the stable public activity name' do
    expect(described_class._activity_definition_details[:activity_name]).to eq('ActiveJobExecution')
  end

  it 'delegates execution to ActiveJob::Base.execute with the payload unchanged' do
    payload = { 'job_class' => 'SomeJob', 'arguments' => [1] }
    allow(ActiveJob::Base).to receive(:execute)

    described_class.new.execute(payload)

    expect(ActiveJob::Base).to have_received(:execute).with(payload)
  end
end
