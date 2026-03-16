defmodule EventModeler.EventModel.V2FeaturesTest do
  use ExUnit.Case, async: true

  alias EventModeler.EventModel
  alias EventModeler.EventModel.{Parser, Serializer, Element, Field, Slice}

  describe "new element type prefixes" do
    test "p: prefix maps to processor" do
      assert Element.type_from_prefix("p") == :processor
      assert Element.prefix_from_type(:processor) == "p"
    end

    test "r: prefix maps to translator" do
      assert Element.type_from_prefix("r") == :translator
      assert Element.prefix_from_type(:translator) == "r"
    end

    test "parses processor steps from emlang" do
      markdown = """
      ```yaml emlang
      slices:
        AutoReorder:
          steps:
            - p: Inventory/LowStockMonitor
            - c: ReorderFromSupplier
            - e: Inventory/ReorderPlaced
      ```
      """

      {:ok, [slice]} = EventModeler.EventModel.EmlangParser.parse(markdown)
      [processor, _cmd, _event] = slice.steps
      assert processor.type == :processor
      assert processor.label == "LowStockMonitor"
      assert processor.swimlane == "Inventory"
    end

    test "parses translator steps from emlang" do
      markdown = """
      ```yaml emlang
      slices:
        ReserveStock:
          steps:
            - r: Billing/OrderToInventory
            - c: ReserveStock
            - e: Inventory/StockReserved
      ```
      """

      {:ok, [slice]} = EventModeler.EventModel.EmlangParser.parse(markdown)
      [translator, _cmd, _event] = slice.steps
      assert translator.type == :translator
      assert translator.label == "OrderToInventory"
      assert translator.swimlane == "Billing"
    end
  end

  describe "fields parsing" do
    test "parses fields on elements" do
      markdown = """
      ```yaml emlang
      slices:
        PlaceOrder:
          steps:
            - c: PlaceOrder
              fields:
                orderId: uuid
                total: decimal
            - e: OrderPlaced
              fields:
                orderId: uuid
                placedAt: datetime
      ```
      """

      {:ok, [slice]} = EventModeler.EventModel.EmlangParser.parse(markdown)
      [cmd, event] = slice.steps

      assert length(cmd.fields) == 2
      order_field = Enum.find(cmd.fields, &(&1.name == "orderId"))
      assert order_field.type == :uuid

      total_field = Enum.find(cmd.fields, &(&1.name == "total"))
      assert total_field.type == :decimal

      assert length(event.fields) == 2
    end

    test "fields coexist with props" do
      markdown = """
      ```yaml emlang
      slices:
        Test:
          steps:
            - c: Test
              props:
                description: string
              fields:
                orderId: uuid
      ```
      """

      {:ok, [slice]} = EventModeler.EventModel.EmlangParser.parse(markdown)
      [cmd] = slice.steps
      assert cmd.props == %{"description" => "string"}
      assert length(cmd.fields) == 1
    end

    test "no fields returns empty list" do
      markdown = """
      ```yaml emlang
      slices:
        Test:
          steps:
            - c: DoThing
      ```
      """

      {:ok, [slice]} = EventModeler.EventModel.EmlangParser.parse(markdown)
      [cmd] = slice.steps
      assert cmd.fields == []
    end
  end

  describe "slice pattern and domain" do
    test "parses pattern from slice definition" do
      markdown = """
      ```yaml emlang
      slices:
        PlaceOrder:
          pattern: command
          steps:
            - c: PlaceOrder
            - e: OrderPlaced
      ```
      """

      {:ok, [slice]} = EventModeler.EventModel.EmlangParser.parse(markdown)
      assert slice.pattern == :command
    end

    test "parses domain from slice definition" do
      markdown = """
      ```yaml emlang
      slices:
        PlaceOrder:
          domain: Billing
          steps:
            - c: PlaceOrder
            - e: OrderPlaced
      ```
      """

      {:ok, [slice]} = EventModeler.EventModel.EmlangParser.parse(markdown)
      assert slice.domain == "Billing"
    end

    test "all four pattern types are recognized" do
      for {pattern_str, pattern_atom} <- [
            {"command", :command},
            {"view", :view},
            {"automation", :automation},
            {"translation", :translation}
          ] do
        markdown = """
        ```yaml emlang
        slices:
          Test:
            pattern: #{pattern_str}
            steps:
              - c: Test
        ```
        """

        {:ok, [slice]} = EventModeler.EventModel.EmlangParser.parse(markdown)
        assert slice.pattern == pattern_atom
      end
    end

    test "unknown pattern returns nil" do
      markdown = """
      ```yaml emlang
      slices:
        Test:
          pattern: unknown
          steps:
            - c: Test
      ```
      """

      {:ok, [slice]} = EventModeler.EventModel.EmlangParser.parse(markdown)
      assert slice.pattern == nil
    end
  end

  describe "frontmatter domains and format" do
    test "parses format from frontmatter" do
      markdown = """
      ---
      title: "Test"
      format: "em/2"
      ---

      # Test
      """

      {:ok, event_model} = Parser.parse(markdown)
      assert event_model.format == "em/2"
    end

    test "parses domains list from frontmatter" do
      markdown = """
      ---
      title: "Test"
      domains:
        - name: "Billing"
          description: "Payment processing"
          color: "#3B82F6"
        - name: "Inventory"
          description: "Stock management"
      ---

      # Test
      """

      {:ok, event_model} = Parser.parse(markdown)
      assert length(event_model.domains) == 2
      [billing, inventory] = event_model.domains
      assert billing.name == "Billing"
      assert billing.description == "Payment processing"
      assert billing.color == "#3B82F6"
      assert inventory.name == "Inventory"
    end

    test "v1 models have no domains or format" do
      markdown = """
      ---
      title: "Test"
      domain: "Board"
      ---

      # Test
      """

      {:ok, event_model} = Parser.parse(markdown)
      assert event_model.domain == "Board"
      assert event_model.domains == []
      assert event_model.format == nil
    end
  end

  describe "serialization of new features" do
    test "serializes format in frontmatter" do
      event_model = %EventModel{title: "Test", format: "em/2"}
      result = Serializer.serialize(event_model)
      assert result =~ "format: \"em/2\""
    end

    test "serializes domains in frontmatter" do
      event_model = %EventModel{
        title: "Test",
        domains: [
          %EventModeler.EventModel.Domain{
            name: "Billing",
            description: "Payments",
            color: "#3B82F6"
          }
        ]
      }

      result = Serializer.serialize(event_model)
      assert result =~ "domains:"
      assert result =~ "Billing"
    end

    test "serializes slice pattern and domain" do
      event_model = %EventModel{
        title: "Test",
        slices: [
          %Slice{
            name: "PlaceOrder",
            pattern: :command,
            domain: "Billing",
            steps: [
              %Element{type: :command, label: "PlaceOrder", props: %{}}
            ],
            tests: []
          }
        ]
      }

      result = Serializer.serialize(event_model)
      assert result =~ "pattern: command"
      assert result =~ "domain: Billing"
    end

    test "serializes processor and translator prefixes" do
      event_model = %EventModel{
        title: "Test",
        slices: [
          %Slice{
            name: "AutoReorder",
            steps: [
              %Element{
                type: :processor,
                label: "LowStockMonitor",
                swimlane: "Inventory",
                props: %{}
              },
              %Element{type: :command, label: "Reorder", props: %{}}
            ],
            tests: []
          },
          %Slice{
            name: "Translate",
            steps: [
              %Element{
                type: :translator,
                label: "OrderToInventory",
                swimlane: "Billing",
                props: %{}
              },
              %Element{type: :command, label: "Reserve", props: %{}}
            ],
            tests: []
          }
        ]
      }

      result = Serializer.serialize(event_model)
      assert result =~ "p: Inventory/LowStockMonitor"
      assert result =~ "r: Billing/OrderToInventory"
    end

    test "serializes fields on elements" do
      event_model = %EventModel{
        title: "Test",
        slices: [
          %Slice{
            name: "Test",
            steps: [
              %Element{
                type: :command,
                label: "PlaceOrder",
                props: %{},
                fields: [
                  %Field{name: "orderId", type: :uuid},
                  %Field{name: "total", type: :decimal}
                ]
              }
            ],
            tests: []
          }
        ]
      }

      result = Serializer.serialize(event_model)
      assert result =~ "fields:"
      assert result =~ "orderId: uuid"
      assert result =~ "total: decimal"
    end
  end

  describe "multi-domain round-trip" do
    test "round-trip parse -> serialize -> parse preserves v2 features" do
      source = File.read!("priv/event_models/order-fulfillment.md")
      {:ok, em1} = Parser.parse(source)

      assert em1.format == "em/2"
      assert length(em1.domains) == 3

      serialized = Serializer.serialize(em1)
      {:ok, em2} = Parser.parse(serialized)

      # Structural equivalence
      assert em2.title == em1.title
      assert em2.format == em1.format
      assert length(em2.domains) == length(em1.domains)
      assert length(em2.slices) == length(em1.slices)

      # Domain names preserved
      domain_names1 = Enum.map(em1.domains, & &1.name)
      domain_names2 = Enum.map(em2.domains, & &1.name)
      assert domain_names2 == domain_names1

      # Slice patterns preserved
      for {s1, s2} <- Enum.zip(em1.slices, em2.slices) do
        assert s2.name == s1.name
        assert s2.pattern == s1.pattern
        assert s2.domain == s1.domain
        assert length(s2.steps) == length(s1.steps)
      end
    end

    test "v1 event model still parses correctly" do
      source = File.read!("priv/event_models/board-management.md")
      {:ok, em} = Parser.parse(source)

      assert em.format == nil
      assert em.domains == []
      assert em.domain == "Board"
      assert length(em.slices) == 3
    end

    test "v1 round-trip still works" do
      source = File.read!("priv/event_models/board-management.md")
      {:ok, em1} = Parser.parse(source)

      serialized = Serializer.serialize(em1)
      {:ok, em2} = Parser.parse(serialized)

      assert em2.title == em1.title
      assert em2.domain == em1.domain
      assert length(em2.slices) == length(em1.slices)
    end
  end
end
