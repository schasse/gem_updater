require 'spec_helper'

RSpec.describe GemUpdater do
  it 'creates a pr for the repository' do
    expect(Git).to receive(:pull_request)
    update_gems
  end
end
