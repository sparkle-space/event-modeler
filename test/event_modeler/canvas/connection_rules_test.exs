defmodule EventModeler.Canvas.ConnectionRulesTest do
  use ExUnit.Case, async: true

  alias EventModeler.Canvas.ConnectionRules

  describe "valid connections" do
    test "command -> event is valid" do
      assert ConnectionRules.valid?(:command, :event)
    end

    test "command -> exception is valid" do
      assert ConnectionRules.valid?(:command, :exception)
    end

    test "event -> view is valid" do
      assert ConnectionRules.valid?(:event, :view)
    end

    test "event -> automation is valid" do
      assert ConnectionRules.valid?(:event, :automation)
    end

    test "exception -> view is valid" do
      assert ConnectionRules.valid?(:exception, :view)
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

  describe "invalid connections - views cannot have outgoing connections" do
    test "view -> command is rejected" do
      refute ConnectionRules.valid?(:view, :command)
    end

    test "view -> event is rejected" do
      refute ConnectionRules.valid?(:view, :event)
    end

    test "view -> view is rejected" do
      refute ConnectionRules.valid?(:view, :view)
    end

    test "view -> trigger is rejected" do
      refute ConnectionRules.valid?(:view, :trigger)
    end

    test "view -> automation is rejected" do
      refute ConnectionRules.valid?(:view, :automation)
    end

    test "view -> exception is rejected" do
      refute ConnectionRules.valid?(:view, :exception)
    end
  end

  describe "invalid connections - nothing can target triggers" do
    test "command -> trigger is rejected" do
      refute ConnectionRules.valid?(:command, :trigger)
    end

    test "event -> trigger is rejected" do
      refute ConnectionRules.valid?(:event, :trigger)
    end

    test "automation -> trigger is rejected" do
      refute ConnectionRules.valid?(:automation, :trigger)
    end

    test "exception -> trigger is rejected" do
      refute ConnectionRules.valid?(:exception, :trigger)
    end

    test "trigger -> trigger is rejected" do
      refute ConnectionRules.valid?(:trigger, :trigger)
    end
  end

  describe "invalid connections - methodology violations" do
    test "event -> command is rejected (should use automation)" do
      refute ConnectionRules.valid?(:event, :command)
    end

    test "command -> view is rejected (should go through event)" do
      refute ConnectionRules.valid?(:command, :view)
    end

    test "command -> command is rejected" do
      refute ConnectionRules.valid?(:command, :command)
    end

    test "event -> event is rejected" do
      refute ConnectionRules.valid?(:event, :event)
    end

    test "trigger -> event is rejected" do
      refute ConnectionRules.valid?(:trigger, :event)
    end

    test "trigger -> automation is rejected" do
      refute ConnectionRules.valid?(:trigger, :automation)
    end

    test "trigger -> exception is rejected" do
      refute ConnectionRules.valid?(:trigger, :exception)
    end

    test "command -> automation is rejected" do
      refute ConnectionRules.valid?(:command, :automation)
    end

    test "automation -> event is rejected" do
      refute ConnectionRules.valid?(:automation, :event)
    end

    test "automation -> view is rejected" do
      refute ConnectionRules.valid?(:automation, :view)
    end

    test "automation -> automation is rejected" do
      refute ConnectionRules.valid?(:automation, :automation)
    end

    test "automation -> exception is rejected" do
      refute ConnectionRules.valid?(:automation, :exception)
    end

    test "exception -> command is rejected" do
      refute ConnectionRules.valid?(:exception, :command)
    end

    test "exception -> event is rejected" do
      refute ConnectionRules.valid?(:exception, :event)
    end

    test "exception -> automation is rejected" do
      refute ConnectionRules.valid?(:exception, :automation)
    end

    test "exception -> exception is rejected" do
      refute ConnectionRules.valid?(:exception, :exception)
    end

    test "event -> exception is rejected" do
      refute ConnectionRules.valid?(:event, :exception)
    end
  end

  describe "rejection_reason/2" do
    test "returns nil for valid connections" do
      assert ConnectionRules.rejection_reason(:command, :event) == nil
    end

    test "views outgoing explains they are read-only" do
      reason = ConnectionRules.rejection_reason(:view, :command)
      assert reason =~ "read-only"
    end

    test "targeting trigger explains they are entry points" do
      reason = ConnectionRules.rejection_reason(:event, :trigger)
      assert reason =~ "entry point"
    end

    test "event -> command suggests using automation" do
      reason = ConnectionRules.rejection_reason(:event, :command)
      assert reason =~ "Automation"
    end

    test "command -> view explains event step is required" do
      reason = ConnectionRules.rejection_reason(:command, :view)
      assert reason =~ "Event"
    end

    test "trigger -> event explains command step is required" do
      reason = ConnectionRules.rejection_reason(:trigger, :event)
      assert reason =~ "Command"
    end

    test "trigger -> automation explains triggers are user interactions" do
      reason = ConnectionRules.rejection_reason(:trigger, :automation)
      assert reason =~ "user interaction"
    end

    test "trigger -> exception explains command step is required" do
      reason = ConnectionRules.rejection_reason(:trigger, :exception)
      assert reason =~ "Command"
    end
  end

  describe "valid_targets/1" do
    test "command can target event and exception" do
      targets = ConnectionRules.valid_targets(:command)
      assert :event in targets
      assert :exception in targets
      assert length(targets) == 2
    end

    test "event can target view and automation" do
      targets = ConnectionRules.valid_targets(:event)
      assert :view in targets
      assert :automation in targets
      assert length(targets) == 2
    end

    test "trigger can target command and view" do
      targets = ConnectionRules.valid_targets(:trigger)
      assert :command in targets
      assert :view in targets
      assert length(targets) == 2
    end

    test "automation can only target command" do
      assert ConnectionRules.valid_targets(:automation) == [:command]
    end

    test "exception can only target view" do
      assert ConnectionRules.valid_targets(:exception) == [:view]
    end

    test "view has no valid targets" do
      assert ConnectionRules.valid_targets(:view) == []
    end
  end

  describe "valid_sources/1" do
    test "command can be sourced from automation and trigger" do
      sources = ConnectionRules.valid_sources(:command)
      assert :automation in sources
      assert :trigger in sources
      assert length(sources) == 2
    end

    test "event can only be sourced from command" do
      assert ConnectionRules.valid_sources(:event) == [:command]
    end

    test "view can be sourced from event, exception, and trigger" do
      sources = ConnectionRules.valid_sources(:view)
      assert :event in sources
      assert :exception in sources
      assert :trigger in sources
      assert length(sources) == 3
    end

    test "automation can only be sourced from event" do
      assert ConnectionRules.valid_sources(:automation) == [:event]
    end

    test "exception can only be sourced from command" do
      assert ConnectionRules.valid_sources(:exception) == [:command]
    end

    test "trigger has no valid sources" do
      assert ConnectionRules.valid_sources(:trigger) == []
    end
  end

  describe "all_valid/0" do
    test "returns all 8 valid connection pairs" do
      valid = ConnectionRules.all_valid()
      assert length(valid) == 8
      assert {:command, :event} in valid
      assert {:command, :exception} in valid
      assert {:event, :view} in valid
      assert {:event, :automation} in valid
      assert {:exception, :view} in valid
      assert {:automation, :command} in valid
      assert {:trigger, :command} in valid
      assert {:trigger, :view} in valid
    end
  end
end
