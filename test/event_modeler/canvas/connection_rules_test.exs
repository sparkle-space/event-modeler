defmodule EventModeler.Canvas.ConnectionRulesTest do
  use ExUnit.Case, async: true

  alias EventModeler.Canvas.ConnectionRules

  describe "valid connections" do
    test "command -> event is valid" do
      assert ConnectionRules.valid?(:command, :event)
    end

    test "event -> view is valid" do
      assert ConnectionRules.valid?(:event, :view)
    end

    test "event -> automation is valid" do
      assert ConnectionRules.valid?(:event, :automation)
    end

    test "automation -> command is valid" do
      assert ConnectionRules.valid?(:automation, :command)
    end

    test "trigger -> command is valid" do
      assert ConnectionRules.valid?(:trigger, :command)
    end

    test "trigger -> view is valid" do
      assert ConnectionRules.valid?(:trigger, :view)
    end
  end

  describe "invalid connections" do
    test "command -> view is rejected" do
      refute ConnectionRules.valid?(:command, :view)
    end

    test "trigger -> event is rejected" do
      refute ConnectionRules.valid?(:trigger, :event)
    end

    test "trigger -> automation is rejected" do
      refute ConnectionRules.valid?(:trigger, :automation)
    end

    test "view -> command is rejected" do
      refute ConnectionRules.valid?(:view, :command)
    end

    test "view -> event is rejected" do
      refute ConnectionRules.valid?(:view, :event)
    end

    test "event -> command is rejected" do
      refute ConnectionRules.valid?(:event, :command)
    end
  end

  test "rejection_reason returns nil for valid connections" do
    assert ConnectionRules.rejection_reason(:command, :event) == nil
  end

  test "rejection_reason returns message for invalid connections" do
    reason = ConnectionRules.rejection_reason(:command, :view)
    assert is_binary(reason)
    assert reason =~ "Command"
    assert reason =~ "View"
  end

  test "all_valid returns all valid connection pairs" do
    valid = ConnectionRules.all_valid()
    assert length(valid) == 6
    assert {:command, :event} in valid
    assert {:event, :view} in valid
  end
end
