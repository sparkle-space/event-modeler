---
title: "Order Fulfillment"
status: "draft"
format: "em/2"
version: 1
created: "2026-03-16"
updated: "2026-03-16"
tags:
  - "event-modeling"
  - "multi-domain"
domains:
  - name: "Billing"
    description: "Payment processing and invoicing"
    color: "#3B82F6"
  - name: "Inventory"
    description: "Stock management and allocation"
    color: "#22C55E"
  - name: "Shipping"
    description: "Order delivery and logistics"
    color: "#F97316"
---

# Order Fulfillment

## Overview

Multi-domain order fulfillment system demonstrating the four architectural patterns: Command, View, Automation (Processor), and Translation (Translator). Covers billing, inventory, and shipping as separate bounded contexts.

## Key Ideas

- **Command Pattern** -- User triggers a command that produces events (PlaceOrder)
- **View Pattern** -- Events project into read models for display (OrderDashboard)
- **Automation Pattern** -- Events within the same domain trigger automated commands (AutoReorder)
- **Translation Pattern** -- Events in one domain trigger commands in another domain (ReserveStock from OrderPlaced)

## Slices

### Slice: PlaceOrder

**Wireframe:** Order form with product selector, quantity, and checkout button

```yaml emlang
slices:
  PlaceOrder:
    pattern: command
    domain: Billing
    steps:
      - t: Customer/OrderForm
      - c: PlaceOrder
        fields:
          orderId: {type: uuid, generated: true}
          customerId: uuid
          items: {type: list, of: OrderItem}
          total: decimal
      - e: Billing/OrderPlaced
        fields:
          orderId: uuid
          customerId: uuid
          items: {type: list, of: OrderItem}
          total: decimal
          placedAt: datetime
      - v: OrderConfirmation
        fields:
          orderId: uuid
          status: string
          total: decimal
    tests:
      HappyPath:
        when:
          - c: PlaceOrder
            props:
              customerId: cust-123
              total: 99.99
        then:
          - e: Billing/OrderPlaced
      EmptyCart:
        when:
          - c: PlaceOrder
            props:
              items: []
        then:
          - x: EmptyCartError
```


### Slice: ReserveStock

**Wireframe:** Automated process triggered by order events

```yaml emlang
slices:
  ReserveStock:
    pattern: translation
    domain: Inventory
    connections:
      consumes:
        - Billing/OrderPlaced
    steps:
      - r: Billing/OrderToInventory
      - c: ReserveStock
        fields:
          orderId: uuid
          items: {type: list, of: OrderItem}
      - e: Inventory/StockReserved
        fields:
          orderId: uuid
          reservationId: uuid
          items: {type: list, of: ReservedItem}
      - v: InventoryStatus
        fields:
          reservationId: uuid
          status: string
    tests:
      SufficientStock:
        given:
          - e: Inventory/StockAvailable
        when:
          - c: ReserveStock
            props:
              orderId: order-123
        then:
          - e: Inventory/StockReserved
      InsufficientStock:
        given:
          - e: Inventory/StockDepleted
        when:
          - c: ReserveStock
            props:
              orderId: order-123
        then:
          - x: InsufficientStockError
```


### Slice: ShipOrder

**Wireframe:** Shipping dashboard with order queue

```yaml emlang
slices:
  ShipOrder:
    pattern: translation
    domain: Shipping
    connections:
      consumes:
        - Inventory/StockReserved
    steps:
      - r: Inventory/ReservedToShipping
      - c: ShipOrder
        fields:
          orderId: uuid
          reservationId: uuid
          shippingAddress: string
      - e: Shipping/OrderShipped
        fields:
          orderId: uuid
          trackingNumber: string
          shippedAt: datetime
      - v: ShipmentTracking
        fields:
          trackingNumber: string
          status: string
          estimatedDelivery: date
```


### Slice: AutoReorder

**Wireframe:** Automated internal process (no UI)

```yaml emlang
slices:
  AutoReorder:
    pattern: automation
    domain: Inventory
    connections:
      consumes:
        - Inventory/StockReserved
    steps:
      - p: Inventory/LowStockMonitor
      - c: ReorderFromSupplier
        fields:
          productId: uuid
          quantity: integer
          supplierId: uuid
      - e: Inventory/ReorderPlaced
        fields:
          reorderId: uuid
          productId: uuid
          quantity: integer
```


### Slice: OrderDashboard

**Wireframe:** Customer-facing order status dashboard

```yaml emlang
slices:
  OrderDashboard:
    pattern: view
    domain: Billing
    connections:
      consumes:
        - Billing/OrderPlaced
        - Shipping/OrderShipped
    steps:
      - v: OrderDashboard
        fields:
          orderId: uuid
          status: string
          trackingNumber: string
          total: decimal
```


## Scenarios

### Scenario: End-to-End Order Flow

- **Given** a customer has items in their cart and inventory is available
- **When** customer places an order for $99.99
- **Then** order is created, stock reserved, and shipment initiated

### Scenario: Out of Stock Handling

- **Given** a product has zero available inventory
- **When** customer places an order containing that product
- **Then** stock reservation fails with InsufficientStockError

## Dependencies

None -- this is a sample multi-domain event model.

## Sources

- Event Modeling methodology by Adam Dymitruk
- Domain-Driven Design by Eric Evans
