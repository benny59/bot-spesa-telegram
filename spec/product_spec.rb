require_relative 'spec_helper'

describe Product do
  it 'responds to save_for_item (interface)' do
    expect(Product).to respond_to(:save_for_item)
  end
end