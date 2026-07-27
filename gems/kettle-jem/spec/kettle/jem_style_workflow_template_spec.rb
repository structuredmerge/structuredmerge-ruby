# frozen_string_literal: true

RSpec.describe Kettle::Jem do
  it "loads the RBS environment instead of only parsing signatures" do
    workflow = File.read(File.join(__dir__, "../../lib/kettle/jem/templates/.github/workflows/style.yml.example"))

    expect(workflow).to include("Validate RBS Environment")
    expect(workflow).to include("RBS::Environment.from_loader(loader).resolve_type_names")
    expect(workflow).not_to include("rbs validate")
  end
end
