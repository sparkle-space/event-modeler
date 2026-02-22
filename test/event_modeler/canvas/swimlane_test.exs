defmodule EventModeler.Canvas.SwimlaneTest do
  use ExUnit.Case, async: true

  alias EventModeler.Canvas.Swimlane

  describe "type_for_element/1" do
    test "wireframe and automation map to trigger" do
      assert Swimlane.type_for_element(:wireframe) == :trigger
      assert Swimlane.type_for_element(:automation) == :trigger
    end

    test "command and view map to command_view" do
      assert Swimlane.type_for_element(:command) == :command_view
      assert Swimlane.type_for_element(:view) == :command_view
    end

    test "event and exception map to event" do
      assert Swimlane.type_for_element(:event) == :event
      assert Swimlane.type_for_element(:exception) == :event
    end
  end

  describe "allowed_element_types/1" do
    test "trigger allows wireframe and automation" do
      assert Swimlane.allowed_element_types(:trigger) == [:wireframe, :automation]
    end

    test "command_view allows command and view" do
      assert Swimlane.allowed_element_types(:command_view) == [:command, :view]
    end

    test "event allows event and exception" do
      assert Swimlane.allowed_element_types(:event) == [:event, :exception]
    end
  end

  describe "allowed?/2" do
    test "wireframe is allowed in trigger lane" do
      assert Swimlane.allowed?(:wireframe, :trigger)
    end

    test "command is not allowed in trigger lane" do
      refute Swimlane.allowed?(:command, :trigger)
    end

    test "event is allowed in event lane" do
      assert Swimlane.allowed?(:event, :event)
    end

    test "event is not allowed in command_view lane" do
      refute Swimlane.allowed?(:event, :command_view)
    end
  end

  describe "sort_order/1" do
    test "trigger comes first, then command_view, then event" do
      assert Swimlane.sort_order(:trigger) < Swimlane.sort_order(:command_view)
      assert Swimlane.sort_order(:command_view) < Swimlane.sort_order(:event)
    end
  end

  describe "default_name/1" do
    test "returns default names for each type" do
      assert Swimlane.default_name(:trigger) == "Triggers"
      assert Swimlane.default_name(:command_view) == "Processing"
      assert Swimlane.default_name(:event) == "Events"
    end
  end
end
