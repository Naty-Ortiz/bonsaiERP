require 'spec_helper'

describe TransactionDetail do
  it { should belong_to(:item) }

  it{ should have_valid(:quantity).when(0.1, 1)}
  it{ should_not have_valid(:quantity).when(0)}
end
