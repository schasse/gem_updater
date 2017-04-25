require 'spec_helper'

RSpec.describe GemUpdater do
  it 'pushes a new branch  and creates a pr for the repository' do
    expect(Git).to receive(:push).twice
    expect(Git).to receive(:pull_request)
    update_gems
  end
end
